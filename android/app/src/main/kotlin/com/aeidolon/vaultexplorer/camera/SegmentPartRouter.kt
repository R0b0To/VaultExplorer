package com.aeidolon.vaultexplorer.camera

/** Which elementary stream a sample belongs to. */
enum class SampleTrack { VIDEO, AUDIO }

/**
 * One encoded sample on the shared recording timeline.
 *
 * [ptsUs] is in microseconds on a single clock for both tracks (the camera's
 * clock; audio is converted to it before it gets here). [payload] is opaque to
 * the router -- the muxer side puts the bytes in it, a test puts anything.
 */
class RoutedSample<T>(
    val track: SampleTrack,
    val ptsUs: Long,
    val isKeyFrame: Boolean,
    val payload: T,
)

/** Where [SegmentPartRouter] sends samples; backed by a `MediaMuxer` per part in the app. */
interface PartSink<T> {
    /** Starts part number [index] (1-based). Its first sample is a video keyframe at [startUs]. */
    fun openPart(index: Int, startUs: Long)

    /** Writes [sample] into the open part, [relativePtsUs] after the part's start (never negative). */
    fun write(sample: RoutedSample<T>, relativePtsUs: Long)

    /**
     * Ends the open part. [durationUs] is its exact length on the recording
     * timeline. [isLast] is true only for the part that [SegmentPartRouter.finish] closes.
     */
    fun closePart(durationUs: Long, isLast: Boolean)
}

/**
 * Cuts one continuous stream of encoded video + audio into parts of an exact
 * length, each a complete, independently playable file.
 *
 * Why this exists: `MediaRecorder` can only roll over to a new file on a *size*
 * limit, never on a duration, so a part's length drifts with whatever bitrate
 * the encoder really produced. Cutting here instead means the length is what
 * was asked for, whatever the resolution, codec or scene.
 *
 * How a cut is made so that every part looks like a fresh recording:
 *  - A part only ever starts on a video **keyframe**, and that keyframe sits at
 *    relative time 0. A player or a scrub-preview decoder can therefore seek to
 *    any position and always finds a keyframe at or before it, in every part
 *    (parts cut by `MediaRecorder` start their video late, behind a gap).
 *  - A little before a cut is due the router asks the encoder for a keyframe
 *    ([requestSyncFrame]), so the cut lands within about two frames of the
 *    target instead of waiting for the next natural keyframe. If the encoder
 *    ignores the request the cut simply happens on the next natural keyframe.
 *  - Audio is split purely by timestamp: everything before the cut keyframe
 *    belongs to the old part, everything from it on to the new one, so no audio
 *    is lost or repeated at a seam. Audio is held back until video has caught
 *    up with it (the video encoder is slower than the audio one), so an audio
 *    sample is never written to the old part just because it arrived early.
 *
 * Not thread safe: call from one thread. Holds no Android types.
 *
 * @param partLengthUs wanted length of every part but the last, in microseconds
 * @param frameDurationUs nominal video frame duration; sets the cut tolerance
 */
class SegmentPartRouter<T>(
    private val partLengthUs: Long,
    private val frameDurationUs: Long,
    private val sink: PartSink<T>,
    private val requestSyncFrame: () -> Unit,
    private val maxPendingAudio: Int = DEFAULT_MAX_PENDING_AUDIO,
) {
    init {
        require(partLengthUs > 0) { "partLengthUs must be positive" }
        require(frameDurationUs > 0) { "frameDurationUs must be positive" }
    }

    /** A keyframe at least this far into a part ends it; also how early a keyframe is requested. */
    private val slackUs = 2 * frameDurationUs

    private var open = false
    private var partIndex = 0
    private var partStartUs = 0L
    private var syncRequested = false

    private var watermarkUs = Long.MIN_VALUE
    private var lastVideoUs = Long.MIN_VALUE
    private var lastFrameDurationUs = frameDurationUs

    private val pendingAudio = ArrayDeque<RoutedSample<T>>()

    /** Parts closed so far, including the last one once [finish] ran. */
    var partsClosed = 0
        private set

    /** Audio samples that fell before the first keyframe (or overflowed) and were dropped. */
    var droppedAudio = 0
        private set

    /** Video samples dropped because they arrived before the first keyframe. */
    var skippedVideo = 0
        private set

    val isOpen: Boolean get() = open

    /**
     * Routes one video sample.
     *
     * @param pipelineLagUs how long ago the camera captured this frame (now minus
     *   its timestamp). Used only to time the keyframe request; 0 is fine if unknown.
     */
    fun onVideo(sample: RoutedSample<T>, pipelineLagUs: Long = 0L) {
        require(sample.track == SampleTrack.VIDEO) { "not a video sample" }

        if (!open) {
            if (!sample.isKeyFrame) {
                skippedVideo++
                return
            }
            beginPart(sample.ptsUs)
        } else if (sample.isKeyFrame) {
            if (sample.ptsUs - partStartUs >= partLengthUs - slackUs) {
                // The cut: audio older than this keyframe is the old part's tail.
                flushAudio { it.ptsUs < sample.ptsUs }
                closeOpenPart(durationUs = sample.ptsUs - partStartUs, isLast = false)
                beginPart(sample.ptsUs)
            } else {
                // A keyframe too early to cut on (a natural one, or one we asked
                // for too soon): allow asking again when the cut is really due.
                syncRequested = false
            }
        }

        val lag = pipelineLagUs.coerceIn(0L, MAX_LAG_US)
        if (!syncRequested && sample.ptsUs + lag - partStartUs >= partLengthUs - slackUs) {
            syncRequested = true
            requestSyncFrame()
        }

        sink.write(sample, (sample.ptsUs - partStartUs).coerceAtLeast(0L))

        if (lastVideoUs != Long.MIN_VALUE) {
            val delta = sample.ptsUs - lastVideoUs
            if (delta in 1..MAX_FRAME_DURATION_US) lastFrameDurationUs = delta
        }
        if (sample.ptsUs > lastVideoUs) lastVideoUs = sample.ptsUs
        if (sample.ptsUs > watermarkUs) watermarkUs = sample.ptsUs

        flushAudio { it.ptsUs <= watermarkUs }
    }

    /** Routes one audio sample. It is written once video has progressed past its timestamp. */
    fun onAudio(sample: RoutedSample<T>) {
        require(sample.track == SampleTrack.AUDIO) { "not an audio sample" }
        pendingAudio.addLast(sample)
        if (pendingAudio.size > maxPendingAudio) {
            pendingAudio.removeFirst()
            droppedAudio++
        }
        if (open) flushAudio { it.ptsUs <= watermarkUs }
    }

    /**
     * Ends the recording: every audio sample still waiting goes into the open
     * part, which is then closed as the last one. Does nothing if no part was
     * ever opened (no keyframe arrived).
     */
    fun finish() {
        if (!open) {
            droppedAudio += pendingAudio.size
            pendingAudio.clear()
            return
        }
        flushAudio { true }
        val durationUs = (lastVideoUs + lastFrameDurationUs - partStartUs).coerceAtLeast(1L)
        closeOpenPart(durationUs, isLast = true)
    }

    private fun beginPart(startUs: Long) {
        sink.openPart(partIndex + 1, startUs)
        partIndex++
        partStartUs = startUs
        syncRequested = false
        open = true
    }

    private fun closeOpenPart(durationUs: Long, isLast: Boolean) {
        open = false
        partsClosed++
        sink.closePart(durationUs, isLast)
    }

    /** Writes (or drops, if before the part) the leading audio samples that match [due]. */
    private inline fun flushAudio(due: (RoutedSample<T>) -> Boolean) {
        while (true) {
            val head = pendingAudio.firstOrNull() ?: return
            if (!due(head)) return
            pendingAudio.removeFirst()
            if (head.ptsUs < partStartUs) {
                droppedAudio++
            } else {
                sink.write(head, head.ptsUs - partStartUs)
            }
        }
    }

    companion object {
        const val DEFAULT_MAX_PENDING_AUDIO = 4096

        /** A lag above this is a clock problem, not a pipeline delay; do not let it skew the request. */
        private const val MAX_LAG_US = 500_000L

        /** A gap between video frames above this is a stall, not the frame rate. */
        private const val MAX_FRAME_DURATION_US = 200_000L
    }
}
