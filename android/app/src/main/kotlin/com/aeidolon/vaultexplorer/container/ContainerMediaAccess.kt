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
        if (n <= 0) return 0
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

    private var cachedSize: Long = -1L

    override fun getSize(): Long {
        if (cachedSize >= 0) return cachedSize
        cachedSize = try {
            ContainerFileSystem.getFileSize(volId, fileName)
        } catch (_: Exception) { 0L }
        return cachedSize
    }

    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        val fileLength = getSize()
        if (position >= fileLength) return -1
        val readSize = minOf(size.toLong(), fileLength - position).toInt()
        if (readSize <= 0) return -1
        return try {
            val chunk = ContainerFileSystem.readFileChunk(volId, fileName, position, readSize)
                ?: return -1
            if (chunk.isEmpty()) return -1
            val actualRead = minOf(chunk.size, readSize)
            System.arraycopy(chunk, 0, buffer, offset, actualRead)
            actualRead
        } catch (_: Exception) { -1 }
    }

    override fun close() {}
}
