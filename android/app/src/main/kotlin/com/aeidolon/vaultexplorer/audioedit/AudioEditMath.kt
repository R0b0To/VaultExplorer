package com.aeidolon.vaultexplorer.audioedit

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** What the lossless audio cut writes its output into. */
enum class AudioContainer {
    /** `MediaMuxer` MPEG-4 (AAC) -> `.m4a`. */
    MP4,

    /** `MediaMuxer` WebM (Vorbis / Opus) -> `.weba`. */
    WEBM,

    /** `MediaMuxer` Ogg (Opus, API 30+). */
    OGG,

    /** Concatenated MP3 frames, written by hand: `MediaMuxer` can't write MP3. */
    MP3,

    /** PCM re-wrapped in a fresh RIFF/WAVE header, written by hand. */
    WAV,
}

sealed class AudioCutPlan {
    /** The encoded samples can be copied into [container] as they are: no quality loss. */
    class Supported(val container: AudioContainer, val extension: String) : AudioCutPlan()

    /**
     * Nothing here can write this codec as it is, so the audio is decoded and
     * encoded again as AAC in an `.m4a` (see `AudioReencoder`). Audio is cheap to
     * re-encode, so this is the fallback for FLAC, WMA, AC-3, AMR and the like.
     */
    class Reencode(val extension: String = "m4a") : AudioCutPlan()

    /** Not editable at all (no audio, or a layout the fallback can't handle either). */
    class Unsupported(val reason: String) : AudioCutPlan()
}

/**
 * The parts of the Audio Editor's native half that don't touch Android
 * classes, kept apart from [LosslessAudioCutter] / [AudioWaveformExtractor]
 * so plain JVM unit tests can exercise them (see `AudioEditMathTest`).
 */
object AudioEditMath {
    // android.media.AudioFormat PCM encodings, as MediaFormat.KEY_PCM_ENCODING reports them.
    const val PCM_16BIT = 2
    const val PCM_8BIT = 3
    const val PCM_FLOAT = 4
    const val PCM_24BIT_PACKED = 21
    const val PCM_32BIT = 22

    const val MIME_AAC = "audio/mp4a-latm"
    const val MIME_MP3 = "audio/mpeg"
    const val MIME_OPUS = "audio/opus"
    const val MIME_VORBIS = "audio/vorbis"
    const val MIME_RAW = "audio/raw"

    /** RIFF sizes are 32-bit, so a WAV can't hold more data than this. */
    const val MAX_WAV_DATA_BYTES = 0xFFFF_FFFFL - 36L

    /** Waveform resolution: 10 ms per peak, until the peak list would exceed [MAX_PEAKS]. */
    const val TARGET_PEAKS_PER_SECOND = 100.0
    const val MAX_PEAKS = 100_000

    /**
     * Picks the output container and file extension for a source track.
     *
     * `MediaMuxer` can only write a few audio codecs (AAC, Opus, Vorbis), so
     * MP3 and WAV get hand-written writers. Every other codec (FLAC, WMA,
     * AC-3, AMR, ...) is a [AudioCutPlan.Reencode]: it can't be copied, so it
     * is decoded and re-encoded to AAC. Lossless copying is always preferred.
     *
     * [sourceExtension] only influences the result where several extensions
     * share a codec (`.opus` vs `.ogg`) or where `audio/raw` has to be a WAV.
     */
    fun planOutput(mime: String?, sourceExtension: String, sdkInt: Int): AudioCutPlan {
        val ext = sourceExtension.lowercase(Locale.ROOT)
        return when (mime) {
            null -> AudioCutPlan.Unsupported("No audio track found in this file")
            MIME_AAC -> AudioCutPlan.Supported(AudioContainer.MP4, "m4a")
            MIME_MP3 -> AudioCutPlan.Supported(AudioContainer.MP3, "mp3")
            MIME_VORBIS -> AudioCutPlan.Supported(AudioContainer.WEBM, "weba")
            MIME_OPUS ->
                if (sdkInt >= 30) {
                    val keep = if (ext == "opus" || ext == "oga") ext else "ogg"
                    AudioCutPlan.Supported(AudioContainer.OGG, keep)
                } else {
                    AudioCutPlan.Supported(AudioContainer.WEBM, "weba")
                }
            MIME_RAW ->
                if (ext == "wav" || ext == "wave") {
                    AudioCutPlan.Supported(AudioContainer.WAV, "wav")
                } else {
                    // PCM in some other container: no WAV header to reuse, so re-encode.
                    AudioCutPlan.Reencode()
                }
            else ->
                if (mime.startsWith("audio/")) {
                    AudioCutPlan.Reencode()
                } else {
                    AudioCutPlan.Unsupported("$mime is not an audio format")
                }
        }
    }

    /** Sample rates the AAC encoder accepts. */
    val AAC_SAMPLE_RATES: Set<Int> = setOf(
        8_000, 11_025, 12_000, 16_000, 22_050, 24_000,
        32_000, 44_100, 48_000, 64_000, 88_200, 96_000,
    )

    /**
     * Why the AAC fallback can't take this audio, or null when it can. Very
     * high rates (176.4 / 192 kHz FLAC) would need resampling, which isn't done.
     */
    fun reencodeIssue(sampleRate: Int?, channels: Int?): String? = when {
        sampleRate == null || sampleRate <= 0 -> "The sample rate of this file is unknown"
        channels == null || channels <= 0 -> "The channel count of this file is unknown"
        sampleRate !in AAC_SAMPLE_RATES -> "$sampleRate Hz audio can't be re-encoded"
        else -> null
    }

    /** Output channel count of the AAC fallback: mono stays mono, anything wider is cut to the front pair. */
    fun reencodeChannels(inputChannels: Int): Int = if (inputChannels <= 1) 1 else 2

    /**
     * AAC bitrate for the fallback. A lossy source keeps roughly its own
     * bitrate (so re-encoding doesn't throw away more than needed); lossless
     * and unknown sources get 96 kbps per channel. Clamped to 64..160 kbps per
     * channel.
     */
    fun reencodeBitrate(sourceBitrate: Int?, inputChannels: Int): Int {
        val ch = reencodeChannels(inputChannels)
        val floor = 64_000 * ch
        val ceil = 160_000 * ch
        val base = if (sourceBitrate != null && sourceBitrate in 1..ceil) sourceBitrate else 96_000 * ch
        return base.coerceIn(floor, ceil)
    }

    /** Bytes per sample for [encoding] (null = the 16-bit default), or null when unsupported. */
    fun bytesPerSample(encoding: Int?): Int? = when (encoding ?: PCM_16BIT) {
        PCM_8BIT -> 1
        PCM_16BIT -> 2
        PCM_24BIT_PACKED -> 3
        PCM_32BIT, PCM_FLOAT -> 4
        else -> null
    }

    /** Microseconds -> a PCM frame index at [sampleRate], rounded to nearest. */
    fun usToFrame(us: Long, sampleRate: Int): Long = (us * sampleRate + 500_000L) / 1_000_000L

    /**
     * The part of one PCM chunk that lies inside the frame window
     * `[windowStartFrame, windowEndFrame)`, as `(fromByte, toByte)` offsets
     * into the chunk -- or null when they don't overlap. A trailing partial
     * frame in the chunk is ignored.
     */
    fun pcmSlice(
        chunkStartFrame: Long,
        chunkBytes: Int,
        blockAlign: Int,
        windowStartFrame: Long,
        windowEndFrame: Long,
    ): Pair<Int, Int>? {
        if (blockAlign <= 0 || chunkBytes < blockAlign) return null
        val chunkEndFrame = chunkStartFrame + chunkBytes / blockAlign
        val from = max(chunkStartFrame, windowStartFrame)
        val to = min(chunkEndFrame, windowEndFrame)
        if (to <= from) return null
        return Pair(
            ((from - chunkStartFrame) * blockAlign).toInt(),
            ((to - chunkStartFrame) * blockAlign).toInt(),
        )
    }

    /** The 44-byte RIFF/WAVE header for [dataBytes] of PCM (pass 0 and patch it on finish). */
    fun wavHeader(
        sampleRate: Int,
        channels: Int,
        bytesPerSample: Int,
        isFloat: Boolean,
        dataBytes: Long,
    ): ByteArray {
        val blockAlign = channels * bytesPerSample
        val byteRate = sampleRate.toLong() * blockAlign
        val b = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray(Charsets.US_ASCII))
        b.putInt(((36L + dataBytes) and 0xFFFF_FFFFL).toInt())
        b.put("WAVE".toByteArray(Charsets.US_ASCII))
        b.put("fmt ".toByteArray(Charsets.US_ASCII))
        b.putInt(16)
        b.putShort((if (isFloat) 3 else 1).toShort()) // 1 = PCM, 3 = IEEE float
        b.putShort(channels.toShort())
        b.putInt(sampleRate)
        b.putInt((byteRate and 0xFFFF_FFFFL).toInt())
        b.putShort(blockAlign.toShort())
        b.putShort((bytesPerSample * 8).toShort())
        b.put("data".toByteArray(Charsets.US_ASCII))
        b.putInt((dataBytes and 0xFFFF_FFFFL).toInt())
        return b.array()
    }

    // ── Waveform ─────────────────────────────────────────────────────────

    /** Peaks per second to use for a file of [durationUs]. */
    fun peaksPerSecondFor(durationUs: Long): Double {
        val seconds = durationUs / 1_000_000.0
        if (seconds <= 0.0) return TARGET_PEAKS_PER_SECOND
        return min(TARGET_PEAKS_PER_SECOND, MAX_PEAKS / seconds)
    }

    /** Number of peak buckets covering [durationUs] at [peaksPerSecond]. */
    fun bucketCountFor(durationUs: Long, peaksPerSecond: Double): Int {
        val raw = ceil(durationUs / 1_000_000.0 * peaksPerSecond).toInt()
        return raw.coerceIn(1, MAX_PEAKS)
    }
}

/**
 * Keeps the loudest sample seen in each time bucket, as a 0..255 byte.
 * [bucketsPerFrame] is buckets per PCM frame (peaks-per-second / sample rate).
 */
class PeakAccumulator(val bucketCount: Int, var bucketsPerFrame: Double) {
    val peaks = ByteArray(bucketCount)

    /** [amplitude] is the absolute sample level, 0..1 (the loudest channel of the frame). */
    fun add(frameIndex: Long, amplitude: Float) {
        val bucket = (frameIndex * bucketsPerFrame).toInt()
        if (bucket < 0 || bucket >= bucketCount) return
        val level = (amplitude * 255f + 0.5f).toInt().coerceIn(0, 255)
        if (level > (peaks[bucket].toInt() and 0xFF)) peaks[bucket] = level.toByte()
    }
}

/** Feeds interleaved little-endian PCM into a [PeakAccumulator], one frame at a time. */
class PcmPeakReader(private val accumulator: PeakAccumulator) {
    var channels: Int = 2
    var encoding: Int = AudioEditMath.PCM_16BIT

    /** Index of the next PCM frame; also the number of frames consumed so far. */
    var frameIndex: Long = 0L
        private set

    fun consume(data: ByteBuffer, offset: Int, size: Int) {
        val bytesPerSample = AudioEditMath.bytesPerSample(encoding) ?: return
        val channelCount = max(1, channels)
        val frames = size / (bytesPerSample * channelCount)

        val view = data.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        view.limit(offset + size)
        var pos = offset
        for (frame in 0 until frames) {
            var loudest = 0f
            for (channel in 0 until channelCount) {
                val level = amplitudeAt(view, pos)
                if (level > loudest) loudest = level
                pos += bytesPerSample
            }
            accumulator.add(frameIndex, loudest)
            frameIndex++
        }
    }

    private fun amplitudeAt(b: ByteBuffer, pos: Int): Float = when (encoding) {
        AudioEditMath.PCM_8BIT -> abs((b.get(pos).toInt() and 0xFF) - 128) / 128f
        AudioEditMath.PCM_16BIT -> abs(b.getShort(pos).toInt()) / 32768f
        AudioEditMath.PCM_24BIT_PACKED -> {
            // The top byte is read signed, which sign-extends the 24-bit value.
            val v = (b.get(pos).toInt() and 0xFF) or
                ((b.get(pos + 1).toInt() and 0xFF) shl 8) or
                (b.get(pos + 2).toInt() shl 16)
            abs(v) / 8388608f
        }
        AudioEditMath.PCM_32BIT -> abs(b.getInt(pos).toLong()).toFloat() / 2147483648f
        AudioEditMath.PCM_FLOAT -> abs(b.getFloat(pos))
        else -> 0f
    }
}

/** Converts the PCM layouts [AudioEditMath.bytesPerSample] knows into 16-bit, for the AAC encoder. */
object PcmConvert {
    /**
     * Reads [frameCount] frames starting at frame [firstFrame] of the
     * interleaved little-endian PCM in [data] (which begins at byte [offset]),
     * keeps the first [outChannels] channels of each, and writes them as
     * interleaved 16-bit samples into [out] (needs `frameCount * outChannels`
     * room).
     */
    fun toPcm16(
        data: ByteBuffer,
        offset: Int,
        encoding: Int,
        inChannels: Int,
        outChannels: Int,
        firstFrame: Int,
        frameCount: Int,
        out: ShortArray,
    ) {
        val bytesPerSample = AudioEditMath.bytesPerSample(encoding)
            ?: throw IllegalArgumentException("Unsupported PCM encoding $encoding")
        val view = data.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        val frameBytes = bytesPerSample * inChannels
        var pos = offset + firstFrame * frameBytes
        var o = 0
        for (frame in 0 until frameCount) {
            for (channel in 0 until outChannels) {
                out[o++] = sample16(view, pos + channel * bytesPerSample, encoding)
            }
            pos += frameBytes
        }
    }

    private fun sample16(b: ByteBuffer, pos: Int, encoding: Int): Short = when (encoding) {
        AudioEditMath.PCM_8BIT -> (((b.get(pos).toInt() and 0xFF) - 128) shl 8).toShort()
        AudioEditMath.PCM_16BIT -> b.getShort(pos)
        AudioEditMath.PCM_24BIT_PACKED -> {
            val v = (b.get(pos).toInt() and 0xFF) or
                ((b.get(pos + 1).toInt() and 0xFF) shl 8) or
                (b.get(pos + 2).toInt() shl 16)
            (v shr 8).toShort()
        }
        AudioEditMath.PCM_32BIT -> (b.getInt(pos) shr 16).toShort()
        AudioEditMath.PCM_FLOAT -> (b.getFloat(pos).coerceIn(-1f, 1f) * 32767f).toInt().toShort()
        else -> 0
    }
}
