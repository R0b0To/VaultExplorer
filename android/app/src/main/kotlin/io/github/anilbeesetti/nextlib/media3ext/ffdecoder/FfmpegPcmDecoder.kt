package io.github.anilbeesetti.nextlib.media3ext.ffdecoder

import android.media.MediaFormat
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.util.MediaFormatUtil
import java.nio.ByteBuffer

/**
 * Decode-to-PCM access to nextlib's FFmpeg audio decoder, for code that has to turn compressed
 * audio into samples outside the player (the Audio Editor's waveform).
 *
 * `MediaCodec` is the first choice everywhere, but Android doesn't guarantee an AC-3 / E-AC-3 /
 * DTS decoder (many Qualcomm phones, e.g. the Moto Edge 30, ship none), whereas the player already
 * falls back to FFmpeg for exactly those formats. This gives the waveform the same fallback.
 *
 * It sits in nextlib's own package on purpose: [FfmpegAudioDecoder] is package-private, and
 * everything of nextlib's that *is* public is player-shaped (renderers). Same package name is all
 * the Java/Kotlin visibility check needs; there is no JPMS on Android.
 *
 * The underlying `SimpleDecoder` decodes on its own thread and never blocks, so the three calls
 * here don't either: [queueSample] / [queueEndOfStream] return false when no input buffer is free
 * yet, [drain] returns whatever has been decoded so far. The caller loops, sleeping briefly when
 * neither made progress.
 *
 * Output is interleaved 16-bit PCM in native byte order.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class FfmpegPcmDecoder private constructor(
    private val decoder: FfmpegAudioDecoder,
) : AutoCloseable {

    /** Channel count of the decoded PCM; 0 until the first chunk has come out. */
    val channelCount: Int get() = decoder.channelCount

    /** Sample rate of the decoded PCM; 0 until the first chunk has come out. */
    val sampleRate: Int get() = decoder.sampleRate

    /**
     * Hands one compressed access unit (`data[0, size)`) to the decoder. Returns false, having
     * consumed nothing, when every input buffer is still busy -- [drain] and try again.
     */
    fun queueSample(data: ByteBuffer, size: Int, timeUs: Long): Boolean {
        val input = decoder.dequeueInputBuffer() ?: return false
        input.ensureSpaceForWrite(size)
        val dst = checkNotNull(input.data)
        val src = data.duplicate()
        src.position(0)
        src.limit(size)
        dst.put(src)
        input.timeUs = timeUs
        input.flip()
        decoder.queueInputBuffer(input)
        return true
    }

    /** Signals that no more input is coming. Returns false when no input buffer is free yet. */
    fun queueEndOfStream(): Boolean {
        val input = decoder.dequeueInputBuffer() ?: return false
        input.addFlag(C.BUFFER_FLAG_END_OF_STREAM)
        decoder.queueInputBuffer(input)
        return true
    }

    /**
     * Passes every chunk decoded so far to [sink] as (buffer, offset, size) and releases it.
     * Returns true once the end-of-stream marker has come out (so after [queueEndOfStream]).
     */
    fun drain(sink: (ByteBuffer, Int, Int) -> Unit): Boolean {
        while (true) {
            val out = decoder.dequeueOutputBuffer() ?: return false
            try {
                if (out.isEndOfStream) return true
                val data = out.data
                if (data != null && data.remaining() > 0) sink(data, data.position(), data.remaining())
            } finally {
                out.release()
            }
        }
    }

    override fun close() = decoder.release()

    companion object {
        private const val NUM_BUFFERS = 8
        private const val DEFAULT_INPUT_BUFFER_SIZE = 16 * 1024

        /** Whether the bundled FFmpeg can decode [mime] (and its native library loaded at all). */
        fun supports(mime: String): Boolean = FfmpegLibrary.supportsFormat(mime)

        /** Opens a decoder for a track whose format came from an extractor. Check [supports] first. */
        fun create(trackFormat: MediaFormat): FfmpegPcmDecoder {
            val format = MediaFormatUtil.createFormatFromMediaFormat(trackFormat)
            val inputSize =
                if (format.maxInputSize != Format.NO_VALUE) format.maxInputSize else DEFAULT_INPUT_BUFFER_SIZE
            return FfmpegPcmDecoder(
                FfmpegAudioDecoder(format, NUM_BUFFERS, NUM_BUFFERS, inputSize, /* outputFloat= */ false),
            )
        }
    }
}
