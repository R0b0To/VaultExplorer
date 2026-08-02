package com.aeidolon.vaultexplorer

import android.app.PendingIntent
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import kotlin.concurrent.withLock

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

    private var pendingUsbPermissionResult: MethodChannel.Result? = null
    private var pendingUsbPermissionDeviceName: String? = null

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
        val device = deviceName?.let { usbManager.deviceList[it] }
        if (device == null) {
            result.error("USB_NOT_FOUND", "USB device not found: $deviceName", null)
            return
        }
        if (usbManager.hasPermission(device)) {
            result.success(true)
            return
        }
        pendingUsbPermissionResult = result
        pendingUsbPermissionDeviceName = deviceName
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val permissionIntent = PendingIntent.getBroadcast(
            activity, 0, Intent(actionUsbPermission), flags
        )
        usbManager.requestPermission(device, permissionIntent)
    }

    /** Called by MainActivity's usbPermissionReceiver for every
     *  ACTION_USB_PERMISSION broadcast. */
    fun onPermissionBroadcast(intent: Intent?) {
        if (intent?.action != actionUsbPermission) return
        synchronized(this) {
            val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
            }
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            val res = pendingUsbPermissionResult
            pendingUsbPermissionResult = null
            pendingUsbPermissionDeviceName = null
            if (device != null && res != null) {
                activity.runOnUiThread { res.success(granted) }
            }
        }
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
                msd = UsbMassStorageDevice.open(usbManager, device)
                    ?: throw Exception("Failed to open USB mass storage device")

                val sizeBytes = msd.sectorCount * msd.sectorSize
                UsbBlockBridge.register(targetVolId, msd)

                val keyfileFds = nativeOps.openKeyfileFds(args.keyfilePaths)

                if (args.preservedKey != null) {
                    Log.i("VaultExplorer_C++", "USB unlock using preserved derived key (len=${args.preservedKey.size})")
                } else if (args.cacheDerivedKey) {
                    Log.i("VaultExplorer_C++", "USB unlock will derive and cache a fresh key")
                }
                if (keyfileFds != null && keyfileFds.isNotEmpty()) {
                    Log.i("VaultExplorer_C++", "USB unlock using ${keyfileFds.size} keyfile(s)")
                }

                val files = ContainerSessionRegistry.locks[targetVolId].writeLock().withLock {
                    ContainerEngine.unlockUsb(
                        args.password, args.pim, targetVolId, sizeBytes, args.cipherId, args.hashId, args.preservedKey,
                        keyfileFds = keyfileFds, readOnly = args.readOnly
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
                        result.error("AUTH_FAIL", "Incorrect password/keyfiles or invalid drive", null)
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
        if (device == null || !usbManager.hasPermission(device)) {
            result.error("USB_NOT_FOUND", "Device not found or no permission", null)
            return
        }
        val volId = ContainerSessionRegistry.getFreeVolumeId()
        if (volId == null) {
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
            return
        }
        ioExecutor.execute {
            var msd: UsbMassStorageDevice? = null
            try {
                msd = UsbMassStorageDevice.open(usbManager, device) ?: throw Exception("Failed to open USB device")

                val deviceCapacityBytes = msd.sectorCount * msd.sectorSize
                val partitionStartBytes = 2048L * 512L
                Log.i("VaultExplorer_C++", "createUsbContainer: device=$deviceName capacity=$deviceCapacityBytes requested=$sizeBytes")
                if (sizeBytes <= 0 || sizeBytes > deviceCapacityBytes - partitionStartBytes) {
                    Log.w("VaultExplorer_C++", "createUsbContainer: requested size exceeds usable capacity")
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

                UsbBlockBridge.register(volId, msd)

                val createHiddenVolume = call.argument<Boolean>("createHiddenVolume") ?: false
                val quickFormat = call.argument<Boolean>("quickFormat") ?: false
                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)

                val success = if (createHiddenVolume) {
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
                        keyfileFds, hiddenKeyfileFds, quickFormat
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
                        keyfileFds, quickFormat
                    )
                }
                Log.i("VaultExplorer_C++", "createUsbContainer: native result=$success")
                activity.runOnUiThread { result.success(success) }
            } catch (e: Exception) {
                Log.e("VaultExplorer_C++", "createUsbContainer: exception", e)
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                UsbBlockBridge.unregister(volId)
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

    /** Called by MainActivity's usbDetachReceiver when a mounted USB
     *  container's underlying device is physically unplugged. */
    fun onDeviceDetached(device: UsbDevice) {
        val containerUri = "usb:${device.deviceName}"
        val volId = ContainerSessionRegistry.getVolumeIdByUri(containerUri) ?: return
        val session = ContainerSessionRegistry.activeSessions[volId]
        if (session?.isUsbSource != true) return

        ioExecutor.execute {
            UsbBlockBridge.unregister(volId)
            try {
                ContainerSessionRegistry.locks[volId].writeLock().withLock {
                    ContainerEngine.lock(volId)
                }
            } catch (e: Exception) {
                Log.w("VaultExplorer_C++", "lockNative on USB detach failed for volId=$volId: ${e.message}")
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
}