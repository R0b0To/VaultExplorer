package com.aeidolon.vaultexplorer.container

import android.content.Context
import android.os.HandlerThread
import android.os.ProxyFileDescriptorCallback
import android.provider.DocumentsContract
import android.system.ErrnoException
import android.system.OsConstants
import java.io.FileNotFoundException
import com.aeidolon.vaultexplorer.DocumentId
import com.aeidolon.vaultexplorer.VeLog

/**
 * Zero-copy proxy-file-descriptor bridge onto a decrypted container/vault
 * stream. Originally lived as an inner class of [ContainerDocumentsProvider];
 * pulled out to a top-level class (taking [context] explicitly instead of
 * capturing it implicitly) so [ContainerShareProvider] can reuse the exact
 * same read/write/cache logic instead of duplicating it.
 *
 * Both callers stream decrypted bytes straight out of [ContainerFileSystem]
 * on every read; nothing is ever written to disk here.
 *
 * [context] is only touched from the write-completion notifyChange calls in
 * [onRelease], which never run for a read-only (isWrite=false) instance --
 * the only kind [ContainerShareProvider] ever creates.
 */
class ContainerProxyCallback(
    private val context: Context?,
    private val volId: Int,
    private val session: ContainerSession,
    private val fatPath: String,
    private val isWrite: Boolean,
    private val handlerThread: HandlerThread
) : ProxyFileDescriptorCallback() {

    companion object {
        private const val TAG = "ContainerProxyCallback"
    }

    private var hasChanges = false
    private var fileSizeCached: Long = -1L
    private var streamPtr: Long = 0L

    // 1 MB Read-Ahead Cache
    private val isCacheEnabled = !isWrite
    private val readCacheCapacity = 1024 * 1024
    private val readCache = if (isCacheEnabled) ByteArray(readCacheCapacity) else null
    private var readCacheOffset: Long = -1L
    private var readCacheLength: Int = 0

    // 2 MB Write-Behind Cache
    private val writeCacheCapacity = 2 * 1024 * 1024
    private val writeCache = if (isWrite) ByteArray(writeCacheCapacity) else null
    private var writeCacheOffset: Long = -1L
    private var writeCacheLength: Int = 0

    init {
        try {
            ContainerFileSystem.withReadLock(volId) {
                fileSizeCached = ContainerFileSystem.getFileSize(volId, fatPath)
                if (fileSizeCached < 0) fileSizeCached = 0L
                if (!isWrite) {
                    streamPtr = ContainerFileSystem.openStream(volId, fatPath)
                }
            }
            VeLog.d(TAG) { "ContainerProxyCallback initialized for $fatPath (isWrite=$isWrite, initialSize=$fileSizeCached)" }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "Container stream init failed for $fatPath: ${e.message}" }
            handlerThread.quitSafely()
            throw FileNotFoundException("Container stream init failed for $fatPath: ${e.message}")
        }
    }

    private fun flushWriteCache() {
        if (writeCache != null && writeCacheLength > 0) {
            val chunk = if (writeCacheLength == writeCacheCapacity) writeCache else writeCache.copyOf(writeCacheLength)
            ContainerFileSystem.withWriteLock(volId) {
                ContainerFileSystem.writeFileChunk(volId, fatPath, writeCacheOffset, chunk)
            }

            val endOffset = writeCacheOffset + writeCacheLength
            if (endOffset > fileSizeCached) fileSizeCached = endOffset

            writeCacheLength = 0
            writeCacheOffset = -1L
        }
    }

    override fun onGetSize(): Long {
        val pendingSize = if (writeCacheOffset >= 0) writeCacheOffset + writeCacheLength else 0L
        return maxOf(fileSizeCached, pendingSize)
    }

    override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
        if (offset >= fileSizeCached || streamPtr == 0L) return 0
        val readSize = minOf(size.toLong(), fileSizeCached - offset).toInt()
        if (readSize <= 0) return 0

        if (readCache != null) {
            if (offset >= readCacheOffset && offset + readSize <= readCacheOffset + readCacheLength) {
                val relativeOffset = (offset - readCacheOffset).toInt()
                System.arraycopy(readCache, relativeOffset, data, 0, readSize)
                return readSize
            }

            if (readSize <= readCacheCapacity) {
                val fetchSize = minOf(readCacheCapacity.toLong(), fileSizeCached - offset).toInt()
                val actualRead = ContainerFileSystem.withReadLock(volId) {
                    ContainerFileSystem.readStream(volId, streamPtr, offset, readCache, fetchSize)
                }
                if (actualRead < 0) throw ErrnoException("onRead", OsConstants.EIO)

                readCacheOffset = offset
                readCacheLength = actualRead

                val copySize = minOf(readSize, readCacheLength)
                if (copySize > 0) {
                    System.arraycopy(readCache, 0, data, 0, copySize)
                }
                return copySize
            }
        }

        val actualRead = ContainerFileSystem.withReadLock(volId) {
            ContainerFileSystem.readStream(volId, streamPtr, offset, data, readSize)
        }
        if (actualRead < 0) throw ErrnoException("onRead", OsConstants.EIO)
        return actualRead
    }

    override fun onWrite(offset: Long, size: Int, data: ByteArray): Int {
        if (!isWrite || writeCache == null) throw ErrnoException("onWrite", OsConstants.EBADF)

        if (writeCacheLength > 0 && (offset != writeCacheOffset + writeCacheLength || writeCacheLength + size > writeCacheCapacity)) {
            flushWriteCache()
        }

        if (size >= writeCacheCapacity) {
            val chunkData = if (data.size == size) data else data.copyOf(size)
            val success = ContainerFileSystem.withWriteLock(volId) {
                ContainerFileSystem.writeFileChunk(volId, fatPath, offset, chunkData)
            }
            if (!success) throw ErrnoException("onWrite", OsConstants.EIO)

            val endOffset = offset + size
            if (endOffset > fileSizeCached) fileSizeCached = endOffset
        } else {
            if (writeCacheLength == 0) writeCacheOffset = offset
            System.arraycopy(data, 0, writeCache, writeCacheLength, size)
            writeCacheLength += size
        }

        hasChanges = true
        return size
    }

    override fun onFsync() {
        flushWriteCache()
    }

    override fun onRelease() {
        VeLog.d(TAG) { "ContainerProxyCallback releasing for $fatPath (hasChanges=$hasChanges)" }
        try {
            flushWriteCache()
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Error flushing write cache on release for $fatPath" }
        }

        if (isWrite) {
            try {
                ContainerFileSystem.withWriteLock(volId) {
                    ContainerEngine.finishWrite(fatPath, volId)
                }
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "Error finishing write on release for $fatPath" }
            }
        }

        try {
            ContainerFileSystem.withReadLock(volId) {
                if (streamPtr != 0L) {
                    ContainerFileSystem.closeStream(volId, streamPtr)
                    streamPtr = 0L
                }
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Error closing stream on release for $fatPath" }
        }

        try {
            if (isWrite && hasChanges) {
                val parentPath = if (fatPath.contains("/")) fatPath.substringBeforeLast("/") else ""
                val parentDocId = DocumentId(volId, "dir", parentPath).toString()

                context?.contentResolver?.notifyChange(
                    DocumentsContract.buildChildDocumentsUri(ContainerDocumentsProvider.AUTHORITY, parentDocId), null
                )
                context?.contentResolver?.notifyChange(
                    DocumentsContract.buildDocumentUri(ContainerDocumentsProvider.AUTHORITY, parentDocId), null
                )

                val fileDocId = DocumentId(volId, "file", fatPath).toString()
                context?.contentResolver?.notifyChange(
                    DocumentsContract.buildDocumentUri(ContainerDocumentsProvider.AUTHORITY, fileDocId), null
                )
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Error notifying change on release for $fatPath" }
        }

        handlerThread.quitSafely()
    }
}
