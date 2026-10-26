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

    /**
     * Concatenated AC-3 / E-AC-3 syncframes (a plain `.ac3` / `.eac3` elementary
     * stream), written by hand: every frame is self-contained, like MP3's.
     */
    AC3,
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

    // Media3's big-endian encodings (C.ENCODING_PCM_*_BIG_ENDIAN). They have no android.media.AudioFormat
    // equivalent, so Media3 reports them only through MediaFormat key "exo-pcm-encoding-int"; AIFF is the
    // one place they come from here (AiffExtractor).
    const val PCM_16BIT_BE = 0x10000000
    const val PCM_24BIT_BE = 0x50000000
    const val PCM_32BIT_BE = 0x60000000
    const val PCM_FLOAT_BE = 0x71000000

    /** Extensions of Apple's AIFF family; these decode as PCM and are cut to WAV without loss. */
    val AIFF_EXTENSIONS: Set<String> = setOf("aif", "aiff", "aifc", "afc")

    const val MIME_AAC = "audio/mp4a-latm"
    const val MIME_MP3 = "audio/mpeg"
    const val MIME_OPUS = "audio/opus"
    const val MIME_VORBIS = "audio/vorbis"
    const val MIME_FLAC = "audio/flac"
    const val MIME_RAW = "audio/raw"
    const val MIME_AC3 = "audio/ac3"
    const val MIME_EAC3 = "audio/eac3"
    const val MIME_EAC3_JOC = "audio/eac3-joc"

    /** RIFF sizes are 32-bit, so a WAV can't hold more data than this. */
    const val MAX_WAV_DATA_BYTES = 0xFFFF_FFFFL - 36L

    /**
     * Waveform resolution: 10 ms per peak, until the peak list would exceed [MAX_PEAKS].
     *
     * One byte per peak, so 500k peaks is half a megabyte -- cheap to hold and to ship over the
     * channel. It is the full 100/s up to ~83 minutes; a 3 hour file still gets ~46 peaks per
     * second (~22 ms), enough to see where a cut lands when zoomed in. (It used to be 100k, which
     * left a 3 hour file at ~9 peaks per second: only a handful of blocks across the screen at
     * the editor's maximum zoom.)
     */
    const val TARGET_PEAKS_PER_SECOND = 100.0
    const val MAX_PEAKS = 500_000

    // ── Decoding a long file in parallel ─────────────────────────────────

    /** Shorter files decode quickly enough in one piece, so they take the plain path. */
    const val PARALLEL_MIN_DURATION_US = 20L * 60L * 1_000_000L
    const val PARALLEL_MAX_WORKERS = 4

    /** A worker takes the file in pieces of about this much audio, front to back. */
    const val PARALLEL_CHUNK_SECONDS = 120.0

    /**
     * Codecs whose containers seek to an exact frame with exact timestamps (MP4/M4A, Ogg, FLAC), which a
     * decode that starts mid-file relies on to put each peak at the right time. MP3 is left out on
     * purpose: without a full seek table Android estimates a position from the bitrate, and the
     * timestamp it then reports can be seconds off the real audio.
     */
    fun seeksExactly(mime: String): Boolean =
        mime == MIME_AAC || mime == MIME_OPUS || mime == MIME_VORBIS || mime == MIME_FLAC

    /** How many decoders to run side by side for this file: 1 means the plain front-to-back decode. */
    fun parallelWorkersFor(mime: String, durationUs: Long, cpuCount: Int): Int {
        if (!seeksExactly(mime) || durationUs < PARALLEL_MIN_DURATION_US) return 1
        val workers = min(PARALLEL_MAX_WORKERS, cpuCount / 2)
        return if (workers >= 2) workers else 1
    }

    /** Peaks per piece. Pieces start on a bucket boundary, so no two workers ever share a bucket. */
    fun chunkBuckets(peaksPerSecond: Double): Int =
        max(1, ceil(PARALLEL_CHUNK_SECONDS * peaksPerSecond).toInt())

    /** Where bucket [bucket] begins in the audio, in microseconds. */
    fun bucketStartUs(bucket: Int, peaksPerSecond: Double): Long =
        (bucket / peaksPerSecond * 1_000_000.0).toLong()

    /** The PCM frame a presentation time falls on, at [sampleRate]. */
    fun frameAtUs(timeUs: Long, sampleRate: Int): Long =
        Math.round(max(0L, timeUs) * sampleRate / 1_000_000.0)

    // ── A rough picture of a long file, first ────────────────────────────

    /**
     * Decoding a 3 hour file in full takes minutes whatever is done to the PCM afterwards (a frame is
     * decoded whole before anything can be thrown away), so a long file first gets a rough picture from
     * short samples spread across it: [OVERVIEW_WINDOW_US] of audio every few seconds, about a tenth of
     * the file or less. The editor shows that at once; the full decode then replaces it from the left.
     */
    const val OVERVIEW_MAX_WINDOWS = 3000
    const val OVERVIEW_MIN_SPACING_US = 3_000_000L
    const val OVERVIEW_WINDOW_US = 300_000L

    /** The rough pass needs exact seeks (like the parallel decode) and a file long enough to be worth it. */
    fun overviewEligible(mime: String, durationUs: Long): Boolean =
        seeksExactly(mime) && durationUs >= PARALLEL_MIN_DURATION_US

    fun overviewWindowCount(durationUs: Long): Int =
        ((durationUs + OVERVIEW_MIN_SPACING_US - 1) / OVERVIEW_MIN_SPACING_US).toInt()
            .coerceIn(1, OVERVIEW_MAX_WINDOWS)

    /** The stretch of the file each window stands for. */
    fun overviewSpacingUs(durationUs: Long, windows: Int): Long =
        max(1L, ceil(durationUs.toDouble() / max(1, windows)).toLong())

    /** Where window [window] measures: the middle of its stretch, so it is the most typical sample of it. */
    fun overviewWindowStartUs(window: Int, spacingUs: Long): Long =
        window * spacingUs + max(0L, (spacingUs - OVERVIEW_WINDOW_US) / 2)

    /** Spreads one level per window over the full-resolution peak array: each peak takes its window's level. */
    fun expandOverview(levels: ByteArray, spacingUs: Long, bucketCount: Int, peaksPerSecond: Double): ByteArray {
        val out = ByteArray(bucketCount)
        if (levels.isEmpty() || spacingUs <= 0 || peaksPerSecond <= 0) return out
        for (bucket in 0 until bucketCount) {
            val window = (bucketStartUs(bucket, peaksPerSecond) / spacingUs).toInt().coerceIn(0, levels.size - 1)
            out[bucket] = levels[window]
        }
        return out
    }

    /** The coarse-bucket sampler looks at no fewer than this many frames per peak (see [strideFor]). */
    const val MIN_FRAMES_PER_PEAK_SAMPLED = 256

    /**
     * Picks the output container and file extension for a source track.
     *
     * `MediaMuxer` can only write a few audio codecs (AAC, Opus, Vorbis), so
     * MP3 and WAV get hand-written writers. Every other codec (FLAC, WMA,
     * AC-3, AMR, ...) is a [AudioCutPlan.Reencode]: it can't be copied, so it
     * is decoded and re-encoded to AAC. Lossless copying is always preferred.
     *
     * AC-3 / E-AC-3 are copied frame by frame into a raw `.ac3` / `.eac3`
     * stream, which (unlike a re-encode) needs no decoder at all.
     *
     * [sourceExtension] only influences the result where several extensions
     * share a codec (`.opus` vs `.ogg`) or where `audio/raw` has to be a WAV.
     * [losslessPcm] says the raw PCM can be written as a WAV whatever its
     * container (AIFF, or any big-endian source): the WAV header is built from
     * the track's own layout, so there is nothing to reuse from the source.
     */
    fun planOutput(
        mime: String?,
        sourceExtension: String,
        sdkInt: Int,
        losslessPcm: Boolean = false,
    ): AudioCutPlan {
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
            MIME_AC3 -> AudioCutPlan.Supported(AudioContainer.AC3, "ac3")
            MIME_EAC3, MIME_EAC3_JOC -> AudioCutPlan.Supported(AudioContainer.AC3, "eac3")
            MIME_RAW ->
                if (ext == "wav" || ext == "wave" || losslessPcm) {
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

    /**
     * AAC bitrate for an explicit "compress" export: [perChannel] bits per
     * second for each of [outChannels] channels, kept within the same
     * 16..160 kbps per channel the encoder handles well. Unlike
     * [reencodeBitrate] it ignores the source's own bitrate -- the whole point
     * is to go lower than the source.
     */
    fun compressBitrate(perChannel: Int, outChannels: Int): Int {
        val ch = outChannels.coerceIn(1, 2)
        return (perChannel.coerceIn(16_000, 160_000)) * ch
    }

    /** Bytes per sample for [encoding] (null = the 16-bit default), or null when unsupported. */
    fun bytesPerSample(encoding: Int?): Int? = when (encoding ?: PCM_16BIT) {
        PCM_8BIT -> 1
        PCM_16BIT, PCM_16BIT_BE -> 2
        PCM_24BIT_PACKED, PCM_24BIT_BE -> 3
        PCM_32BIT, PCM_FLOAT, PCM_32BIT_BE, PCM_FLOAT_BE -> 4
        else -> null
    }

    fun isBigEndian(encoding: Int?): Boolean = when (encoding) {
        PCM_16BIT_BE, PCM_24BIT_BE, PCM_32BIT_BE, PCM_FLOAT_BE -> true
        else -> false
    }

    fun isFloat(encoding: Int?): Boolean = encoding == PCM_FLOAT || encoding == PCM_FLOAT_BE

    /** The little-endian encoding with the same sample layout as [encoding] (itself when already little-endian). */
    fun littleEndianOf(encoding: Int): Int = when (encoding) {
        PCM_16BIT_BE -> PCM_16BIT
        PCM_24BIT_BE -> PCM_24BIT_PACKED
        PCM_32BIT_BE -> PCM_32BIT
        PCM_FLOAT_BE -> PCM_FLOAT
        else -> encoding
    }

    /**
     * Reverses the byte order of every [bytesPerSample]-byte sample in the first
     * [length] bytes of [data], in place. A trailing partial sample is left alone;
     * one-byte samples have no byte order, so nothing happens for them.
     */
    fun swapSampleBytes(data: ByteArray, length: Int, bytesPerSample: Int) {
        if (bytesPerSample <= 1) return
        val whole = length - length % bytesPerSample
        var i = 0
        while (i < whole) {
            var lo = i
            var hi = i + bytesPerSample - 1
            while (lo < hi) {
                val t = data[lo]; data[lo] = data[hi]; data[hi] = t
                lo++; hi--
            }
            i += bytesPerSample
        }
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

    /**
     * How many PCM frames [PcmPeakReader] may skip between the ones it looks at.
     *
     * A bucket of a long file spans thousands of frames (a 3 hour file at 44.1 kHz: ~1000 per
     * peak). Reading every one of them costs time the picture can't show, so only every n-th frame
     * is read, as long as that still leaves [MIN_FRAMES_PER_PEAK_SAMPLED] looks per bucket. Files
     * at full 10 ms resolution and 44.1 / 48 kHz (441 / 480 frames per bucket) get 1: every frame
     * is read, exactly as before.
     */
    fun strideFor(sampleRate: Int, peaksPerSecond: Double): Int {
        if (sampleRate <= 0 || peaksPerSecond <= 0.0) return 1
        val framesPerPeak = sampleRate / peaksPerSecond
        return (framesPerPeak / MIN_FRAMES_PER_PEAK_SAMPLED).toInt().coerceIn(1, 64)
    }
}

/**
 * Works out a stream's length from its sample timestamps: the last one plus one
 * frame. For raw elementary streams (`.ac3`, `.eac3`) that declare no duration.
 * [durationUs] is 0 until at least two samples have been seen (one frame's
 * length can't be told from a single timestamp).
 */
class StreamDurationMeter {
    private var prevUs = -1L
    private var lastUs = -1L
    private var frameUs = 0L

    fun add(timeUs: Long) {
        if (timeUs < 0) return
        if (prevUs >= 0 && timeUs > prevUs) frameUs = timeUs - prevUs
        prevUs = timeUs
        lastUs = timeUs
    }

    val durationUs: Long get() = if (lastUs < 0 || frameUs <= 0) 0L else lastUs + frameUs
}

/**
 * Keeps the loudest sample seen in each time bucket, as a 0..255 byte.
 * [bucketsPerFrame] is buckets per PCM frame (peaks-per-second / sample rate).
 */
class PeakAccumulator(
    val bucketCount: Int,
    var bucketsPerFrame: Double,
    /** Where the levels go. Several accumulators can share one array, each in its own window. */
    val peaks: ByteArray = ByteArray(bucketCount),
    /** Only buckets in `[firstBucket, endBucket)` are written; frames outside that are ignored. */
    val firstBucket: Int = 0,
    val endBucket: Int = bucketCount,
) {
    /**
     * How many buckets from the start are final after [framesConsumed] frames: every bucket before
     * the one the next frame falls in. The partial bucket at the frontier is left out, so a
     * progressive waveform never shows a half-measured (too quiet) last bar that later jumps up.
     */
    fun completeBuckets(framesConsumed: Long): Int =
        (framesConsumed * bucketsPerFrame).toLong().coerceIn(0L, bucketCount.toLong()).toInt()

    /** [amplitude] is the absolute sample level, 0..1 (the loudest channel of the frame). */
    fun add(frameIndex: Long, amplitude: Float) {
        val bucket = (frameIndex * bucketsPerFrame).toInt()
        if (bucket < firstBucket || bucket >= endBucket) return
        val level = (amplitude * 255f + 0.5f).toInt().coerceIn(0, 255)
        if (level > (peaks[bucket].toInt() and 0xFF)) peaks[bucket] = level.toByte()
    }
}

/** Feeds interleaved little-endian PCM into a [PeakAccumulator], one frame at a time. */
class PcmPeakReader(private val accumulator: PeakAccumulator) {
    var channels: Int = 2
    var encoding: Int = AudioEditMath.PCM_16BIT

    /**
     * Look at every [stride]-th frame only (1 = all of them). The frame counter still advances over
     * the skipped ones, so every peak stays at the right time; only the loudest-of-bucket gets
     * slightly less exact on files whose buckets are thousands of frames wide.
     */
    var stride: Int = 1

    /**
     * Index of the next PCM frame: the number of frames consumed so far, or wherever the caller put it
     * (a decode that starts in the middle of the file sets it from the first buffer's timestamp).
     */
    var frameIndex: Long = 0L

    fun consume(data: ByteBuffer, offset: Int, size: Int) {
        val bytesPerSample = AudioEditMath.bytesPerSample(encoding) ?: return
        val channelCount = max(1, channels)
        val frames = size / (bytesPerSample * channelCount)

        val bigEndian = AudioEditMath.isBigEndian(encoding)
        val layout = AudioEditMath.littleEndianOf(encoding)
        val view = data.duplicate().order(if (bigEndian) ByteOrder.BIG_ENDIAN else ByteOrder.LITTLE_ENDIAN)
        view.limit(offset + size)
        val step = max(1, stride)
        val frameBytes = bytesPerSample * channelCount
        // Which frame of this chunk is the first one to read: the stride is counted across chunks,
        // not restarted at every chunk boundary.
        var frame = ((step - (frameIndex % step)) % step).toInt()
        while (frame < frames) {
            var pos = offset + frame * frameBytes
            var loudest = 0f
            for (channel in 0 until channelCount) {
                val level = amplitudeAt(view, pos, layout, bigEndian)
                if (level > loudest) loudest = level
                pos += bytesPerSample
            }
            accumulator.add(frameIndex + frame, loudest)
            frame += step
        }
        frameIndex += frames
    }

    /** [layout] is a little-endian encoding; [bigEndian] says the bytes (and [b]'s order) are reversed. */
    private fun amplitudeAt(b: ByteBuffer, pos: Int, layout: Int, bigEndian: Boolean): Float = when (layout) {
        AudioEditMath.PCM_8BIT -> abs((b.get(pos).toInt() and 0xFF) - 128) / 128f
        AudioEditMath.PCM_16BIT -> abs(b.getShort(pos).toInt()) / 32768f
        AudioEditMath.PCM_24BIT_PACKED -> abs(PcmConvert.int24(b, pos, bigEndian)) / 8388608f
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
        val bigEndian = AudioEditMath.isBigEndian(encoding)
        val layout = AudioEditMath.littleEndianOf(encoding)
        val view = data.duplicate().order(if (bigEndian) ByteOrder.BIG_ENDIAN else ByteOrder.LITTLE_ENDIAN)
        val frameBytes = bytesPerSample * inChannels
        var pos = offset + firstFrame * frameBytes
        var o = 0
        for (frame in 0 until frameCount) {
            for (channel in 0 until outChannels) {
                out[o++] = sample16(view, pos + channel * bytesPerSample, layout, bigEndian)
            }
            pos += frameBytes
        }
    }

    /**
     * A signed 24-bit sample at [pos]; [bigEndian] says its most significant byte comes first.
     * The top byte is read signed, which sign-extends the value.
     */
    fun int24(b: ByteBuffer, pos: Int, bigEndian: Boolean): Int =
        if (bigEndian) {
            (b.get(pos).toInt() shl 16) or
                ((b.get(pos + 1).toInt() and 0xFF) shl 8) or
                (b.get(pos + 2).toInt() and 0xFF)
        } else {
            (b.get(pos).toInt() and 0xFF) or
                ((b.get(pos + 1).toInt() and 0xFF) shl 8) or
                (b.get(pos + 2).toInt() shl 16)
        }

    private fun sample16(b: ByteBuffer, pos: Int, layout: Int, bigEndian: Boolean): Short = when (layout) {
        AudioEditMath.PCM_8BIT -> (((b.get(pos).toInt() and 0xFF) - 128) shl 8).toShort()
        AudioEditMath.PCM_16BIT -> b.getShort(pos)
        AudioEditMath.PCM_24BIT_PACKED -> (int24(b, pos, bigEndian) shr 8).toShort()
        AudioEditMath.PCM_32BIT -> (b.getInt(pos) shr 16).toShort()
        AudioEditMath.PCM_FLOAT -> (b.getFloat(pos).coerceIn(-1f, 1f) * 32767f).toInt().toShort()
        else -> 0
    }
}
