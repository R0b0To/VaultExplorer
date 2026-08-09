package com.aeidolon.vaultexplorer

import android.os.ProxyFileDescriptorCallback
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.min

/**
 * Exposes an ordered sequence of local split-container part files
 * (`<name>.001`, `<name>.002`, ... -- see [SplitPartResolver]) as one
 * normal seekable file. [SplitContainerMountHandlers] hands the resulting
 * proxy fd straight to [ContainerEngine.unlockFile] exactly like a
 * normal single-file mount's fd, so native VeraCrypt/LUKS/BitLocker
 * parsing and every existing mounted-volume code path (browsing, editing,
 * document provider, lock) stays completely unaware the backing store is
 * split across several files on disk -- mirrors the same
 * `ProxyFileDescriptorCallback` shape `CloudFuseCallback` used for
 * remote chunked vaults (see that class's doc comment), just with plain
 * local file reads/writes instead of a cross-process chunk RPC, so there's
 * no need for its LRU chunk cache: a [RandomAccessFile] handle per part,
 * opened lazily and kept open for the life of the mount, is already as
 * fast as local I/O gets.
 *
 * [parts] must all already exist and be a real, unbroken sequence
 * ([SplitPartResolver.resolvePartSequence]'s job, not this class's) --
 * this class only maps byte offsets to (part index, offset-in-part) and
 * does not re-validate the sequence.
 */
class LocalSplitFuseCallback(
    private val parts: List<File>,
    private val onReleased: () -> Unit,
) : ProxyFileDescriptorCallback() {
    init {
        require(parts.isNotEmpty()) { "LocalSplitFuseCallback needs at least one part" }
    }

    // Cumulative byte offset at which each part begins, so a request
    // range can be mapped to the covering part(s) directly instead of
    // re-summing sizes on every read/write. partStarts[i] is where
    // parts[i] begins; the implicit partStarts[parts.size] is totalSize.
    private val partStarts: LongArray = run {
        var acc = 0L
        LongArray(parts.size) { i -> acc.also { acc += parts[i].length() } }
    }
    private val totalSizeBytes: Long = partStarts.last() + parts.last().length()

    // Opened lazily per part on first touch, kept open for the mount's
    // lifetime, closed together in onRelease -- avoids a
    // open/seek/read/close round trip per request the way a fresh
    // FileInputStream per read would.
    private val openParts = arrayOfNulls<RandomAccessFile>(parts.size)

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
            val partIndex = partIndexFor(sourceOffset)
            val offsetInPart = sourceOffset - partStarts[partIndex]
            val raf = openPart(partIndex, forWrite = false)
            val bytesInThisPart = min(remaining.toLong(), parts[partIndex].length() - offsetInPart).toInt()
            if (bytesInThisPart <= 0) fail("read beyond part $partIndex")
            raf.seek(offsetInPart)
            var readInPart = 0
            while (readInPart < bytesInThisPart) {
                val n = raf.read(data, outputOffset + readInPart, bytesInThisPart - readInPart)
                if (n < 0) fail("part $partIndex ended unexpectedly")
                readInPart += n
            }
            remaining -= bytesInThisPart
            sourceOffset += bytesInThisPart
            outputOffset += bytesInThisPart
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
            val partIndex = partIndexFor(targetOffset)
            val offsetInPart = targetOffset - partStarts[partIndex]
            val raf = openPart(partIndex, forWrite = true)
            val bytesInThisPart = min(remaining.toLong(), parts[partIndex].length() - offsetInPart).toInt()
            if (bytesInThisPart <= 0) fail("write beyond part $partIndex")
            raf.seek(offsetInPart)
            raf.write(data, inputOffset, bytesInThisPart)
            remaining -= bytesInThisPart
            targetOffset += bytesInThisPart
            inputOffset += bytesInThisPart
        }
        return requested
    }

    @Synchronized
    override fun onFsync() {
        for (raf in openParts) {
            try { raf?.fd?.sync() } catch (_: Exception) {}
        }
    }

    @Synchronized
    override fun onRelease() {
        for (raf in openParts) {
            try { raf?.close() } catch (_: Exception) {}
        }
        openParts.fill(null)
        onReleased()
    }

    private fun partIndexFor(byteOffset: Long): Int {
        // Linear scan: split-container part counts are small (tens, not
        // thousands, even at the smallest 8 MB cloud preset against a
        // multi-GB container) and reads/writes are already chunk-batched
        // upstream (disk_read/disk_write's MAX_SECTORS_PER_BATCH), so this
        // isn't a hot enough path to justify a binary search here.
        for (i in parts.indices.reversed()) {
            if (byteOffset >= partStarts[i]) return i
        }
        fail("offset $byteOffset before first part")
    }

    private fun openPart(index: Int, forWrite: Boolean): RandomAccessFile {
        openParts[index]?.let { return it }
        val mode = if (forWrite) "rw" else "r"
        val raf = try {
            RandomAccessFile(parts[index], mode)
        } catch (e: Exception) {
            fail("could not open part ${parts[index].name}: ${e.message}")
        }
        openParts[index] = raf
        return raf
    }

    private fun fail(message: String): Nothing {
        Log.w(TAG, message)
        throw ErrnoException(message, OsConstants.EIO)
    }

    private companion object {
        const val TAG = "LocalSplitFuseCallback"
    }
}
