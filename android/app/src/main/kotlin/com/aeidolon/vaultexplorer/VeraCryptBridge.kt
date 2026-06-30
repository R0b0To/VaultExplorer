package com.aeidolon.vaultexplorer

/**
 * Single chokepoint for native calls that need the session-lock + fd
 * resolution pattern, used by both MainActivity (via runNativeOp, which can
 * delegate to this for the fd-requiring calls) and VeraCryptDocumentsProvider
 * (which previously duplicated this logic inline with its own error style).
 *
 * Centralizing this means a native API contract change (e.g. the
 * NOT_UNLOCKED exception introduced above) only needs handling in one place.
 */
object VeraCryptBridge {

    /** Runs [block] under the per-volume lock; caller supplies the native call. */
    fun <T> withSession(volId: Int, block: () -> T): T =
        synchronized(VeraCryptSession.locks[volId]) { block() }

    fun listDirectory(volId: Int, dirPath: String): Array<String>? = withSession(volId) {
        VeraCryptEngine.listDirectoryNative(
            VeraCryptEngine.SESSION_FD_UNUSED, VeraCryptEngine.SESSION_PW_UNUSED,
            VeraCryptEngine.SESSION_PIM_UNUSED, dirPath, volId)
    }

    fun getFileSize(volId: Int, fatPath: String): Long = withSession(volId) {
        VeraCryptEngine.getFileSizeNative(
            VeraCryptEngine.SESSION_FD_UNUSED, VeraCryptEngine.SESSION_PW_UNUSED,
            VeraCryptEngine.SESSION_PIM_UNUSED, fatPath, volId)
    }

    fun getSpaceInfo(volId: Int): LongArray? = withSession(volId) {
        VeraCryptEngine.getSpaceInfoNative(
            VeraCryptEngine.SESSION_FD_UNUSED, VeraCryptEngine.SESSION_PW_UNUSED,
            VeraCryptEngine.SESSION_PIM_UNUSED, volId)
    }

    fun deleteFile(volId: Int, fatPath: String): Boolean = withSession(volId) {
        VeraCryptEngine.deleteFileNative(
            VeraCryptEngine.SESSION_FD_UNUSED, VeraCryptEngine.SESSION_PW_UNUSED,
            VeraCryptEngine.SESSION_PIM_UNUSED, fatPath, volId)
    }

    fun createDirectory(volId: Int, fatPath: String): Boolean = withSession(volId) {
        VeraCryptEngine.createDirectoryNative(
            VeraCryptEngine.SESSION_FD_UNUSED, VeraCryptEngine.SESSION_PW_UNUSED,
            VeraCryptEngine.SESSION_PIM_UNUSED, fatPath, volId)
    }

    fun writeBackFile(volId: Int, fatPath: String, sourcePath: String): Boolean = withSession(volId) {
        VeraCryptEngine.writeBackFileNative(
            VeraCryptEngine.SESSION_FD_UNUSED, VeraCryptEngine.SESSION_PW_UNUSED,
            VeraCryptEngine.SESSION_PIM_UNUSED, fatPath, sourcePath, volId)
    }

    fun extractToFile(volId: Int, fatPath: String, destPath: String): Boolean = withSession(volId) {
        VeraCryptEngine.unlockAndExtractNative(
            VeraCryptEngine.SESSION_FD_UNUSED, VeraCryptEngine.SESSION_PW_UNUSED,
            VeraCryptEngine.SESSION_PIM_UNUSED, fatPath, destPath, volId)
    }
}