package com.aeidolon.vaultexplorer

/**
 * JNI bridge to vaultexplorer.cpp.
 *
 * API is split into two clear tiers:
 *
 *   1. Session-establishment calls — take a real fd + password + pim because
 *      they are creating the crypto session from scratch.
 *
 *   2. Stateless calls — take volId only; the C++ side asserts an active
 *      session exists via requireActiveSession() and throws
 *      IllegalStateException("NOT_UNLOCKED: ...") if it doesn't.
 *
 */
object VeraCryptEngine {
    init {
        System.loadLibrary("vaultexplorer")
    }

    // ── Config ───────────────────────────────────────────────────────────

    @JvmStatic
    external fun getMaxVolumesNative(): Int

    // ── Tier 1: session establishment ──────────────────────────────────────

    /** Opens fd, runs PBKDF2, mounts the FAT layer, returns root listing. */
    @JvmStatic
    external fun unlockAndListNative(
        fd: Int, password: String, pim: Int, volId: Int
    ): Array<String>?

    /** Writes a new VeraCrypt container to fd, formats it. */
    @JvmStatic
    external fun createContainerNative(
        fd: Int, password: String, pim: Int, sizeBytes: Long, fileSystem: String
    ): Boolean

    /** PBKDF2-SHA512 via mbedTLS; no volId, no session required. */
    @JvmStatic
    external fun hashPasswordNative(
        password: String, salt: ByteArray, iterations: Int
    ): ByteArray?

    // ── Session teardown ───────────────────────────────────────────────────

    @JvmStatic
    external fun lockNative(volId: Int)

    // ── Tier 2: stateless file operations (volId-only) ─────────────────────

    @JvmStatic external fun listDirectory(dirPath: String, volId: Int): Array<String>?
    @JvmStatic external fun getFileSize(fileName: String, volId: Int): Long
    @JvmStatic external fun getFolderSize(dirPath: String, volId: Int): Long
    @JvmStatic external fun readFileChunk(fileName: String, offset: Long, length: Int, volId: Int): ByteArray?
    @JvmStatic external fun writeFileChunk(fileName: String, offset: Long, data: ByteArray, volId: Int): Boolean
    @JvmStatic external fun writeBackFile(targetFileName: String, sourcePath: String, volId: Int): Boolean
    @JvmStatic external fun extractFile(targetFileName: String, destPath: String, volId: Int): Boolean
    @JvmStatic external fun deleteFile(targetFileName: String, volId: Int): Boolean
    @JvmStatic external fun createDirectory(dirPath: String, volId: Int): Boolean
    @JvmStatic external fun renameFile(oldPath: String, newPath: String, volId: Int): Boolean
    @JvmStatic external fun getSpaceInfo(volId: Int): LongArray?
    @JvmStatic external fun unlockUsbAndListNative(password: String, pim: Int, volId: Int, deviceSizeBytes: Long): Array<String>?

    // ── Tier 2: stream lifecycle ───────────────────────────────────────────
    // Used exclusively by VeraCryptProxyCallback. Passes a raw C++ FIL*
    // as a Long — kept separate from the one-shot stateless methods above
    // because the pointer lifetime is tied to the ProxyFileDescriptor callback.

    @JvmStatic external fun openStream(targetFileName: String, volId: Int): Long
    @JvmStatic external fun readStream(streamPtr: Long, offset: Long, outBuffer: ByteArray, length: Int, volId: Int): Int
    @JvmStatic external fun closeStream(streamPtr: Long, volId: Int)
}