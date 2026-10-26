package com.aeidolon.vaultexplorer.audioedit

import android.media.MediaDataSource

/**
 * Puts a read-ahead block in front of a [MediaDataSource].
 *
 * `MediaExtractor` walks a file in small steps: one audio frame is a few hundred bytes, and the
 * platform's own cache in front of the source is only a few KB. Against a vault file every one of those
 * reads is a call into the native engine (JNI, locking, finding and decrypting the block the bytes live
 * in), so a 3 hour file means tens of thousands of calls, each paying that fixed cost for a handful of
 * bytes. This reads a megabyte at a time instead and serves the small reads from memory (the logic is in
 * [ReadAheadReader]).
 *
 * Meant for a front-to-back scan, which is what the waveform does. One block per instance; every
 * extractor gets its own source, so there is nothing to share.
 */
class ReadAheadMediaDataSource(
    private val delegate: MediaDataSource,
    blockSize: Int = ReadAheadReader.DEFAULT_BLOCK_SIZE,
) : MediaDataSource() {
    private val reader = ReadAheadReader(blockSize) { position, buffer, offset, size ->
        delegate.readAt(position, buffer, offset, size)
    }

    override fun getSize(): Long = delegate.getSize()

    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int =
        reader.readAt(position, buffer, offset, size)

    override fun close() {
        delegate.close()
    }
}
