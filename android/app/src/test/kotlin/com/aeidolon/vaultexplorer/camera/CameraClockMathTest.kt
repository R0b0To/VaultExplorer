package com.aeidolon.vaultexplorer.camera

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The camera stamps frames on the boot or the monotonic clock; audio is on the
 * boot clock. [CameraClockMath] works out which, so the two can share a timeline.
 */
class CameraClockMathTest {

    // A phone that has been up 10 h but spent 4 h of that suspended.
    private val nowBoot = 10L * 3600 * 1_000_000
    private val nowMono = 6L * 3600 * 1_000_000

    @Test
    fun `a frame stamped on the boot clock is detected as boot`() {
        assertEquals(CameraClock.BOOTTIME, CameraClockMath.detect(nowBoot - 80_000, nowBoot, nowMono))
    }

    @Test
    fun `a frame stamped on the monotonic clock is detected as monotonic`() {
        assertEquals(CameraClock.MONOTONIC, CameraClockMath.detect(nowMono - 80_000, nowBoot, nowMono))
    }

    @Test
    fun `when both clocks agree it does not matter, boot wins`() {
        assertEquals(CameraClock.BOOTTIME, CameraClockMath.detect(1_000_000, 1_050_000, 1_050_000))
    }

    @Test
    fun `a frame far from both clocks is unknown`() {
        assertEquals(CameraClock.UNKNOWN, CameraClockMath.detect(123_456, nowBoot, nowMono))
    }

    @Test
    fun `audio needs no shift on the boot clock`() {
        assertEquals(0L, CameraClockMath.bootToCameraOffsetUs(CameraClock.BOOTTIME, nowBoot, nowBoot, nowMono))
    }

    @Test
    fun `audio is shifted by the time spent suspended on the monotonic clock`() {
        val off = CameraClockMath.bootToCameraOffsetUs(CameraClock.MONOTONIC, nowMono - 80_000, nowBoot, nowMono)
        assertEquals(4L * 3600 * 1_000_000, off)
        // an audio sample captured "now" on the boot clock lands on "now" on the camera's
        assertEquals(nowMono, nowBoot - off)
    }

    @Test
    fun `an unknown clock is aligned on the first frame`() {
        val firstFramePts = 777_000L
        val off = CameraClockMath.bootToCameraOffsetUs(CameraClock.UNKNOWN, firstFramePts, nowBoot, nowMono)
        // audio captured just before "now" (where that frame was captured) maps onto the frame's time
        val audioAtFrameCapture = nowBoot - CameraClockMath.ASSUMED_PIPELINE_LAG_US
        assertEquals(firstFramePts, audioAtFrameCapture - off)
    }

    @Test
    fun `lag is measured on the camera's own clock and never negative`() {
        assertEquals(80_000L, CameraClockMath.lagUs(CameraClock.BOOTTIME, nowBoot - 80_000, nowBoot, nowMono))
        assertEquals(80_000L, CameraClockMath.lagUs(CameraClock.MONOTONIC, nowMono - 80_000, nowBoot, nowMono))
        assertEquals(0L, CameraClockMath.lagUs(CameraClock.BOOTTIME, nowBoot + 5_000, nowBoot, nowMono))
        assertEquals(0L, CameraClockMath.lagUs(CameraClock.UNKNOWN, 1, nowBoot, nowMono))
    }
}
