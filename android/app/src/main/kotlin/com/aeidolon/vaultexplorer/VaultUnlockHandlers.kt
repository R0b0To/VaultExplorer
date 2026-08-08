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
 * Parsed, validated arguments shared by [VaultUnlockHandlers.handleUnlockContainer]
 * and [UsbContainerHandlers.handleUnlockUsbContainer] (TD-17) -- password,
 * pim, display/mount options, cipher/hash hints, preserved-key, and keyfile
 * data. Deliberately does NOT include how the underlying container is
 * located or opened (a content:// [Uri] vs. a raw USB block device):
 * that part differs enough between the two handlers -- different native
 * engine calls, different pre-checks, different cleanup on failure -- that
 * folding it into this same abstraction would trade real, testable
 * behavior for a smaller diff.
 */
data class UnlockArgs(
    val password: String,
    val pim: Int,
    val displayName: String?,
    val docProvider: Boolean,
    val autoMountFolders: List<String>?,
    val cipherId: Int,
    val hashId: Int,
    val preservedKey: ByteArray?,
    val cacheDerivedKey: Boolean,
    val keyfilePaths: List<String>?,
    val readOnly: Boolean,
)

/**
 * Parses and validates the [UnlockArgs] common to both password-based
 * unlock handlers. On invalid input, calls `result.error(...)` itself
 * (matching this codebase's existing early-return convention) and returns
 * null -- callers should return immediately when this returns null.
 *
 * [sourceIdentifier] is the caller's own source-specific identifier
 * (`filePath` for file-backed containers, `deviceName` for USB) -- it's
 * passed in rather than parsed here because the two callers need it for
 * more than validation (registry lookup, session URI, derived-key storage
 * key), so parsing it twice would be worse than parsing it once at each
 * call site the way the original code already did.
 */
fun parseUnlockArgs(
    call: MethodCall,
    result: MethodChannel.Result,
    sourceIdentifier: String?,
    sourceIdentifierArgName: String,
): UnlockArgs? {
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

    if (sourceIdentifier == null || password == null) {
        result.error("INVALID_ARGS", "$sourceIdentifierArgName and password required", null)
        return null
    }
    if (password.isEmpty() && keyfilePaths.isNullOrEmpty() && preservedKey == null) {
        result.error("INVALID_ARGS", "password or keyfiles required", null)
        return null
    }

    return UnlockArgs(
        password = password,
        pim = pim,
        displayName = displayName,
        docProvider = docProvider,
        autoMountFolders = autoMountFolders,
        cipherId = cipherId,
        hashId = hashId,
        preservedKey = preservedKey,
        cacheDerivedKey = cacheDerivedKey,
        keyfilePaths = keyfilePaths,
        readOnly = readOnly,
    )
}

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
        val uriStringOrNull = call.argument<String>("filePath")
        val args = parseUnlockArgs(call, result, uriStringOrNull, "filePath") ?: return
        val uriString = uriStringOrNull!! // parseUnlockArgs already validated this is non-null

        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
            return
        }
        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))

        ioExecutor.execute {
            var pfd: ParcelFileDescriptor? = null
            try {
                val uri = Uri.parse(uriString)
                pfd = activity.contentResolver.openFileDescriptor(uri, "rw")
                    ?: throw Exception("Could not open file descriptor")

                val keyfileFds = nativeOps.openKeyfileFds(args.keyfilePaths)
                val fd = pfd.detachFd()

                if (args.preservedKey != null) {
                    Log.i("VaultExplorer_C++", "File unlock using preserved derived key (len=${args.preservedKey.size})")
                } else if (args.cacheDerivedKey) {
                    Log.i("VaultExplorer_C++", "File unlock will derive and cache a fresh key")
                }
                if (keyfileFds != null && keyfileFds.isNotEmpty()) {
                    Log.i("VaultExplorer_C++", "File unlock using ${keyfileFds.size} keyfile(s)")
                }

                val files = ContainerSessionRegistry.locks[targetVolId].writeLock().withLock {
                    ContainerEngine.unlockFile(fd, args.password, args.pim, targetVolId, args.cipherId, args.hashId, args.preservedKey, keyfileFds, args.readOnly)
                }

                activity.runOnUiThread {
                    if (files != null) {
                        ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                            uri = uriString,
                            volId = targetVolId,
                            cachedFilesList = files.toList(),
                            displayName = args.displayName,
                            documentProvider = args.docProvider,
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
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
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
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
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
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
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

    /**
     * Shared plumbing for the three folder-vault "change password" handlers
     * below: parses filePath/oldPassword/newPassword, runs [changePassword]
     * on [ioExecutor], and maps its [com.aeidolon.vaultexplorer.engine.VaultOpenResult]
     * onto the same AUTH_FAIL/INVALID_VAULT error-code contract the folder
     * vaults' unlock handlers already use (see e.g. [handleUnlockCryptomatorVault]),
     * so the Dart side's existing PlatformException handling covers this too.
     */
    private fun handleFolderVaultPasswordChange(
        call: MethodCall,
        result: MethodChannel.Result,
        changePassword: (uri: Uri, oldPassword: CharArray, newPassword: CharArray) -> com.aeidolon.vaultexplorer.engine.VaultOpenResult<Unit>,
    ) {
        val uriString = call.argument<String>("filePath")
        val oldPassword = call.argument<String>("oldPassword")
        val newPassword = call.argument<String>("newPassword")
        if (uriString == null || oldPassword == null || newPassword == null) {
            result.error("INVALID_ARGS", "filePath, oldPassword and newPassword required", null)
            return
        }
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val oldChars = oldPassword.toCharArray()
                val newChars = newPassword.toCharArray()
                val changeResult = try {
                    changePassword(uri, oldChars, newChars)
                } finally {
                    oldChars.fill('\u0000')
                    newChars.fill('\u0000')
                }
                activity.runOnUiThread {
                    when (changeResult) {
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success -> result.success(true)
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.WrongPassword -> {
                            result.error("AUTH_FAIL", "Incorrect password", null)
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault -> {
                            result.error("INVALID_VAULT", changeResult.reason, null)
                        }
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleChangeCryptomatorVaultPassword(call: MethodCall, result: MethodChannel.Result) {
        handleFolderVaultPasswordChange(call, result) { uri, oldPassword, newPassword ->
            com.aeidolon.vaultexplorer.cryptomator.CryptomatorVault.changePassword(activity, uri, oldPassword, newPassword)
        }
    }

    fun handleChangeGocryptfsVaultPassword(call: MethodCall, result: MethodChannel.Result) {
        handleFolderVaultPasswordChange(call, result) { uri, oldPassword, newPassword ->
            com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault.changePassword(activity, uri, oldPassword, newPassword)
        }
    }

    fun handleChangeCryfsVaultPassword(call: MethodCall, result: MethodChannel.Result) {
        handleFolderVaultPasswordChange(call, result) { uri, oldPassword, newPassword ->
            com.aeidolon.vaultexplorer.cryfs.CryfsVault.changePassword(activity, uri, oldPassword, newPassword)
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

    /** No PIM: LUKS has no PIM concept, unlike VeraCrypt's
     *  handleChangeContainerPassword above. Maps ContainerEngine
     *  .changeLuksPassword's tri-state result to the same AUTH_FAIL/
     *  INVALID_VAULT error-code contract the folder-vault change-password
     *  handlers use (see handleFolderVaultPasswordChange). */
    fun handleChangeLuksContainerPassword(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val oldPassword = call.argument<String>("oldPassword") ?: ""
        val newPassword = call.argument<String>("newPassword") ?: ""
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
                val outcome = ContainerEngine.changeLuksPassword(
                    pfd.detachFd(), oldPassword, newPassword, oldKfFds, newKfFds
                )
                activity.runOnUiThread {
                    when (outcome) {
                        0 -> result.success(true)
                        1 -> result.error("AUTH_FAIL", "Incorrect password", null)
                        else -> result.error("INVALID_VAULT", "Could not change the LUKS container's password", null)
                    }
                }
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