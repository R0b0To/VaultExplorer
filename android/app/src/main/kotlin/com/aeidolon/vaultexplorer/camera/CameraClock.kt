package com.aeidolon.vaultexplorer.camera

import kotlin.math.abs

/** Which system clock a camera's frame timestamps are on. */
enum class CameraClock { BOOTTIME, MONOTONIC, UNKNOWN }

/**
 * Lines the audio timeline up with the camera's.
 *
 * Camera2 stamps frames in either `CLOCK_BOOTTIME` (SENSOR_INFO_TIMESTAMP_SOURCE
 * = REALTIME) or `CLOCK_MONOTONIC` (UNKNOWN), and the two differ by however long
 * the device has spent suspended. Audio is timestamped on the boot clock, so to
 * share a timeline with video it has to be shifted when the camera is on the
 * other one -- otherwise audio and video would be offset by the time the phone
 * slept. Rather than plumb the camera's characteristics down here, the clock is
 * inferred from the first video frame: it was captured a moment ago, so its
 * timestamp is close to "now" on the clock it is on and far from the other.
 *
 * Pure arithmetic, no Android types, so it is covered by plain JVM tests.
 */
object CameraClockMath {
    /** A frame older than this on both clocks is not on either of them. */
    const val MAX_SKEW_US = 5_000_000L

    /** Used only when the clock cannot be inferred: how long a frame spends in the pipeline. */
    const val ASSUMED_PIPELINE_LAG_US = 100_000L

    /**
     * Picks the clock whose current reading is closer to [videoPtsUs], the
     * timestamp of a frame captured just now. [nowBootUs] and [nowMonoUs] must be
     * read at (nearly) the same moment.
     */
    fun detect(videoPtsUs: Long, nowBootUs: Long, nowMonoUs: Long): CameraClock {
        val bootDistance = abs(nowBootUs - videoPtsUs)
        val monoDistance = abs(nowMonoUs - videoPtsUs)
        return when {
            minOf(bootDistance, monoDistance) > MAX_SKEW_US -> CameraClock.UNKNOWN
            bootDistance <= monoDistance -> CameraClock.BOOTTIME
            else -> CameraClock.MONOTONIC
        }
    }

    /**
     * Microseconds to subtract from a boot-clock timestamp (an audio one) to
     * express it on the camera's clock.
     */
    fun bootToCameraOffsetUs(
        clock: CameraClock,
        videoPtsUs: Long,
        nowBootUs: Long,
        nowMonoUs: Long,
    ): Long = when (clock) {
        CameraClock.BOOTTIME -> 0L
        CameraClock.MONOTONIC -> nowBootUs - nowMonoUs
        // Best guess: the frame was captured a little before it reached us.
        CameraClock.UNKNOWN -> (nowBootUs - ASSUMED_PIPELINE_LAG_US) - videoPtsUs
    }

    /**
     * How long ago the camera captured a frame stamped [ptsUs], or 0 when that
     * cannot be told. Never negative.
     */
    fun lagUs(clock: CameraClock, ptsUs: Long, nowBootUs: Long, nowMonoUs: Long): Long = when (clock) {
        CameraClock.BOOTTIME -> (nowBootUs - ptsUs).coerceAtLeast(0L)
        CameraClock.MONOTONIC -> (nowMonoUs - ptsUs).coerceAtLeast(0L)
        CameraClock.UNKNOWN -> 0L
    }
}
