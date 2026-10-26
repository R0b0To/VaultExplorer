package com.aeidolon.vaultexplorer.audioedit

import kotlin.math.min

/**
 * A one-block read-ahead cache over a positional reader. The logic behind [ReadAheadMediaDataSource],
 * kept free of Android types so it can be tested on the plain JVM.
 *
 * [read] is the underlying source: `read(position, buffer, offset, size)` returns the number of bytes
 * it put in [buffer], or -1 / 0 at the end of the data (the `MediaDataSource.readAt` contract).
 *
 * The block starts at the requested position rather than at an aligned one, since the use is a scan
 * from the start towards the end: everything ahead of the reader is already in memory. A read at a
 * position outside the block loads a new block there; one at least as big as a block skips the cache.
 */
class ReadAheadReader(
    private val blockSize: Int,
    private val read: (position: Long, buffer: ByteArray, offset: Int, size: Int) -> Int,
) {
    private var block: ByteArray? = null
    private var blockStart = -1L
    private var blockLength = 0

    /** How many reads went to the underlying source. */
    var sourceReads = 0
        private set

    @Synchronized
    fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (size <= 0) return 0
        var available = availableAt(position)
        if (available == 0) {
            sourceReads++
            if (size >= blockSize) return read(position, buffer, offset, size)
            val b = block ?: ByteArray(blockSize).also { block = it }
            val n = read(position, b, 0, blockSize)
            if (n <= 0) {
                blockStart = -1L
                blockLength = 0
                return n
            }
            blockStart = position
            blockLength = n
            available = n
        }
        val take = min(size, available)
        System.arraycopy(block!!, (position - blockStart).toInt(), buffer, offset, take)
        return take
    }

    /** How many bytes of the current block lie at and after [position]; 0 when it isn't inside the block. */
    private fun availableAt(position: Long): Int {
        if (block == null || blockStart < 0 || position < blockStart || position >= blockStart + blockLength) return 0
        return (blockStart + blockLength - position).toInt()
    }

    companion object {
        /** 1 MB: a minute or two of typical compressed audio, so a handful of source reads per minute. */
        const val DEFAULT_BLOCK_SIZE = 1024 * 1024
    }
}
