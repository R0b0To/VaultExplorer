package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Base64
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.UriToPath
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import kotlin.concurrent.withLock
import com.aeidolon.vaultexplorer.bridge.UsbBlockBridge
import com.aeidolon.vaultexplorer.container.ContainerEngine
import com.aeidolon.vaultexplorer.container.ContainerLifecycleCore
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.container.ContainerSession
import com.aeidolon.vaultexplorer.container.VaultBackendRegistry
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.SafSplitResolver
import com.aeidolon.vaultexplorer.SplitFuseCallback
import com.aeidolon.vaultexplorer.SplitPartInfo
import com.aeidolon.vaultexplorer.UriNameResolver
import com.aeidolon.vaultexplorer.VeLog

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
    val protectHiddenVolume: Boolean,
    val hiddenPassword: String?,
    val hiddenPim: Int,
    val hiddenCipherId: Int,
    val hiddenHashId: Int,
    val hiddenKeyfilePaths: List<String>?,
)

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
        VeLog.i("VaultExplorer_C++") { "Unlock request is using preserved key" }
    }
    val cacheDerivedKey = call.argument<Boolean>("cacheDerivedKey") ?: false
    val keyfilePaths = call.argument<List<String>>("keyfilePaths")
    val readOnly = call.argument<Boolean>("readOnly") ?: false
    val protectHiddenVolume = call.argument<Boolean>("protectHiddenVolume") ?: false
    val hiddenPassword = call.argument<String>("hiddenVolumePassword")
    val hiddenPim = call.argument<Number>("hiddenVolumePim")?.toInt() ?: 0
    val hiddenCipherId = call.argument<Number>("hiddenVolumeCipherId")?.toInt() ?: 255
    val hiddenHashId = call.argument<Number>("hiddenVolumeHashId")?.toInt() ?: 255
    val hiddenKeyfilePaths = call.argument<List<String>>("hiddenVolumeKeyfilePaths")

    if (sourceIdentifier == null || password == null) {
        result.error("INVALID_ARGS", "$sourceIdentifierArgName and password required", null)
        return null
    }
    if (password.isEmpty() && keyfilePaths.isNullOrEmpty() && preservedKey == null) {
        result.error("INVALID_ARGS", "password or keyfiles required", null)
        return null
    }
    if (protectHiddenVolume && hiddenPassword.isNullOrEmpty() && hiddenKeyfilePaths.isNullOrEmpty()) {
        result.error("INVALID_ARGS", "hidden volume password or keyfiles required to protect it", null)
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
        protectHiddenVolume = protectHiddenVolume,
        hiddenPassword = hiddenPassword,
        hiddenPim = hiddenPim,
        hiddenCipherId = hiddenCipherId,
        hiddenHashId = hiddenHashId,
        hiddenKeyfilePaths = hiddenKeyfilePaths,
    )
}

class VaultUnlockHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
    private val derivedKeyHandlers: DerivedKeyHandlers,
) {
    private val fuseThread = HandlerThread("split-container-fuse").apply { start() }
    private val fuseHandler = Handler(fuseThread.looper)

    private fun displayNameForSplit(fileName: String): String =
        Regex("""^(.*)\.(\d+|part\d+)$""", RegexOption.IGNORE_CASE)
            .find(fileName)?.groupValues?.get(1) ?: fileName

    private fun getFileSize(uri: Uri): Long {
        if (uri.scheme == "file" || uri.scheme == null) {
            val path = uri.path
            if (path != null) {
                val f = File(path)
                if (f.exists()) return f.length()
            }
        }
        var size: Long? = null
        try {
            activity.contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_SIZE, OpenableColumns.SIZE),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val colIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                        .takeIf { it >= 0 }
                        ?: cursor.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }
                    if (colIdx != null && !cursor.isNull(colIdx)) {
                        size = cursor.getLong(colIdx)
                    }
                }
            }
        } catch (_: Exception) {}

        if (size == null || size!! <= 0L) {
            try {
                activity.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                    val statSize = pfd.statSize
                    if (statSize > 0) size = statSize
                }
            } catch (_: Exception) {}
        }
        return size ?: 0L
    }

    fun onActivityDestroyed() {
        fuseThread.quitSafely()
    }

    private fun censorUri(rawUri: String?): String {
        if (rawUri.isNullOrEmpty()) return "<null>"
        if (rawUri.startsWith("content://")) {
            return try {
                val u = Uri.parse(rawUri)
                val authority = u.authority ?: "unknown"
                val lastPath = u.lastPathSegment ?: ""
                val ext = if (lastPath.contains(".")) "." + lastPath.substringAfterLast(".") else ""
                val isTree = rawUri.contains("/tree/")
                val isDoc = rawUri.contains("/document/")
                val kind = if (isTree && isDoc) "tree+doc" else if (isTree) "tree" else "doc"
                "content://$authority/[$kind${if (ext.isNotEmpty()) "*$ext" else ""}]"
            } catch (_: Exception) {
                "content://[REDACTED_URI]"
            }
        }
        val ext = if (rawUri.contains(".")) "." + rawUri.substringAfterLast(".") else ""
        return "file://[path]/***$ext"
    }

    private fun censorName(name: String?): String {
        if (name.isNullOrEmpty()) return "<null>"
        val ext = if (name.contains(".")) "." + name.substringAfterLast(".") else ""
        return "***$ext"
    }

    fun handleUnlockContainer(call: MethodCall, result: MethodChannel.Result) {
        val uriStringOrNull = call.argument<String>("filePath")
        val args = parseUnlockArgs(call, result, uriStringOrNull, "filePath") ?: return
        val uriString = uriStringOrNull!!
        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
            return
        }
        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))
        ioExecutor.execute {
            val keyfileFds = nativeOps.openKeyfileFds(args.keyfilePaths)
            val hiddenKeyfileFds =
                if (args.protectHiddenVolume) nativeOps.openKeyfileFds(args.hiddenKeyfilePaths) else null
            val outcome = ContainerLifecycleCore.unlockContainer(
                context = activity,
                uriString = uriString,
                targetVolId = targetVolId,
                password = args.password,
                pim = args.pim,
                cipherId = args.cipherId,
                hashId = args.hashId,
                readOnly = args.readOnly,
                docProvider = args.docProvider,
                autoMountFolders = args.autoMountFolders,
                displayNameOverride = args.displayName,
                preservedKey = args.preservedKey,
                keyfileFds = keyfileFds,
                protectHiddenVolume = args.protectHiddenVolume,
                hiddenPassword = args.hiddenPassword,
                hiddenPim = args.hiddenPim,
                hiddenCipherId = args.hiddenCipherId,
                hiddenHashId = args.hiddenHashId,
                hiddenKeyfileFds = hiddenKeyfileFds,
                cacheDerivedKey = args.cacheDerivedKey,
                derivedKeyHandlers = derivedKeyHandlers,
                fuseHandler = fuseHandler,
            )
            activity.runOnUiThread {
                when (outcome) {
                    is ContainerLifecycleCore.UnlockCoreOutcome.Success -> {
                        val r = outcome.result
                        val resultMap = mutableMapOf<String, Any>(
                            "volId" to r.volId,
                            "files" to r.files,
                            "matchedCipherId" to r.matchedCipherId,
                            "matchedHashId" to r.matchedHashId,
                            "containerFormat" to r.format.wireName,
                        )
                        if (r.partCount > 1) {
                            resultMap["partCount"] = r.partCount
                        }
                        result.success(resultMap)
                    }
                    is ContainerLifecycleCore.UnlockCoreOutcome.AuthFailure ->
                        result.error("AUTH_FAIL", outcome.message, null)
                    is ContainerLifecycleCore.UnlockCoreOutcome.Error ->
                        nativeOps.dispatchNativeError(outcome.exception, result)
                }
            }
        }
    }

    fun handleUnlockCryptomatorVault(call: MethodCall, result: MethodChannel.Result) {
        handleUnlockDirectoryVault(
            call, result, ContainerLifecycleCore.DirectoryVaultFormat.CRYPTOMATOR, "cryptomator",
        )
    }

    fun handleUnlockGocryptfsVault(call: MethodCall, result: MethodChannel.Result) {
        handleUnlockDirectoryVault(
            call, result, ContainerLifecycleCore.DirectoryVaultFormat.GOCRYPTFS, "gocryptfs",
        )
    }

    fun handleUnlockCryfsVault(call: MethodCall, result: MethodChannel.Result) {
        val preservedKeyBase64 = call.argument<String>("preservedKey")
        val preservedKey = preservedKeyBase64?.let { Base64.decode(it, Base64.NO_WRAP) }
        val cacheDerivedKey = call.argument<Boolean>("cacheDerivedKey") ?: false
        handleUnlockDirectoryVault(
            call, result, ContainerLifecycleCore.DirectoryVaultFormat.CRYFS, "cryfs",
            preservedKey = preservedKey, cacheDerivedKey = cacheDerivedKey,
        )
    }

    /**
     * Shared body for the three handleUnlock*Vault entry points above --
     * they differ only in which format they pass, the wire-format string
     * Dart expects back, and (CryFS only) preservedKey/cacheDerivedKey.
     * All argument parsing, MAX_CONTAINERS/slot resolution, the
     * onUnlockStarted progress event, and result-map/error-code shape are
     * unchanged from what each of the three used to do individually.
     */
    private fun handleUnlockDirectoryVault(
        call: MethodCall,
        result: MethodChannel.Result,
        format: ContainerLifecycleCore.DirectoryVaultFormat,
        wireFormatName: String,
        preservedKey: ByteArray? = null,
        cacheDerivedKey: Boolean = false,
    ) {
        val uriString = call.argument<String>("filePath")
        val password = call.argument<String>("password")
        val displayName = call.argument<String>("displayName")
        val docProvider = call.argument<Boolean>("documentProvider") ?: false
        val autoMountFolders = call.argument<List<String>>("autoMountFolders")
        val readOnly = call.argument<Boolean>("readOnly") ?: false
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
            val outcome = ContainerLifecycleCore.unlockDirectoryVault(
                context = activity,
                format = format,
                uriString = uriString,
                targetVolId = targetVolId,
                password = password,
                readOnly = readOnly,
                docProvider = docProvider,
                autoMountFolders = autoMountFolders,
                displayNameOverride = displayName,
                preservedKey = preservedKey,
                cacheDerivedKey = cacheDerivedKey,
                derivedKeyHandlers = derivedKeyHandlers,
            )
            activity.runOnUiThread {
                when (outcome) {
                    is ContainerLifecycleCore.DirectoryVaultOutcome.Success -> {
                        val r = outcome.result
                        result.success(
                            mapOf(
                                "volId" to r.volId,
                                "files" to r.files,
                                "matchedCipherId" to 255,
                                "matchedHashId" to 255,
                                "containerFormat" to wireFormatName,
                            )
                        )
                    }
                    is ContainerLifecycleCore.DirectoryVaultOutcome.AuthFailure ->
                        result.error("AUTH_FAIL", outcome.message, null)
                    is ContainerLifecycleCore.DirectoryVaultOutcome.InvalidVault ->
                        result.error("INVALID_VAULT", outcome.reason, null)
                    is ContainerLifecycleCore.DirectoryVaultOutcome.Error ->
                        nativeOps.dispatchNativeError(outcome.exception, result)
                }
            }
        }
    }

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

    /** Commits a buffered [ContainerEngine.writeFileChunk] sequence for
     *  whichever backend is registered for [volId] (Cryptomator, gocryptfs,
     *  or CryFS) -- see [ContainerEngine.finishWrite]'s doc comment. Safe to
     *  call unconditionally; a no-op for VeraCrypt/LUKS/BitLocker. */
    fun handleFinishWrite(call: MethodCall, result: MethodChannel.Result) {
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
                VeLog.w("VaultExplorer_SAF") { "handleDocumentExists threw exception for uri=${censorUri(filePath)}: ${e.message}" }
                false
            }
            VeLog.i("VaultExplorer_SAF") { "handleDocumentExists: uri=${censorUri(filePath)} => exists=$exists" }
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
        ioExecutor.execute {
            try {
                val locked = ContainerLifecycleCore.lockContainer(activity, uriString)
                activity.runOnUiThread { result.success(locked) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    /**
     * Ground-truth reconciliation: returns every container session
     * currently active, regardless of what mounted or unmounted it --
     * a normal in-app unlock/lock, VaultAutomationReceiver's UNLOCK_VAULT
     * (Tasker/MacroDroid, which can run with no Activity and so no
     * Flutter engine at all), or VaultKeepAliveService's "Lock all
     * vaults" notification action (same headless situation, opposite
     * direction). VaultAutomationUnlockedBridge/VaultForceLockedBridge
     * only cover the case a Flutter engine happens to already be
     * attached when one of those fires; VaultDashboardScreen calls this
     * on init and on every app resume to catch whatever those missed.
     *
     * Synchronous and UI-thread-safe to call directly (no ioExecutor hop)
     * -- activeSessions is a ConcurrentHashMap and this only reads it,
     * same as the quick getters elsewhere in this file
     * (handleUpdateContainerSettings et al).
     */
    fun handleGetActiveContainerSessions(call: MethodCall, result: MethodChannel.Result) {
        val sessions = ContainerSessionRegistry.activeSessions.map { (volId, session) ->
            val displayName = session.displayName
                ?: runCatching { UriNameResolver.resolve(activity.contentResolver, Uri.parse(session.uri)) }
                    .getOrDefault(session.uri)
            mapOf(
                "volId" to volId,
                "uri" to session.uri,
                "displayName" to displayName,
                "containerFormat" to (session.containerFormat?.wireName ?: "unknown"),
                "readOnly" to session.readOnly,
                "files" to session.cachedFilesList,
            )
        }
        result.success(mapOf("sessions" to sessions))
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