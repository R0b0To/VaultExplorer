package com.aeidolon.vaultexplorer.cloudbridge

import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Log
import java.io.InputStream
import java.util.LinkedHashMap
import kotlin.math.min

/**
 * Exposes a fixed-size remote chunk collection as a normal seekable file.
 * AppFuse calls this from the native container engine's existing file-descriptor
 * path, so native VeraCrypt/LUKS parsing remains unchanged.
 */
class CloudFuseCallback(
    private val client: VaultCloudBridgeClient,
    private val accountId: String,
    private val remoteVaultPath: String,
    private val totalSizeBytes: Long,
    private val chunkSizeBytes: Int,
    private val onReleased: () -> Unit,
) : ProxyFileDescriptorCallback() {
    private data class CachedChunk(var bytes: ByteArray, var dirty: Boolean = false)

    private val chunks = LinkedHashMap<Long, CachedChunk>(MAX_CACHED_CHUNKS, 0.75f, true)

    override fun onGetSize(): Long = totalSizeBytes

    @Synchronized
    override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
        if (offset < 0 || size < 0) fail("invalid read range")
        if (offset >= totalSizeBytes || size == 0) return 0
        val requested = min(size.toLong(), totalSizeBytes - offset).toInt()
        var remaining = requested
        var sourceOffset = offset
        var outputOffset = 0
        while (remaining > 0) {
            val chunkIndex = sourceOffset / chunkSizeBytes
            val offsetInChunk = (sourceOffset % chunkSizeBytes).toInt()
            val chunk = loadChunk(chunkIndex)
            val bytes = min(remaining, chunk.bytes.size - offsetInChunk)
            if (bytes <= 0) fail("read beyond remote chunk")
            System.arraycopy(chunk.bytes, offsetInChunk, data, outputOffset, bytes)
            remaining -= bytes
            sourceOffset += bytes
            outputOffset += bytes
        }
        return requested
    }

    @Synchronized
    override fun onWrite(offset: Long, size: Int, data: ByteArray): Int {
        if (offset < 0 || size < 0) fail("invalid write range")
        if (offset >= totalSizeBytes || size == 0) return 0
        val requested = min(size.toLong(), totalSizeBytes - offset).toInt()
        var remaining = requested
        var targetOffset = offset
        var inputOffset = 0
        while (remaining > 0) {
            val chunkIndex = targetOffset / chunkSizeBytes
            val offsetInChunk = (targetOffset % chunkSizeBytes).toInt()
            val chunk = loadChunk(chunkIndex)
            val bytes = min(remaining, chunk.bytes.size - offsetInChunk)
            if (bytes <= 0) fail("write beyond remote chunk")
            System.arraycopy(data, inputOffset, chunk.bytes, offsetInChunk, bytes)
            chunk.dirty = true
            remaining -= bytes
            targetOffset += bytes
            inputOffset += bytes
        }
        trimCache()
        return requested
    }

    @Synchronized
    override fun onFsync() {
        flushDirtyChunks()
    }

    @Synchronized
    override fun onRelease() {
        try {
            flushDirtyChunks()
        } catch (e: Exception) {
            Log.w(TAG, "Could not flush cloud chunks during release", e)
        } finally {
            chunks.clear()
            client.closeRemoteVaultSession(accountId, remoteVaultPath)
            onReleased()
        }
    }

    private fun loadChunk(chunkIndex: Long): CachedChunk {
        chunks[chunkIndex]?.let { return it }
        val expectedSize = chunkLength(chunkIndex)
        val descriptor = client.openChunkForRead(accountId, remoteVaultPath, chunkIndex)
            ?: fail("remote chunk read failed")
        val bytes = ParcelFileDescriptor.AutoCloseInputStream(descriptor).use {
            it.readExact(expectedSize)
        }
        return CachedChunk(bytes).also {
            chunks[chunkIndex] = it
            trimCache()
        }
    }

    private fun flushDirtyChunks() {
        for ((chunkIndex, chunk) in chunks) {
            if (!chunk.dirty) continue
            val descriptor = client.openChunkForWrite(
                accountId,
                remoteVaultPath,
                chunkIndex,
                chunk.bytes.size.toLong(),
            ) ?: fail("remote chunk write failed")
            ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { it.write(chunk.bytes) }
            if (!client.finalizeChunkWrite(accountId, remoteVaultPath, chunkIndex)) {
                fail("remote chunk write was not committed")
            }
            chunk.dirty = false
        }
    }

    private fun trimCache() {
        while (chunks.size > MAX_CACHED_CHUNKS) {
            val eldest = chunks.entries.iterator().next()
            if (eldest.value.dirty) flushDirtyChunks()
            chunks.remove(eldest.key)
        }
    }

    private fun chunkLength(chunkIndex: Long): Int {
        val chunkStart = chunkIndex * chunkSizeBytes
        if (chunkStart < 0 || chunkStart >= totalSizeBytes) fail("invalid chunk index")
        return min(chunkSizeBytes.toLong(), totalSizeBytes - chunkStart).toInt()
    }

    private fun InputStream.readExact(length: Int): ByteArray {
        val output = ByteArray(length)
        var position = 0
        while (position < output.size) {
            val read = read(output, position, output.size - position)
            if (read <= 0) fail("remote chunk was truncated")
            position += read
        }
        return output
    }

    private fun fail(message: String): Nothing = throw ErrnoException(message, OsConstants.EIO)

    private companion object {
        const val TAG = "CloudFuseCallback"
        const val MAX_CACHED_CHUNKS = 8
    }
}
