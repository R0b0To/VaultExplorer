package com.aeidolon.vaultexplorer.container

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * VideoThumbnailCoordinator.calculateInSampleSize and isCodecResourceError
 * were already public (no visibility change needed) -- container/ as a
 * whole just had no coverage beyond SafThumbnailCacheTest. These are plain
 * JVM tests: calculateInSampleSize is pure int math, and
 * isCodecResourceError's message-based branches don't need a real
 * MediaCodec. Its `e is MediaCodec.CodecException` branch is NOT covered
 * here -- that class has no public constructor available to app/test code,
 * so it can only be exercised with a real decoder failure, not synthesized.
 */
class VideoThumbnailCoordinatorTest {

    // --- calculateInSampleSize ---

    @Test
    fun `image already within target bounds is not downsampled`() {
        assertEquals(1, VideoThumbnailCoordinator.calculateInSampleSize(100, 100, 100, 100))
        assertEquals(1, VideoThumbnailCoordinator.calculateInSampleSize(50, 50, 100, 100))
    }

    @Test
    fun `oversized square image is downsampled by the smallest safe power of two`() {
        // At inSampleSize=8, 1000/8=125 still >= the 100 target; 16 would
        // drop it to 62, below target -- 8 is the largest (most aggressive)
        // factor that still satisfies the "at least reqWidth x reqHeight" contract.
        assertEquals(8, VideoThumbnailCoordinator.calculateInSampleSize(1000, 1000, 100, 100))
        assertEquals(2, VideoThumbnailCoordinator.calculateInSampleSize(200, 200, 100, 100))
    }

    @Test
    fun `non-square image is bound by whichever dimension is more constraining`() {
        // 2000x1000 against a 500x500 target: halving by 2 gives 1000x500,
        // both still >= 500; halving again would drop height to 250.
        assertEquals(2, VideoThumbnailCoordinator.calculateInSampleSize(2000, 1000, 500, 500))
    }

    @Test
    fun `zero-size input does not crash and returns no downsampling`() {
        assertEquals(1, VideoThumbnailCoordinator.calculateInSampleSize(0, 0, 100, 100))
    }

    @Test
    fun `square-target overload matches calling the four-arg form with equal width and height`() {
        assertEquals(
            VideoThumbnailCoordinator.calculateInSampleSize(1000, 1000, 100, 100),
            VideoThumbnailCoordinator.calculateInSampleSize(1000, 1000, 100),
        )
    }

    // --- isCodecResourceError (message-based branches only) ---

    @Test
    fun `recognizes known resource-exhaustion message fragments case-insensitively`() {
        assertTrue(VideoThumbnailCoordinator.isCodecResourceError(RuntimeException("OMX_ErrorInsufficientResources during decode")))
        assertTrue(VideoThumbnailCoordinator.isCodecResourceError(RuntimeException("out of memory: no_memory")))
        assertTrue(VideoThumbnailCoordinator.isCodecResourceError(RuntimeException("Codec allocation failed")))
        assertTrue(VideoThumbnailCoordinator.isCodecResourceError(RuntimeException("native error 0x80001000")))
    }

    @Test
    fun `unrelated exceptions are not misclassified as codec resource errors`() {
        assertFalse(VideoThumbnailCoordinator.isCodecResourceError(RuntimeException("disk is full")))
        assertFalse(VideoThumbnailCoordinator.isCodecResourceError(RuntimeException(null as String?)))
        assertFalse(VideoThumbnailCoordinator.isCodecResourceError(IllegalStateException()))
    }
}
