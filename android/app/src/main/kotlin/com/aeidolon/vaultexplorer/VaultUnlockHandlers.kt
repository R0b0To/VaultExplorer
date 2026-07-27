package com.aeidolon.vaultexplorer

import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.util.Base64
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import kotlin.concurrent.withLock

/**
 * Container lifecycle for every non-USB source: unlocking VeraCrypt/LUKS
 * (via the native ProxyFileDescriptor session) and Cryptomator/gocryptfs/
 * CryFS (via their pure-Kotlin [VaultBackend] sessions), locking, password
 * changes, and small lifecycle utilities (warm/exists/settings/cancel).
 */
class VaultUnlockHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
    private val derivedKeyHandlers: DerivedKeyHandlers,
) {
    fun handleUnlockContainer(call: MethodCall, result: MethodChannel.Result) {
        val uriString   = call.argument<String>("filePath")
        val password    = call.argument<String>("password")
        val pim         = call.argument<Number>("pim")?.toInt() ?: 0
        val displayName = call.argument<String>("displayName")
        val docProvider = call.argument<Boolean>("documentProvider") ?: false
        val autoMountFolders = call.argument<List<String>>("autoMountFolders")
        val cipherId    = call.argument<Number>("cipherId")?.toInt() ?: 255
        val hashId      = call.argument<Number>("hashId")?.toInt() ?: 255
        val preservedKeyBase64 = call.argument<String>("preservedKey")
        val preservedKey = preservedKeyBase64?.let { Base64.decode(it, Base64.NO_WRAP) }
        if (preservedKey != null) {
            Log.i("VaultExplorer_C++", "Unlock request is using preserved key (${preservedKey.size} bytes)")
        }
        val cacheDerivedKey = call.argument<Boolean>("cacheDerivedKey") ?: false
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        val readOnly = call.argument<Boolean>("readOnly") ?: false

        if (uriString == null || password == null) {
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }
        if (password.isEmpty() && keyfilePaths.isNullOrEmpty() && preservedKey == null) {
            result.error("INVALID_ARGS", "password or keyfiles required", null)
            return
        }

        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "Maximum 8 containers already mounted", null)
            return
        }
        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))

        ioExecutor.execute {
            var pfd: ParcelFileDescriptor? = null
            try {
                val uri = Uri.parse(uriString)
                pfd = activity.contentResolver.openFileDescriptor(uri, "rw")
                    ?: throw Exception("Could not open file descriptor")

                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)
                val fd = pfd.detachFd()

                if (preservedKey != null) {
                    Log.i("VaultExplorer_C++", "File unlock using preserved derived key (len=${preservedKey.size})")
                } else if (cacheDerivedKey) {
                    Log.i("VaultExplorer_C++", "File unlock will derive and cache a fresh key")
                }
                if (keyfileFds != null && keyfileFds.isNotEmpty()) {
                    Log.i("VaultExplorer_C++", "File unlock using ${keyfileFds.size} keyfile(s)")
                }

                val files = ContainerSessionRegistry.locks[targetVolId].writeLock().withLock {
                    ContainerEngine.unlockFile(fd, password, pim, targetVolId, cipherId, hashId, preservedKey, keyfileFds, readOnly)
                }

                activity.runOnUiThread {
                    if (files != null) {
                        ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                            uri = uriString,
                            volId = targetVolId,
                            cachedFilesList = files.toList(),
                            displayName = displayName,
                            documentProvider = docProvider,
                            readOnly = readOnly,
                        )
                        ContainerSessionRegistry.applyAutoMountFolders(targetVolId, autoMountFolders)
                        val hasFolderMounts = ContainerSessionRegistry.activeSessions[targetVolId]
                            ?.subFolderMounts?.isNotEmpty() == true
                        if (docProvider || hasFolderMounts) {
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
                        if (cacheDerivedKey && preservedKey == null) {
                            val derived = ContainerEngine.lastDerivedKeyMaterial(targetVolId)
                            if (derived != null) {
                                ioExecutor.execute { derivedKeyHandlers.storeDerivedKeyBytes(uriString, derived) }
                            }
                        }
                    } else {
                        result.error("AUTH_FAIL",
                            "Incorrect password/keyfiles or invalid container", null)
                    }
                }
            } catch (e: Exception) {
                try { pfd?.close() } catch (_: Exception) {}
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleUnlockCryptomatorVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val password = call.argument<String>("password")
        val displayName = call.argument<String>("displayName")
        val docProvider = call.argument<Boolean>("documentProvider") ?: false
        val autoMountFolders = call.argument<List<String>>("autoMountFolders")
        val readOnly = call.argument<Boolean>("readOnly") ?: false
        if (uriString == null || password == null) {
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }
        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "Maximum containers already mounted", null)
            return
        }
        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val passwordChars = password.toCharArray()
                val openResult = try {
                    com.aeidolon.vaultexplorer.cryptomator.CryptomatorVault.open(activity, uri, passwordChars, readOnly)
                } finally {
                    passwordChars.fill('\u0000')
                }

                val files = if (openResult is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success) {
                    openResult.session.listDirectory("")?.toList() ?: emptyList()
                } else null

                activity.runOnUiThread {
                    when (openResult) {
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success -> {
                            val session = openResult.session
                            VaultBackendRegistry.put(targetVolId, session)
                            ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                                uri = uriString,
                                volId = targetVolId,
                                cachedFilesList = files ?: emptyList(),
                                displayName = displayName ?: openResult.vaultDisplayName,
                                documentProvider = docProvider,
                                readOnly = readOnly,
                            )
                            ContainerSessionRegistry.applyAutoMountFolders(targetVolId, autoMountFolders)
                            val hasFolderMounts = ContainerSessionRegistry.activeSessions[targetVolId]
                                ?.subFolderMounts?.isNotEmpty() == true
                            if (docProvider || hasFolderMounts) {
                                activity.contentResolver.notifyChange(
                                    DocumentsContract.buildRootsUri(
                                        "com.aeidolon.vaultexplorer.documents"), null)
                            }
                            result.success(mapOf(
                                "volId" to targetVolId,
                                "files" to (files ?: emptyList<String>()),
                                "matchedCipherId" to 255,
                                "matchedHashId" to 255,
                                "containerFormat" to "cryptomator",
                            ))
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.WrongPassword -> {
                            result.error("AUTH_FAIL", "Incorrect password", null)
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault -> {
                            result.error("INVALID_VAULT", openResult.reason, null)
                        }
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleUnlockGocryptfsVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val password = call.argument<String>("password")
        val displayName = call.argument<String>("displayName")
        val docProvider = call.argument<Boolean>("documentProvider") ?: false
        val autoMountFolders = call.argument<List<String>>("autoMountFolders")
        val readOnly = call.argument<Boolean>("readOnly") ?: false
        if (uriString == null || password == null) {
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }
        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "Maximum containers already mounted", null)
            return
        }
        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val passwordChars = password.toCharArray()
                val openResult = try {
                    com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault.open(activity, uri, passwordChars, readOnly)
                } finally {
                    passwordChars.fill('\u0000')
                }

                val files = if (openResult is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success) {
                    openResult.session.listDirectory("")?.toList() ?: emptyList()
                } else null

                activity.runOnUiThread {
                    when (openResult) {
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success -> {
                            val session = openResult.session
                            VaultBackendRegistry.put(targetVolId, session)
                            ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                                uri = uriString,
                                volId = targetVolId,
                                cachedFilesList = files ?: emptyList(),
                                displayName = displayName ?: openResult.vaultDisplayName,
                                documentProvider = docProvider,
                                readOnly = readOnly,
                            )
                            ContainerSessionRegistry.applyAutoMountFolders(targetVolId, autoMountFolders)
                            val hasFolderMounts = ContainerSessionRegistry.activeSessions[targetVolId]
                                ?.subFolderMounts?.isNotEmpty() == true
                            if (docProvider || hasFolderMounts) {
                                activity.contentResolver.notifyChange(
                                    DocumentsContract.buildRootsUri(
                                        "com.aeidolon.vaultexplorer.documents"), null)
                            }
                            result.success(mapOf(
                                "volId" to targetVolId,
                                "files" to (files ?: emptyList<String>()),
                                "matchedCipherId" to 255,
                                "matchedHashId" to 255,
                                "containerFormat" to "gocryptfs",
                            ))
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.WrongPassword -> {
                            result.error("AUTH_FAIL", "Incorrect password", null)
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault -> {
                            result.error("INVALID_VAULT", openResult.reason, null)
                        }
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleUnlockCryfsVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val password = call.argument<String>("password")
        val displayName = call.argument<String>("displayName")
        val docProvider = call.argument<Boolean>("documentProvider") ?: false
        val autoMountFolders = call.argument<List<String>>("autoMountFolders")
        val readOnly = call.argument<Boolean>("readOnly") ?: false
        val preservedKeyBase64 = call.argument<String>("preservedKey")
        val preservedKey = preservedKeyBase64?.let { Base64.decode(it, Base64.NO_WRAP) }
        val cacheDerivedKey = call.argument<Boolean>("cacheDerivedKey") ?: false
        if (uriString == null || (password == null && preservedKey == null)) {
            result.error("INVALID_ARGS", "filePath and (password or preservedKey) required", null)
            return
        }
        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "Maximum containers already mounted", null)
            return
        }
        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                if (preservedKey != null) {
                    Log.i("VaultExplorer_C++", "CryFS unlock using preserved combined key (len=${preservedKey.size})")
                } else if (cacheDerivedKey) {
                    Log.i("VaultExplorer_C++", "CryFS unlock will derive and cache a fresh combined key")
                }
                val openResult = if (preservedKey != null) {
                    com.aeidolon.vaultexplorer.cryfs.CryfsVault.openWithCombinedKey(activity, uri, preservedKey, readOnly)
                } else {
                    val passwordChars = password!!.toCharArray()
                    try {
                        com.aeidolon.vaultexplorer.cryfs.CryfsVault.open(activity, uri, passwordChars, readOnly)
                    } finally {
                        passwordChars.fill('\u0000')
                    }
                }

                val files = if (openResult is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success) {
                    openResult.session.listDirectory("")?.toList() ?: emptyList()
                } else null

                activity.runOnUiThread {
                    when (openResult) {
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success -> {
                            val session = openResult.session
                            VaultBackendRegistry.put(targetVolId, session)
                            ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                                uri = uriString,
                                volId = targetVolId,
                                cachedFilesList = files ?: emptyList(),
                                displayName = displayName ?: openResult.vaultDisplayName,
                                documentProvider = docProvider,
                                readOnly = readOnly,
                            )
                            ContainerSessionRegistry.applyAutoMountFolders(targetVolId, autoMountFolders)
                            val hasFolderMounts = ContainerSessionRegistry.activeSessions[targetVolId]
                                ?.subFolderMounts?.isNotEmpty() == true
                            if (docProvider || hasFolderMounts) {
                                activity.contentResolver.notifyChange(
                                    DocumentsContract.buildRootsUri(
                                        "com.aeidolon.vaultexplorer.documents"), null)
                            }
                            result.success(mapOf(
                                "volId" to targetVolId,
                                "files" to (files ?: emptyList<String>()),
                                "matchedCipherId" to 255,
                                "matchedHashId" to 255,
                                "containerFormat" to "cryfs",
                            ))
                            if (cacheDerivedKey && preservedKey == null) {
                                val derived = openResult.derivedKey
                                if (derived != null) {
                                    ioExecutor.execute { derivedKeyHandlers.storeDerivedKeyBytes(uriString, derived) }
                                }
                            }
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.WrongPassword -> {
                            result.error("AUTH_FAIL", "Incorrect password", null)
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault -> {
                            result.error("INVALID_VAULT", openResult.reason, null)
                        }
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleIsGocryptfsVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGS", "uri is required", null)
            return
        }
        ioExecutor.execute {
            val isVault = try {
                val uri = Uri.parse(uriString)
                com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault.looksLikeVault(activity, uri)
            } catch (_: Exception) {
                false
            }
            activity.runOnUiThread { result.success(isVault) }
        }
    }

    fun handleIsCryfsVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGS", "uri is required", null)
            return
        }
        ioExecutor.execute {
            val isVault = try {
                val uri = Uri.parse(uriString)
                com.aeidolon.vaultexplorer.cryfs.CryfsVault.looksLikeVault(activity, uri)
            } catch (_: Exception) {
                false
            }
            activity.runOnUiThread { result.success(isVault) }
        }
    }

    fun handleFinishWriteIfCryptomator(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Number>("volId")?.toInt()
        val path = call.argument<String>("path")
        if (volId == null || path == null) {
            result.error("INVALID_ARGS", "volId and path required", null)
            return
        }
        ioExecutor.execute {
            try {
                val success = ContainerSessionRegistry.locks[volId].writeLock().withLock {
                    ContainerEngine.finishWrite(path, volId)
                }
                activity.runOnUiThread { result.success(success) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleCancelUnlock(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Number>("volId")?.toInt()
        if (volId == null) {
            result.error("INVALID_ARGS", "volId required", null)
            return
        }
        ContainerEngine.requestUnlockCancellation(volId)
        result.success(true)
    }

    fun handleChangeContainerPassword(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val oldPassword = call.argument<String>("oldPassword") ?: ""
        val newPassword = call.argument<String>("newPassword") ?: ""
        val oldPim = call.argument<Number>("oldPim")?.toInt() ?: 0
        val newPim = call.argument<Number>("newPim")?.toInt() ?: 0
        val cipherId = call.argument<Number>("cipherId")?.toInt() ?: 255
        val hashId = call.argument<Number>("hashId")?.toInt() ?: 255
        val oldKeyfilePaths = call.argument<List<String>>("oldKeyfilePaths")
        val newKeyfilePaths = call.argument<List<String>>("newKeyfilePaths")

        if (uri.isNullOrEmpty() || newPassword.isEmpty()) {
            result.error("INVALID_ARGS", "uri and newPassword required", null)
            return
        }

        ioExecutor.execute {
            try {
                val docUri = Uri.parse(uri)
                val pfd = activity.contentResolver.openFileDescriptor(docUri, "rw")
                    ?: throw Exception("Could not open file descriptor")
                val oldKfFds = nativeOps.openKeyfileFds(oldKeyfilePaths)
                val newKfFds = nativeOps.openKeyfileFds(newKeyfilePaths)
                val success = ContainerEngine.changePassword(
                    pfd.detachFd(), oldPassword, newPassword,
                    oldPim, newPim, cipherId, hashId,
                    oldKfFds, newKfFds
                )
                activity.runOnUiThread { result.success(success) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleDocumentExists(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")

        if (filePath == null) {
            result.error("INVALID_ARGS", "filePath required", null)
            return
        }

        ioExecutor.execute {
            val exists = try {
                val uri = Uri.parse(filePath)
                if (filePath.startsWith("content://")) {
                    if (DocumentsContract.isTreeUri(uri)) {
                        DocumentFile.fromTreeUri(activity, uri)?.exists() == true
                    } else {
                        DocumentFile.fromSingleUri(activity, uri)?.exists() == true
                    }
                } else {
                    File(filePath).exists()
                }
            } catch (e: Exception) {
                false
            }
            activity.runOnUiThread { result.success(exists) }
        }
    }

    fun handleWarmContainer(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath != null) {
            ioExecutor.execute {
                try {
                    val uri = Uri.parse(filePath)
                    activity.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                        ParcelFileDescriptor.AutoCloseInputStream(pfd).use { stream ->
                            val buf = ByteArray(65536)
                            stream.read(buf)
                        }
                    }
                } catch (_: Exception) {}
            }
        }
        result.success(null)
    }

    fun handleLockContainer(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        if (uriString == null) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        if (volId != null) {
            val session = ContainerSessionRegistry.activeSessions[volId]
            ioExecutor.execute {
                try {
                    ContainerSessionRegistry.locks[volId].writeLock().withLock {
                        ContainerEngine.lock(volId)
                    }
                    if (session?.isUsbSource == true) {
                        UsbBlockBridge.unregister(volId)
                    }
                    ContainerSessionRegistry.removeSession(volId)
                    activity.runOnUiThread {
                        activity.contentResolver.notifyChange(
                            DocumentsContract.buildRootsUri(
                                "com.aeidolon.vaultexplorer.documents"), null)
                        result.success(true)
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
                }
            }
        } else {
            result.success(false)
        }
    }

    fun handleUpdateContainerSettings(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val displayName = call.argument<String>("displayName")
        val docProvider = call.argument<Boolean>("documentProvider") ?: false

        if (uriString == null) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        if (volId != null) {
            val session = ContainerSessionRegistry.activeSessions[volId]
            if (session != null) {
                session.displayName = displayName
                session.documentProvider = docProvider
                activity.contentResolver.notifyChange(
                    DocumentsContract.buildRootsUri(
                        "com.aeidolon.vaultexplorer.documents"), null)
                result.success(true)
            } else {
                result.success(false)
            }
        } else {
            result.success(false)
        }
    }
}