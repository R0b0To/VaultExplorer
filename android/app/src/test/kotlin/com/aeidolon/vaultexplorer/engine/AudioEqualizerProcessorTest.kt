package com.aeidolon.vaultexplorer.engine

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.roundToInt
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Drives [AudioEqualizerProcessor] the way DefaultAudioSink does (configure ->
 * flush -> queueInput -> getOutput) and checks what comes out. Robolectric is
 * only here because Media3's `Util` (used by AudioFormat) touches android.os.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class AudioEqualizerProcessorTest {

    private val fs = 48_000

    private fun format(channels: Int = 2, encoding: Int = C.ENCODING_PCM_16BIT) =
        AudioProcessor.AudioFormat(fs, channels, encoding)

    private fun settings(
        gains: FloatArray = FloatArray(EqualizerDsp.BAND_COUNT),
        preamp: Float = 0f,
        enabled: Boolean = true,
        preventClipping: Boolean = false,
    ) = EqualizerSettings(enabled, preamp, gains, preventClipping)

    private fun gainsWith(band: Int, db: Float) =
        FloatArray(EqualizerDsp.BAND_COUNT).also { it[band] = db }

    private fun newProcessor(s: EqualizerSettings, channels: Int = 2): AudioEqualizerProcessor {
        val p = AudioEqualizerProcessor()
        p.update(s)
        p.configure(format(channels))
        p.flush(AudioProcessor.StreamMetadata.DEFAULT)
        return p
    }

    private fun toBuffer(samples: ShortArray): ByteBuffer {
        val b = ByteBuffer.allocateDirect(samples.size * 2).order(ByteOrder.nativeOrder())
        for (s in samples) b.putShort(s)
        b.flip()
        return b
    }

    private fun process(p: AudioEqualizerProcessor, samples: ShortArray): ShortArray {
        val input = toBuffer(samples)
        p.queueInput(input)
        assertEquals("input fully consumed", 0, input.remaining())
        val out = p.getOutput()
        val result = ShortArray(out.remaining() / 2)
        for (i in result.indices) result[i] = out.getShort()
        return result
    }

    private fun sine(freqHz: Double, frames: Int, channels: Int, amp: Double, startFrame: Int = 0): ShortArray {
        val out = ShortArray(frames * channels)
        for (i in 0 until frames) {
            val v = (amp * 32767.0 * sin(2.0 * PI * freqHz * (startFrame + i) / fs)).roundToInt().toShort()
            for (c in 0 until channels) out[i * channels + c] = v
        }
        return out
    }

    /** RMS of channel 0 over the second half (past the filter's transient), in dB. */
    private fun settledRmsDb(samples: ShortArray, channels: Int): Double {
        val frames = samples.size / channels
        var sum = 0.0
        var n = 0
        for (i in frames / 2 until frames) {
            val v = samples[i * channels] / 32768.0
            sum += v * v
            n++
        }
        return 10.0 * log10(sum / n)
    }

    private fun gainDb(p: AudioEqualizerProcessor, freqHz: Double, amp: Double = 0.1): Double {
        val input = sine(freqHz, fs, 2, amp)
        return settledRmsDb(process(p, input), 2) - settledRmsDb(input, 2)
    }

    // -- format handling --------------------------------------------------------

    @Test
    fun staysActiveForPcm16WhetherOrNotTheEqualizerIsOn() {
        val p = AudioEqualizerProcessor()
        val out = p.configure(format())
        assertTrue(p.isActive)
        assertEquals(format(), out)
    }

    @Test
    fun staysOutOfTheWayOfOtherEncodings() {
        for (enc in listOf(C.ENCODING_PCM_FLOAT, C.ENCODING_PCM_24BIT, C.ENCODING_PCM_8BIT)) {
            val p = AudioEqualizerProcessor()
            assertEquals(AudioProcessor.AudioFormat.NOT_SET, p.configure(format(encoding = enc)))
            assertFalse(p.isActive)
        }
    }

    @Test
    fun ignoresStreamsWithMoreChannelsThanItCanHandle() {
        val p = AudioEqualizerProcessor()
        assertEquals(AudioProcessor.AudioFormat.NOT_SET, p.configure(format(channels = 9)))
    }

    // -- pass-through ---------------------------------------------------------

    @Test
    fun disabledEqualizerPassesAudioThroughBitExact() {
        val p = newProcessor(EqualizerSettings.DISABLED)
        val input = ShortArray(4000) { ((it * 7919) % 65536 - 32768).toShort() }
        assertTrue(input.contentEquals(process(p, input)))
    }

    @Test
    fun flatEnabledEqualizerIsAlsoBitExact() {
        val p = newProcessor(settings())
        val input = ShortArray(4000) { ((it * 104_729) % 65536 - 32768).toShort() }
        assertTrue(input.contentEquals(process(p, input)))
    }

    @Test
    fun aTrailingPartialFrameIsConsumedAndDropped() {
        val p = newProcessor(EqualizerSettings.DISABLED)
        val b = ByteBuffer.allocateDirect(9).order(ByteOrder.nativeOrder()) // 2 stereo frames + 1 byte
        b.limit(9)
        p.queueInput(b)
        assertEquals(0, b.remaining())
        assertEquals(8, p.getOutput().remaining())
    }

    // -- filtering --------------------------------------------------------------

    @Test
    fun boostRaisesTheLevelAtTheBandCentre() {
        val p = newProcessor(settings(gainsWith(5, 12f)))
        assertEquals(12.0, gainDb(p, 1000.0), 0.4)
    }

    @Test
    fun cutLowersTheLevelAtTheBandCentre() {
        val p = newProcessor(settings(gainsWith(5, -12f)))
        assertEquals(-12.0, gainDb(p, 1000.0), 0.4)
    }

    @Test
    fun preampAppliesABroadbandGain() {
        val p = newProcessor(settings(preamp = -6f))
        assertEquals(-6.0, gainDb(p, 440.0), 0.1)
    }

    @Test
    fun preventClippingCancelsTheLoudestBoost() {
        val p = newProcessor(settings(gainsWith(5, 12f), preventClipping = true))
        assertEquals(0.0, gainDb(p, 1000.0), 0.4)
    }

    @Test
    fun preventClippingKeepsAFullScaleBoostedToneFromClipping() {
        val p = newProcessor(settings(gainsWith(5, 12f), preventClipping = true))
        val out = process(p, sine(1000.0, fs / 2, 2, 0.8))
        assertTrue(out.all { it > Short.MIN_VALUE && it < Short.MAX_VALUE })
    }

    @Test
    fun withoutPreventClippingOverloadIsHardClippedNotWrapped() {
        val p = newProcessor(settings(gainsWith(5, 12f), preventClipping = false))
        val out = process(p, sine(1000.0, fs / 2, 2, 0.98))
        assertTrue(out.any { it == Short.MAX_VALUE })
        assertTrue(out.any { it == Short.MIN_VALUE })
    }

    @Test
    fun channelsAreProcessedIndependently() {
        val p = newProcessor(settings(gainsWith(5, 12f)))
        val frames = fs / 4
        val input = ShortArray(frames * 2)
        val tone = sine(1000.0, frames, 1, 0.2)
        for (i in 0 until frames) input[i * 2] = tone[i] // left only
        val out = process(p, input)
        for (i in 0 until frames) assertEquals(0, out[i * 2 + 1].toInt())
        assertTrue(out.indices.any { it % 2 == 0 && out[it] != 0.toShort() })
    }

    @Test
    fun surroundLayoutsKeepTheirChannelCount() {
        val p = newProcessor(settings(gainsWith(3, 6f)), channels = 6)
        val input = sine(250.0, 4800, 6, 0.1)
        assertEquals(input.size, process(p, input).size)
    }

    @Test
    fun outputDoesNotDependOnHowTheStreamIsChunked() {
        val s = settings(gainsWith(4, 8f).also { it[7] = -5f }, preamp = -1f, preventClipping = true)
        val input = sine(700.0, 20_000, 2, 0.3)

        val whole = process(newProcessor(s), input)

        val chunked = newProcessor(s)
        val pieces = ArrayList<Short>()
        var pos = 0
        for (sizeFrames in listOf(1, 3, 997, 4096, 11, 9000, 5892)) {
            val end = minOf(pos + sizeFrames * 2, input.size)
            pieces.addAll(process(chunked, input.copyOfRange(pos, end)).toList())
            pos = end
        }
        assertEquals(input.size, pos)
        assertTrue(whole.contentEquals(pieces.toShortArray()))
    }

    // -- switching on/off while playing --------------------------------------------

    @Test
    fun enablingMidStreamFadesInInsteadOfJumping() {
        val p = newProcessor(EqualizerSettings.DISABLED)
        val frames = 4800
        process(p, sine(1000.0, frames, 2, 0.3)) // equalizer off: untouched

        p.update(settings(gainsWith(5, 12f)))
        // Resume a quarter period in, so the very first sample sits at the
        // tone's peak -- a hard switch to the filtered signal would show up
        // as a ~7% step right there.
        val next = sine(1000.0, frames, 2, 0.3, startFrame = frames + 12)
        val out = process(p, next)

        // The first output samples must still be (nearly) the dry signal ...
        assertTrue("first sample jumped: ${out[0]} vs ${next[0]}", abs(next[0].toInt() - out[0].toInt()) <= 60)
        // ... and by the end of the buffer the boost is fully applied.
        val tail = out.copyOfRange(out.size - 480 * 2, out.size)
        val tailIn = next.copyOfRange(next.size - 480 * 2, next.size)
        assertTrue(peak(tail) > 2 * peak(tailIn))
    }

    @Test
    fun disablingMidStreamFadesBackToTheOriginal() {
        val p = newProcessor(settings(gainsWith(5, 12f)))
        process(p, sine(1000.0, 24_000, 2, 0.2)) // settle with the boost on
        p.update(EqualizerSettings.DISABLED)
        process(p, sine(1000.0, 4800, 2, 0.2, startFrame = 24_000)) // the fade-out buffer
        val input = sine(1000.0, 4800, 2, 0.2, startFrame = 28_800)
        assertTrue(input.contentEquals(process(p, input))) // now bit-exact again
    }

    @Test
    fun reEnablingAfterBypassStartsFromSilentFilters() {
        val s = settings(gainsWith(3, 12f))
        val p = newProcessor(s)
        process(p, sine(250.0, 24_000, 2, 0.5)) // the filters now hold loud state
        p.update(EqualizerSettings.DISABLED)
        process(p, sine(250.0, 4800, 2, 0.5, startFrame = 24_000)) // fade-out
        process(p, sine(250.0, 4800, 2, 0.5, startFrame = 28_800)) // bypass
        p.update(s)
        // Silence in must give silence out; stale filter memory would ring.
        assertTrue(process(p, ShortArray(2 * 4800)).all { it == 0.toShort() })
    }

    @Test
    fun flushRestartsFromSilenceWithTheCurrentSettings() {
        val p = newProcessor(settings(gainsWith(5, 12f)))
        process(p, sine(1000.0, 24_000, 2, 0.3))
        p.flush(AudioProcessor.StreamMetadata.DEFAULT) // seek
        assertTrue(process(p, ShortArray(2 * 480)).all { it == 0.toShort() }) // no leftover ringing
        val input = sine(1000.0, fs, 2, 0.1)
        val out = process(p, input)
        assertEquals(12.0, settledRmsDb(out, 2) - settledRmsDb(input, 2), 0.4)
    }

    private fun peak(samples: ShortArray): Int = samples.maxOf { abs(it.toInt()) }
}
