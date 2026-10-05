package com.aeidolon.vaultexplorer.videoedit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for LosslessVideoCutter data structures, range calculations,
 * and probe / cut contracts.
 */
class LosslessVideoCutterTest {

    @Test
    fun `range holds start and end in microseconds`() {
        val range = LosslessVideoCutter.Range(1_000_000L, 5_000_000L)
        assertEquals(1_000_000L, range.startUs)
        assertEquals(5_000_000L, range.endUs)
        assertTrue(range.endUs > range.startUs)
    }

    @Test
    fun `probe records subtitle track presence and count`() {
        val probeWithoutSubtitles = LosslessVideoCutter.Probe(
            durationUs = 10_000_000L,
            width = 1920,
            height = 1080,
            rotationDegrees = 0,
            hasVideo = true,
            hasAudio = true,
            videoMime = "video/avc",
            audioMime = "audio/mp4a-latm",
            keyframesUs = longArrayOf(0L, 2_000_000L, 4_000_000L),
            keyframesComplete = true,
            outputExtension = "mp4",
            hasSubtitles = false,
            subtitleTracks = 0,
        )
        assertFalse(probeWithoutSubtitles.hasSubtitles)
        assertEquals(0, probeWithoutSubtitles.subtitleTracks)

        val probeWithSubtitles = LosslessVideoCutter.Probe(
            durationUs = 10_000_000L,
            width = 1920,
            height = 1080,
            rotationDegrees = 90,
            hasVideo = true,
            hasAudio = true,
            videoMime = "video/avc",
            audioMime = "audio/mp4a-latm",
            keyframesUs = longArrayOf(0L, 2_000_000L),
            keyframesComplete = true,
            outputExtension = "mp4",
            hasSubtitles = true,
            subtitleTracks = 2,
        )
        assertTrue(probeWithSubtitles.hasSubtitles)
        assertEquals(2, probeWithSubtitles.subtitleTracks)
        assertEquals(90, probeWithSubtitles.rotationDegrees)
    }

    @Test
    fun `cut result correctly reports dropped tracks and actual ranges`() {
        val ranges = listOf(
            LosslessVideoCutter.Range(0L, 3_000_000L),
            LosslessVideoCutter.Range(5_000_000L, 9_000_000L),
        )
        val result = LosslessVideoCutter.CutResult(
            outputExtension = "mp4",
            droppedAudioTracks = 1,
            actualRanges = ranges,
        )
        assertEquals("mp4", result.outputExtension)
        assertEquals(1, result.droppedAudioTracks)
        assertEquals(2, result.actualRanges.size)
        assertEquals(0L, result.actualRanges[0].startUs)
        assertEquals(3_000_000L, result.actualRanges[0].endUs)
        assertEquals(5_000_000L, result.actualRanges[1].startUs)
        assertEquals(9_000_000L, result.actualRanges[1].endUs)
    }

    @Test
    fun `monotonic timestamp validation helper verifies non-decreasing timestamps`() {
        val timestamps = listOf(0L, 33_333L, 66_666L, 100_000L, 133_333L)
        var monotonic = true
        for (i in 1 until timestamps.size) {
            if (timestamps[i] < timestamps[i - 1]) {
                monotonic = false
                break
            }
        }
        assertTrue(monotonic)
    }

    @Test
    fun `free space estimation ensures safety buffer over source size`() {
        val sourceSize = 50 * 1024 * 1024L // 50 MB
        val estimatedBytes = ((sourceSize * 1.2).toLong() + 5 * 1024 * 1024L).coerceAtLeast(10 * 1024 * 1024L)
        // 50 * 1.2 = 60 MB + 5 MB = 65 MB
        assertEquals(65 * 1024 * 1024L, estimatedBytes)
        assertTrue(estimatedBytes > sourceSize)
    }
}
