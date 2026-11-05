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
     * Returns a handle > 0, 0 for "not a valid vault", -1 for "wrong password".
     * out[0] receives the failure message, out[1] the CryFS derived key.
     */
    @JvmStatic external fun nativeOpen(
        format: Int, rawRoot: String?, bootstrap: FolderVaultStorage?,
        sessionProvider: FolderVaultSessionProvider?, password: ByteArray, readOnly: Boolean,
        localStateDir: String, tempDir: String, combinedKey: ByteArray?, out: Array<Any?>,
    ): Long

    /**
     * Writes a new vault's skeleton. [options]: gocryptfs = [cipher 0=GCM 1=XChaCha
     * 2=AES-SIV, plaintextNames 0/1]; cryfs = [blocksizeBytes, 0].
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

    @JvmStatic external fun nativeClose(handle: Long)
    @JvmStatic external fun nativeListDirectory(handle: Long, path: String): Array<String>?
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

    /** "f:<name>:<base64>" (binary) and "s:<name>:<value>" entries; see [KeyMaterial]. */
    @JvmStatic external fun nativeExportKeys(handle: Long): Array<String>?
}
