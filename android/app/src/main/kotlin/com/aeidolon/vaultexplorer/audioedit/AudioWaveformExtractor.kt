package com.aeidolon.vaultexplorer.audioedit

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.SystemClock
import com.aeidolon.vaultexplorer.VeLog
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.FfmpegPcmDecoder
import java.nio.ByteBuffer

/**
 * Decodes an audio file just far enough to draw its waveform: the loudest
 * sample in every 10 ms slice (or coarser for very long files, see
 * [AudioEditMath.peaksPerSecondFor]), as one byte per slice.
 *
 * The decode runs through `MediaCodec` straight off the extractor, so a vault
 * file is decrypted on demand and never written out in plaintext. When the
 * device has no `MediaCodec` decoder for the codec (AC-3 / E-AC-3 / DTS on many
 * phones) the FFmpeg decoder the player already bundles is used instead, see
 * [FfmpegPcmDecoder]; the data path is the same.
 *
 * **There is no overall time limit.** An earlier version gave up after 60 s and
 * drew the rest flat, which on a 3 hour file left everything past the first
 * ~18 minutes blank. The whole file is decoded now, however long that takes; what
 * keeps this usable is that
 *  - finished peaks are handed out as they are produced (`onPartial`), so the
 *    editor draws the waveform growing from the left instead of waiting for the end;
 *  - the decoder is kept busy (several buffers in flight) rather than fed one
 *    frame at a time; and
 *  - very long files are sampled sparsely inside each peak (see [AudioEditMath.strideFor]).
 *
 * What does end a decode early is a decoder that has stopped producing anything for
 * [STALL_TIMEOUT_MS] (a broken stream): it returns what it has with
 * [Waveform.complete] false. Cancelling (the editor closing) ends it at any time.
 */
object AudioWaveformExtractor {
    private const val TAG = "AudioWaveformExtractor"
    private const val STALL_TIMEOUT_MS = 20_000L
    private const val PARTIAL_INTERVAL_MS = 400L
    private const val DEQUEUE_TIMEOUT_US = 10_000L
    private const val FFMPEG_IDLE_SLEEP_MS = 2L
    private const val MAX_SAMPLE_BUFFER = 16 * 1024 * 1024

    class CancelledException : Exception("Waveform cancelled")

    /** One line in the log saying how long the decode took and where the time went. */
    private fun logTiming(stats: WaveformStats, mime: String, durationUs: Long, wallStartNs: Long, complete: Boolean) {
        val wallMs = (System.nanoTime() - wallStartNs) / 1_000_000L
        val audioSeconds = durationUs / 1_000_000L
        val speed = if (wallMs > 0) audioSeconds * 1000.0 / wallMs else 0.0
        VeLog.i(TAG) {
            "waveform timing: ${stats.mode}, $mime, ${audioSeconds}s of audio in ${wallMs}ms " +
                "(${"%.0f".format(speed)}x realtime), complete=$complete; thread time: " +
                "reading ${stats.extractorNs.get() / 1_000_000L}ms, " +
                "waiting on decoder ${stats.waitNs.get() / 1_000_000L}ms, " +
                "measuring peaks ${stats.peaksNs.get() / 1_000_000L}ms"
        }
    }

    class Waveform(
        /** One 0..255 level per slice, oldest first. */
        val peaks: ByteArray,
        val peaksPerSecond: Double,
        /** False when the decoder stalled before the end of the file (see [STALL_TIMEOUT_MS]). */
        val complete: Boolean,
    )

    /**
     * [onPartial] gets `(peaks, peaksPerSecond, from, to)`: peaks `[from, to)` of the final array are finished and will
     * not change. It runs on the decoding thread, at most every [PARTIAL_INTERVAL_MS]; [peaks] is the
     * live array, so a receiver that keeps the bytes must copy them before returning.
     */
    fun extract(
        newExtractor: () -> AudioSource,
        isCancelled: () -> Boolean,
        onProgress: (Float) -> Unit,
        onPartial: (peaks: ByteArray, peaksPerSecond: Double, from: Int, to: Int) -> Unit = { _, _, _, _ -> },
        cpuCount: Int = Runtime.getRuntime().availableProcessors(),
    ): Waveform {
        val wallStartNs = System.nanoTime()
        val stats = WaveformStats()
        val extractor = newExtractor()
        var codec: MediaCodec? = null
        var ffmpeg: FfmpegPcmDecoder? = null
        try {
            val track = LosslessAudioCutter.firstAudioTrack(extractor)
            if (track < 0) throw IllegalStateException("No audio track found in this file")
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: throw IllegalStateException("Unknown audio format")
            val isRawTrack = mime == AudioEditMath.MIME_RAW
            // MediaCodec first. Without a platform decoder for this codec the bundled FFmpeg takes over;
            // only when neither can decode it is there no waveform (and no point measuring the length).
            val useFfmpeg = !isRawTrack && !LosslessAudioCutter.hasDecoder(format)
            if (useFfmpeg && !FfmpegPcmDecoder.supports(mime)) {
                throw IllegalStateException("This device can't decode $mime, so there is no waveform")
            }
            val durationUs = LosslessAudioCutter.durationUsOrMeasure(extractor, track, format) {
                if (isCancelled()) throw CancelledException()
            }
            if (durationUs <= 0L) throw IllegalStateException("Unknown audio length")

            val peaksPerSecond = AudioEditMath.peaksPerSecondFor(durationUs)
            val accumulator = PeakAccumulator(
                bucketCount = AudioEditMath.bucketCountFor(durationUs, peaksPerSecond),
                bucketsPerFrame = 0.0,
            )
            val reader = PcmPeakReader(accumulator)

            var sampleRate = LosslessAudioCutter.intValue(format, MediaFormat.KEY_SAMPLE_RATE) ?: 44_100
            reader.channels = LosslessAudioCutter.intValue(format, MediaFormat.KEY_CHANNEL_COUNT) ?: 2
            val isRaw = mime == AudioEditMath.MIME_RAW
            reader.encoding = if (isRaw) {
                LosslessAudioCutter.pcmEncodingOf(format) ?: AudioEditMath.PCM_16BIT
            } else {
                AudioEditMath.PCM_16BIT
            }
            if (AudioEditMath.bytesPerSample(reader.encoding) == null) {
                throw IllegalStateException("This PCM sample format isn't supported")
            }

            // The decoder's real rate can differ from the container's (HE-AAC doubles it, FFmpeg reports
            // its own), and the bucket size and sampling stride both follow from it.
            fun applySampleRate(rate: Int) {
                if (rate <= 0) return
                sampleRate = rate
                accumulator.bucketsPerFrame = peaksPerSecond / rate
                reader.stride = AudioEditMath.strideFor(rate, peaksPerSecond)
            }
            applySampleRate(sampleRate)

            // A long file with a codec that seeks exactly is decoded in pieces by several workers at once.
            // If that gives up for any reason, everything it wrote is cleared and the plain front-to-back
            // decode below runs instead; it is the reference behaviour and always correct.
            val workers = if (isRaw || useFfmpeg) {
                1
            } else {
                AudioEditMath.parallelWorkersFor(mime, durationUs, cpuCount)
            }
            if (workers > 1) {
                stats.mode = "parallel x$workers"
                val done = ParallelWaveformDecoder.decode(
                    newExtractor = newExtractor,
                    track = track,
                    format = format,
                    mime = mime,
                    sampleRate = sampleRate,
                    channels = reader.channels,
                    peaksPerSecond = peaksPerSecond,
                    peaks = accumulator.peaks,
                    workers = workers,
                    isCancelled = isCancelled,
                    onProgress = onProgress,
                    onPartial = onPartial,
                    stats = stats,
                )
                if (done) {
                    onProgress(1f)
                    logTiming(stats, mime, durationUs, wallStartNs, complete = true)
                    return Waveform(accumulator.peaks, peaksPerSecond, true)
                }
                java.util.Arrays.fill(accumulator.peaks, 0.toByte())
                stats.mode = "sequential (parallel decode gave up)"
            }

            extractor.selectTrack(track)
            val activeCodec = if (isRaw || useFfmpeg) {
                null
            } else {
                MediaCodec.createDecoderByType(mime).also {
                    it.configure(format, null, null, 0)
                    it.start()
                }
            }
            codec = activeCodec
            val activeFfmpeg = if (useFfmpeg) FfmpegPcmDecoder.create(format) else null
            ffmpeg = activeFfmpeg

            var lastPermille = -1
            var complete = true

            fun report(timeUs: Long) {
                val permille = ((timeUs.toDouble() / durationUs) * 1000).toInt().coerceIn(0, 1000)
                if (permille != lastPermille) {
                    lastPermille = permille
                    onProgress(permille / 1000f)
                }
            }

            // Hands the finished peaks to the caller every PARTIAL_INTERVAL_MS, so the editor can draw
            // the waveform as it grows. The last, partly measured bucket is held back until it is done.
            var sentUpTo = 0
            var lastEmitMs = SystemClock.elapsedRealtime()
            fun emitPartial() {
                val now = SystemClock.elapsedRealtime()
                if (now - lastEmitMs < PARTIAL_INTERVAL_MS) return
                lastEmitMs = now
                val upTo = accumulator.completeBuckets(reader.frameIndex)
                if (upTo > sentUpTo) {
                    onPartial(accumulator.peaks, peaksPerSecond, sentUpTo, upTo)
                    sentUpTo = upTo
                }
            }

            // Watchdog: the clock restarts whenever the decoder takes or gives anything. Only a decoder
            // that has gone quiet for STALL_TIMEOUT_MS ends the decode early; a slow one never does.
            var lastMovedMs = SystemClock.elapsedRealtime()
            fun stalled(moved: Boolean): Boolean {
                val now = SystemClock.elapsedRealtime()
                if (moved) {
                    lastMovedMs = now
                    return false
                }
                return now - lastMovedMs > STALL_TIMEOUT_MS
            }

            if (activeFfmpeg != null) {
                // No platform decoder: FFmpeg turns the samples into PCM. It decodes on its own thread and
                // never blocks, so one loop feeds it and drains it, napping only when neither side moved.
                var buffer = ByteBuffer.allocateDirect(64 * 1024)
                var pendingSize = -1 // a sample read from the extractor, waiting for a free decoder input
                var pendingTimeUs = 0L
                var inputDone = false
                var outputDone = false
                while (!outputDone) {
                    if (isCancelled()) throw CancelledException()
                    var progressed = false

                    if (!inputDone) {
                        if (pendingSize < 0 && extractor.sampleTrackIndex >= 0) {
                            var size = -1
                            while (true) {
                                try {
                                    buffer.clear()
                                    size = extractor.readSampleData(buffer, 0)
                                    break
                                } catch (e: IllegalArgumentException) {
                                    if (buffer.capacity() >= MAX_SAMPLE_BUFFER) throw e
                                    buffer = ByteBuffer.allocateDirect(buffer.capacity() * 2)
                                }
                            }
                            if (size >= 0) {
                                pendingSize = size
                                pendingTimeUs = extractor.sampleTime
                                extractor.advance()
                            }
                        }
                        if (pendingSize >= 0) {
                            if (activeFfmpeg.queueSample(buffer, pendingSize, pendingTimeUs)) {
                                report(pendingTimeUs)
                                pendingSize = -1
                                progressed = true
                            }
                        } else if (activeFfmpeg.queueEndOfStream()) {
                            inputDone = true
                            progressed = true
                        }
                    }

                    val ended = activeFfmpeg.drain { data, offset, size ->
                        // The decoder's real output layout (known from its first chunk on).
                        val outRate = activeFfmpeg.sampleRate
                        if (outRate > 0 && outRate != sampleRate) applySampleRate(outRate)
                        val outChannels = activeFfmpeg.channelCount
                        if (outChannels > 0) reader.channels = outChannels
                        stats.time(stats.peaksNs) { reader.consume(data, offset, size) }
                        progressed = true
                    }
                    emitPartial()
                    if (ended) {
                        outputDone = true
                    } else if (stalled(progressed)) {
                        complete = false
                        break
                    } else if (!progressed) {
                        Thread.sleep(FFMPEG_IDLE_SLEEP_MS)
                    }
                }
            } else if (activeCodec == null) {
                // Raw PCM (WAV): the extractor already hands out samples, nothing to decode.
                var buffer = ByteBuffer.allocateDirect(64 * 1024)
                while (extractor.sampleTrackIndex >= 0) {
                    if (isCancelled()) throw CancelledException()
                    var size = -1
                    val readStart = System.nanoTime()
                    while (true) {
                        try {
                            buffer.clear()
                            size = extractor.readSampleData(buffer, 0)
                            break
                        } catch (e: IllegalArgumentException) {
                            if (buffer.capacity() >= MAX_SAMPLE_BUFFER) throw e
                            buffer = ByteBuffer.allocateDirect(buffer.capacity() * 2)
                        }
                    }
                    stats.extractorNs.addAndGet(System.nanoTime() - readStart)
                    if (size < 0) break
                    stats.time(stats.peaksNs) { reader.consume(buffer, 0, size) }
                    report(extractor.sampleTime)
                    emitPartial()
                    stats.time(stats.extractorNs) { extractor.advance() }
                }
            } else {
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false

                // Takes one decoded buffer (or format change) if the decoder has one within timeoutUs.
                fun drainOne(timeoutUs: Long): Boolean {
                    val outIndex = activeCodec.dequeueOutputBuffer(info, timeoutUs)
                    return when {
                        outIndex >= 0 -> {
                            val outBuffer = activeCodec.getOutputBuffer(outIndex)
                            if (outBuffer != null && info.size > 0) {
                                stats.time(stats.peaksNs) { reader.consume(outBuffer, info.offset, info.size) }
                            }
                            activeCodec.releaseOutputBuffer(outIndex, false)
                            if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true
                            true
                        }
                        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            // The decoder's real output layout (HE-AAC doubles the rate, for one).
                            val out = activeCodec.outputFormat
                            LosslessAudioCutter.intValue(out, MediaFormat.KEY_CHANNEL_COUNT)?.let { reader.channels = it }
                            reader.encoding = LosslessAudioCutter.pcmEncodingOf(out) ?: AudioEditMath.PCM_16BIT
                            LosslessAudioCutter.intValue(out, MediaFormat.KEY_SAMPLE_RATE)?.let { applySampleRate(it) }
                            true
                        }
                        else -> false
                    }
                }

                while (!outputDone) {
                    if (isCancelled()) throw CancelledException()
                    var progressed = false

                    // Keep the decoder fed: queue every input buffer it has free right now. Handing it one
                    // frame and then waiting for it to come back (what this used to do) caps the speed at one
                    // codec round trip per ~23 ms of audio, however fast the decoder itself is.
                    while (!inputDone) {
                        val inIndex = activeCodec.dequeueInputBuffer(0L)
                        if (inIndex < 0) break
                        val inBuffer = activeCodec.getInputBuffer(inIndex)
                        val size = if (inBuffer == null) {
                            -1
                        } else {
                            stats.time(stats.extractorNs) { extractor.readSampleData(inBuffer, 0) }
                        }
                        if (size < 0) {
                            activeCodec.queueInputBuffer(inIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            val ts = extractor.sampleTime
                            activeCodec.queueInputBuffer(inIndex, 0, size, ts, 0)
                            report(ts)
                            stats.time(stats.extractorNs) { extractor.advance() }
                        }
                        progressed = true
                    }

                    // ...and take everything it has decoded so far.
                    while (!outputDone && drainOne(0L)) progressed = true
                    emitPartial()

                    if (!progressed && !outputDone) {
                        // Nothing moved: wait on the decoder briefly rather than spin.
                        val waitStart = System.nanoTime()
                        if (drainOne(DEQUEUE_TIMEOUT_US)) progressed = true
                        stats.waitNs.addAndGet(System.nanoTime() - waitStart)
                        if (stalled(progressed)) {
                            complete = false
                            break
                        }
                    } else {
                        stalled(true)
                    }
                }
            }

            VeLog.d(TAG) { "extract: ${accumulator.bucketCount} peaks, complete=$complete" }
            onProgress(1f)
            logTiming(stats, mime, durationUs, wallStartNs, complete)
            return Waveform(accumulator.peaks, peaksPerSecond, complete)
        } finally {
            codec?.let {
                runCatching { it.stop() }
                runCatching { it.release() }
            }
            ffmpeg?.let { runCatching { it.close() } }
            runCatching { extractor.release() }
        }
    }
}
