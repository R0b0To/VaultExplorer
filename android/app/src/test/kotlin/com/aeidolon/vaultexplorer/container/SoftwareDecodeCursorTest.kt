package com.aeidolon.vaultexplorer.container

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The decisions behind frame-accurate scrub previews: when the decoder may
 * keep going forward instead of re-seeking, and how close a frame must be
 * to the requested position. Pure logic, no MediaCodec involved.
 */
class SoftwareDecodeCursorTest {

    private fun cursorAt(ptsUs: Long) = SoftwareDecodeCursor().apply { lastOutputPtsUs = ptsUs }

    // ---- SoftwareDecodeCursor.canContinueTo ----

    @Test
    fun `a fresh cursor always seeks`() {
        assertFalse(SoftwareDecodeCursor().canContinueTo(0L))
        assertFalse(SoftwareDecodeCursor().canContinueTo(5_000_000L))
    }

    @Test
    fun `continues forward to a nearby later target`() {
        val cursor = cursorAt(2_000_000L)

        assertTrue(cursor.canContinueTo(2_040_000L))
        assertTrue(cursor.canContinueTo(2_900_000L))
    }

    @Test
    fun `a target equal to the last output can continue`() {
        assertTrue(cursorAt(2_000_000L).canContinueTo(2_000_000L))
    }

    @Test
    fun `dragging backwards seeks, since decoding only goes forward`() {
        val cursor = cursorAt(2_000_000L)

        assertFalse(cursor.canContinueTo(1_999_999L))
        assertFalse(cursor.canContinueTo(0L))
    }

    @Test
    fun `a far jump forward seeks to the target's own keyframe instead`() {
        val cursor = cursorAt(2_000_000L)

        assertTrue(cursor.canContinueTo(2_000_000L + SoftwareDecodeCursor.CONTINUE_WINDOW_US))
        assertFalse(cursor.canContinueTo(2_000_000L + SoftwareDecodeCursor.CONTINUE_WINDOW_US + 1))
    }

    @Test
    fun `after end of stream the codec must be flushed, so it seeks`() {
        val cursor = cursorAt(2_000_000L).apply { inputDone = true }

        assertFalse(cursor.canContinueTo(2_100_000L))
    }

    @Test
    fun `reset forgets the position and the end-of-stream flag`() {
        val cursor = cursorAt(2_000_000L).apply { inputDone = true }

        cursor.reset()

        assertEquals(SoftwareDecodeCursor.NONE, cursor.lastOutputPtsUs)
        assertFalse(cursor.inputDone)
        assertFalse(cursor.canContinueTo(2_100_000L))
    }

    @Test
    fun `a huge gap from a fresh cursor cannot overflow into a false continue`() {
        // NONE is Long.MIN_VALUE; subtracting it from a target would overflow
        // if the "has output" check didn't short-circuit first.
        assertFalse(SoftwareDecodeCursor().canContinueTo(Long.MAX_VALUE))
    }

    // ---- scrubToleranceUs ----

    @Test
    fun `tolerance is about one slider pixel of the video`() {
        assertEquals(5_000_000L / 360, scrubToleranceUs(5_000_000L))
        assertEquals(20_000_000L, scrubToleranceUs(7_200_000_000L)) // 2 h -> 20 s
    }

    @Test
    fun `unknown or bogus duration asks for full accuracy`() {
        assertEquals(0L, scrubToleranceUs(0L))
        assertEquals(0L, scrubToleranceUs(-1L))
    }

    // ---- hasReachedTarget ----

    @Test
    fun `a frame reaches the target once it is within tolerance behind it`() {
        assertFalse(hasReachedTarget(framePtsUs = 900_000L, targetUs = 1_000_000L, toleranceUs = 50_000L))
        assertTrue(hasReachedTarget(framePtsUs = 950_000L, targetUs = 1_000_000L, toleranceUs = 50_000L))
        assertTrue(hasReachedTarget(framePtsUs = 1_000_000L, targetUs = 1_000_000L, toleranceUs = 0L))
    }

    @Test
    fun `a frame past the target counts, e.g. a target before the first frame`() {
        assertTrue(hasReachedTarget(framePtsUs = 66_000L, targetUs = 0L, toleranceUs = 0L))
    }

    // ---- what it means for real clips ----

    @Test
    fun `a short clip refuses the bare keyframe, so it decodes on toward the target`() {
        // 5 s clip, keyframe every second: a request half a second after a
        // keyframe must not settle for that keyframe -- the old behaviour,
        // which gave a 5 s clip only ~5 distinct previews.
        val tolerance = scrubToleranceUs(5_000_000L)

        assertFalse(hasReachedTarget(framePtsUs = 1_000_000L, targetUs = 1_500_000L, toleranceUs = tolerance))
    }

    @Test
    fun `a short clip is accurate to well within one 30fps frame`() {
        val frameUs = 33_333L

        assertTrue(scrubToleranceUs(5_000_000L) < frameUs)
    }

    @Test
    fun `a feature-length film keeps the cheap keyframe-only behaviour`() {
        // The same half-second gap is far below one slider pixel of a 2 h
        // film (~20 s), so the keyframe is accepted straight away.
        val tolerance = scrubToleranceUs(7_200_000_000L)

        assertTrue(hasReachedTarget(framePtsUs = 1_000_000L, targetUs = 1_500_000L, toleranceUs = tolerance))
    }
}
