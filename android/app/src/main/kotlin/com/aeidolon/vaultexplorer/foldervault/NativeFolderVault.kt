package com.aeidolon.vaultexplorer.foldervault

import com.aeidolon.vaultexplorer.NativeEngine

/**
 * JNI surface of the native folder-vault core (cpp/foldervault, bridged by
 * cpp/jni/foldervault_bridge.cpp). All format logic -- gocryptfs, Cryptomator
 * and CryFS -- runs natively; Kotlin only decides *where* a vault's files live
 * (raw path vs. SAF/mirror, see [FolderVaultStorage]) and adapts the result to
 * [com.aeidolon.vaultexplorer.container.VaultBackend].
 *
 * Session functions take the handle returned by [nativeOpen]. A stale or
 * closed handle simply makes them fail (false / null / -1), never crash.
 */
internal object NativeFolderVault {
    const val GOCRYPTFS = 0
    const val CRYPTOMATOR = 1
    const val CRYFS = 2

    /** [nativeOpen] result: CryFS vault is in single-client mode for another device; needs the user's consent. */
    const val SINGLE_CLIENT_MODE = -2L

    /** Error code Dart receives (instead of INVALID_VAULT) for [SINGLE_CLIENT_MODE]. */
    const val CODE_SINGLE_CLIENT_MODE = "SINGLE_CLIENT_MODE"

    // Result codes of nativeCreate / nativeChangePassword.
    const val STATUS_OK = 0
    const val STATUS_WRONG_PASSWORD = 1
    const val STATUS_INVALID = 2

    val isAvailable: Boolean = NativeEngine.isLoaded && try {
        nativeInit()
        true
    } catch (_: UnsatisfiedLinkError) {
        false
    }

    @JvmStatic external fun nativeInit()

    /**
     * Exactly one of [rawRoot] (a verified local directory; the core does all
     * I/O itself) or [bootstrap] (callbacks) locates the vault for the unlock
     * step. If [sessionProvider] is set it is asked, after the password has
     * been verified, for the storage the session will actually run on (the SAF
     * mirror is only worth building once the password is known to be right).
     *
     * Returns a handle > 0, 0 for "not a valid vault", -1 for "wrong password", [SINGLE_CLIENT_MODE] when a
     * CryFS vault is locked to another device and the user has not yet agreed (see [disableSingleClientMode]).
     * out[0] receives the failure message, out[1] the CryFS derived key.
     *
     * [backupKeyFiles] only matters for Cryptomator (the `.bkup` copies of the key files on a read-write
     * unlock); the other formats ignore it.
     *
     * [disableSingleClientMode] only matters for CryFS read-write opens: the user agreed to remove the
     * "single-client mode" lock another device put on the vault (official CryFS asks the same question).
     */
    @JvmStatic external fun nativeOpen(
        format: Int, rawRoot: String?, bootstrap: FolderVaultStorage?,
        sessionProvider: FolderVaultSessionProvider?, password: ByteArray, readOnly: Boolean,
        backupKeyFiles: Boolean, disableSingleClientMode: Boolean, localStateDir: String, tempDir: String,
        combinedKey: ByteArray?, out: Array<Any?>,
    ): Long

    /**
     * Writes a new vault's skeleton. [options]: gocryptfs = [cipher 0=GCM 1=XChaCha
     * 2=AES-SIV, plaintextNames 0/1, deterministicNames 0/1 (gocryptfs
     * -deterministic-names), longNameMax 0 or 62..255 (gocryptfs -longnamemax)] --
     * the last two may be omitted; cryfs = [blocksizeBytes, 0].
     */
    @JvmStatic external fun nativeCreate(
        format: Int, rawRoot: String?, storage: FolderVaultStorage?, password: ByteArray,
        options: IntArray, cipherName: String?, localStateDir: String, tempDir: String,
        userEntropy: ByteArray?, out: Array<Any?>,
    ): Int

    @JvmStatic external fun nativeChangePassword(
        format: Int, rawRoot: String?, storage: FolderVaultStorage?,
        oldPassword: ByteArray, newPassword: ByteArray, out: Array<Any?>,
    ): Int

    /** Cryptomator format 7 -> 8, one way. Result codes as [nativeChangePassword]. */
    @JvmStatic external fun nativeMigrateCryptomator(
        rawRoot: String?, storage: FolderVaultStorage?, password: ByteArray, out: Array<Any?>,
    ): Int

    /**
     * Password-free format check of a Cryptomator folder: 0 unknown, 7 format 7 (migratable), 8 current,
     * -8 key file says 8+ but vault.cryptomator is missing (not synced yet; never migrate), 6 older than 7.
     */
    @JvmStatic external fun nativeProbeCryptomator(rawRoot: String?, storage: FolderVaultStorage?): Int

    @JvmStatic external fun nativeClose(handle: Long)
    @JvmStatic external fun nativeListDirectory(handle: Long, path: String): Array<String>?
    // Symlinks (Cryptomator). Deliberately not part of nativeListDirectory: the entries come back in the same
    // wire shape with kind "L" and only callers that know how to present one ask for them.
    @JvmStatic external fun nativeListSymlinks(handle: Long, path: String): Array<String>?
    @JvmStatic external fun nativeReadSymlink(handle: Long, path: String): String?
    @JvmStatic external fun nativeCreateSymlink(handle: Long, path: String, target: String): Boolean
    /** Entries that exist on disk but are not listed (sync-conflict copies, undecryptable names). -1 = unknown. */
    @JvmStatic external fun nativeHiddenEntryCount(handle: Long, path: String): Int
    @JvmStatic external fun nativeCreateDirectory(handle: Long, path: String): Boolean
    @JvmStatic external fun nativeDeleteFile(handle: Long, path: String): Boolean
    @JvmStatic external fun nativeFinishWrite(handle: Long, path: String): Boolean
    @JvmStatic external fun nativeRenameFile(handle: Long, from: String, to: String): Boolean
    @JvmStatic external fun nativeSetLastModified(handle: Long, path: String, epochSeconds: Long): Boolean
    @JvmStatic external fun nativeGetFileSize(handle: Long, path: String): Long
    @JvmStatic external fun nativeGetFolderSize(handle: Long, path: String): Long
    @JvmStatic external fun nativeReadFileChunk(handle: Long, path: String, offset: Long, length: Int): ByteArray?
    @JvmStatic external fun nativeWriteFileChunk(handle: Long, path: String, offset: Long, data: ByteArray): Boolean
    @JvmStatic external fun nativeWriteBackFile(handle: Long, path: String, sourcePath: String, opId: Int, singlePass: Boolean): Boolean
    @JvmStatic external fun nativeImportStream(handle: Long, path: String, input: java.io.InputStream): Boolean
    @JvmStatic external fun nativeExtractFile(handle: Long, path: String, destPath: String, opId: Int, singlePass: Boolean): Boolean
    @JvmStatic external fun nativeBeginBatchWrite(handle: Long)
    @JvmStatic external fun nativeEndBatchWrite(handle: Long)
    @JvmStatic external fun nativeBeginBatchDelete(handle: Long)
    @JvmStatic external fun nativeEndBatchDelete(handle: Long)
    @JvmStatic external fun nativeInvalidateCache(handle: Long, path: String)
    @JvmStatic external fun nativeSpaceInfo(handle: Long): LongArray?

    /** Flat triples: key, kind ("s" | "i" | "b"), value. */
    @JvmStatic external fun nativeInfo(handle: Long): Array<String>?

    /**
     * Check & Repair (cpp/foldervault/fv_check.h). Both return a String[]:
     *   [0] outcome "0" ok / "1" wrong password / "2" not a vault or refused; for anything but ok, [1] is the message
     *   check, ok:  [1] filesScanned, [2] deep scan "1"/"0", then (severity, path, message) triples
     *   repair, ok: [1] fixed, [2] recovered, [3] removed, then (severity, path, message) triples still wrong
     * [password] may be null (structure-only check). [session] is the handle of an unlocked vault of the same
     * vault, or 0; its keys are used inside the native core and never reach the JVM. [opId] > 0 streams the
     * step-by-step log to the repair log panel.
     */
    @JvmStatic external fun nativeCheck(
        format: Int, rawRoot: String?, storage: FolderVaultStorage?, password: ByteArray?, session: Long,
        localStateDir: String, tempDir: String, opId: Int,
    ): Array<String>?

    @JvmStatic external fun nativeRepair(
        format: Int, rawRoot: String?, storage: FolderVaultStorage?, password: ByteArray?, session: Long,
        localStateDir: String, tempDir: String, opId: Int,
    ): Array<String>?
}
