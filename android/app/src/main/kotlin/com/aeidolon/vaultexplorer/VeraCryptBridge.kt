package com.aeidolon.vaultexplorer

import java.io.FileNotFoundException

/**
 * Single chokepoint for all stateless native calls.
 *
 * Wraps every VeraCryptEngine Tier-2 call with:
 *   - synchronized(VeraCryptSession.locks[volId])  — JVM-side serialization
 *   - requireSession()                              — fast existence check
 *
 * Both MainActivity (via runNativeOp) and VeraCryptDocumentsProvider call
 * through here so locking and error-dispatch live in one place.
 */
object VeraCryptBridge {

    /**
     * Runs [block] under the per-volume JVM monitor.
     * Use directly when batching multiple native calls under one lock
     * acquisition (e.g. VeraCryptProxyCallback.init).
     */
    fun <T> withLock(volId: Int, block: () -> T): T =
        synchronized(VeraCryptSession.locks[volId], block)

    /**
     * Returns the active session for [volId] or throws [FileNotFoundException].
     * Called at the top of every Provider override so the error surfaces
     * cleanly through the DocumentsProvider contract.
     */
    fun requireSession(volId: Int): ContainerSession =
        VeraCryptSession.activeSessions[volId]
            ?: throw FileNotFoundException(
                "No active session for volume $volId — container not unlocked"
            )

    // ── Directory operations ───────────────────────────────────────────────

    fun listDirectory(volId: Int, dirPath: String): Array<String>? =
        withLock(volId) { VeraCryptEngine.listDirectory(dirPath, volId) }

    fun createDirectory(volId: Int, dirPath: String): Boolean =
        withLock(volId) { VeraCryptEngine.createDirectory(dirPath, volId) }

    fun renameFile(volId: Int, oldPath: String, newPath: String): Boolean =
        withLock(volId) { VeraCryptEngine.renameFile(oldPath, newPath, volId) }

    fun setLastModifiedTime(volId: Int, fatPath: String, epochSeconds: Long): Boolean =
        withLock(volId) { VeraCryptEngine.setLastModifiedTime(fatPath, epochSeconds, volId) }

    fun deleteFile(volId: Int, fatPath: String): Boolean =
        withLock(volId) { VeraCryptEngine.deleteFile(fatPath, volId) }

    // ── File I/O ──────────────────────────────────────────────────────────

    fun getFileSize(volId: Int, fatPath: String): Long =
        withLock(volId) { VeraCryptEngine.getFileSize(fatPath, volId) }

    fun readFileChunk(volId: Int, fatPath: String, offset: Long, length: Int): ByteArray? =
        withLock(volId) { VeraCryptEngine.readFileChunk(fatPath, offset, length, volId) }

    fun writeBackFile(volId: Int, fatPath: String, sourcePath: String): Boolean =
        withLock(volId) { VeraCryptEngine.writeBackFile(fatPath, sourcePath, volId) }

    fun extractToFile(volId: Int, fatPath: String, destPath: String): Boolean =
        withLock(volId) { VeraCryptEngine.extractFile(fatPath, destPath, volId) }

    // ── Space info ────────────────────────────────────────────────────────

    fun getSpaceInfo(volId: Int): LongArray? =
        withLock(volId) { VeraCryptEngine.getSpaceInfo(volId) }

    fun getSpacePair(volId: Int): Pair<Long, Long> = try {
        val space = getSpaceInfo(volId)
        if (space != null && space.size > 1) Pair(space[0], space[1])
        else Pair(0L, 0L)
    } catch (_: Exception) { Pair(0L, 0L) }
}