package com.aeidolon.vaultexplorer.container

/**
 * Where a long-lived software decode session currently stands, so
 * [VideoThumbnailCoordinator.decodeSoftwareFrameNear] can keep decoding
 * *forward* from it for the next request instead of seeking back to a
 * keyframe and starting over each time.
 *
 * Owned by whoever owns the codec (the scrub-preview session) and, like
 * the codec itself, only ever touched from that owner's single thread.
 *
 * Deliberately free of Android types so the decisions it makes can be unit
 * tested on the plain JVM.
 */
class SoftwareDecodeCursor {
    /**
     * Presentation time of the last frame the codec has output since it
     * was last flushed, or [NONE] if it hasn't output one.
     */
    var lastOutputPtsUs: Long = NONE

    /**
     * True once end-of-stream has been queued: the codec takes no more
     * input until it is flushed.
     */
    var inputDone: Boolean = false

    /** Forget everything -- call whenever the codec is flushed or torn down. */
    fun reset() {
        lastOutputPtsUs = NONE
        inputDone = false
    }

    /**
     * Whether the decoder can simply carry on forward to reach [targetUs],
     * rather than seek + flush and decode up from a keyframe.
     *
     * Carrying on is only correct for a target at or after the last frame
     * already output, and only worthwhile while that target is close:
     * further out than [CONTINUE_WINDOW_US], seeking to the target's own
     * keyframe is the cheaper way there.
     */
    fun canContinueTo(targetUs: Long): Boolean =
        !inputDone &&
            lastOutputPtsUs != NONE &&
            targetUs >= lastOutputPtsUs &&
            targetUs - lastOutputPtsUs <= CONTINUE_WINDOW_US

    companion object {
        const val NONE: Long = Long.MIN_VALUE

        /** About one typical keyframe interval. */
        const val CONTINUE_WINDOW_US: Long = 1_000_000L
    }
}

/**
 * Roughly how many slider pixels a scrub-preview drag spans. Only used to
 * turn a video's length into "how much time is one pixel".
 */
private const val SCRUB_SLIDER_PIXELS = 360L

/**
 * How far (in microseconds) a preview frame may sit from the requested
 * position before it's worth decoding further to get closer: about one
 * slider pixel's worth of the video.
 *
 * Short clips get a tolerance under a frame, so every position shows its
 * own frame. A feature-length film gets tens of seconds -- and there, the
 * keyframe the seek lands on is already as close as anyone can tell while
 * dragging, so the cheap keyframe-only behaviour is kept. An unknown
 * duration (0) asks for full accuracy.
 */
fun scrubToleranceUs(durationUs: Long): Long =
    if (durationUs > 0L) durationUs / SCRUB_SLIDER_PIXELS else 0L

/**
 * Whether decoding has caught up to [targetUs]: the frame at [framePtsUs] is
 * no more than [toleranceUs] behind it. A codec outputs frames in
 * presentation order, so the first frame that passes this is the one to
 * show; a frame *past* the target passes too (e.g. a target before the
 * clip's first frame).
 */
fun hasReachedTarget(framePtsUs: Long, targetUs: Long, toleranceUs: Long): Boolean =
    framePtsUs + toleranceUs >= targetUs
