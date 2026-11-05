package com.aeidolon.vaultexplorer.container

import java.io.FileNotFoundException
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.bridge.CopyProgressBridge
import com.aeidolon.vaultexplorer.cancellation.CopyCancellation

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

    fun copyFile(srcVolId: Int, srcPath: String, destVolId: Int, destPath: String, opId: Int = 0): Boolean {
        val srcIsBackend = VaultBackendRegistry.get(srcVolId) != null
        val destIsBackend = VaultBackendRegistry.get(destVolId) != null
        if (!srcIsBackend && !destIsBackend) {
            // Disk-image-to-disk-image path: single native JNI call, one
            // multi-chunk transfer under NativeEngine.copyFile. This is the
            // path yieldContainerCopyLocks (ContainerSessionRegistry) exists
            // for -- see that function's doc comment -- so holding the pair
            // of locks across the whole call is fine: NativeEngine.copyFile's
            // progress callback yields both locks between chunks internally.
            return withWriteLock(destVolId) {
                withReadLock(srcVolId) {
                    ContainerEngine.copyFile(srcVolId, srcPath, destVolId, destPath, opId)
                }
            }
        }
        // At least one side is a folder-vault session (gocryptfs / Cryptomator
        // / CryFS). There is no native cross-container copy primitive for
        // these, and the file's plaintext must never be written to disk, so
        // the bytes are streamed through memory: the source is read a chunk
        // at a time (VaultCopyInputStream) and handed straight to the
        // destination.
        //
        // Locking: the three folder-vault backends all skip the per-volume
        // lock and lock internally, and the disk-image side is locked per
        // chunk by readFileChunk/writeFileChunk, so no lock is held across
        // the whole transfer -- the "spinner until the copy finishes" and
        // 4-thread ioExecutor starvation problems (see yieldContainerCopyLocks)
        // that a single long-held lock would bring don't arise.
        return copyFileStreaming(srcVolId, srcPath, destVolId, destPath, opId)
    }

    private fun copyFileStreaming(
        srcVolId: Int, srcPath: String, destVolId: Int, destPath: String, opId: Int,
    ): Boolean {
        val total = getFileSize(srcVolId, srcPath)
        if (total <= 0L) {
            // Empty (the Dart side normally handles that before it gets here)
            // or unreadable: nothing worth streaming, so keep the previous
            // path. An empty file has no plaintext to leak to a temp file.
            return ContainerEngine.copyFileViaBackend(srcVolId, srcPath, destVolId, destPath, opId,
                extract = { path, dest -> extractFileLocked(srcVolId, path, dest, opId) },
                writeBack = { path, source -> writeBackFile(destVolId, path, source, opId) })
        }

        val input = VaultCopyInputStream(
            total = total,
            readChunk = { offset, length -> readFileChunk(srcVolId, srcPath, offset, length) },
            isCancelled = { opId > 0 && CopyCancellation.isCancelled(opId) },
            onProgress = { bytes -> CopyProgressBridge.reportProgress(opId, bytes) },
        )
        val written = try {
            input.use {
                if (VaultBackendRegistry.get(destVolId) != null) {
                    importStream(destVolId, destPath, it)
                } else {
                    writeStreamToDiskImage(destVolId, destPath, it, total)
                }
            }
        } catch (e: Exception) {
            VeLog.w("ContainerFileSystem") { "streaming copy failed: ${e.message}" }
            false
        }

        // The destination must have consumed the whole stream: a writer that
        // returned success after reading less than the source holds is not a
        // successful copy.
        if (written && input.position == total) return true

        // Don't leave a truncated file under the real name. (The Dart caller
        // clears the destination before copying, so this only ever removes
        // what this attempt created.) It then retries with its own chunked
        // loop, which also never touches disk.
        try {
            deleteFile(destVolId, destPath)
        } catch (_: Exception) {
        }
        return false
    }

    /** Disk-image destinations take the file as offset-addressed chunks. */
    private fun writeStreamToDiskImage(
        volId: Int, path: String, input: java.io.InputStream, total: Long,
    ): Boolean {
        val buffer = ByteArray(VaultCopyInputStream.DEFAULT_CHUNK_BYTES)
        try {
            var offset = 0L
            while (offset < total) {
                val n = input.read(buffer, 0, minOf(buffer.size.toLong(), total - offset).toInt())
                if (n <= 0) return false
                val data = if (n == buffer.size) buffer else buffer.copyOf(n)
                try {
                    if (!writeFileChunk(volId, path, offset, data)) return false
                } finally {
                    if (data !== buffer) data.fill(0)
                }
                offset += n
            }
            return finishWrite(volId, path)
        } finally {
            buffer.fill(0)
        }
    }

    /**
     * extractFile has no lock wrapper of its own in [ContainerEngine]
     * (dispatches straight to VaultBackend.extractFile or
     * NativeEngine.extractFile), so this applies the same
     * skipsPerVolumeLock fork [importStream] uses -- a large extract-read
     * shouldn't need to block listDirectory/getSpaceInfo on a backend that
     * already manages its own fine-grained locking internally (see
     * ChunkedFileEngine's per-path pathLocks), and disk-image sources are
     * already read-only-safe under a shared lock the same way
     * listDirectory/readFileChunk are (see filesystem_bridge.cpp's own
     * shared-lock conversion for the C++ side of this).
     */
    private fun extractFileLocked(
        volId: Int,
        fatPath: String,
        destinationPath: String,
        opId: Int,
        singlePass: Boolean = false,
    ): Boolean =
        if (VaultBackendRegistry.get(volId)?.skipsPerVolumeLock == true) {
            ContainerEngine.extractFile(fatPath, destinationPath, volId, opId, singlePass)
        } else {
            runReadLock(volId) { ContainerEngine.extractFile(fatPath, destinationPath, volId, opId, singlePass) }
        }

    fun beginBatchWrite(volId: Int) {
        withWriteLock(volId) { ContainerEngine.beginBatchWrite(volId) }
    }
    
    fun beginBatchDelete(volId: Int) {
    VaultBackendRegistry.get(volId)?.beginBatchDelete()
}

fun endBatchDelete(volId: Int) {
    VaultBackendRegistry.get(volId)?.endBatchDelete()
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

    /**
     * opId defaults to 0 (no progress/cancellation tracking) for the many
     * call sites that just want a file out on disk -- viewers, automation,
     * the documents provider. Export passes a real opId so the
     * skipsPerVolumeLock-aware [extractFileLocked] path can report chunk
     * progress via [com.aeidolon.vaultexplorer.bridge.ExportProgressBridge]
     * (folder-vault formats) the same way intra-vault copy already does via
     * CopyProgressBridge -- see ExportProgressBridge's doc comment for why
     * the two bridges can't just share one code path. [singlePass] is for
     * a third caller, [handleDecryptFile][com.aeidolon.vaultexplorer.handlers.FileOperationHandlers]
     * with an opId attached (a plain vault -> real-file decrypt that isn't
     * export and isn't half of a copy) -- see VaultBackend.extractFile's doc.
     */
    fun extractToFile(volId: Int, fatPath: String, destPath: String, opId: Int = 0, singlePass: Boolean = false): Boolean =
        extractFileLocked(volId, fatPath, destPath, opId, singlePass)

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

    fun writeBackFile(volId: Int, fatPath: String, sourcePath: String, opId: Int = 0, singlePass: Boolean = false): Boolean {
        requireSession(volId)
        return if (VaultBackendRegistry.get(volId)?.managesOwnWriteLocking == true) {
            ContainerEngine.writeBackFile(fatPath, sourcePath, volId, opId, singlePass)
        } else {
            withWriteLock(volId) { ContainerEngine.writeBackFile(fatPath, sourcePath, volId, opId, singlePass) }
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
        // A count the caller's buffer cannot hold means the native read
        // misreported; copying it would overrun `out`, so treat it as a failed
        // read instead of corrupting memory or throwing mid-playback.
        if (bytesRead > length || bytesRead > tmp.size || bufferOffset < 0 ||
            (bytesRead > 0 && bufferOffset + bytesRead > out.size)
        ) {
            return -1
        }
        if (bytesRead > 0) {
            System.arraycopy(tmp, 0, out, bufferOffset, bytesRead)
        }
        return bytesRead
    }

    fun closeStream(volId: Int, streamPtr: Long) =
        withReadLock(volId) { ContainerEngine.closeStream(streamPtr, volId) }
}