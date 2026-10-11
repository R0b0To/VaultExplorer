package com.aeidolon.vaultexplorer.audioedit

import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.util.Locale

/**
 * Lossless audio trimming / cutting / joining: the audio counterpart of
 * `LosslessVideoCutter`. Encoded samples are copied from the source straight
 * into the output, never decoded and re-encoded, so quality is untouched.
 *
 * Unlike video there are no keyframes to snap to -- every audio frame is
 * independently decodable -- so a cut lands on the nearest frame (about
 * 20-30 ms) instead of the nearest group of pictures.
 *
 * **Writers.** `MediaMuxer` can only write AAC (`.m4a`), Opus (`.ogg`, API 30+,
 * else WebM) and Vorbis (WebM). MP3 and WAV are by far the most common audio
 * files that it can't write, so they get small hand-rolled writers: MP3 frames
 * are self-contained and simply concatenated, and WAV PCM is re-wrapped in a
 * new header and trimmed to the exact sample. AC-3 / E-AC-3 are handled like
 * MP3 (concatenated syncframes in a raw `.ac3` / `.eac3`), which also means no
 * decoder is needed for them. AIFF is PCM too, so it is cut to a WAV (byte-swapped
 * when big-endian) without loss. Anything else (FLAC, WMA, AMR, ...) can't be
 * copied, so [AudioReencoder] decodes and re-encodes it as AAC instead -- audio
 * is cheap to re-encode, unlike video. The probe says which of the two will
 * happen so the editor can tell the user up front; see [AudioEditMath.planOutput].
 *
 * **Sources.** Everything reads through [AudioSource], which is either the
 * platform `MediaExtractor` or Media3's extractors (the player's demuxers,
 * including AIFF); see `AudioEditHandlers.extractorFactory` for how one is picked.
 *
 * Known limits: tags/cover art and chapters aren't carried over (only the
 * audio stream is copied), and the first MP3 frame after a cut can click
 * because MP3 frames may borrow bits from the frame before them.
 */
object LosslessAudioCutter {
    /** An end within this of the media duration is treated as "to the end". */
    private const val END_EPSILON_US = 1_000L

    private const val INITIAL_SAMPLE_BUFFER = 256 * 1024
    private const val MAX_SAMPLE_BUFFER = 16 * 1024 * 1024

    class CutCancelledException : Exception("Cut cancelled")

    /** The source can't be cut without re-encoding (codec/container nothing here can write). */
    class UnsupportedCutException(message: String) : Exception(message)

    class Probe(
        val durationUs: Long,
        val mime: String?,
        val bitrate: Int?,
        val sampleRate: Int?,
        val channels: Int?,
        /** File extension (no dot) the cut will be written with. */
        val outputExtension: String,
        /** False when the file can't be edited at all; [unsupportedReason] says why. */
        val cutSupported: Boolean,
        /** True when the cut can't be a plain copy and will be re-encoded to AAC. */
        val reencode: Boolean,
        val unsupportedReason: String?,
    )

    class Range(val startUs: Long, val endUs: Long)

    class CutResult(val outputExtension: String)

    /** Sample rate / channel count / sample width of a raw PCM (WAV) source. */
    private class PcmLayout(
        val sampleRate: Int,
        val channels: Int,
        val bytesPerSample: Int,
        val isFloat: Boolean,
        /** The source stores samples most-significant byte first (AIFF); the WAV output is always little-endian. */
        val bigEndian: Boolean,
    ) {
        val blockAlign: Int get() = channels * bytesPerSample
    }

    // ── Track helpers ────────────────────────────────────────────────────

    /** Index of the first audio track, or -1. Shared with [AudioWaveformExtractor]. */
    internal fun firstAudioTrack(extractor: AudioSource): Int {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) return i
        }
        return -1
    }

    internal fun intValue(format: MediaFormat, key: String): Int? {
        if (!format.containsKey(key)) return null
        return runCatching { format.getInteger(key) }.getOrNull()
            ?: runCatching { format.getLong(key).toInt() }.getOrNull()
    }

    internal fun durationUsOf(format: MediaFormat): Long {
        if (!format.containsKey(MediaFormat.KEY_DURATION)) return 0L
        return runCatching { format.getLong(MediaFormat.KEY_DURATION) }.getOrDefault(0L)
    }

    /**
     * Media3's MediaFormat key for the full PCM encoding (`MediaFormatUtil.KEY_PCM_ENCODING_EXTENDED`).
     * `KEY_PCM_ENCODING` can't express big-endian PCM, so for those (AIFF) it is simply absent and
     * reading only it would mistake big-endian samples for little-endian ones.
     */
    private const val KEY_PCM_ENCODING_EXTENDED = "exo-pcm-encoding-int"

    /**
     * The track's duration. Raw elementary streams (`.ac3`, `.eac3`) have no header or index to read
     * it from -- Media3's extractor for them declares the length unknown and the stream unseekable --
     * so then it is measured by stepping through every frame: timestamps accumulate from the frame
     * sizes and no sample data is read. [onStep] runs now and then during that pass (throw from it to
     * cancel). The source is rewound to the start afterwards (for an unseekable stream a seek simply
     * restarts it). Returns 0 when it can't be determined.
     */
    internal fun durationUsOrMeasure(
        extractor: AudioSource,
        track: Int,
        format: MediaFormat,
        onStep: () -> Unit = {},
    ): Long {
        val known = durationUsOf(format)
        if (known > 0L) return known
        extractor.selectTrack(track)
        val meter = StreamDurationMeter()
        var steps = 0
        while (extractor.sampleTrackIndex >= 0) {
            val ts = extractor.sampleTime
            if (ts < 0) break
            meter.add(ts)
            if (++steps % 512 == 0) onStep()
            if (!extractor.advance()) break
        }
        extractor.seekTo(0L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        return meter.durationUs
    }

    internal fun pcmEncodingOf(format: MediaFormat): Int? =
        intValue(format, KEY_PCM_ENCODING_EXTENDED) ?: intValue(format, MediaFormat.KEY_PCM_ENCODING)

    private fun pcmLayoutOf(format: MediaFormat): PcmLayout {
        val sampleRate = intValue(format, MediaFormat.KEY_SAMPLE_RATE)
            ?: throw UnsupportedCutException("The sample rate of this file is unknown")
        val channels = intValue(format, MediaFormat.KEY_CHANNEL_COUNT)
            ?: throw UnsupportedCutException("The channel count of this file is unknown")
        val encoding = pcmEncodingOf(format)
        val bytesPerSample = AudioEditMath.bytesPerSample(encoding)
            ?: throw UnsupportedCutException("This PCM sample format can't be cut without re-encoding")
        return PcmLayout(
            sampleRate,
            channels,
            bytesPerSample,
            isFloat = AudioEditMath.isFloat(encoding),
            bigEndian = AudioEditMath.isBigEndian(encoding),
        )
    }

    private fun planFor(format: MediaFormat, sourceExtension: String): AudioCutPlan {
        val mime = format.getString(MediaFormat.KEY_MIME)
        // AIFF (and any other big-endian PCM) is cut to WAV rather than re-encoded.
        val losslessPcm = mime == AudioEditMath.MIME_RAW &&
            (AudioEditMath.isBigEndian(pcmEncodingOf(format)) ||
                sourceExtension.lowercase(Locale.ROOT) in AudioEditMath.AIFF_EXTENSIONS)
        val plan = AudioEditMath.planOutput(
            mime,
            sourceExtension,
            Build.VERSION.SDK_INT,
            losslessPcm,
        )
        val unsupportedPcm = mime == AudioEditMath.MIME_RAW &&
            AudioEditMath.bytesPerSample(pcmEncodingOf(format)) == null
        if (unsupportedPcm && (plan is AudioCutPlan.Supported || plan is AudioCutPlan.Reencode)) {
            return AudioCutPlan.Unsupported("This PCM sample format isn't supported")
        }
        return plan
    }

    /** Whether this device has a decoder for [format] (the re-encode path needs one, unless it's raw PCM). */
    internal fun hasDecoder(format: MediaFormat): Boolean {
        if (format.getString(MediaFormat.KEY_MIME) == AudioEditMath.MIME_RAW) return true
        return runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).findDecoderForFormat(format) != null
        }.getOrDefault(false)
    }

    /** Whether this device can encode AAC (every Android device can, but a probe shouldn't assume). */
    private fun hasAacEncoder(): Boolean = runCatching {
        val probe = MediaFormat.createAudioFormat(AudioEditMath.MIME_AAC, 44_100, 2)
        MediaCodecList(MediaCodecList.REGULAR_CODECS).findEncoderForFormat(probe) != null
    }.getOrDefault(false)

    // ── Probe ────────────────────────────────────────────────────────────

    fun probe(newExtractor: () -> AudioSource, sourceExtension: String): Probe {
        val extractor = newExtractor()
        try {
            val track = firstAudioTrack(extractor)
            if (track < 0) throw UnsupportedCutException("No audio track found in this file")
            val format = extractor.getTrackFormat(track)
            val plan = planFor(format, sourceExtension)
            val sampleRate = intValue(format, MediaFormat.KEY_SAMPLE_RATE)
            val channels = intValue(format, MediaFormat.KEY_CHANNEL_COUNT)
            val durationUs = durationUsOrMeasure(extractor, track, format)

            // A re-encode is only an option if the device can decode the source and encode AAC.
            val reencodeProblem = if (plan is AudioCutPlan.Reencode) {
                AudioEditMath.reencodeIssue(sampleRate, channels)
                    ?: if (!hasDecoder(format)) "This device can't decode ${format.getString(MediaFormat.KEY_MIME)}"
                    else if (!hasAacEncoder()) "This device can't encode AAC audio"
                    else null
            } else {
                null
            }

            return Probe(
                durationUs = durationUs,
                mime = format.getString(MediaFormat.KEY_MIME),
                bitrate = intValue(format, MediaFormat.KEY_BIT_RATE),
                sampleRate = sampleRate,
                channels = channels,
                outputExtension = when (plan) {
                    is AudioCutPlan.Supported -> plan.extension
                    is AudioCutPlan.Reencode -> plan.extension
                    is AudioCutPlan.Unsupported -> sourceExtension.lowercase(Locale.ROOT)
                },
                cutSupported = plan is AudioCutPlan.Supported ||
                    (plan is AudioCutPlan.Reencode && reencodeProblem == null),
                reencode = plan is AudioCutPlan.Reencode,
                unsupportedReason = (plan as? AudioCutPlan.Unsupported)?.reason ?: reencodeProblem,
            )
        } finally {
            runCatching { extractor.release() }
        }
    }

    // ── Output writers ───────────────────────────────────────────────────

    private interface SampleSink {
        /** Writes [size] bytes of [data] starting at [offset]. [ptsUs] is ignored by the raw writers. */
        fun write(data: ByteBuffer, offset: Int, size: Int, ptsUs: Long, isKey: Boolean)

        /** Completes the file. */
        fun finish()

        /** Releases everything after a failure or cancel; the caller deletes the file. */
        fun abort()
    }

    private class MuxerSink(outFile: File, containerFormat: Int, format: MediaFormat) : SampleSink {
        private val muxer = MediaMuxer(outFile.absolutePath, containerFormat)
        private var started = false
        private val info = MediaCodec.BufferInfo()
        private val trackIndex: Int = try {
            muxer.addTrack(format)
        } catch (e: Exception) {
            runCatching { muxer.release() }
            throw UnsupportedCutException(
                "This audio's codec (${format.getString(MediaFormat.KEY_MIME)}) " +
                    "can't be cut without re-encoding on this device",
            )
        }

        init {
            muxer.start()
            started = true
        }

        override fun write(data: ByteBuffer, offset: Int, size: Int, ptsUs: Long, isKey: Boolean) {
            info.set(offset, size, ptsUs, if (isKey) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
            muxer.writeSampleData(trackIndex, data, info)
        }

        override fun finish() {
            muxer.stop()
            started = false
            muxer.release()
        }

        override fun abort() {
            if (started) runCatching { muxer.stop() }
            started = false
            runCatching { muxer.release() }
        }
    }

    /** Appends each sample's bytes to the file as-is: MP3 and AC-3 / E-AC-3 frames are self-contained. */
    private class RawFrameSink(outFile: File) : SampleSink {
        private val out = BufferedOutputStream(FileOutputStream(outFile), 64 * 1024)
        private var scratch = ByteArray(8 * 1024)

        override fun write(data: ByteBuffer, offset: Int, size: Int, ptsUs: Long, isKey: Boolean) {
            if (scratch.size < size) scratch = ByteArray(size)
            data.position(offset)
            data.get(scratch, 0, size)
            out.write(scratch, 0, size)
        }

        override fun finish() {
            out.flush()
            out.close()
        }

        override fun abort() {
            runCatching { out.close() }
        }
    }

    /** Writes a RIFF/WAVE header, then PCM, and patches the sizes in once the length is known. */
    private class WavSink(outFile: File, private val pcm: PcmLayout) : SampleSink {
        private val file = RandomAccessFile(outFile, "rw")
        private var dataBytes = 0L
        private var scratch = ByteArray(64 * 1024)

        init {
            file.setLength(0L)
            file.write(header(0L))
        }

        private fun header(dataBytes: Long): ByteArray = AudioEditMath.wavHeader(
            pcm.sampleRate,
            pcm.channels,
            pcm.bytesPerSample,
            pcm.isFloat,
            dataBytes,
        )

        override fun write(data: ByteBuffer, offset: Int, size: Int, ptsUs: Long, isKey: Boolean) {
            if (dataBytes + size > AudioEditMath.MAX_WAV_DATA_BYTES) {
                throw UnsupportedCutException("The result is too large for a WAV file")
            }
            if (scratch.size < size) scratch = ByteArray(size)
            data.position(offset)
            data.get(scratch, 0, size)
            if (pcm.bigEndian) AudioEditMath.swapSampleBytes(scratch, size, pcm.bytesPerSample)
            file.write(scratch, 0, size)
            dataBytes += size
        }

        override fun finish() {
            file.seek(0L)
            file.write(header(dataBytes))
            file.close()
        }

        override fun abort() {
            runCatching { file.close() }
        }
    }

    private fun openSink(
        container: AudioContainer,
        format: MediaFormat,
        outFile: File,
        pcm: PcmLayout?,
    ): SampleSink = when (container) {
        AudioContainer.MP4 -> MuxerSink(outFile, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4, format)
        AudioContainer.WEBM -> MuxerSink(outFile, MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM, format)
        AudioContainer.OGG -> MuxerSink(outFile, MediaMuxer.OutputFormat.MUXER_OUTPUT_OGG, format)
        AudioContainer.MP3, AudioContainer.AC3 -> RawFrameSink(outFile)
        AudioContainer.WAV -> WavSink(
            outFile,
            pcm ?: throw UnsupportedCutException("The PCM layout of this file is unknown"),
        )
    }

    // ── Cut ──────────────────────────────────────────────────────────────

    /**
     * Stream-copies [ranges] from the source into [outFile]. One range gives a
     * plain cut; several are joined in the order given. [onProgress] receives
     * 0..1 across the whole call.
     */
    fun cut(
        newExtractor: () -> AudioSource,
        sourceExtension: String,
        ranges: List<Range>,
        outFile: File,
        isCancelled: () -> Boolean,
        onProgress: (Float) -> Unit,
    ): CutResult {
        require(ranges.isNotEmpty()) { "No ranges to cut" }

        val extractor = newExtractor()
        var sink: SampleSink? = null
        var finished = false
        try {
            val track = firstAudioTrack(extractor)
            if (track < 0) throw UnsupportedCutException("No audio track found in this file")
            val format = extractor.getTrackFormat(track)
            val durationUs = durationUsOf(format)

            val plan = planFor(format, sourceExtension)
            if (plan is AudioCutPlan.Reencode) {
                // Can't be copied: decode and encode to AAC instead (own extractor; this one is released below).
                return AudioReencoder.reencode(newExtractor, ranges, outFile, isCancelled, onProgress)
            }
            if (plan !is AudioCutPlan.Supported) {
                throw UnsupportedCutException((plan as AudioCutPlan.Unsupported).reason)
            }

            val pcm = if (plan.container == AudioContainer.WAV) pcmLayoutOf(format) else null
            val activeSink = openSink(plan.container, format, outFile, pcm)
            sink = activeSink

            extractor.selectTrack(track)
            var maxInput = INITIAL_SAMPLE_BUFFER
            if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                maxInput = maxOf(maxInput, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
            }
            var buffer = ByteBuffer.allocateDirect(maxInput)

            // Presentation-time offset of the segment being written, so joined segments run back to back.
            var offsetUs = 0L
            var lastPermille = -1

            for ((segIndex, requested) in ranges.withIndex()) {
                if (isCancelled()) throw CutCancelledException()

                val startUs = requested.startUs.coerceAtLeast(0L)
                val toEnd = durationUs > 0 && requested.endUs >= durationUs - END_EPSILON_US
                val endUs = if (toEnd) Long.MAX_VALUE else requested.endUs
                if (endUs <= startUs) throw UnsupportedCutException("A segment is too short to cut")
                val spanUs = when {
                    !toEnd -> endUs - startUs
                    durationUs > startUs -> durationUs - startUs
                    else -> 0L
                }

                // PCM is cut to the exact sample, so it works in frames rather than in whole chunks.
                val windowStartFrame = if (pcm != null) AudioEditMath.usToFrame(startUs, pcm.sampleRate) else 0L
                val windowEndFrame = when {
                    pcm == null -> 0L
                    toEnd -> Long.MAX_VALUE
                    else -> AudioEditMath.usToFrame(endUs, pcm.sampleRate)
                }

                extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

                var wroteAny = false
                var lastRelUs = 0L
                var prevTsUs = -1L
                var frameDurUs = 0L

                while (true) {
                    if (isCancelled()) throw CutCancelledException()
                    if (extractor.sampleTrackIndex < 0) break
                    val ts = extractor.sampleTime
                    if (ts < 0) break
                    if (pcm == null && ts >= endUs) break

                    // Compressed frames before the start (the seek lands at or before it) are skipped unread.
                    if (pcm != null || ts >= startUs) {
                        var size = -1
                        while (true) {
                            try {
                                buffer.clear()
                                size = extractor.readSampleData(buffer, 0)
                                break
                            } catch (e: IllegalArgumentException) {
                                // Sample bigger than the buffer: grow and retry.
                                if (buffer.capacity() >= MAX_SAMPLE_BUFFER) throw e
                                buffer = ByteBuffer.allocateDirect(buffer.capacity() * 2)
                            }
                        }
                        if (size < 0) break

                        if (pcm != null) {
                            val chunkStartFrame = AudioEditMath.usToFrame(ts, pcm.sampleRate)
                            if (chunkStartFrame >= windowEndFrame) break
                            val slice = AudioEditMath.pcmSlice(
                                chunkStartFrame,
                                size,
                                pcm.blockAlign,
                                windowStartFrame,
                                windowEndFrame,
                            )
                            if (slice != null) {
                                activeSink.write(buffer, slice.first, slice.second - slice.first, 0L, true)
                                wroteAny = true
                            }
                        } else {
                            val rel = ts - startUs
                            val isKey = (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0
                            activeSink.write(buffer, 0, size, rel + offsetUs, isKey)
                            wroteAny = true
                            if (rel > lastRelUs) lastRelUs = rel
                            if (prevTsUs >= 0 && ts > prevTsUs) frameDurUs = ts - prevTsUs
                            prevTsUs = ts
                        }

                        if (spanUs > 0) {
                            val within = ((ts - startUs).toDouble() / spanUs).coerceIn(0.0, 1.0)
                            val overall = ((segIndex + within) / ranges.size).toFloat()
                            val permille = (overall * 1000).toInt()
                            if (permille != lastPermille) {
                                lastPermille = permille
                                onProgress(overall)
                            }
                        }
                    }

                    extractor.advance()
                }

                if (!wroteAny) throw UnsupportedCutException("This part of the file contains no audio")
                // Compressed audio carries timestamps: the next segment starts one frame after this one's last.
                if (pcm == null) offsetUs += lastRelUs + maxOf(frameDurUs, 1L)
            }

            onProgress(1f)
            activeSink.finish()
            finished = true
            return CutResult(plan.extension)
        } finally {
            if (!finished) runCatching { sink?.abort() }
            runCatching { extractor.release() }
        }
    }
}
