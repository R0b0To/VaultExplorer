package com.aeidolon.vaultexplorer.container

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import com.aeidolon.vaultexplorer.SafSplitResolver
import com.aeidolon.vaultexplorer.SplitFuseCallback
import com.aeidolon.vaultexplorer.SplitPartInfo
import com.aeidolon.vaultexplorer.UriNameResolver
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
 *
 * This is a mechanical extraction of what handleLockContainer /
 * handleUnlockContainer already did -- same SAF/split resolution, same
 * native calls, same ContainerSessionRegistry bookkeeping -- with every
 * Dart-specific concern (the onUnlockStarted progress event, building the
 * Flutter result map, MethodChannel.Result error codes, hopping to the UI
 * thread) left in the thin wrappers that call this. Safe to call from any
 * background thread; does not itself touch the UI thread.
 *
 * Scope note: this only covers standard block-device containers (VeraCrypt
 * / LUKS / BitLocker / VHD-VHDX) reached via handleUnlockContainer. The
 * three pure-Kotlin directory-vault formats (Cryptomator, gocryptfs, CryFS)
 * and USB containers go through separate handler functions
 * (handleUnlockCryptomatorVault etc., ContainerEngine.unlockUsb) that
 * are not yet extracted here.
 */
object ContainerLifecycleCore {

    data class UnlockCoreResult(
        val volId: Int,
        val files: List<String>,
        val format: ContainerFormat,
        val matchedCipherId: Int,
        val matchedHashId: Int,
        val partCount: Int,
    )

    sealed class UnlockCoreOutcome {
        data class Success(val result: UnlockCoreResult) : UnlockCoreOutcome()
        data class AuthFailure(val message: String) : UnlockCoreOutcome()
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

    /**
     * Locks whichever volume [uriString] is currently mounted at, if any.
     * Returns false if it wasn't mounted; throws never -- exceptions are
     * caught and reported as false so an automation LOCK_VAULT can't wedge a
     * task chain on a container that was already locked from elsewhere.
     */
    fun lockContainer(context: Context, uriString: String): Boolean {
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString) ?: return false
        val session = ContainerSessionRegistry.activeSessions[volId]
        return try {
            com.aeidolon.vaultexplorer.pdf.PdfRendererRegistry.closeAllForVolume(volId)
            com.aeidolon.vaultexplorer.pdf.VaultPdfSessionRegistry.revokeAllForVolume(volId)
            ContainerSessionRegistry.locks[volId].writeLock().withLock {
                ContainerEngine.lock(volId)
            }
            if (session?.isUsbSource == true) {
                UsbBlockBridge.unregister(volId)
            }
            ContainerSessionRegistry.removeSession(volId)
            context.contentResolver.notifyChange(
                DocumentsContract.buildRootsUri("com.aeidolon.vaultexplorer.documents"), null,
            )
            true
        } catch (e: Exception) {
            Log.e("VaultExplorer_Automation", "lockContainer failed for ${censorUri(uriString)}", e)
            false
        }
    }

    /**
     * Unlocks a standard block-device container at [uriString] into
     * [targetVolId] (caller resolves the slot up front via
     * ContainerSessionRegistry.getVolumeIdByUri/getFreeVolumeId, exactly as
     * handleUnlockContainer already did -- kept as a caller responsibility
     * here rather than re-resolved internally, so a caller that needs to
     * fire an early progress event with the volId before doing the actual
     * unlock work -- as Dart's onUnlockStarted event does -- can't race
     * against a second, independent slot resolution inside this function).
     *
     * hiddenPassword/hidden* and keyfileFds/hiddenKeyfileFds are passed
     * through unchanged for Dart's benefit (existing in-app unlock already
     * supports both). The automation receiver deliberately never populates
     * the hidden-volume fields: automation credentials sit in on-device
     * storage for unattended use, and wiring a stored password to unlock a
     * hidden volume undercuts the plausible-deniability model hidden
     * volumes exist for. It doesn't populate keyfileFds either, since
     * automation has no interactive picker to source them from in v1.
     */
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
    ): UnlockCoreOutcome {
        var pfd: ParcelFileDescriptor? = null
        var proxyPfd: ParcelFileDescriptor? = null
        return try {
            val uri = Uri.parse(uriString)
            val displayName = displayNameOverride ?: UriNameResolver.resolve(context.contentResolver, uri)
            Log.i("VaultExplorer_SAF", "unlockContainer starting: uri=${censorUri(uriString)}, readOnly=$readOnly")

            val parts = SafSplitResolver.resolveParts(context, uri, displayName)
                .ifEmpty {
                    val size = getFileSize(context, uri)
                    listOf(SplitPartInfo(uri, size))
                }
            val isSplit = parts.size > 1
            if (isSplit) {
                Log.i("VaultExplorer_C++", "Auto-detected split container across ${parts.size} parts")
                val fuseCallback = SplitFuseCallback(
                    context = context,
                    parts = parts,
                    readOnly = readOnly,
                    onReleased = { ContainerSessionRegistry.removeSession(targetVolId) },
                )
                val storageManager = context.getSystemService(StorageManager::class.java)
                proxyPfd = storageManager.openProxyFileDescriptor(
                    if (readOnly) ParcelFileDescriptor.MODE_READ_ONLY else ParcelFileDescriptor.MODE_READ_WRITE,
                    fuseCallback,
                    fuseHandler,
                )
                pfd = proxyPfd
            } else {
                val singleUri = parts.firstOrNull()?.uri ?: uri
                val rawFile = UriToPath.getRawFile(context, singleUri)
                pfd = if (rawFile != null && rawFile.canRead()) {
                    ParcelFileDescriptor.open(
                        rawFile,
                        if (readOnly) ParcelFileDescriptor.MODE_READ_ONLY else ParcelFileDescriptor.MODE_READ_WRITE,
                    )
                } else {
                    val mode = if (readOnly) "r" else "rw"
                    try {
                        context.contentResolver.openFileDescriptor(singleUri, mode)
                    } catch (e: Exception) {
                        if (mode == "rw") context.contentResolver.openFileDescriptor(singleUri, "r") else throw e
                    }
                }
            }

            val fd = (pfd ?: throw Exception("Could not open container file descriptor")).detachFd()

            val files = ContainerSessionRegistry.locks[targetVolId].writeLock().withLock {
                ContainerEngine.unlockFile(
                    fd, password, pim, targetVolId, cipherId, hashId, preservedKey, keyfileFds, readOnly,
                    if (protectHiddenVolume) hiddenPassword ?: "" else null,
                    hiddenPim, hiddenCipherId, hiddenHashId, hiddenKeyfileFds,
                )
            }

            if (files == null) {
                if (proxyPfd != null) runCatching { proxyPfd.close() }
                return UnlockCoreOutcome.AuthFailure(
                    if (protectHiddenVolume)
                        "Incorrect password/keyfiles, or the hidden volume password/keyfiles did not match"
                    else
                        "Incorrect password/keyfiles or invalid container"
                )
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

            ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                uri = uriString,
                volId = targetVolId,
                cachedFilesList = files.toList(),
                displayName = computedDisplayName,
                documentProvider = docProvider,
                readOnly = readOnly,
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

            UnlockCoreOutcome.Success(
                UnlockCoreResult(
                    volId = targetVolId,
                    files = files.toList(),
                    format = ContainerEngine.format(targetVolId),
                    matchedCipherId = ContainerEngine.matchedCipherId(targetVolId),
                    matchedHashId = ContainerEngine.matchedHashId(targetVolId),
                    partCount = parts.size,
                )
            )
        } catch (e: Exception) {
            if (proxyPfd != null) runCatching { proxyPfd.close() }
            try { pfd?.close() } catch (_: Exception) {}
            Log.e("VaultExplorer_Automation", "unlockContainer failed for ${censorUri(uriString)}", e)
            UnlockCoreOutcome.Error(e)
        }
    }

    // ------------------------------------------------------------------
    // Directory-based vaults: Cryptomator / gocryptfs / CryFS
    // ------------------------------------------------------------------

    enum class DirectoryVaultFormat {
        CRYPTOMATOR, GOCRYPTFS, CRYFS;

        // Mirrors ContainerFormat.wireName above. Single source of truth for
        // the enum->wire direction -- AutomationSettingsHandlers.directoryFormatToWire
        // used to duplicate this mapping privately; it now delegates here.
        val wireName: String get() = when (this) {
            CRYPTOMATOR -> "cryptomator"
            GOCRYPTFS -> "gocryptfs"
            CRYFS -> "cryfs"
        }
    }

    data class DirectoryVaultResult(
        val volId: Int,
        val files: List<String>,
        val format: DirectoryVaultFormat,
    )

    sealed class DirectoryVaultOutcome {
        data class Success(val result: DirectoryVaultResult) : DirectoryVaultOutcome()
        data class AuthFailure(val message: String) : DirectoryVaultOutcome()
        data class InvalidVault(val reason: String) : DirectoryVaultOutcome()
        data class Error(val exception: Exception) : DirectoryVaultOutcome()
    }

    /**
     * Shared unlock path for the three pure-Kotlin directory-vault formats,
     * used by both handleUnlockCryptomatorVault/GocryptfsVault/CryfsVault
     * and headless callers such as the automation receiver. All three
     * backends share the same open() contract -- (Context, Uri, CharArray
     * password, Boolean readOnly) -> VaultOpenResult<out VaultBackend> --
     * and the exact same post-open session registration
     * (VaultBackendRegistry.put + ContainerSessionRegistry bookkeeping),
     * so this is one function instead of three near-identical copies.
     *
     * As with unlockContainer above, callers on a UI/Flutter path own
     * anything Dart-specific (MethodChannel.Result dispatch, hopping to
     * the main thread); this function does none of that.
     *
     * [preservedKey]/[cacheDerivedKey] only apply to CRYFS -- the only one
     * of the three with a combined-key fast-unlock path today -- and are
     * silently ignored for the other two formats, matching what their
     * existing handlers already do (neither ever accepted those params).
     * targetVolId is a caller-resolved parameter for the same reason it is
     * in unlockContainer: to avoid a second, independent slot resolution
     * racing the one a caller may have already used to fire an early
     * progress event.
     */
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
            return DirectoryVaultOutcome.Error(IllegalArgumentException("password or preservedKey is required"))
        }
        return try {
            val uri = Uri.parse(uriString)
            Log.i("VaultExplorer_SAF", "unlockDirectoryVault starting: format=$format, uri=${censorUri(uriString)}")

            val openResult: VaultOpenResult<out VaultBackend> = when (format) {
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
                    DirectoryVaultOutcome.Success(DirectoryVaultResult(targetVolId, files, format))
                }
                is VaultOpenResult.WrongPassword -> DirectoryVaultOutcome.AuthFailure("Incorrect password")
                is VaultOpenResult.InvalidVault -> DirectoryVaultOutcome.InvalidVault(openResult.reason)
            }
        } catch (e: Exception) {
            Log.e("VaultExplorer_Automation", "unlockDirectoryVault failed for ${censorUri(uriString)}", e)
            DirectoryVaultOutcome.Error(e)
        }
    }
}