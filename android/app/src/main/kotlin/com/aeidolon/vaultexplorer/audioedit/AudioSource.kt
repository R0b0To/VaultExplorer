package com.aeidolon.vaultexplorer.audioedit

import android.media.MediaExtractor
import android.media.MediaFormat
import androidx.media3.decoder.DecoderInputBuffer
import androidx.media3.inspector.MediaExtractorCompat
import java.nio.ByteBuffer

/**
 * The slice of `MediaExtractor` the Audio Editor uses, so the cutter, the
 * waveform and the re-encoder don't care which extractor stack is behind it:
 *
 *  - [PlatformAudioSource]: Android's own `MediaExtractor` (MP4/M4A, MP3, WAV,
 *    Ogg, FLAC, ... whatever the OS knows). Tried first, so everything that
 *    already worked behaves exactly as before.
 *  - [Media3AudioSource]: Media3's extractors through `MediaExtractorCompat`,
 *    i.e. the same demuxers the player uses -- including `AiffAwareExtractorsFactory`
 *    (AIFF/AIFF-C), AC-3 / E-AC-3 / DTS elementary streams and so on. The
 *    platform extractor fails with "failed to instantiate extractor" on those.
 *
 * Property names match `MediaExtractor`'s Kotlin synthetic properties on
 * purpose, so call sites read the same as before.
 */
interface AudioSource {
    val trackCount: Int

    /** Track of the current sample, or -1 at the end of the stream. */
    val sampleTrackIndex: Int

    /** Presentation time of the current sample in microseconds, or -1 at the end. */
    val sampleTime: Long

    val sampleFlags: Int

    fun getTrackFormat(index: Int): MediaFormat
    fun selectTrack(index: Int)
    fun seekTo(timeUs: Long, mode: Int)
    fun readSampleData(buffer: ByteBuffer, offset: Int): Int
    fun advance(): Boolean
    fun release()
}

class PlatformAudioSource(private val extractor: MediaExtractor) : AudioSource {
    override val trackCount: Int get() = extractor.trackCount
    override val sampleTrackIndex: Int get() = extractor.sampleTrackIndex
    override val sampleTime: Long get() = extractor.sampleTime
    override val sampleFlags: Int get() = extractor.sampleFlags

    override fun getTrackFormat(index: Int): MediaFormat = extractor.getTrackFormat(index)
    override fun selectTrack(index: Int) = extractor.selectTrack(index)
    override fun seekTo(timeUs: Long, mode: Int) = extractor.seekTo(timeUs, mode)
    override fun readSampleData(buffer: ByteBuffer, offset: Int): Int = extractor.readSampleData(buffer, offset)
    override fun advance(): Boolean = extractor.advance()
    override fun release() = extractor.release()
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class Media3AudioSource(private val extractor: MediaExtractorCompat) : AudioSource {
    override val trackCount: Int get() = extractor.trackCount
    override val sampleTrackIndex: Int get() = extractor.sampleTrackIndex
    override val sampleTime: Long get() = extractor.sampleTime
    override val sampleFlags: Int get() = extractor.sampleFlags

    override fun getTrackFormat(index: Int): MediaFormat = extractor.getTrackFormat(index)
    override fun selectTrack(index: Int) = extractor.selectTrack(index)
    override fun seekTo(timeUs: Long, mode: Int) = extractor.seekTo(timeUs, mode)
    override fun readSampleData(buffer: ByteBuffer, offset: Int): Int = try {
        extractor.readSampleData(buffer, offset)
    } catch (e: DecoderInputBuffer.InsufficientCapacityException) {
        // The platform extractor reports an undersized buffer as IllegalArgumentException; callers
        // grow the buffer and retry on exactly that (the sample stays queued, so a retry is safe).
        throw IllegalArgumentException(e.message, e)
    }
    override fun advance(): Boolean = extractor.advance()
    override fun release() = extractor.release()
}
