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

    inline fun <T> withReadLock(volId: Int, block: () -> T): T {
        val lock = ContainerSessionRegistry.locks[volId].readLock()
        lock.lock()
        try {
            return block()
        } finally {
            lock.unlock()
        }
    }

    inline fun <T> withWriteLock(volId: Int, block: () -> T): T {
        val lock = ContainerSessionRegistry.locks[volId].writeLock()
        lock.lock()
        try {
            return block()
        } finally {
            lock.unlock()
        }
    }

    @Deprecated("Use withReadLock or withWriteLock instead")
    fun <T> withLock(volId: Int, block: () -> T): T = withWriteLock(volId, block)

    fun requireSession(volId: Int): ContainerSession =
        ContainerSessionRegistry.activeSessions[volId]
            ?: throw FileNotFoundException(
                "No active session for volume $volId — container not unlocked"
            )

    // ── Directory operations (Read-Only) ───────────────────────────────────

    fun importStream(volId: Int, fatPath: String, inputStream: java.io.InputStream): Boolean =
        withWriteLock(volId) { ContainerEngine.importStream(fatPath, inputStream, volId) }
        
    fun listDirectory(volId: Int, dirPath: String): Array<String>? =
        withReadLock(volId) { ContainerEngine.listDirectory(dirPath, volId) }

    // ── Directory operations (Write) ───────────────────────────────────────

    fun createDirectory(volId: Int, dirPath: String): Boolean =
        withWriteLock(volId) { ContainerEngine.createDirectory(dirPath, volId) }

    fun renameFile(volId: Int, oldPath: String, newPath: String): Boolean =
        withWriteLock(volId) { ContainerEngine.renameFile(oldPath, newPath, volId) }

    fun setLastModifiedTime(volId: Int, fatPath: String, epochSeconds: Long): Boolean =
        withWriteLock(volId) { ContainerEngine.setLastModifiedTime(fatPath, epochSeconds, volId) }

    fun deleteFile(volId: Int, fatPath: String): Boolean =
        withWriteLock(volId) { ContainerEngine.deleteFile(fatPath, volId) }

    // ── File I/O (Read-Only) ───────────────────────────────────────────────

    fun getFileSize(volId: Int, fatPath: String): Long {
        val session = requireSession(volId)
        val name = session.javaClass.simpleName
        return if (name.contains("Cryptomator") || name.contains("Gocryptfs")) {
            ContainerEngine.getFileSize(fatPath, volId)
        } else {
            withReadLock(volId) { ContainerEngine.getFileSize(fatPath, volId) }
        }
    }

    fun getFolderSize(volId: Int, fatPath: String): Long =
        withReadLock(volId) { ContainerEngine.getFolderSize(fatPath, volId) }

    fun readFileChunk(volId: Int, fatPath: String, offset: Long, length: Int): ByteArray? {
        val session = requireSession(volId)
        val name = session.javaClass.simpleName
        return if (name.contains("Cryptomator") || name.contains("Gocryptfs")) {
            ContainerEngine.readFileChunk(fatPath, offset, length, volId)
        } else {
            withReadLock(volId) { ContainerEngine.readFileChunk(fatPath, offset, length, volId) }
        }
    }

    fun extractToFile(volId: Int, fatPath: String, destPath: String): Boolean =
        withReadLock(volId) { ContainerEngine.extractFile(fatPath, destPath, volId) }

    // ── File I/O (Write) ───────────────────────────────────────────────────

    fun writeFileChunk(volId: Int, fatPath: String, offset: Long, data: ByteArray): Boolean =
        withWriteLock(volId) { ContainerEngine.writeFileChunk(fatPath, offset, data, volId) }

    fun writeBackFile(volId: Int, fatPath: String, sourcePath: String): Boolean =
        withWriteLock(volId) { ContainerEngine.writeBackFile(fatPath, sourcePath, volId) }

    // ── Space info (Read-Only) ─────────────────────────────────────────────

    fun getSpaceInfo(volId: Int): LongArray? =
        withReadLock(volId) { ContainerEngine.getSpaceInfo(volId) }

    fun getSpacePair(volId: Int): Pair<Long, Long> = try {
        val space = getSpaceInfo(volId)
        if (space != null && space.size > 1) Pair(space[0], space[1])
        else Pair(0L, 0L)
    } catch (_: Exception) { Pair(0L, 0L) }

    // ── Proxy-file stream lifecycle ───────────────────────────────────────

    fun openStream(volId: Int, fatPath: String): Long =
        withReadLock(volId) { ContainerEngine.openStream(fatPath, volId) }

    fun readStream(volId: Int, streamPtr: Long, offset: Long, out: ByteArray, length: Int): Int =
        withReadLock(volId) { ContainerEngine.readStream(streamPtr, offset, out, length, volId) }

    fun closeStream(volId: Int, streamPtr: Long) =
        withReadLock(volId) { ContainerEngine.closeStream(streamPtr, volId) }
}