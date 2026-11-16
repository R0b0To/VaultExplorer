package com.aeidolon.vaultexplorer.container

import android.annotation.TargetApi
import android.content.Context
import android.media.MediaDataSource
import android.os.Build

// ── ContainerInputStream (Optimized Subsampled Native Image Stream) ─────────────

class ContainerInputStream(
    private val context: Context,
    private val uriString: String,
    private val fileName: String,
    private val volId: Int
) : java.io.InputStream() {

    private var position: Long = 0L
    private var fileSize: Long = -1L
    private var markedPosition: Long = 0L

    init {
        fileSize = ContainerFileSystem.getFileSize(volId, fileName)
    }

    override fun read(): Int {
        if (fileSize >= 0 && position >= fileSize) return -1
        val buf = ByteArray(1)
        val read = read(buf, 0, 1)
        return if (read > 0) buf[0].toInt() and 0xFF else -1
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (fileSize >= 0 && position >= fileSize) return -1
        val toRead = minOf(len.toLong(), fileSize - position).toInt()
        if (toRead <= 0) return -1
        val chunk = ContainerFileSystem.readFileChunk(volId, fileName, position, toRead) ?: return -1
        if (chunk.isEmpty()) return -1
        val actual = minOf(chunk.size, toRead)
        System.arraycopy(chunk, 0, b, off, actual)
        position += actual
        return actual
    }

   override fun skip(n: Long): Long {
        if (n <= 0 || fileSize < 0) return 0
        val actualSkip = minOf(n, fileSize - position)
        position += actualSkip
        return actualSkip
    }

    override fun available(): Int {
        val avail = fileSize - position
        return when {
            fileSize < 0          -> 0
            avail > Int.MAX_VALUE -> Int.MAX_VALUE
            else                  -> avail.toInt()
        }
    }

    override fun markSupported() = true
    override fun mark(readlimit: Int) { synchronized(this) { markedPosition = position } }
    override fun reset()              { synchronized(this) { position = markedPosition } }
}

@TargetApi(Build.VERSION_CODES.M)
class ContainerMediaDataSource(
    private val context: Context,
    private val uriString: String,
    private val fileName: String,
    private val volId: Int
) : MediaDataSource() {

   companion object {
        private const val READ_AHEAD_BYTES = 128 * 1024
        private const val MAX_CACHED_WINDOWS = 4
    }

    private class CachedWindow(val start: Long, val data: ByteArray)

    private var cachedSize: Long = -1L
    private val windows = ArrayList<CachedWindow>(MAX_CACHED_WINDOWS)

    override fun getSize(): Long {
        if (cachedSize >= 0) return cachedSize
        val size = try {
            ContainerFileSystem.getFileSize(volId, fileName)
        } catch (e: Exception) {
            return 0L
        }
        cachedSize = size
        return size
    }

    @Synchronized
    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (size <= 0) return 0
        val fileLength = getSize()
        if (fileLength <= 0L || position < 0L || position >= fileLength) {
            return -1
        }
        val maxWritable = buffer.size - offset
        if (offset < 0 || maxWritable <= 0) return 0
        val readSize = minOf(size.toLong(), fileLength - position, maxWritable.toLong()).toInt()
        if (readSize <= 0) return -1

        for (i in windows.lastIndex downTo 0) {
            val w = windows[i]
            if (position >= w.start && position < w.start + w.data.size) {
                val inOffset = (position - w.start).toInt()
                val avail = w.data.size - inOffset
                if (avail >= readSize || w.start + w.data.size >= fileLength) {
                    val n = minOf(readSize, avail)
                    System.arraycopy(w.data, inOffset, buffer, offset, n)
                    if (i != windows.lastIndex) {
                        windows.removeAt(i)
                        windows.add(w)
                    }
                    return n
                }
            }
        }

        return try {
            if (readSize >= READ_AHEAD_BYTES) {
                val chunk = ContainerFileSystem.readFileChunk(volId, fileName, position, readSize)
                if (chunk == null || chunk.isEmpty()) {
                    return -1
                }
                val actualRead = minOf(chunk.size, readSize)
                System.arraycopy(chunk, 0, buffer, offset, actualRead)
                chunk.fill(0)
                return actualRead
            }

            val fetchSize = minOf(READ_AHEAD_BYTES.toLong(), fileLength - position).toInt()
            val fetched = ContainerFileSystem.readFileChunk(volId, fileName, position, fetchSize)
            if (fetched == null || fetched.isEmpty()) {
                return -1
            }
            if (windows.size >= MAX_CACHED_WINDOWS) {
                windows.removeAt(0).data.fill(0)
            }
            windows.add(CachedWindow(position, fetched))
            val actualRead = minOf(fetched.size, readSize)
            System.arraycopy(fetched, 0, buffer, offset, actualRead)
            actualRead
        } catch (e: Exception) {
            -1
        }
    }

    @Synchronized
    override fun close() {
        for (w in windows) {
            w.data.fill(0)
        }
        windows.clear()
    }
}