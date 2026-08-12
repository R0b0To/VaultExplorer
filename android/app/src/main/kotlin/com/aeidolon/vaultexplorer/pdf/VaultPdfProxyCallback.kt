package com.aeidolon.vaultexplorer.pdf

import android.os.HandlerThread
import android.os.ProxyFileDescriptorCallback
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Log
import com.aeidolon.vaultexplorer.ContainerFileSystem


class VaultPdfProxyCallback(
    private val volId: Int,
    private val fatPath: String,
    private val handlerThread: HandlerThread,
    private val onReleased: () -> Unit,
) : ProxyFileDescriptorCallback() {

    companion object {
        private const val TAG = "VaultPdfProxyCallback"
        private const val READ_CACHE_CAPACITY = 1024 * 1024 // 1 MB
    }

    private var fileSize: Long = -1L
    private var streamPtr: Long = 0L

    private val readCache = ByteArray(READ_CACHE_CAPACITY)
    private var readCacheOffset: Long = -1L
    private var readCacheLength: Int = 0

    init {
        try {
            ContainerFileSystem.withReadLock(volId) {
                fileSize = ContainerFileSystem.getFileSize(volId, fatPath)
                if (fileSize < 0) fileSize = 0L
                streamPtr = ContainerFileSystem.openStream(volId, fatPath)
            }
        } catch (e: Exception) {
            Log.e(TAG, "init: stream init failed for $fatPath (volId=$volId)", e)
            handlerThread.quitSafely()
            throw java.io.FileNotFoundException("PDF stream init failed for $fatPath: ${e.message}")
        }
    }

    override fun onGetSize(): Long = fileSize

    @Synchronized
    override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
        if (offset >= fileSize || streamPtr == 0L) return 0
        val readSize = minOf(size.toLong(), fileSize - offset).toInt()
        if (readSize <= 0) return 0

        if (offset >= readCacheOffset && offset + readSize <= readCacheOffset + readCacheLength) {
            val relativeOffset = (offset - readCacheOffset).toInt()
            System.arraycopy(readCache, relativeOffset, data, 0, readSize)
            return readSize
        }

        if (readSize <= READ_CACHE_CAPACITY) {
            val fetchSize = minOf(READ_CACHE_CAPACITY.toLong(), fileSize - offset).toInt()
            val actualRead = ContainerFileSystem.withReadLock(volId) {
                ContainerFileSystem.readStream(volId, streamPtr, offset, readCache, fetchSize)
            }
            if (actualRead < 0) throw ErrnoException("onRead", OsConstants.EIO)

            readCacheOffset = offset
            readCacheLength = actualRead

            val copySize = minOf(readSize, readCacheLength)
            if (copySize > 0) System.arraycopy(readCache, 0, data, 0, copySize)
            return copySize
        }

        val actualRead = ContainerFileSystem.withReadLock(volId) {
            ContainerFileSystem.readStream(volId, streamPtr, offset, data, readSize)
        }
        if (actualRead < 0) throw ErrnoException("onRead", OsConstants.EIO)
        return actualRead
    }

    override fun onWrite(offset: Long, size: Int, data: ByteArray): Int {
        throw ErrnoException("onWrite", OsConstants.EROFS)
    }

    override fun onFsync() {
        // Read-only: nothing to flush.
    }

    @Synchronized
    override fun onRelease() {
        try {
            ContainerFileSystem.withReadLock(volId) {
                if (streamPtr != 0L) {
                    ContainerFileSystem.closeStream(volId, streamPtr)
                    streamPtr = 0L
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "onRelease: failed to close stream for $fatPath (volId=$volId)", e)
        }
        handlerThread.quitSafely()
        onReleased()
    }
}
