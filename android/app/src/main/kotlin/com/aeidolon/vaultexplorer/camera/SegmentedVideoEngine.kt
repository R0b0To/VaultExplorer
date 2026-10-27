package com.aeidolon.vaultexplorer.camera

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.view.Surface
import com.aeidolon.vaultexplorer.VeLog
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

private const val TAG = "SegmentedVideoEngine"

/**
 * Records video + audio into a series of files, each [partSeconds] long.
 *
 * This is what segmented recording uses instead of `MediaRecorder`. The stock
 * recorder can only roll over to a new file on a *size* limit, so part lengths
 * wandered with whatever bitrate the encoder really produced (and differed per
 * resolution), and the files it rolled into started their video late, behind a
 * gap, which left later parts without usable frames for seek-bar previews.
 *
 * Here the encoding and the muxing are owned directly:
 *
 *   camera --> [video MediaCodec, surface input] --\
 *                                                   >--> queue --> [mux thread]
 *   mic --> AudioRecord --> [AAC MediaCodec] ------/                  |
 *                                                  SegmentPartRouter decides the cuts
 *                                                  and one MediaMuxer writes each part
 *
 * Every part is a complete MP4 whose first video sample is a keyframe at time
 * zero (see [SegmentPartRouter] for how cuts are made exactly on time).
 *
 * Threads: a video drain thread, an audio thread (read + encode + drain) and a
 * mux thread. Encoder output is copied and released at once, so a slow disk
 * only grows the queue, never stalls an encoder.
 *
 * Lifecycle, mirroring `MediaRecorder`: [prepare] (gives [inputSurface]) ->
 * [start] -> ([pause] -> [resume])* -> [stop] -> [release]. [release] is safe in
 * any state.
 *
 * A pause closes the part in progress and the next part opens after [resume]
 * (see [SegmentPartRouter]), so a paused recording is simply a recording whose
 * parts are cut where the pauses were. The video encoder is suspended meanwhile
 * (as `MediaRecorder.pause` does). The microphone keeps being read, but what it
 * hears is dropped before anything is written, so keeping the audio encoder's
 * clock running costs nothing and cannot put the two tracks out of step.
 */
internal class SegmentedVideoEngine(
    private val width: Int,
    private val height: Int,
    private val preferHevc: Boolean,
    private val hevcBitrate: Int,
    private val h264Bitrate: Int,
    private val frameRate: Int,
    private val recordAudio: Boolean,
    private val partSeconds: Int,
    orientationDegrees: Int,
    private val cacheDir: File?,
    private val tempPrefix: String,
    private val tempSuffix: String,
    /** Zero-fills and deletes a plaintext file. */
    private val wipe: (File) -> Unit,
) {
    private companion object {
        const val SAMPLE_RATE = 44_100
        const val AUDIO_BITRATE = 128_000
        const val AUDIO_CHUNK_BYTES = 2048 // 1024 mono 16-bit frames, ~23 ms
        const val DEQUEUE_TIMEOUT_US = 10_000L

        /** How long the threads get to drain after the stop request before they are cut off. */
        const val STOP_DRAIN_MS = 4_000L

        /** If storage stalls and this much encoded data piles up, give up rather than run out of memory. */
        const val MAX_QUEUED_BYTES = 96L * 1024 * 1024

        /** Video held back waiting for the audio format before recording goes on without audio. */
        const val AUDIO_FORMAT_WAIT_US = 3_000_000L
    }

    private val orientation = (((orientationDegrees % 360) + 360) % 360) / 90 * 90

    // --- What flows from the encoder threads to the mux thread --------------
    private sealed class Item {
        class Format(val track: SampleTrack, val format: MediaFormat) : Item()
        class Sample(val track: SampleTrack, val ptsUs: Long, val isKey: Boolean, val data: ByteArray) : Item()
        class End(val track: SampleTrack) : Item()

        /** Pause / resume, travelling in the queue so the mux thread sees them in step with the samples. */
        object Pause : Item()
        object Resume : Item()
    }

    private val queue = LinkedBlockingQueue<Item>()
    private val queuedBytes = AtomicLong(0)

    // --- Public surface ------------------------------------------------------

    /** The surface the camera renders into; valid after [prepare]. */
    @Volatile
    var inputSurface: Surface? = null
        private set

    /**
     * Called, from the mux thread, with every part as soon as it is closed --
     * except the last one, which [stop] leaves as [currentFile].
     */
    @Volatile
    var onPartFinished: ((VideoSegment) -> Unit)? = null

    /** The part being written, or, after [stop], the last part. Null before the first keyframe. */
    @Volatile
    var currentFile: File? = null
        private set

    /** Length of the last part, valid once [stop] has returned. */
    @Volatile
    var lastPartDurationMs: Long = 0L
        private set

    // --- Codecs and threads --------------------------------------------------
    @Volatile
    private var videoCodec: MediaCodec? = null

    @Volatile
    private var audioCodec: MediaCodec? = null

    @Volatile
    private var audioRecord: AudioRecord? = null

    private var videoThread: Thread? = null
    private var audioThread: Thread? = null
    private var muxThread: Thread? = null

    private val started = AtomicBoolean(false)
    private val stopRequested = AtomicBoolean(false)
    private val abort = AtomicBoolean(false)
    private val audioStop = AtomicBoolean(false)

    @Volatile
    private var stopDeadlineNs = Long.MAX_VALUE

    @Volatile
    private var pausedFlag = false

    /** True between [pause] and [resume] (or [stop]). */
    val isPaused: Boolean get() = pausedFlag

    @Volatile
    private var failure: Throwable? = null

    // --- Setup ---------------------------------------------------------------

    /** Builds the encoders and the microphone. Throws if the device cannot do it. */
    fun prepare() {
        try {
            prepareVideo()
            if (recordAudio) prepareAudio()
        } catch (e: Throwable) {
            release()
            throw e
        }
    }

    private fun prepareVideo() {
        if (preferHevc) {
            try {
                configureVideo(MediaFormat.MIMETYPE_VIDEO_HEVC, hevcBitrate)
                return
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "HEVC encoder could not be configured, falling back to H264" }
            }
        }
        configureVideo(MediaFormat.MIMETYPE_VIDEO_AVC, h264Bitrate)
    }

    private fun configureVideo(mime: String, bitrate: Int) {
        val codec = MediaCodec.createEncoderByType(mime)
        try {
            val format = MediaFormat.createVideoFormat(mime, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
                // One-second GOP: bounds how far a seek or scrub preview has to
                // decode forward from a keyframe. Cuts add one more on demand.
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                setInteger(MediaFormat.KEY_PRIORITY, 0) // real time
            }
            val caps = codec.codecInfo.getCapabilitiesForType(mime).encoderCapabilities
            if (caps != null && caps.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)) {
                format.setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = codec.createInputSurface()
            videoCodec = codec
            VeLog.d(TAG) { "video encoder ready: $mime ${width}x$height bitrate=$bitrate fps=$frameRate parts=${partSeconds}s" }
        } catch (e: Exception) {
            inputSurface?.release()
            inputSurface = null
            try { codec.release() } catch (_: Exception) {}
            throw e
        }
    }

    @SuppressLint("MissingPermission") // RECORD_AUDIO is requested by the capture screen, as MediaRecorder needed.
    private fun prepareAudio() {
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        check(minBuffer > 0) { "audio input is not supported" }
        val bufferBytes = maxOf(minBuffer * 4, SAMPLE_RATE) // at least half a second

        var record: AudioRecord? = null
        // The camcorder source is what MediaRecorder used here; not every device
        // offers it to AudioRecord, so fall back to the plain microphone.
        for (source in intArrayOf(MediaRecorder.AudioSource.CAMCORDER, MediaRecorder.AudioSource.MIC)) {
            val candidate = try {
                AudioRecord.Builder()
                    .setAudioSource(source)
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                            .build(),
                    )
                    .setBufferSizeInBytes(bufferBytes)
                    .build()
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "audio source $source unavailable" }
                null
            }
            if (candidate != null && candidate.state == AudioRecord.STATE_INITIALIZED) {
                record = candidate
                break
            }
            candidate?.release()
        }
        checkNotNull(record) { "the microphone could not be opened" }
        audioRecord = record

        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        try {
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_BITRATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, AUDIO_CHUNK_BYTES * 4)
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            audioCodec = codec
        } catch (e: Exception) {
            try { codec.release() } catch (_: Exception) {}
            throw e
        }
    }

    // --- Running -------------------------------------------------------------

    /** Starts encoding. Frames the camera sends to [inputSurface] from now on are recorded. */
    fun start() {
        val video = checkNotNull(videoCodec) { "not prepared" }
        check(started.compareAndSet(false, true)) { "already started" }

        video.start()
        audioCodec?.start()
        audioRecord?.startRecording()

        muxThread = Thread({ muxLoop() }, "vault-seg-mux").also { it.start() }
        videoThread = Thread({ videoLoop(video) }, "vault-seg-video").also { it.start() }
        val record = audioRecord
        val audio = audioCodec
        if (record != null && audio != null) {
            audioThread = Thread({ audioLoop(record, audio) }, "vault-seg-audio").also { it.start() }
        }
    }

    /**
     * Pauses the recording: the part in progress is closed and nothing is
     * written until [resume]. Does nothing unless recording.
     */
    fun pause() {
        if (!started.get() || stopRequested.get() || pausedFlag) return
        pausedFlag = true
        queue.put(Item.Pause)
        suspendVideoInput(true)
    }

    /** Ends a [pause]; the next keyframe opens a new part. */
    fun resume() {
        if (!started.get() || stopRequested.get() || !pausedFlag) return
        pausedFlag = false
        // The mux thread must know the pause is over before the first frame of
        // the new part can reach it, so this goes into the queue first.
        queue.put(Item.Resume)
        suspendVideoInput(false)
    }

    private fun suspendVideoInput(suspend: Boolean) {
        try {
            val params = Bundle()
            params.putInt(MediaCodec.PARAMETER_KEY_SUSPEND, if (suspend) 1 else 0)
            videoCodec?.setParameters(params)
        } catch (e: Exception) {
            // Not fatal: without it frames still reach the router, which drops them while paused.
            VeLog.w(TAG, e) { "could not ${if (suspend) "suspend" else "resume"} the video encoder input" }
        }
    }

    /**
     * Ends the recording and waits until the last part is closed. The camera
     * must have stopped sending frames. Returns the length of the last part, in
     * milliseconds; the file is [currentFile].
     */
    fun stop(): Long {
        if (!started.get() || !stopRequested.compareAndSet(false, true)) return lastPartDurationMs
        stopDeadlineNs = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(STOP_DRAIN_MS)

        // End of stream is only reliably delivered by an encoder that is taking
        // input. The router still drops anything that comes out while paused.
        if (pausedFlag) {
            pausedFlag = false
            suspendVideoInput(false)
        }
        try {
            videoCodec?.signalEndOfInputStream()
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "signalEndOfInputStream failed; the video thread will time out" }
        }
        audioStop.set(true)
        try { audioRecord?.stop() } catch (_: Exception) {}

        val patience = STOP_DRAIN_MS + 2_000L
        join(videoThread, patience)
        join(audioThread, patience)
        join(muxThread, patience + 2_000L)
        if (listOf(videoThread, audioThread, muxThread).any { it?.isAlive == true }) {
            VeLog.w(TAG) { "recording threads did not finish in time; cutting them off" }
            abort.set(true)
            for (t in listOf(videoThread, audioThread, muxThread)) t?.interrupt()
            join(videoThread, 1_000L)
            join(audioThread, 1_000L)
            join(muxThread, 2_000L)
        }
        VeLog.d(TAG) { "stopped; last part ${lastPartDurationMs}ms" }
        return lastPartDurationMs
    }

    /**
     * Stops everything and frees the encoders and the microphone. Safe in any
     * state, and after [stop]. The part files are left alone: see [wipeCurrentFile].
     */
    fun release() {
        abort.set(true)
        for (t in listOf(videoThread, audioThread, muxThread)) {
            if (t != null && t.isAlive && t !== Thread.currentThread()) t.interrupt()
        }
        join(videoThread, 1_000L)
        join(audioThread, 1_000L)
        join(muxThread, 2_000L)

        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        for (codec in listOf(videoCodec, audioCodec)) {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
        }
        videoCodec = null
        audioCodec = null
        try { inputSurface?.release() } catch (_: Exception) {}
        inputSurface = null
        queue.clear()
        queuedBytes.set(0)
    }

    /** Wipes the part being written (or the last one), if its file still exists. */
    fun wipeCurrentFile() {
        val file = currentFile ?: return
        currentFile = null
        wipe(file)
    }

    private fun join(thread: Thread?, millis: Long) {
        if (thread == null || thread === Thread.currentThread()) return
        try { thread.join(millis) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
    }

    private fun shouldGiveUp(): Boolean =
        abort.get() || (stopRequested.get() && System.nanoTime() > stopDeadlineNs)

    private fun enqueue(item: Item) {
        if (item is Item.Sample) {
            if (queuedBytes.addAndGet(item.data.size.toLong()) > MAX_QUEUED_BYTES) {
                queuedBytes.addAndGet(-item.data.size.toLong())
                if (failure == null) failure = IllegalStateException("storage cannot keep up with the recording")
                return
            }
        }
        queue.put(item)
    }

    // --- Video drain thread --------------------------------------------------

    private fun videoLoop(codec: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        var formatSent = false
        try {
            while (!shouldGiveUp()) {
                val index = codec.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US)
                when {
                    index == MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        enqueue(Item.Format(SampleTrack.VIDEO, codec.outputFormat))
                        formatSent = true
                    }
                    index >= 0 -> {
                        if (!formatSent) {
                            // Encoders announce their format before the first buffer; be safe if one did not.
                            enqueue(Item.Format(SampleTrack.VIDEO, codec.outputFormat))
                            formatSent = true
                        }
                        val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                        val buffer = codec.getOutputBuffer(index)
                        if (buffer != null && info.size > 0 && !isConfig) {
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            val bytes = ByteArray(info.size)
                            buffer.get(bytes)
                            enqueue(
                                Item.Sample(
                                    SampleTrack.VIDEO,
                                    info.presentationTimeUs,
                                    info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0,
                                    bytes,
                                ),
                            )
                        }
                        codec.releaseOutputBuffer(index, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                }
            }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "video drain failed" }
            if (failure == null) failure = e
        } finally {
            queue.put(Item.End(SampleTrack.VIDEO))
        }
    }

    // --- Audio thread --------------------------------------------------------

    private fun audioLoop(record: AudioRecord, codec: MediaCodec) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        val info = MediaCodec.BufferInfo()
        val chunk = ByteArray(AUDIO_CHUNK_BYTES)
        val timestamp = AudioTimestamp()
        var framesRead = 0L
        var anchorUs = Long.MIN_VALUE // boot-clock time of audio frame 0
        try {
            while (!audioStop.get() && !abort.get()) {
                val read = record.read(chunk, 0, chunk.size)
                if (read < 0) {
                    VeLog.w(TAG) { "audio read failed ($read); continuing without audio" }
                    break
                }
                if (read == 0) continue
                if (anchorUs == Long.MIN_VALUE) {
                    anchorUs = if (record.getTimestamp(timestamp, AudioTimestamp.TIMEBASE_BOOTTIME) == AudioRecord.SUCCESS) {
                        // The driver says when frame N was captured: exact.
                        timestamp.nanoTime / 1000L - timestamp.framePosition * 1_000_000L / SAMPLE_RATE
                    } else {
                        // Otherwise assume this read ended about now.
                        SystemClock.elapsedRealtimeNanos() / 1000L - (read / 2L) * 1_000_000L / SAMPLE_RATE
                    }
                }
                val ptsUs = anchorUs + framesRead * 1_000_000L / SAMPLE_RATE
                feedPcm(codec, chunk, read, ptsUs, info)
                framesRead += read / 2
                drainAudio(codec, info)
            }
            val endPtsUs = if (anchorUs == Long.MIN_VALUE) 0L else anchorUs + framesRead * 1_000_000L / SAMPLE_RATE
            feedEndOfStream(codec, endPtsUs, info)
            while (!shouldGiveUp()) {
                if (drainAudio(codec, info, DEQUEUE_TIMEOUT_US)) break
            }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "audio thread failed" }
        } finally {
            queue.put(Item.End(SampleTrack.AUDIO))
        }
    }

    private fun feedPcm(codec: MediaCodec, data: ByteArray, size: Int, ptsUs: Long, info: MediaCodec.BufferInfo) {
        var offset = 0
        while (offset < size && !abort.get()) {
            val index = codec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
            if (index < 0) {
                drainAudio(codec, info)
                continue
            }
            val buffer = codec.getInputBuffer(index) ?: continue
            buffer.clear()
            val length = minOf(size - offset, buffer.remaining()) and 1.inv() // whole 16-bit frames
            buffer.put(data, offset, length)
            codec.queueInputBuffer(index, 0, length, ptsUs + (offset / 2L) * 1_000_000L / SAMPLE_RATE, 0)
            offset += length
        }
    }

    private fun feedEndOfStream(codec: MediaCodec, ptsUs: Long, info: MediaCodec.BufferInfo) {
        while (!shouldGiveUp()) {
            val index = codec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
            if (index >= 0) {
                codec.queueInputBuffer(index, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                return
            }
            drainAudio(codec, info)
        }
    }

    /** Moves finished AAC frames to the queue. Returns true once the end of the stream came out. */
    private fun drainAudio(codec: MediaCodec, info: MediaCodec.BufferInfo, timeoutUs: Long = 0L): Boolean {
        while (true) {
            val index = codec.dequeueOutputBuffer(info, timeoutUs)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> return false
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                    enqueue(Item.Format(SampleTrack.AUDIO, codec.outputFormat))
                index >= 0 -> {
                    val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    val buffer = codec.getOutputBuffer(index)
                    if (buffer != null && info.size > 0 && !isConfig) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        val bytes = ByteArray(info.size)
                        buffer.get(bytes)
                        enqueue(Item.Sample(SampleTrack.AUDIO, info.presentationTimeUs, true, bytes))
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return true
                }
            }
        }
    }

    // --- Mux thread ----------------------------------------------------------

    private fun requestKeyFrame() {
        try {
            val params = Bundle()
            params.putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
            videoCodec?.setParameters(params)
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "keyframe request failed" }
        }
    }

    private fun muxLoop() {
        var videoFormat: MediaFormat? = null
        var audioFormat: MediaFormat? = null
        var videoEnded = false
        var audioEnded = !recordAudio
        var audioGivenUp = !recordAudio

        var clock = CameraClock.UNKNOWN
        var clockKnown = false
        var audioShiftUs = 0L

        // Until both formats are known (a muxer needs them) samples wait here, in order.
        val early = ArrayList<Item.Sample>()
        var earlyFirstVideoUs = Long.MIN_VALUE
        var earlyLastVideoUs = Long.MIN_VALUE
        var sink: MuxerSink? = null
        var router: SegmentPartRouter<ByteArray>? = null
        // A pause that arrived before the first part could even be set up.
        var pausedEarly = false

        fun route(sample: Item.Sample) {
            val r = router ?: return
            if (failure != null) return
            try {
                if (sample.track == SampleTrack.VIDEO) {
                    val lag = CameraClockMath.lagUs(
                        clock, sample.ptsUs, SystemClock.elapsedRealtimeNanos() / 1000L, System.nanoTime() / 1000L,
                    )
                    r.onVideo(RoutedSample(SampleTrack.VIDEO, sample.ptsUs, sample.isKey, sample.data), lag)
                } else if (!audioGivenUp) {
                    r.onAudio(RoutedSample(SampleTrack.AUDIO, sample.ptsUs - audioShiftUs, true, sample.data))
                }
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "writing a part failed; recording stops saving" }
                if (failure == null) failure = e
            }
        }

        try {
            while (true) {
                val item = queue.poll(100, TimeUnit.MILLISECONDS)
                if (item == null) {
                    if (abort.get()) break
                    continue
                }
                if (item is Item.Sample) queuedBytes.addAndGet(-item.data.size.toLong())

                when (item) {
                    is Item.Format ->
                        if (item.track == SampleTrack.VIDEO) videoFormat = item.format else audioFormat = item.format
                    is Item.End ->
                        if (item.track == SampleTrack.VIDEO) videoEnded = true else audioEnded = true
                    Item.Pause -> {
                        val r = router
                        if (r != null) {
                            try {
                                r.pause()
                            } catch (e: Exception) {
                                VeLog.e(TAG, e) { "closing the part at the pause failed; recording stops saving" }
                                if (failure == null) failure = e
                            }
                        } else {
                            // Nothing was written yet; what is waiting is footage from before the pause.
                            pausedEarly = true
                            early.clear()
                            earlyFirstVideoUs = Long.MIN_VALUE
                            earlyLastVideoUs = Long.MIN_VALUE
                        }
                    }
                    Item.Resume -> {
                        val r = router
                        if (r != null) r.resume() else pausedEarly = false
                    }
                    is Item.Sample -> {
                        if (item.track == SampleTrack.VIDEO && !clockKnown) {
                            val boot = SystemClock.elapsedRealtimeNanos() / 1000L
                            val mono = System.nanoTime() / 1000L
                            clock = CameraClockMath.detect(item.ptsUs, boot, mono)
                            audioShiftUs = CameraClockMath.bootToCameraOffsetUs(clock, item.ptsUs, boot, mono)
                            clockKnown = true
                            VeLog.d(TAG) { "camera clock=$clock audioShiftUs=$audioShiftUs" }
                        }
                        if (router != null) {
                            route(item)
                        } else if (pausedEarly) {
                            // Dropped, as the router would while paused.
                        } else {
                            if (item.track == SampleTrack.VIDEO) {
                                if (earlyFirstVideoUs == Long.MIN_VALUE) earlyFirstVideoUs = item.ptsUs
                                earlyLastVideoUs = item.ptsUs
                            }
                            early.add(item)
                        }
                    }
                }

                if (router == null && failure == null) {
                    // Video must not wait forever for an audio format that is not coming.
                    val waitedTooLong = earlyFirstVideoUs != Long.MIN_VALUE &&
                        earlyLastVideoUs - earlyFirstVideoUs > AUDIO_FORMAT_WAIT_US
                    if (audioFormat == null && !audioGivenUp && (audioEnded || waitedTooLong)) {
                        VeLog.w(TAG) { "no audio format arrived; recording video without audio" }
                        audioGivenUp = true
                    }
                    val vf = videoFormat
                    val haveVideo = early.any { it.track == SampleTrack.VIDEO }
                    if (vf != null && haveVideo && (audioFormat != null || audioGivenUp)) {
                        try {
                            val s = MuxerSink(vf, if (audioGivenUp) null else audioFormat)
                            sink = s
                            router = SegmentPartRouter(
                                partLengthUs = partSeconds * 1_000_000L,
                                frameDurationUs = 1_000_000L / frameRate,
                                sink = s,
                                requestSyncFrame = this::requestKeyFrame,
                            )
                            if (pausedEarly) router?.pause()
                            for (queued in early) route(queued)
                            early.clear()
                        } catch (e: Exception) {
                            VeLog.e(TAG, e) { "could not start the first part" }
                            failure = e
                        }
                    }
                }

                if (videoEnded && audioEnded) break
            }
        } catch (e: InterruptedException) {
            VeLog.w(TAG) { "mux thread interrupted" }
        } finally {
            try {
                if (failure != null) sink?.closeAfterFailure() else router?.finish()
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "closing the last part failed" }
                sink?.closeAfterFailure()
            }
            VeLog.d(TAG) { "mux done: parts=${router?.partsClosed ?: 0} droppedAudio=${router?.droppedAudio ?: 0}" }
        }
    }

    /** Writes each part with its own [MediaMuxer]; see [SegmentPartRouter] for what is written when. */
    private inner class MuxerSink(
        private val videoFormat: MediaFormat,
        private val audioFormat: MediaFormat?,
    ) : PartSink<ByteArray> {
        private var muxer: MediaMuxer? = null
        private var file: File? = null
        private var videoTrack = -1
        private var audioTrack = -1
        private var lastVideoRelUs = 0L
        private val info = MediaCodec.BufferInfo()

        override fun openPart(index: Int, startUs: Long) {
            val target = File.createTempFile(tempPrefix, tempSuffix, cacheDir)
            var m: MediaMuxer? = null
            try {
                m = MediaMuxer(target.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                m.setOrientationHint(orientation)
                videoTrack = m.addTrack(videoFormat)
                audioTrack = if (audioFormat != null) m.addTrack(audioFormat) else -1
                m.start()
            } catch (e: Exception) {
                try { m?.release() } catch (_: Exception) {}
                wipe(target)
                throw e
            }
            muxer = m
            file = target
            lastVideoRelUs = 0L
            currentFile = target
            VeLog.d(TAG) { "part $index opened" }
        }

        override fun write(sample: RoutedSample<ByteArray>, relativePtsUs: Long) {
            val m = muxer ?: return
            val track = if (sample.track == SampleTrack.VIDEO) videoTrack else audioTrack
            if (track < 0) return
            val data = sample.payload
            info.set(0, data.size, relativePtsUs, if (sample.isKeyFrame) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
            m.writeSampleData(track, ByteBuffer.wrap(data), info)
            if (sample.track == SampleTrack.VIDEO) lastVideoRelUs = relativePtsUs
        }

        override fun closePart(durationUs: Long, isLast: Boolean) {
            val done = file
            file = null
            val finished = stopAndRelease()
            val durationMs = durationUs / 1000L
            if (done == null) return
            if (isLast) {
                lastPartDurationMs = durationMs
                if (!finished) wipe(done) // currentFile stays; the missing file reads as "no video"
            } else {
                // A part that could not be completed is dropped: it cannot be played.
                currentFile = null // handed over below; must not also be reported as the last part
                if (finished) {
                    VeLog.d(TAG) { "part closed: ${durationMs}ms" }
                    onPartFinished?.invoke(VideoSegment(done.absolutePath, durationMs))
                } else {
                    wipe(done)
                }
            }
        }

        /**
         * Closes the part that is open, if any, after an error, keeping what was
         * written as the last part. A part that was already handed over is not touched.
         */
        fun closeAfterFailure() {
            if (muxer == null) return
            val done = file
            file = null
            val finished = stopAndRelease()
            lastPartDurationMs = (lastVideoRelUs + 1_000_000L / frameRate) / 1000L
            if (!finished && done != null) wipe(done)
        }

        /** Finalizes the open muxer. Returns false if there was none or the file could not be completed. */
        private fun stopAndRelease(): Boolean {
            val m = muxer ?: return false
            muxer = null
            var ok = true
            try {
                m.stop()
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "could not finish a part" }
                ok = false
            }
            try { m.release() } catch (_: Exception) {}
            return ok
        }
    }
}
