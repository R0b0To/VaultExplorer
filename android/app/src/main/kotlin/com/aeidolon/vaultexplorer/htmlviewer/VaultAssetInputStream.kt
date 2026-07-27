package com.aeidolon.vaultexplorer.htmlviewer

import com.aeidolon.vaultexplorer.ContainerFileSystem
import java.io.IOException
import java.io.InputStream

/**
 * Streams a single decrypted vault file to a WebView, one bounded chunk at a
 * time, straight from [ContainerFileSystem] — the same chokepoint every
 * other reader in the app goes through. Nothing is buffered beyond the
 * current chunk and nothing is ever written to plaintext disk.
 */
class VaultAssetInputStream(
    private val volId: Int,
    private val fatPath: String,
    private val fileSize: Long,
) : InputStream() {

    companion object {
        private const val CHUNK_SIZE = 256 * 1024 // 256 KB per native read
    }

    private var position = 0L
    private var buffer: ByteArray? = null
    private var bufferPos = 0

    private fun fillBuffer(): Boolean {
        if (position >= fileSize) return false
        val remaining = (fileSize - position).coerceAtMost(CHUNK_SIZE.toLong()).toInt()
        val chunk = try {
            ContainerFileSystem.readFileChunk(volId, fatPath, position, remaining)
        } catch (e: Exception) {
            throw IOException("Failed to read vault asset: $fatPath", e)
        }
        if (chunk == null || chunk.isEmpty()) return false
        buffer = chunk
        bufferPos = 0
        position += chunk.size
        return true
    }

    override fun read(): Int {
        if (buffer == null || bufferPos >= buffer!!.size) {
            if (!fillBuffer()) return -1
        }
        return buffer!![bufferPos++].toInt() and 0xFF
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (len == 0) return 0
        if (buffer == null || bufferPos >= buffer!!.size) {
            if (!fillBuffer()) return -1
        }
        val current = buffer!!
        val available = current.size - bufferPos
        val toCopy = minOf(available, len)
        System.arraycopy(current, bufferPos, b, off, toCopy)
        bufferPos += toCopy
        return toCopy
    }

    override fun available(): Int {
        val current = buffer
        return if (current != null) (current.size - bufferPos) else 0
    }

    override fun close() {
        buffer = null
    }
}
