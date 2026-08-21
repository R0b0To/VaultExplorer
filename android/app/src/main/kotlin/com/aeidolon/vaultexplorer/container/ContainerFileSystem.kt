package com.aeidolon.vaultexplorer.container

import java.io.FileNotFoundException
import com.aeidolon.vaultexplorer.MainActivity

object ContainerFileSystem {

    inline fun <T> runReadLock(volId: Int, block: () -> T): T = withReadLock(volId, block)

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
        if (VaultBackendRegistry.get(volId)?.skipsPerVolumeLock == true) {
            ContainerEngine.importStream(fatPath, inputStream, volId)
        } else {
            withWriteLock(volId) { ContainerEngine.importStream(fatPath, inputStream, volId) }
        }

    fun copyFile(srcVolId: Int, srcPath: String, destVolId: Int, destPath: String, opId: Int = 0): Boolean =
        withWriteLock(destVolId) {
            withReadLock(srcVolId) {
                ContainerEngine.copyFile(srcVolId, srcPath, destVolId, destPath, opId)
            }
        }

    fun beginBatchWrite(volId: Int) {
        withWriteLock(volId) { ContainerEngine.beginBatchWrite(volId) }
    }

    fun endBatchWrite(volId: Int) {
        withWriteLock(volId) { ContainerEngine.endBatchWrite(volId) }
    }
        
    fun listDirectory(volId: Int, dirPath: String): Array<String>? =
        withReadLock(volId) { ContainerEngine.listDirectory(dirPath, volId) }

    fun invalidateCache(volId: Int, dirPath: String = "") {
        withWriteLock(volId) { ContainerEngine.invalidateCache(dirPath, volId) }
    }

    // ── Directory operations (Write) ───────────────────────────────────────

    fun createDirectory(volId: Int, dirPath: String): Boolean {
        requireSession(volId)
        return withWriteLock(volId) { ContainerEngine.createDirectory(dirPath, volId) }
    }

    fun renameFile(volId: Int, oldPath: String, newPath: String): Boolean {
        requireSession(volId)
        return withWriteLock(volId) { ContainerEngine.renameFile(oldPath, newPath, volId) }
    }

    fun setLastModifiedTime(volId: Int, fatPath: String, epochSeconds: Long): Boolean {
        requireSession(volId)
        return withWriteLock(volId) { ContainerEngine.setLastModifiedTime(fatPath, epochSeconds, volId) }
    }

    fun deleteFile(volId: Int, fatPath: String): Boolean {
        requireSession(volId)
        return if (VaultBackendRegistry.get(volId)?.managesOwnWriteLocking == true) {
            ContainerEngine.deleteFile(fatPath, volId)
        } else {
            withWriteLock(volId) { ContainerEngine.deleteFile(fatPath, volId) }
        }
    }

    // ── File I/O (Read-Only) ───────────────────────────────────────────────

    fun getFileSize(volId: Int, fatPath: String): Long {
        requireSession(volId)
        return if (VaultBackendRegistry.get(volId)?.skipsPerVolumeLock == true) {
            ContainerEngine.getFileSize(fatPath, volId)
        } else {
            withReadLock(volId) { ContainerEngine.getFileSize(fatPath, volId) }
        }
    }

    fun getFolderSize(volId: Int, fatPath: String): Long =
        withReadLock(volId) { ContainerEngine.getFolderSize(fatPath, volId) }

    fun readFileChunk(volId: Int, fatPath: String, offset: Long, length: Int): ByteArray? {
        requireSession(volId)
        return if (VaultBackendRegistry.get(volId)?.skipsPerVolumeLock == true) {
            ContainerEngine.readFileChunk(fatPath, offset, length, volId)
        } else {
            withReadLock(volId) { ContainerEngine.readFileChunk(fatPath, offset, length, volId) }
        }
    }

    fun extractToFile(volId: Int, fatPath: String, destPath: String): Boolean =
        withReadLock(volId) { ContainerEngine.extractFile(fatPath, destPath, volId) }

    // ── File I/O (Write) ───────────────────────────────────────────────────

    fun writeFileChunk(volId: Int, fatPath: String, offset: Long, data: ByteArray): Boolean {
        requireSession(volId)
        return withWriteLock(volId) { ContainerEngine.writeFileChunk(fatPath, offset, data, volId) }
    }

    fun finishWrite(volId: Int, fatPath: String): Boolean {
        requireSession(volId)
        return if (VaultBackendRegistry.get(volId)?.managesOwnWriteLocking == true) {
            ContainerEngine.finishWrite(fatPath, volId)
        } else {
            withWriteLock(volId) { ContainerEngine.finishWrite(fatPath, volId) }
        }
    }

    fun writeBackFile(volId: Int, fatPath: String, sourcePath: String, opId: Int = 0): Boolean {
        requireSession(volId)
        return if (VaultBackendRegistry.get(volId)?.managesOwnWriteLocking == true) {
            ContainerEngine.writeBackFile(fatPath, sourcePath, volId, opId)
        } else {
            withWriteLock(volId) { ContainerEngine.writeBackFile(fatPath, sourcePath, volId, opId) }
        }
    }

    // ── Space info (Read-Only) ─────────────────────────────────────────────

    fun getSpaceInfo(volId: Int): LongArray? =
        withReadLock(volId) { ContainerEngine.getSpaceInfo(volId) }

    fun getVaultInfo(volId: Int): Map<String, Any?>? =
        withReadLock(volId) { ContainerEngine.getVaultInfo(volId) }

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

    private val readBufferPool = object : ThreadLocal<ByteArray>() {
        override fun initialValue(): ByteArray = ByteArray(256 * 1024)
    }

    fun readStream(volId: Int, streamPtr: Long, offset: Long, out: ByteArray, length: Int, bufferOffset: Int): Int {
        if (bufferOffset == 0) return readStream(volId, streamPtr, offset, out, length)
        var tmp = readBufferPool.get()
        if (tmp == null || tmp.size < length) {
            tmp = ByteArray(length.coerceAtLeast(256 * 1024))
            readBufferPool.set(tmp)
        }
        val bytesRead = readStream(volId, streamPtr, offset, tmp, length)
        if (bytesRead > 0) {
            System.arraycopy(tmp, 0, out, bufferOffset, bytesRead)
        }
        return bytesRead
    }

    fun closeStream(volId: Int, streamPtr: Long) =
        withReadLock(volId) { ContainerEngine.closeStream(streamPtr, volId) }
}