package com.aeidolon.vaultexplorer.audioedit

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import com.aeidolon.vaultexplorer.VeLog
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max

/**
 * A rough waveform of a long file in a fraction of the time a full decode takes.
 *
 * Instead of decoding every frame, it decodes a short window ([AudioEditMath.OVERVIEW_WINDOW_US]) every
 * few seconds and keeps the loudest level of each. That is about a tenth of the audio or less, and for a
 * vault file most of the file is never read at all. Several workers share the windows, as in
 * [ParallelWaveformDecoder].
 *
 * It is a stopgap, not the result: the levels are expanded over the full-resolution peak array and shown
 * at once, and the real decode then replaces them from the left. So it is optional by design: anything
 * odd (a seek that lands wrong, a decoder that stalls, running past the time budget) makes [measure]
 * return null and the full decode simply starts without it.
 *
 * Seeking into the middle of a stream leaves the decoder without the frames before, so the first frames
 * it produces are not clean. A short stretch before each window is decoded and thrown away to absorb
 * that. For AAC the decoder is then simply fed the next window, no flush needed (every AAC frame stands
 * on its own apart from the overlap with its predecessor, which is the part being absorbed); the other
 * codecs get an end-of-stream and a flush between windows.
 */
object WaveformOverview {
    private const val TAG = "WaveformOverview"

    /** Decoded and discarded before each window. */
    private const val PREROLL_US = 200_000L

    /** An output starting this far before the window still counts (one frame of slack). */
    private const val FRAME_SLACK_US = 30_000L

    /** A seek that lands further than this past the wanted position is not exact enough to use. */
    private const val MAX_SEEK_OVERSHOOT_US = 1_000_000L

    /** One window should take milliseconds; this long without any movement means the decoder is stuck. */
    private const val WINDOW_STALL_MS = 5_000L
    private const val GROUP_WINDOWS = 25
    private const val COORDINATOR_TICK_MS = 50L
    private const val DEQUEUE_TIMEOUT_US = 10_000L

    class Result(val levels: ByteArray, val spacingUs: Long)

    private class WorkerState(var sampleRate: Int, var channels: Int, var encoding: Int)

    /**
     * One level (0..255) per window, or null when the pass was not possible or gave up (the reason is
     * logged). Throws [AudioWaveformExtractor.CancelledException] on cancel.
     */
    fun measure(
        newExtractor: () -> AudioSource,
        track: Int,
        format: MediaFormat,
        mime: String,
        sampleRate: Int,
        channels: Int,
        durationUs: Long,
        peaksPerSecond: Double,
        workers: Int,
        budgetMs: Long,
        isCancelled: () -> Boolean,
        stats: WaveformStats,
    ): Result? {
        val windows = AudioEditMath.overviewWindowCount(durationUs)
        val spacingUs = AudioEditMath.overviewSpacingUs(durationUs, windows)
        val levels = ByteArray(windows)
        val groups = (windows + GROUP_WINDOWS - 1) / GROUP_WINDOWS
        val nextGroup = AtomicInteger(0)
        val done = AtomicInteger(0)
        val abort = AtomicBoolean(false)
        val failure = AtomicReference<String?>(null)
        val flushBetweenWindows = mime != AudioEditMath.MIME_AAC

        val pool = Executors.newFixedThreadPool(max(1, workers)) { r ->
            Thread(r, "AudioWaveform-worker").apply {
                isDaemon = true
                priority = Thread.NORM_PRIORITY - 1
            }
        }
        repeat(max(1, workers)) {
            pool.execute {
                var extractor: AudioSource? = null
                var codec: MediaCodec? = null
                try {
                    val source = newExtractor()
                    extractor = source
                    source.selectTrack(track)
                    val decoder = MediaCodec.createDecoderByType(mime).also {
                        it.configure(format, null, null, 0)
                        it.start()
                    }
                    codec = decoder
                    val state = WorkerState(sampleRate, channels, AudioEditMath.PCM_16BIT)
                    var first = true
                    while (!abort.get()) {
                        val g = nextGroup.getAndIncrement()
                        if (g >= groups) break
                        for (w in g * GROUP_WINDOWS until minOf(windows, (g + 1) * GROUP_WINDOWS)) {
                            if (abort.get()) return@execute
                            val startUs = AudioEditMath.overviewWindowStartUs(w, spacingUs)
                            val level = measureWindow(
                                source, decoder, state, flushBetweenWindows, first,
                                startUs, startUs + AudioEditMath.OVERVIEW_WINDOW_US,
                                peaksPerSecond, abort, stats,
                            )
                            first = false
                            if (level < 0) return@execute // aborted by someone else
                            levels[w] = level.toByte()
                            done.incrementAndGet()
                        }
                    }
                } catch (e: Throwable) {
                    if (failure.compareAndSet(null, "${e.javaClass.simpleName}: ${e.message}")) {
                        VeLog.i(TAG) { "overview worker gave up: ${failure.get()}" }
                    }
                    abort.set(true)
                } finally {
                    codec?.let {
                        runCatching { it.stop() }
                        runCatching { it.release() }
                    }
                    extractor?.let { runCatching { it.release() } }
                }
            }
        }
        pool.shutdown()

        val startedMs = SystemClock.elapsedRealtime()
        try {
            while (true) {
                if (isCancelled()) {
                    abort.set(true)
                    throw AudioWaveformExtractor.CancelledException()
                }
                if (failure.get() != null) break
                if (done.get() >= windows) break
                if (SystemClock.elapsedRealtime() - startedMs > budgetMs) {
                    failure.compareAndSet(null, "over the time budget (${budgetMs}ms)")
                    VeLog.i(TAG) { "overview skipped: ${failure.get()}, ${done.get()}/$windows windows" }
                    break
                }
                Thread.sleep(COORDINATOR_TICK_MS)
            }
        } finally {
            if (failure.get() != null || isCancelled()) abort.set(true)
            if (!pool.awaitTermination(15, TimeUnit.SECONDS)) {
                abort.set(true)
                pool.shutdownNow()
            }
        }
        stats.overviewWindows = windows
        return if (failure.get() == null && done.get() >= windows) Result(levels, spacingUs) else null
    }

    /** The loudest level (0..255) in `[startUs, endUs)`, or -1 when told to stop. */
    private fun measureWindow(
        extractor: AudioSource,
        codec: MediaCodec,
        state: WorkerState,
        flushBetween: Boolean,
        firstWindow: Boolean,
        startUs: Long,
        endUs: Long,
        peaksPerSecond: Double,
        abort: AtomicBoolean,
        stats: WaveformStats,
    ): Int {
        if (flushBetween && !firstWindow) codec.flush()
        stats.time(stats.extractorNs) {
            extractor.seekTo(max(0L, startUs - PREROLL_US), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        }
        if (extractor.sampleTrackIndex < 0) return 0 // past the end: the length estimate was a little long
        val landedUs = extractor.sampleTime
        if (landedUs > startUs + MAX_SEEK_OVERSHOOT_US) {
            throw IllegalStateException("seek to $startUs us landed at $landedUs us")
        }

        // Every frame lands in the one bucket: this measures a single level, not a stretch of peaks.
        val accumulator = PeakAccumulator(1, 0.0)
        val reader = PcmPeakReader(accumulator)
        reader.channels = state.channels
        reader.encoding = state.encoding
        reader.stride = AudioEditMath.strideFor(state.sampleRate, peaksPerSecond)

        val info = MediaCodec.BufferInfo()
        var lastFedUs = -1L
        var lastOutUs = -1L
        var inputDone = false
        var outputDone = false
        var lastMovedMs = SystemClock.elapsedRealtime()

        fun drainOne(timeoutUs: Long): Boolean {
            val outIndex = codec.dequeueOutputBuffer(info, timeoutUs)
            return when {
                outIndex >= 0 -> {
                    val outBuffer = codec.getOutputBuffer(outIndex)
                    if (outBuffer != null && info.size > 0) {
                        val ptsUs = info.presentationTimeUs
                        if (ptsUs > lastOutUs) lastOutUs = ptsUs
                        // The decoder warming up, and (with no flush) anything left from the last window,
                        // comes out before the window starts and doesn't count.
                        if (ptsUs >= startUs - FRAME_SLACK_US) {
                            stats.time(stats.peaksNs) { reader.consume(outBuffer, info.offset, info.size) }
                        }
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true
                    true
                }
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val out = codec.outputFormat
                    LosslessAudioCutter.intValue(out, MediaFormat.KEY_CHANNEL_COUNT)?.let {
                        state.channels = it
                        reader.channels = it
                    }
                    state.encoding = LosslessAudioCutter.pcmEncodingOf(out) ?: AudioEditMath.PCM_16BIT
                    reader.encoding = state.encoding
                    LosslessAudioCutter.intValue(out, MediaFormat.KEY_SAMPLE_RATE)?.let {
                        if (it > 0) {
                            state.sampleRate = it
                            reader.stride = AudioEditMath.strideFor(it, peaksPerSecond)
                        }
                    }
                    true
                }
                else -> false
            }
        }

        // Done when everything fed has come back out: by end-of-stream where the decoder is flushed
        // between windows, by timestamp where it isn't (it is never told the stream ended).
        fun finished(): Boolean =
            if (flushBetween) outputDone else inputDone && (lastFedUs < 0 || lastOutUs >= lastFedUs)

        while (true) {
            if (abort.get()) return -1
            var progressed = false

            while (!inputDone) {
                val timeUs = extractor.sampleTime
                val atEnd = extractor.sampleTrackIndex < 0 || timeUs > endUs
                if (atEnd && !flushBetween) {
                    // This decoder is never told the stream ended, so there is nothing to queue: the window
                    // is over once everything fed has come back out.
                    inputDone = true
                    progressed = true
                    break
                }
                val inIndex = codec.dequeueInputBuffer(0L)
                if (inIndex < 0) break
                if (atEnd) {
                    codec.queueInputBuffer(inIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    inputDone = true
                    progressed = true
                    break
                }
                val inBuffer = codec.getInputBuffer(inIndex)
                val size = if (inBuffer == null) {
                    -1
                } else {
                    stats.time(stats.extractorNs) { extractor.readSampleData(inBuffer, 0) }
                }
                if (size < 0) throw IllegalStateException("unexpected end of data in an overview window")
                codec.queueInputBuffer(inIndex, 0, size, timeUs, 0)
                lastFedUs = timeUs
                stats.time(stats.extractorNs) { extractor.advance() }
                progressed = true
            }

            while (!finished() && drainOne(0L)) progressed = true
            if (finished()) break

            if (progressed) {
                lastMovedMs = SystemClock.elapsedRealtime()
            } else {
                val waitStart = System.nanoTime()
                val got = drainOne(DEQUEUE_TIMEOUT_US)
                stats.waitNs.addAndGet(System.nanoTime() - waitStart)
                if (got) {
                    lastMovedMs = SystemClock.elapsedRealtime()
                } else if (SystemClock.elapsedRealtime() - lastMovedMs > WINDOW_STALL_MS) {
                    throw IllegalStateException("decoder stalled in an overview window")
                }
            }
        }
        return accumulator.peaks[0].toInt() and 0xFF
    }
}
