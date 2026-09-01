package com.aeidolon.vaultexplorer.handlers

import android.app.PendingIntent
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import kotlin.concurrent.withLock
import com.aeidolon.vaultexplorer.PendingUsbPermissions
import com.aeidolon.vaultexplorer.bridge.UsbBlockBridge
import com.aeidolon.vaultexplorer.container.ContainerEngine
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.usb.UsbDeviceLocks
import com.aeidolon.vaultexplorer.usb.UsbMassStorageDevice
import com.aeidolon.vaultexplorer.usb.UsbOpenResult
import com.aeidolon.vaultexplorer.container.ContainerSession
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.VeLog

/**
 * USB mass-storage container lifecycle: device discovery, permission
 * requests (via [UsbManager.requestPermission]'s broadcast-based flow),
 * and unlocking/creating VeraCrypt/LUKS containers directly on a raw block
 * device via [UsbBlockBridge]. [onPermissionBroadcast] and
 * [onDeviceDetached] are called by MainActivity's registered
 * BroadcastReceivers, since receiver registration/unregistration has to
 * stay on the Activity itself.
 */
class UsbContainerHandlers(
    private val activity: MainActivity,
    private val actionUsbPermission: String,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
    private val derivedKeyHandlers: DerivedKeyHandlers,
) {
    private val usbManager: UsbManager get() = activity.usbManager

    // Per-device (not global) pending permission requests — see
    // PendingUsbPermissions' doc comment for why a single global
    // pendingUsbPermissionResult/DeviceName pair silently drops a caller
    // when two different USB devices both have permission requested in
    // flight at once.
    private val pendingUsbPermissions = PendingUsbPermissions()

    fun handleListUsbDevices(call: MethodCall, result: MethodChannel.Result) {
        val list = usbManager.deviceList.values
            .filter { device -> (0 until device.interfaceCount).any { i ->
                val intf = device.getInterface(i)
                intf.interfaceClass == 0x08 && intf.interfaceSubclass == 0x06 && intf.interfaceProtocol == 0x50
            } }
            .map { device ->
                mapOf(
                    "deviceName" to device.deviceName,
                    "productName" to (device.productName ?: device.deviceName),
                    "hasPermission" to usbManager.hasPermission(device),
                )
            }
        result.success(list)
    }

    fun handleRequestUsbPermission(call: MethodCall, result: MethodChannel.Result) {
        val deviceName = call.argument<String>("deviceName")
        if (deviceName == null) {
            result.error("USB_NOT_FOUND", "deviceName is required", null)
            return
        }
        val device = usbManager.deviceList[deviceName]
        if (device == null) {
            result.error("USB_NOT_FOUND", "USB device not found: $deviceName", null)
            return
        }
        if (usbManager.hasPermission(device)) {
            result.success(true)
            return
        }
        if (!pendingUsbPermissions.put(deviceName, result)) {
            // A request for this exact device is already in flight — reject
            // the duplicate explicitly rather than overwrite the earlier
            // caller's Result (which would then never complete). See
            // PendingUsbPermissions.put's doc comment.
            VeLog.w(TAG) { "requestUsbPermission: duplicate request for deviceName=$deviceName rejected" }
            result.error("USB_PERMISSION_PENDING", "A permission request is already pending for this device", null)
            return
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val permissionIntent = PendingIntent.getBroadcast(
            activity, 0, Intent(actionUsbPermission), flags
        )
        VeLog.i(TAG) { "requestUsbPermission: requesting for deviceName=$deviceName" }
        usbManager.requestPermission(device, permissionIntent)
    }

    /** Called by MainActivity's usbPermissionReceiver for every
     *  ACTION_USB_PERMISSION broadcast. */
    fun onPermissionBroadcast(intent: Intent?) {
        if (intent?.action != actionUsbPermission) return
        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
        }
        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
        val deviceName = device?.deviceName
        // PendingUsbPermissions.take() is a single atomic ConcurrentHashMap
        // operation, so this no longer needs an outer `synchronized(this)`
        // to extract the matching request without racing a fresh
        // requestUsbPermission() call for the same device.
        val entry = deviceName?.let { pendingUsbPermissions.take(it) }
        VeLog.i(TAG) {
            "USB_PERMISSION_BROADCAST deviceName=$deviceName granted=$granted pendingFound=${entry != null}" +
                (entry?.let { " requestAgeMs=${System.currentTimeMillis() - it.requestedAtMs}" } ?: "")
        }
        if (entry != null) {
            activity.runOnUiThread { entry.result.success(granted) }
        } else if (deviceName != null) {
            VeLog.w(TAG) { "USB_PERMISSION_BROADCAST: unmatched broadcast for deviceName=$deviceName (no pending request, or it already resolved/cancelled)" }
        }
    }

    /** Called by MainActivity.onDestroy() so no [MethodChannel.Result] from
     *  a still-in-flight requestUsbPermission() call is left unresolved
     *  when the Activity (and its Flutter engine binding) goes away. */
    fun onActivityDestroyed() {
        pendingUsbPermissions.cancelAll()
    }

    fun handleUnlockUsbContainer(call: MethodCall, result: MethodChannel.Result) {
        val deviceNameOrNull = call.argument<String>("deviceName")
        val args = parseUnlockArgs(call, result, deviceNameOrNull, "deviceName") ?: return
        val deviceName = deviceNameOrNull!! // parseUnlockArgs already validated this is non-null

        val device = usbManager.deviceList[deviceName]
        if (device == null) {
            result.error("USB_NOT_FOUND", "USB device not found: $deviceName", null)
            return
        }
        if (!usbManager.hasPermission(device)) {
            result.error("USB_NO_PERMISSION", "Permission not granted for device", null)
            return
        }

        val containerUri = "usb:$deviceName"
        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
            return
        }
        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))

        ioExecutor.execute {
            var msd: UsbMassStorageDevice? = null
            try {
                // Re-check immediately before opening: the initial checks
                // above ran on the calling thread before this task was even
                // queued on ioExecutor, so the device may since have been
                // unplugged or had its permission revoked while this task
                // was waiting for a free worker thread.
                val currentDevice = usbManager.deviceList[deviceName]
                if (currentDevice == null) {
                    activity.runOnUiThread { result.error("USB_NOT_FOUND", "USB device is no longer connected", null) }
                    return@execute
                }
                if (!usbManager.hasPermission(currentDevice)) {
                    activity.runOnUiThread { result.error("USB_NO_PERMISSION", "USB permission is no longer granted for this device", null) }
                    return@execute
                }

                val openResult = UsbMassStorageDevice.openDiagnostic(usbManager, currentDevice)
                msd = (openResult as? UsbOpenResult.Success)?.device
                if (msd == null) {
                    val failure = openResult as UsbOpenResult.Failure
                    activity.runOnUiThread { result.error(failure.code, failure.message, null) }
                    return@execute
                }

                val sizeBytes = msd.sectorCount * msd.sectorSize
                UsbBlockBridge.register(targetVolId, msd, deviceName)

                val keyfileFds = nativeOps.openKeyfileFds(args.keyfilePaths)
                val hiddenKeyfileFds =
                    if (args.protectHiddenVolume) nativeOps.openKeyfileFds(args.hiddenKeyfilePaths) else null

                if (args.preservedKey != null) {
                    VeLog.i("VaultExplorer_C++") { "USB unlock using preserved derived key" }
                } else if (args.cacheDerivedKey) {
                    VeLog.i("VaultExplorer_C++") { "USB unlock will derive and cache a fresh key" }
                }
                if (keyfileFds != null && keyfileFds.isNotEmpty()) {
                    VeLog.i("VaultExplorer_C++") { "USB unlock using ${keyfileFds.size} keyfile(s)" }
                }
                if (args.protectHiddenVolume) {
                    VeLog.i("VaultExplorer_C++") { "USB unlock requesting hidden volume protection" }
                }

                val files = ContainerSessionRegistry.locks[targetVolId].writeLock().withLock {
                    ContainerEngine.unlockUsb(
                        args.password, args.pim, targetVolId, sizeBytes, args.cipherId, args.hashId, args.preservedKey,
                        keyfileFds = keyfileFds, readOnly = args.readOnly,
                        hiddenPassword = if (args.protectHiddenVolume) args.hiddenPassword ?: "" else null,
                        hiddenPim = args.hiddenPim, hiddenCipherId = args.hiddenCipherId,
                        hiddenHashId = args.hiddenHashId, hiddenKeyfileFds = hiddenKeyfileFds,
                    )
                }

                activity.runOnUiThread {
                    if (files != null) {
                        ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                            uri = containerUri,
                            volId = targetVolId,
                            cachedFilesList = files.toList(),
                            displayName = args.displayName ?: device.productName ?: deviceName,
                            documentProvider = args.docProvider,
                            isUsbSource = true,
                            readOnly = args.readOnly,
                            containerFormat = ContainerEngine.format(targetVolId),
                        )
                        ContainerSessionRegistry.applyAutoMountFolders(targetVolId, args.autoMountFolders)
                        val hasFolderMounts = ContainerSessionRegistry.activeSessions[targetVolId]
                            ?.subFolderMounts?.isNotEmpty() == true
                        if (args.docProvider || hasFolderMounts) {
                            activity.contentResolver.notifyChange(
                                DocumentsContract.buildRootsUri(
                                    "com.aeidolon.vaultexplorer.documents"), null)
                        }
                        val fmt = ContainerEngine.format(targetVolId).wireName
                        result.success(mapOf(
                            "volId" to targetVolId,
                            "files" to files.toList(),
                            "matchedCipherId" to ContainerEngine.matchedCipherId(targetVolId),
                            "matchedHashId" to ContainerEngine.matchedHashId(targetVolId),
                            "containerFormat" to fmt
                        ))
                        if (args.cacheDerivedKey && args.preservedKey == null) {
                            val derived = ContainerEngine.lastDerivedKeyMaterial(targetVolId)
                            if (derived != null) {
                                ioExecutor.execute { derivedKeyHandlers.storeDerivedKeyBytes(deviceName, derived) }
                            }
                        }
                    } else {
                        UsbBlockBridge.unregister(targetVolId)
                        result.error("AUTH_FAIL",
                            if (args.protectHiddenVolume)
                                "Incorrect password/keyfiles, or the hidden volume password/keyfiles did not match"
                            else
                                "Incorrect password/keyfiles or invalid drive", null)
                    }
                }
            } catch (e: Exception) {
                UsbBlockBridge.unregister(targetVolId)
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleCreateUsbContainer(call: MethodCall, result: MethodChannel.Result) {
        val deviceName   = call.argument<String>("deviceName")
        val password     = call.argument<String>("password") ?: ""
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        val sizeBytes    = call.argument<Number>("sizeBytes")?.toLong() ?: 0L
        if (deviceName == null || (password.isEmpty() && keyfilePaths.isNullOrEmpty())) {
            result.error("INVALID_ARGS", "deviceName and password/keyfiles required", null)
            return
        }
        val device = usbManager.deviceList[deviceName]
        if (device == null) {
            result.error("USB_NOT_FOUND", "USB device not found: $deviceName", null)
            return
        }
        if (!usbManager.hasPermission(device)) {
            result.error("USB_NO_PERMISSION", "Permission not granted for device", null)
            return
        }
        val volId = ContainerSessionRegistry.getFreeVolumeId()
        if (volId == null) {
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
            return
        }

        // Serialize creates against the same physical device: reject a
        // second concurrent create for deviceName immediately (rather than
        // silently queueing it behind a multi-minute format) so the UI can
        // show a clear "already in progress" message instead of two
        // creation jobs corrupting the same drive. tryLock() runs
        // synchronously here, before ioExecutor is ever touched.
        val deviceLock = UsbDeviceLocks.forDevice(deviceName)
        if (!deviceLock.tryLock()) {
            result.error("USB_CREATE_IN_PROGRESS", "A container is already being created on this device", null)
            return
        }

        // Correlates every log line for this one creation attempt — native
        // logs the same id, so a bug report's Kotlin and C++ output can be
        // matched up even when several USB operations interleave in logcat.
        val operationId = java.util.UUID.randomUUID().toString().take(8)
        VeLog.i("VaultExplorer_C++") { "createUsbContainer[$operationId]: requested deviceName=$deviceName sizeBytes=$sizeBytes volId=$volId" }

        ioExecutor.execute {
            var msd: UsbMassStorageDevice? = null
            try {
                // Re-check immediately before opening — see the identical
                // comment in handleUnlockUsbContainer above for why this
                // can't just reuse the check done before scheduling this
                // task.
                val currentDevice = usbManager.deviceList[deviceName]
                if (currentDevice == null) {
                    VeLog.w("VaultExplorer_C++") { "createUsbContainer[$operationId]: device disappeared before worker started" }
                    activity.runOnUiThread { result.error("USB_NOT_FOUND", "USB device is no longer connected", null) }
                    return@execute
                }
                if (!usbManager.hasPermission(currentDevice)) {
                    VeLog.w("VaultExplorer_C++") { "createUsbContainer[$operationId]: permission revoked before worker started" }
                    activity.runOnUiThread { result.error("USB_NO_PERMISSION", "USB permission is no longer granted for this device", null) }
                    return@execute
                }

                val openResult = UsbMassStorageDevice.openDiagnostic(usbManager, currentDevice)
                msd = (openResult as? UsbOpenResult.Success)?.device
                if (msd == null) {
                    val failure = openResult as UsbOpenResult.Failure
                    VeLog.w("VaultExplorer_C++") { "createUsbContainer[$operationId]: open failed code=${failure.code} message=${failure.message}" }
                    activity.runOnUiThread { result.error(failure.code, failure.message, null) }
                    return@execute
                }

                val deviceCapacityBytes = msd.sectorCount * msd.sectorSize
                val partitionStartBytes = 2048L * 512L
                VeLog.i("VaultExplorer_C++") { "createUsbContainer[$operationId]: opened device sectorCount=${msd.sectorCount} sectorSize=${msd.sectorSize}, starting container creation" }
                if (sizeBytes <= 0 || sizeBytes > deviceCapacityBytes - partitionStartBytes) {
                    VeLog.w("VaultExplorer_C++") { "createUsbContainer[$operationId]: requested size exceeds usable capacity" }
                    msd.close()
                    activity.runOnUiThread {
                        result.error(
                            "SIZE_TOO_LARGE",
                            "Requested size ($sizeBytes bytes) exceeds usable device capacity " +
                                "(${deviceCapacityBytes - partitionStartBytes} bytes)",
                            null
                        )
                    }
                    return@execute
                }

                UsbBlockBridge.register(volId, msd, deviceName)

                val createHiddenVolume = call.argument<Boolean>("createHiddenVolume") ?: false
                val quickFormat = call.argument<Boolean>("quickFormat") ?: false
                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)

                val resultMap = if (createHiddenVolume) {
                    val hiddenPassword = call.argument<String>("hiddenPassword") ?: ""
                    val hiddenPim = call.argument<Number>("hiddenPim")?.toInt() ?: 0
                    val hiddenSizeBytes = call.argument<Number>("hiddenSizeBytes")?.toLong() ?: 0L
                    val hiddenFileSystem = call.argument<String>("hiddenFileSystem") ?: "fat"
                    val hiddenCipherId = call.argument<Number>("hiddenCipherId")?.toInt() ?: 255
                    val hiddenHashId = call.argument<Number>("hiddenHashId")?.toInt() ?: 255
                    val hiddenKeyfilePaths = call.argument<List<String>>("hiddenKeyfilePaths")
                    val hiddenKeyfileFds = nativeOps.openKeyfileFds(hiddenKeyfilePaths)

                    ContainerEngine.createUsbWithHidden(
                        volId, "mbr", password, hiddenPassword,
                        call.argument<Number>("pim")?.toInt() ?: 0, hiddenPim,
                        sizeBytes,
                        call.argument<String>("fileSystem") ?: "ext4", hiddenFileSystem,
                        hiddenSizeBytes,
                        call.argument<Number>("cipherId")?.toInt() ?: 255,
                        call.argument<Number>("hashId")?.toInt() ?: 255,
                        hiddenCipherId, hiddenHashId,
                        keyfileFds, hiddenKeyfileFds, quickFormat,
                        deviceSectorCount = msd.sectorCount, operationId = operationId,
                    )
                } else {
                    ContainerEngine.createUsb(
                        volId, "mbr", password,
                        call.argument<Number>("pim")?.toInt() ?: 0,
                        sizeBytes,
                        call.argument<String>("fileSystem") ?: "ext4",
                        call.argument<Number>("containerFormat")?.toInt() ?: 0,
                        call.argument<Number>("cipherId")?.toInt() ?: 255,
                        call.argument<Number>("hashId")?.toInt() ?: 255,
                        keyfileFds, quickFormat,
                        deviceSectorCount = msd.sectorCount, operationId = operationId,
                    )
                }

                val success = resultMap?.get("success") as? Boolean ?: false
                if (success) {
                    VeLog.i("VaultExplorer_C++") { "createUsbContainer[$operationId]: SUCCESS" }
                    activity.runOnUiThread { result.success(true) }
                } else {
                    val phase = resultMap?.get("phase") as? String ?: "unknown"
                    val errorCode = resultMap?.get("errorCode") as? String ?: "USB_CREATE_FAILED"
                    val errorMessage = resultMap?.get("errorMessage") as? String ?: "USB container creation failed"
                    // A device unplugged mid-operation surfaces here as
                    // whatever generic write/format failure the interrupted
                    // phase produced — check UsbBlockBridge's detach flag
                    // (set by onDeviceDetached, possibly moments ago on
                    // another thread) so the user sees "disconnected"
                    // rather than a confusing lower-level error code.
                    val detached = UsbBlockBridge.wasDetached(volId)
                    val finalCode = if (detached) "USB_DEVICE_DISCONNECTED" else errorCode
                    val finalMessage = if (detached) "$errorMessage (USB device was disconnected during the operation)" else errorMessage
                    val lastIoError = UsbBlockBridge.lastError(volId)
                    val details = mutableMapOf<String, Any?>(
                        "operationId" to operationId,
                        "phase" to phase,
                        "offsetBytes" to resultMap?.get("offsetBytes"),
                        "sector" to resultMap?.get("sector"),
                        "sectorCount" to resultMap?.get("sectorCount"),
                    )
                    if (lastIoError != null) details["scsi"] = lastIoError.toLogString()
                    VeLog.e("VaultExplorer_C++") {
                        "createUsbContainer[$operationId]: FAILED phase=$phase errorCode=$finalCode message=$finalMessage" +
                            (lastIoError?.let { " scsi=${it.toLogString()}" } ?: "")
                    }
                    activity.runOnUiThread { result.error(finalCode, finalMessage, details) }
                }
            } catch (e: Exception) {
                VeLog.e("VaultExplorer_C++", e) { "createUsbContainer[$operationId]: exception" }
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                UsbBlockBridge.unregister(volId)
                deviceLock.unlock()
            }
        }
    }

    fun handleGetUsbDeviceCapacity(call: MethodCall, result: MethodChannel.Result) {
        val deviceName = call.argument<String>("deviceName")
        val device = deviceName?.let { usbManager.deviceList[it] }
        if (device == null) {
            result.error("USB_NOT_FOUND", "USB device not found: $deviceName", null)
            return
        }
        if (!usbManager.hasPermission(device)) {
            result.error("USB_NO_PERMISSION", "Permission not granted for device", null)
            return
        }
        ioExecutor.execute {
            var msd: UsbMassStorageDevice? = null
            try {
                msd = UsbMassStorageDevice.open(usbManager, device)
                if (msd == null) {
                    activity.runOnUiThread { result.error("USB_OPEN_FAILED", "Failed to open USB device", null) }
                    return@execute
                }
                val capacityBytes = msd.sectorCount * msd.sectorSize
                val partitionStartBytes = 2048L * 512L
                val usableBytes = (capacityBytes - partitionStartBytes).coerceAtLeast(0L)
                activity.runOnUiThread { result.success(usableBytes) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                msd?.close()
            }
        }
    }

    /** Called by MainActivity's usbDetachReceiver when a USB device backing
     *  a mounted container -- or one in the middle of being unlocked or
     *  created, which has no [ContainerSession] yet -- is physically
     *  unplugged. */
    fun onDeviceDetached(device: UsbDevice) {
        val containerUri = "usb:${device.deviceName}"
        val existingVolId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
        val inFlightVolId = UsbBlockBridge.volIdForDeviceName(device.deviceName)

        if (existingVolId == null) {
            if (inFlightVolId != null) {
                // No mounted session exists yet (this is an in-flight
                // create or unlock), but the device is registered with
                // UsbBlockBridge for that in-flight operation. Mark it
                // detached (so the operation's own failure handling can
                // report USB_DEVICE_DISCONNECTED) and unregister
                // immediately, so any native read/write already in flight
                // fails fast instead of retrying/timing out against a
                // device that is now gone.
                VeLog.w("VaultExplorer_C++") { "onDeviceDetached: device=${device.deviceName} detached during in-flight operation volId=$inFlightVolId" }
                UsbBlockBridge.markDetached(inFlightVolId)
                UsbBlockBridge.unregister(inFlightVolId)
            }
            return
        }

        val session = ContainerSessionRegistry.activeSessions[existingVolId]
        if (session?.isUsbSource != true) return
        val volId = existingVolId

        ioExecutor.execute {
            UsbBlockBridge.unregister(volId)
            try {
                ContainerSessionRegistry.locks[volId].writeLock().withLock {
                    ContainerEngine.lock(volId)
                }
            } catch (e: Exception) {
                VeLog.w("VaultExplorer_C++") { "lockNative on USB detach failed for volId=$volId: ${e.message}" }
            }
            ContainerSessionRegistry.removeSession(volId)
            activity.runOnUiThread {
                activity.contentResolver.notifyChange(
                    DocumentsContract.buildRootsUri(
                        "com.aeidolon.vaultexplorer.documents"), null)
                activity.methodChannel?.invokeMethod(
                    "onUsbContainerDetached", mapOf("volId" to volId))
            }
        }
    }

    companion object {
        private const val TAG = "UsbContainerHandlers"
    }
}
