package com.aeidolon.vaultexplorer

import java.io.FileNotFoundException

/**
 * Single chokepoint for all stateless native calls.
 *
 * Wraps every ContainerEngine Tier-2 call with:
 *   - synchronized(ContainerSessionRegistry.locks[volId]) — JVM-side serialization
 *   - requireSession()                              — fast existence check
 *
 * Both MainActivity and ContainerDocumentsProvider call
 * through here so locking and error-dispatch live in one place.
 */
object ContainerFileSystem {

    /**
     * Runs [block] under the per-volume JVM monitor.
     * Use directly when batching multiple native calls under one lock
     * acquisition (e.g. VeraCryptProxyCallback.init).
     */
    fun <T> withLock(volId: Int, block: () -> T): T =
        synchronized(ContainerSessionRegistry.locks[volId], block)

    /**
     * Returns the active session for [volId] or throws [FileNotFoundException].
     * Called at the top of every Provider override so the error surfaces
     * cleanly through the DocumentsProvider contract.
     */
    fun requireSession(volId: Int): ContainerSession =
        ContainerSessionRegistry.activeSessions[volId]
            ?: throw FileNotFoundException(
                "No active session for volume $volId — container not unlocked"
            )

    // ── Directory operations ───────────────────────────────────────────────

    fun listDirectory(volId: Int, dirPath: String): Array<String>? =
        withLock(volId) { ContainerEngine.listDirectory(dirPath, volId) }

    fun createDirectory(volId: Int, dirPath: String): Boolean =
        withLock(volId) { ContainerEngine.createDirectory(dirPath, volId) }

    fun renameFile(volId: Int, oldPath: String, newPath: String): Boolean =
        withLock(volId) { ContainerEngine.renameFile(oldPath, newPath, volId) }

    fun setLastModifiedTime(volId: Int, fatPath: String, epochSeconds: Long): Boolean =
        withLock(volId) { ContainerEngine.setLastModifiedTime(fatPath, epochSeconds, volId) }

    fun deleteFile(volId: Int, fatPath: String): Boolean =
        withLock(volId) { ContainerEngine.deleteFile(fatPath, volId) }

    // ── File I/O ──────────────────────────────────────────────────────────

    fun getFileSize(volId: Int, fatPath: String): Long {
        val session = requireSession(volId)
        val name = session.javaClass.simpleName
        return if (name.contains("Cryptomator") || name.contains("Gocryptfs")) {
            // Bypass global lock for concurrent non-native reads
            ContainerEngine.getFileSize(fatPath, volId)
        } else {
            withLock(volId) { ContainerEngine.getFileSize(fatPath, volId) }
        }
    }

    fun getFolderSize(volId: Int, fatPath: String): Long =
        withLock(volId) { ContainerEngine.getFolderSize(fatPath, volId) }

    fun readFileChunk(volId: Int, fatPath: String, offset: Long, length: Int): ByteArray? {
        val session = requireSession(volId)
        val name = session.javaClass.simpleName
        return if (name.contains("Cryptomator") || name.contains("Gocryptfs")) {
            // Bypass global lock for concurrent non-native reads
            ContainerEngine.readFileChunk(fatPath, offset, length, volId)
        } else {
            withLock(volId) { ContainerEngine.readFileChunk(fatPath, offset, length, volId) }
        }
    }

    fun writeFileChunk(volId: Int, fatPath: String, offset: Long, data: ByteArray): Boolean =
        withLock(volId) { ContainerEngine.writeFileChunk(fatPath, offset, data, volId) }

    fun writeBackFile(volId: Int, fatPath: String, sourcePath: String): Boolean =
        withLock(volId) { ContainerEngine.writeBackFile(fatPath, sourcePath, volId) }

    fun extractToFile(volId: Int, fatPath: String, destPath: String): Boolean =
        withLock(volId) { ContainerEngine.extractFile(fatPath, destPath, volId) }

    // ── Space info ────────────────────────────────────────────────────────

    fun getSpaceInfo(volId: Int): LongArray? =
        withLock(volId) { ContainerEngine.getSpaceInfo(volId) }

    fun getSpacePair(volId: Int): Pair<Long, Long> = try {
        val space = getSpaceInfo(volId)
        if (space != null && space.size > 1) Pair(space[0], space[1])
        else Pair(0L, 0L)
    } catch (_: Exception) { Pair(0L, 0L) }

    // ── Proxy-file stream lifecycle ───────────────────────────────────────

    fun openStream(volId: Int, fatPath: String): Long =
        withLock(volId) { ContainerEngine.openStream(fatPath, volId) }

    fun readStream(volId: Int, streamPtr: Long, offset: Long, out: ByteArray, length: Int): Int =
        withLock(volId) { ContainerEngine.readStream(streamPtr, offset, out, length, volId) }

    fun closeStream(volId: Int, streamPtr: Long) =
        withLock(volId) { ContainerEngine.closeStream(streamPtr, volId) }
}