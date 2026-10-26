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
import java.util.concurrent.atomic.AtomicIntegerArray
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max
import kotlin.math.min

/**
 * Where a waveform decode spent its time. Thread-time, so with several workers the parts add up to more
 * than the wall clock. Logged once per decode (see [AudioWaveformExtractor]) so a slow file shows whether
 * the time went into reading it, into the decoder, or into the peak measuring.
 */
class WaveformStats {
    /** Reading and demuxing: `readSampleData`, `advance`, `seekTo`. For a vault file this is the decrypt. */
    val extractorNs = AtomicLong()

    /** Blocked waiting for the decoder to hand back a buffer, with nothing else left to do. */
    val waitNs = AtomicLong()

    /** Measuring the decoded samples. */
    val peaksNs = AtomicLong()

    @Volatile
    var mode: String = "sequential"

    inline fun <T> time(counter: AtomicLong, block: () -> T): T {
        val start = System.nanoTime()
        try {
            return block()
        } finally {
            counter.addAndGet(System.nanoTime() - start)
        }
    }
}

/**
 * Decodes a long file for its waveform with several decoders at once: the file is cut into pieces of a
 * couple of minutes, aligned to peak boundaries, and each worker (its own extractor and `MediaCodec`)
 * takes the next piece, seeks there and decodes just that. The peaks of a piece go straight into the
 * shared array, so the pieces never overlap.
 *
 * Why it helps: decoding one frame at a time costs the same whether the CPU has one core free or eight,
 * and for a vault file part of that cost is waiting on the engine, so more decoders in flight means
 * more of both overlapping.
 *
 * Why it is careful: a piece starts mid-file, so every peak's position comes from a timestamp rather than
 * from counting frames from the start. That is only trustworthy where the container seeks exactly
 * ([AudioEditMath.seeksExactly]), and the worker checks where its seek landed. Anything unexpected makes
 * [decode] return false and the caller starts over with the plain front-to-back decode, which is always
 * correct. The waveform is published as a contiguous prefix, so the editor sees it grow from the left
 * just as before, only faster.
 */
object ParallelWaveformDecoder {
    private const val TAG = "ParallelWaveform"

    /** Decoding starts this long before a piece so the decoder is warm (AAC overlaps frames, Vorbis needs the last packet). */
    private const val PREROLL_US = 1_000_000L

    /** ...and runs a little past its end, so the last peak is fully measured. */
    private const val POSTROLL_US = 250_000L

    /** A seek that lands further than this past the wanted start is not exact enough to use. */
    private const val MAX_SEEK_OVERSHOOT_US = 1_000_000L

    private const val STALL_TIMEOUT_MS = 20_000L
    private const val PARTIAL_INTERVAL_MS = 400L
    private const val DEQUEUE_TIMEOUT_US = 10_000L
    private const val COORDINATOR_TICK_MS = 50L

    /** What a worker remembers about its decoder between pieces. */
    private class WorkerState(var sampleRate: Int, var channels: Int, var encoding: Int)

    /**
     * Fills [peaks] (the whole file, one byte per peak) and returns true when every piece was decoded.
     * Returns false when a worker gave up, leaving [peaks] in an unknown state: the caller clears it
     * and decodes again from the start. Throws [AudioWaveformExtractor.CancelledException] on cancel.
     */
    fun decode(
        newExtractor: () -> AudioSource,
        track: Int,
        format: MediaFormat,
        mime: String,
        sampleRate: Int,
        channels: Int,
        peaksPerSecond: Double,
        peaks: ByteArray,
        workers: Int,
        isCancelled: () -> Boolean,
        onProgress: (Float) -> Unit,
        onPartial: (peaks: ByteArray, peaksPerSecond: Double, from: Int, to: Int) -> Unit,
        stats: WaveformStats,
    ): Boolean {
        val bucketCount = peaks.size
        val perChunk = AudioEditMath.chunkBuckets(peaksPerSecond)
        val chunkCount = (bucketCount + perChunk - 1) / perChunk
        // How far each piece has got (a bucket index, from its first bucket up to its end). Written by
        // the worker after it wrote the peaks, read by the coordinator before it reads them: that
        // volatile write/read pair is what makes the peaks visible across threads.
        val filled = AtomicIntegerArray(IntArray(chunkCount) { it * perChunk })
        val nextChunk = AtomicInteger(0)
        val abort = AtomicBoolean(false)
        val failure = AtomicReference<String?>(null)

        fun chunkEnd(c: Int) = min(bucketCount, (c + 1) * perChunk)

        val pool = Executors.newFixedThreadPool(workers) { r ->
            Thread(r, "AudioWaveform-worker").apply {
                isDaemon = true
                priority = Thread.NORM_PRIORITY - 1
            }
        }
        repeat(workers) {
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
                    var used = false
                    while (!abort.get()) {
                        val c = nextChunk.getAndIncrement()
                        if (c >= chunkCount) break
                        decodeChunk(
                            source, decoder, state, flushFirst = used,
                            firstBucket = c * perChunk, endBucket = chunkEnd(c),
                            peaksPerSecond = peaksPerSecond, peaks = peaks,
                            abort = abort, stats = stats,
                            publish = { bucket -> if (bucket > filled.get(c)) filled.set(c, bucket) },
                        )
                        used = true
                    }
                } catch (e: Throwable) {
                    if (failure.compareAndSet(null, "${e.javaClass.simpleName}: ${e.message}")) {
                        VeLog.i(TAG) { "a worker gave up: ${failure.get()}" }
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

        // The first bucket that is not final yet: pieces finish out of order, but only the unbroken run
        // from the start can be shown.
        fun frontier(): Int {
            var f = 0
            for (c in 0 until chunkCount) {
                val end = chunkEnd(c)
                val got = filled.get(c)
                if (got >= end) {
                    f = end
                } else {
                    f = max(f, got)
                    break
                }
            }
            return f
        }

        var sentUpTo = 0
        var lastEmitMs = SystemClock.elapsedRealtime()
        var lastPermille = -1
        try {
            while (true) {
                if (isCancelled()) {
                    abort.set(true)
                    throw AudioWaveformExtractor.CancelledException()
                }
                if (failure.get() != null) break
                val front = frontier()
                val now = SystemClock.elapsedRealtime()
                if (front > sentUpTo && now - lastEmitMs >= PARTIAL_INTERVAL_MS) {
                    lastEmitMs = now
                    onPartial(peaks, peaksPerSecond, sentUpTo, front)
                    sentUpTo = front
                }
                var done = 0L
                for (c in 0 until chunkCount) done += filled.get(c) - c.toLong() * perChunk
                val permille = (done * 1000L / bucketCount).toInt().coerceIn(0, 1000)
                if (permille != lastPermille) {
                    lastPermille = permille
                    onProgress(permille / 1000f)
                }
                if (front >= bucketCount) break
                Thread.sleep(COORDINATOR_TICK_MS)
            }
        } finally {
            // Whatever ended the loop, no worker may outlive this call: each holds a codec.
            if (failure.get() != null || isCancelled()) abort.set(true)
            if (!pool.awaitTermination(15, TimeUnit.SECONDS)) {
                abort.set(true)
                pool.shutdownNow()
            }
        }
        return failure.get() == null
    }

    /** Decodes the peaks of buckets `[firstBucket, endBucket)` into [peaks]. */
    private fun decodeChunk(
        extractor: AudioSource,
        codec: MediaCodec,
        state: WorkerState,
        flushFirst: Boolean,
        firstBucket: Int,
        endBucket: Int,
        peaksPerSecond: Double,
        peaks: ByteArray,
        abort: AtomicBoolean,
        stats: WaveformStats,
        publish: (Int) -> Unit,
    ) {
        val startUs = AudioEditMath.bucketStartUs(firstBucket, peaksPerSecond)
        val endUs = AudioEditMath.bucketStartUs(endBucket, peaksPerSecond)
        val accumulator = PeakAccumulator(peaks.size, 0.0, peaks, firstBucket, endBucket)
        val reader = PcmPeakReader(accumulator)
        reader.channels = state.channels
        reader.encoding = state.encoding

        fun applyRate(rate: Int) {
            if (rate <= 0) return
            state.sampleRate = rate
            accumulator.bucketsPerFrame = peaksPerSecond / rate
            reader.stride = AudioEditMath.strideFor(rate, peaksPerSecond)
        }
        applyRate(state.sampleRate)

        // After the previous piece's end-of-stream the decoder needs a flush before it takes input again.
        if (flushFirst) codec.flush()
        stats.time(stats.extractorNs) {
            extractor.seekTo(max(0L, startUs - PREROLL_US), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        }
        if (extractor.sampleTrackIndex < 0) {
            // Nothing from here on: the length estimate was a little long. The peaks stay silent.
            publish(endBucket)
            return
        }
        val landedUs = extractor.sampleTime
        if (landedUs > startUs + MAX_SEEK_OVERSHOOT_US) {
            throw IllegalStateException("seek to $startUs us landed at $landedUs us")
        }

        val info = MediaCodec.BufferInfo()
        var firstOutput = true
        var inputDone = false
        var outputDone = false
        var lastMovedMs = SystemClock.elapsedRealtime()

        fun drainOne(timeoutUs: Long): Boolean {
            val outIndex = codec.dequeueOutputBuffer(info, timeoutUs)
            return when {
                outIndex >= 0 -> {
                    val outBuffer = codec.getOutputBuffer(outIndex)
                    if (outBuffer != null && info.size > 0) {
                        if (firstOutput) {
                            // Where in the file this decode really starts, from the decoder's own timestamp.
                            reader.frameIndex = AudioEditMath.frameAtUs(info.presentationTimeUs, state.sampleRate)
                            firstOutput = false
                        }
                        stats.time(stats.peaksNs) { reader.consume(outBuffer, info.offset, info.size) }
                        publish(
                            (reader.frameIndex * accumulator.bucketsPerFrame).toLong()
                                .coerceIn(firstBucket.toLong(), endBucket.toLong()).toInt(),
                        )
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
                    LosslessAudioCutter.intValue(out, MediaFormat.KEY_SAMPLE_RATE)?.let { applyRate(it) }
                    true
                }
                else -> false
            }
        }

        while (!outputDone) {
            if (abort.get()) return
            var progressed = false

            while (!inputDone) {
                val inIndex = codec.dequeueInputBuffer(0L)
                if (inIndex < 0) break
                val inBuffer = codec.getInputBuffer(inIndex)
                val timeUs = extractor.sampleTime
                val size = if (inBuffer == null || extractor.sampleTrackIndex < 0 || timeUs > endUs + POSTROLL_US) {
                    -1
                } else {
                    stats.time(stats.extractorNs) { extractor.readSampleData(inBuffer, 0) }
                }
                if (size < 0) {
                    codec.queueInputBuffer(inIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    inputDone = true
                } else {
                    codec.queueInputBuffer(inIndex, 0, size, timeUs, 0)
                    stats.time(stats.extractorNs) { extractor.advance() }
                }
                progressed = true
            }

            while (!outputDone && drainOne(0L)) progressed = true

            if (progressed) {
                lastMovedMs = SystemClock.elapsedRealtime()
            } else if (!outputDone) {
                val waitStart = System.nanoTime()
                val got = drainOne(DEQUEUE_TIMEOUT_US)
                stats.waitNs.addAndGet(System.nanoTime() - waitStart)
                if (got) {
                    lastMovedMs = SystemClock.elapsedRealtime()
                } else if (SystemClock.elapsedRealtime() - lastMovedMs > STALL_TIMEOUT_MS) {
                    throw IllegalStateException("decoder stalled")
                }
            }
        }
        publish(endBucket)
    }
}
