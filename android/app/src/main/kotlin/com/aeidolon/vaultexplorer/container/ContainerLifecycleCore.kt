package com.aeidolon.vaultexplorer.container

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import com.aeidolon.vaultexplorer.SafSplitResolver
import com.aeidolon.vaultexplorer.SplitFuseCallback
import com.aeidolon.vaultexplorer.SplitPartInfo
import com.aeidolon.vaultexplorer.UriNameResolver
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.bridge.UsbBlockBridge
import com.aeidolon.vaultexplorer.cryfs.CryfsVault
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorVault
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault
import com.aeidolon.vaultexplorer.handlers.DerivedKeyHandlers
import com.aeidolon.vaultexplorer.saf.UriToPath
import java.io.File
import kotlin.concurrent.withLock

/**
 * Format-agnostic-at-the-call-site lock/unlock logic shared by the
 * Flutter-facing handlers (VaultUnlockHandlers) and any headless caller,
 * such as the automation receiver, that needs the exact same
 * behaviour without a MethodChannel.Result to satisfy or a live Activity.
 */
object ContainerLifecycleCore {

    private const val TAG = "ContainerLifecycleCore"

    data class UnlockCoreResult(
        val volId: Int,
        val files: List<String>,
        val format: ContainerFormat,
        val matchedCipherId: Int,
        val matchedHashId: Int,
        val partCount: Int,
    )

    enum class AuthFailureCode {
        INCORRECT_PASSWORD_OR_INVALID_CONTAINER,
        INCORRECT_HIDDEN_VOLUME_CREDENTIALS,
        INCORRECT_PASSWORD,
    }

    sealed class UnlockCoreOutcome {
        data class Success(val result: UnlockCoreResult) : UnlockCoreOutcome()
        data class AuthFailure(val code: AuthFailureCode) : UnlockCoreOutcome()
        data class Error(val exception: Exception) : UnlockCoreOutcome()
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

    private fun getFileSize(context: Context, uri: Uri): Long {
        if (uri.scheme == "file" || uri.scheme == null) {
            val path = uri.path
            if (path != null) {
                val f = File(path)
                if (f.exists()) return f.length()
            }
        }
        var size: Long? = null
        try {
            context.contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_SIZE, OpenableColumns.SIZE),
                null, null, null,
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
                context.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                    val statSize = pfd.statSize
                    if (statSize > 0) size = statSize
                }
            } catch (_: Exception) {}
        }
        return size ?: 0L
    }

    /** Why a lock did or did not happen; [lockContainer] collapses this to a Boolean. */
    enum class LockOutcome {
        LOCKED,

        /** Not mounted at all, or a lock for this volume is already running. */
        NOT_LOCKED,

        /** USB device refused the final flush; the volume is still open and retryable. */
        FLUSH_REFUSED,

        /** Any other failure. */
        FAILED,
    }

    fun lockContainer(context: Context, uriString: String, force: Boolean = false): Boolean =
        lockContainerOutcome(context, uriString, force) == LockOutcome.LOCKED

    fun lockContainerOutcome(
        context: Context,
        uriString: String,
        force: Boolean = false,
    ): LockOutcome {
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString) ?: return LockOutcome.NOT_LOCKED
        val session = ContainerSessionRegistry.activeSessions[volId]
        val lockPermit = ContainerDocumentIoRegistry.beginLock(volId) ?: run {
            VeLog.w(TAG) { "lockContainer already pending for volId=$volId" }
            return LockOutcome.NOT_LOCKED
        }
        return try {
            if (lockPermit.handlesAtStart > 0) {
                VeLog.i(TAG) {
                    "lockContainer waiting for ${lockPermit.handlesAtStart} open document operation(s) on volId=$volId"
                }
            }
            lockPermit.awaitHandlesClosed()
            com.aeidolon.vaultexplorer.pdf.PdfRendererRegistry.closeAllForVolume(volId)
            com.aeidolon.vaultexplorer.pdf.VaultPdfSessionRegistry.revokeAllForVolume(volId)
            // Throws when the USB device refuses the final flush (and force is false): the
            // bridge and session below are then left in place so the lock can be retried.
            ContainerSessionRegistry.locks[volId].writeLock().withLock {
                ContainerEngine.lock(volId, force)
            }
            if (session?.isUsbSource == true) {
                UsbBlockBridge.unregister(volId)
            }
            ContainerSessionRegistry.removeSession(volId)
            context.contentResolver.notifyChange(
                DocumentsContract.buildRootsUri("com.aeidolon.vaultexplorer.documents"), null,
            )
            VeLog.i(TAG) {
                "lockContainer succeeded for volId=$volId, remaining active sessions=" +
                    "${ContainerSessionRegistry.activeSessions.keys.toList()}"
            }
            LockOutcome.LOCKED
        } catch (e: LockFlushRefusedException) {
            VeLog.w(TAG) { "lockContainer refused by device for volId=$volId; vault left open" }
            LockOutcome.FLUSH_REFUSED
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "lockContainer failed for ${censorUri(uriString)} (volId=$volId)" }
            LockOutcome.FAILED
        } finally {
            lockPermit.close()
        }
    }

    fun unlockContainer(
        context: Context,
        uriString: String,
        targetVolId: Int,
        password: String,
        pim: Int,
        cipherId: Int = 255,
        hashId: Int = 255,
        readOnly: Boolean = false,
        docProvider: Boolean = false,
        autoMountFolders: List<String>? = null,
        displayNameOverride: String? = null,
        preservedKey: ByteArray? = null,
        keyfileFds: IntArray? = null,
        protectHiddenVolume: Boolean = false,
        hiddenPassword: String? = null,
        hiddenPim: Int = 0,
        hiddenCipherId: Int = 255,
        hiddenHashId: Int = 255,
        hiddenKeyfileFds: IntArray? = null,
        cacheDerivedKey: Boolean = false,
        derivedKeyHandlers: DerivedKeyHandlers? = null,
        fuseHandler: Handler,
        useBackupHeader: Boolean = false,
    ): UnlockCoreOutcome {
        var pfd: ParcelFileDescriptor? = null
        var proxyPfd: ParcelFileDescriptor? = null
        return try {
            val uri = Uri.parse(uriString)
            val displayName = displayNameOverride ?: UriNameResolver.resolve(context.contentResolver, uri)
            VeLog.i(TAG) { "unlockContainer starting: uri=${censorUri(uriString)}, readOnly=$readOnly, volId=$targetVolId" }

            val parts = SafSplitResolver.resolveParts(context, uri, displayName)
                .ifEmpty {
                    val size = getFileSize(context, uri)
                    listOf(SplitPartInfo(uri, size))
                }
            val isSplit = parts.size > 1
            val singleUri = parts.firstOrNull()?.uri ?: uri
            val rawFile = if (isSplit) null else UriToPath.getRawFile(context, singleUri)?.takeIf { it.canRead() }
            // SAF providers often return descriptors that can be read but do
            // not support the random-access pwrite() calls made by the native
            // block layer. Route cloud/document-backed single files through
            // the same proxy as split containers; SplitFuseCallback can stage
            // an unsupported provider locally and upload the updated image on
            // fsync/release. Genuine local files keep the direct-fd fast path.
            val useSafProxy = isSplit || rawFile == null
            if (useSafProxy) {
                if (isSplit) {
                    VeLog.i(TAG) { "Auto-detected split container across ${parts.size} parts for ${censorUri(uriString)}" }
                } else {
                    VeLog.i(TAG) { "Using SAF proxy for single document container ${censorUri(uriString)}" }
                }
                val fuseCallback = SplitFuseCallback(
                    context = context,
                    parts = parts,
                    readOnly = readOnly,
                    onReleased = { ContainerSessionRegistry.removeSession(targetVolId) },
                )
                val storageManager = context.getSystemService(StorageManager::class.java)
                proxyPfd = try {
                    storageManager.openProxyFileDescriptor(
                        if (readOnly) ParcelFileDescriptor.MODE_READ_ONLY else ParcelFileDescriptor.MODE_READ_WRITE,
                        fuseCallback,
                        fuseHandler,
                    )
                } catch (e: Exception) {
                    VeLog.e(TAG, e) { "Failed to open proxy file descriptor for SAF container: ${e.message}" }
                    throw e
                }
                pfd = proxyPfd
            } else {
                pfd = ParcelFileDescriptor.open(
                    requireNotNull(rawFile),
                    if (readOnly) ParcelFileDescriptor.MODE_READ_ONLY else ParcelFileDescriptor.MODE_READ_WRITE,
                )
            }

            if (pfd == null) {
                val msg = "Could not open container file descriptor for ${censorUri(uriString)}"
                VeLog.e(TAG) { msg }
                throw Exception(msg)
            }

            val fd = pfd.detachFd()

            val files = ContainerSessionRegistry.locks[targetVolId].writeLock().withLock {
                ContainerEngine.unlockFile(
                    fd, password, pim, targetVolId, cipherId, hashId, preservedKey, keyfileFds, readOnly,
                    if (protectHiddenVolume) hiddenPassword ?: "" else null,
                    hiddenPim, hiddenCipherId, hiddenHashId, hiddenKeyfileFds,
                    useBackupHeader,
                )
            }

            if (files == null) {
                if (proxyPfd != null) runCatching { proxyPfd.close() }
                val failureCode = if (protectHiddenVolume)
                    AuthFailureCode.INCORRECT_HIDDEN_VOLUME_CREDENTIALS
                else
                    AuthFailureCode.INCORRECT_PASSWORD_OR_INVALID_CONTAINER
                VeLog.e(TAG) { "Native unlock failed (volId=$targetVolId): code=$failureCode (uri=${censorUri(uriString)})" }
                return UnlockCoreOutcome.AuthFailure(failureCode)
            }

            val computedDisplayName = when {
                !displayNameOverride.isNullOrEmpty() -> displayNameOverride
                isSplit -> {
                    val firstPartName = parts.first().file?.name ?: displayName
                    Regex("""^(.*)\.(\d+|part\d+)$""", RegexOption.IGNORE_CASE)
                        .find(firstPartName)?.groupValues?.get(1) ?: firstPartName
                }
                else -> null
            }
            val resolvedFormat = ContainerEngine.format(targetVolId)

            ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                uri = uriString,
                volId = targetVolId,
                cachedFilesList = files.toList(),
                displayName = computedDisplayName,
                documentProvider = docProvider,
                readOnly = readOnly,
                containerFormat = resolvedFormat,
            )
            ContainerSessionRegistry.applyAutoMountFolders(targetVolId, autoMountFolders)
            val hasFolderMounts = ContainerSessionRegistry.activeSessions[targetVolId]
                ?.subFolderMounts?.isNotEmpty() == true
            if (docProvider || hasFolderMounts) {
                context.contentResolver.notifyChange(
                    DocumentsContract.buildRootsUri("com.aeidolon.vaultexplorer.documents"), null,
                )
            }

            if (cacheDerivedKey && preservedKey == null && derivedKeyHandlers != null) {
                val derived = ContainerEngine.lastDerivedKeyMaterial(targetVolId)
                if (derived != null) derivedKeyHandlers.storeDerivedKeyBytes(uriString, derived)
            }

            VeLog.i(TAG) { "unlockContainer successful: volId=$targetVolId format=${resolvedFormat.wireName} files=${files.size}" }
            UnlockCoreOutcome.Success(
                UnlockCoreResult(
                    volId = targetVolId,
                    files = files.toList(),
                    format = resolvedFormat,
                    matchedCipherId = ContainerEngine.matchedCipherId(targetVolId),
                    matchedHashId = ContainerEngine.matchedHashId(targetVolId),
                    partCount = parts.size,
                )
            )
        } catch (e: Exception) {
            if (proxyPfd != null) runCatching { proxyPfd.close() }
            try { pfd?.close() } catch (_: Exception) {}
            VeLog.e(TAG, e) { "unlockContainer encountered exception for ${censorUri(uriString)} (volId=$targetVolId)" }
            UnlockCoreOutcome.Error(e)
        }
    }

    // ------------------------------------------------------------------
    // Directory-based vaults: Cryptomator / gocryptfs / CryFS
    // ------------------------------------------------------------------

    enum class DirectoryVaultFormat {
        CRYPTOMATOR, GOCRYPTFS, CRYFS;

        val wireName: String get() = when (this) {
            CRYPTOMATOR -> "cryptomator"
            GOCRYPTFS -> "gocryptfs"
            CRYFS -> "cryfs"
        }

        val asContainerFormat: ContainerFormat get() = when (this) {
            CRYPTOMATOR -> ContainerFormat.CRYPTOMATOR
            GOCRYPTFS -> ContainerFormat.GOCRYPTFS
            CRYFS -> ContainerFormat.CRYFS
        }
    }

    data class DirectoryVaultResult(
        val volId: Int,
        val files: List<String>,
        val format: DirectoryVaultFormat,
    )

    sealed class DirectoryVaultOutcome {
        data class Success(val result: DirectoryVaultResult) : DirectoryVaultOutcome()
        data class AuthFailure(val code: AuthFailureCode) : DirectoryVaultOutcome()
        data class InvalidVault(val reason: String) : DirectoryVaultOutcome()
        data class Error(val exception: Exception) : DirectoryVaultOutcome()
    }

    fun unlockDirectoryVault(
        context: Context,
        format: DirectoryVaultFormat,
        uriString: String,
        targetVolId: Int,
        password: String?,
        readOnly: Boolean = false,
        docProvider: Boolean = false,
        autoMountFolders: List<String>? = null,
        displayNameOverride: String? = null,
        preservedKey: ByteArray? = null,
        cacheDerivedKey: Boolean = false,
        derivedKeyHandlers: DerivedKeyHandlers? = null,
    ): DirectoryVaultOutcome {
        if (password.isNullOrEmpty() && preservedKey == null) {
            val err = IllegalArgumentException("password or preservedKey is required")
            VeLog.e(TAG, err) { "unlockDirectoryVault failed: missing credentials for ${censorUri(uriString)}" }
            return DirectoryVaultOutcome.Error(err)
        }
        return try {
            val uri = Uri.parse(uriString)
            VeLog.i(TAG) { "unlockDirectoryVault starting: format=$format, uri=${censorUri(uriString)}, volId=$targetVolId" }

            val openResult: VaultOpenResult<out com.aeidolon.vaultexplorer.container.VaultBackend> = when (format) {
                DirectoryVaultFormat.CRYPTOMATOR -> {
                    val chars = (password ?: "").toCharArray()
                    try {
                        CryptomatorVault.open(context, uri, chars, readOnly)
                    } finally {
                        chars.fill('\u0000')
                    }
                }
                DirectoryVaultFormat.GOCRYPTFS -> {
                    val chars = (password ?: "").toCharArray()
                    try {
                        GocryptfsVault.open(context, uri, chars, readOnly)
                    } finally {
                        chars.fill('\u0000')
                    }
                }
                DirectoryVaultFormat.CRYFS -> if (preservedKey != null) {
                    CryfsVault.openWithCombinedKey(context, uri, preservedKey, readOnly)
                } else {
                    val chars = (password ?: "").toCharArray()
                    try {
                        CryfsVault.open(context, uri, chars, readOnly)
                    } finally {
                        chars.fill('\u0000')
                    }
                }
            }

            when (openResult) {
                is VaultOpenResult.Success -> {
                    val session = openResult.session
                    val files = session.listDirectory("")?.toList() ?: emptyList()
                    VaultBackendRegistry.put(targetVolId, session)
                    ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                        uri = uriString,
                        volId = targetVolId,
                        cachedFilesList = files,
                        displayName = displayNameOverride ?: openResult.vaultDisplayName,
                        documentProvider = docProvider,
                        readOnly = readOnly,
                        containerFormat = format.asContainerFormat,
                    )
                    ContainerSessionRegistry.applyAutoMountFolders(targetVolId, autoMountFolders)
                    val hasFolderMounts = ContainerSessionRegistry.activeSessions[targetVolId]
                        ?.subFolderMounts?.isNotEmpty() == true
                    if (docProvider || hasFolderMounts) {
                        context.contentResolver.notifyChange(
                            DocumentsContract.buildRootsUri("com.aeidolon.vaultexplorer.documents"), null,
                        )
                    }
                    if (format == DirectoryVaultFormat.CRYFS && cacheDerivedKey && preservedKey == null &&
                        derivedKeyHandlers != null
                    ) {
                        openResult.derivedKey?.let { derivedKeyHandlers.storeDerivedKeyBytes(uriString, it) }
                    }
                    VeLog.i(TAG) { "unlockDirectoryVault successful: format=$format volId=$targetVolId files=${files.size}" }
                    DirectoryVaultOutcome.Success(DirectoryVaultResult(targetVolId, files, format))
                }
                is VaultOpenResult.WrongPassword -> {
                    VeLog.e(TAG) { "unlockDirectoryVault failed: Incorrect password for $format vault (${censorUri(uriString)})" }
                    DirectoryVaultOutcome.AuthFailure(AuthFailureCode.INCORRECT_PASSWORD)
                }
                is VaultOpenResult.InvalidVault -> {
                    VeLog.e(TAG) { "unlockDirectoryVault failed: Invalid $format vault (${openResult.reason}) for ${censorUri(uriString)}" }
                    DirectoryVaultOutcome.InvalidVault(openResult.reason)
                }
            }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "unlockDirectoryVault failed with exception for $format (${censorUri(uriString)})" }
            DirectoryVaultOutcome.Error(e)
        }
    }
}
