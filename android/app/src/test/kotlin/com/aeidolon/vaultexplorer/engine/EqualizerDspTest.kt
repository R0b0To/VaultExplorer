package com.aeidolon.vaultexplorer.engine

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-math tests for the 10-band equalizer (no Android / Media3 involved):
 * filter design, the filter bank's measured frequency response, headroom
 * detection and the settings payload parsing.
 */
class EqualizerDspTest {

    private val fs = 48_000

    /** Steady-state gain in dB of [bank] for a [freqHz] sine on channel 0. */
    private fun measuredGainDb(bank: EqualizerFilterBank, freqHz: Double, preGainDb: Double = 0.0): Double {
        val amp = 0.1
        val seconds = 1.0
        val n = (fs * seconds).toInt()
        val settle = n / 2
        val g = dbToLinear(preGainDb)
        var inSq = 0.0
        var outSq = 0.0
        for (i in 0 until n) {
            val x = amp * sin(2.0 * PI * freqHz * i / fs)
            val y = bank.process(0, x * g)
            if (i >= settle) {
                inSq += x * x
                outSq += y * y
            }
        }
        return 10.0 * log10(outSq / inSq)
    }

    private fun gainsWith(band: Int, db: Float) =
        FloatArray(EqualizerDsp.BAND_COUNT).also { it[band] = db }

    // -- filter design ------------------------------------------------------

    @Test
    fun peakingFilterHasTheRequestedGainAtItsCentreFrequency() {
        for (gain in listOf(-12.0, -6.0, 3.0, 6.0, 12.0)) {
            val c = EqualizerDsp.peaking(fs, 1000.0, gain)
            val db = EqualizerDsp.magnitudeDb(c, 0, fs, 1000.0)
            assertEquals("gain $gain", gain, db, 0.01)
        }
    }

    @Test
    fun peakingFilterLeavesDistantFrequenciesAlone() {
        val c = EqualizerDsp.peaking(fs, 1000.0, 12.0)
        assertEquals(0.0, EqualizerDsp.magnitudeDb(c, 0, fs, 31.25), 0.3)
        assertEquals(0.0, EqualizerDsp.magnitudeDb(c, 0, fs, 16_000.0), 0.5)
    }

    @Test
    fun zeroGainPeakingFilterIsTransparent() {
        val c = EqualizerDsp.peaking(fs, 250.0, 0.0)
        for (f in listOf(40.0, 250.0, 3000.0, 15_000.0)) {
            assertEquals(0.0, EqualizerDsp.magnitudeDb(c, 0, fs, f), 1e-9)
        }
    }

    @Test
    fun bandsTooCloseToNyquistAreNotUsable() {
        // 16 kHz is above 0.45 * 32 kHz = 14.4 kHz, but fine at 44.1 kHz.
        assertFalse(EqualizerDsp.isBandUsable(32_000, 9))
        assertTrue(EqualizerDsp.isBandUsable(44_100, 9))
        // 8 kHz sample rate: only bands below 3.6 kHz survive (up to 2 kHz).
        assertTrue(EqualizerDsp.isBandUsable(8_000, 6))
        assertFalse(EqualizerDsp.isBandUsable(8_000, 7))
        assertFalse(EqualizerDsp.isBandUsable(0, 0))
    }

    // -- filter bank --------------------------------------------------------

    @Test
    fun flatBankIsAnExactNoOp() {
        val bank = EqualizerFilterBank(1, fs)
        bank.setGains(FloatArray(EqualizerDsp.BAND_COUNT))
        assertTrue(bank.isFlat)
        assertEquals(0.0, bank.peakBoostDb(), 0.0)
        assertEquals(0.123456, bank.process(0, 0.123456), 0.0)
    }

    @Test
    fun measuredGainMatchesTheDesignedGainAtTheBandCentre() {
        val bank = EqualizerFilterBank(1, fs)
        bank.setGains(gainsWith(5, 9f)) // 1 kHz
        assertEquals(9.0, measuredGainDb(bank, 1000.0), 0.2)
    }

    @Test
    fun aBandBarelyAffectsFarAwayFrequencies() {
        val bank = EqualizerFilterBank(1, fs)
        bank.setGains(gainsWith(5, 12f)) // 1 kHz
        assertEquals(0.0, measuredGainDb(bank, 62.5), 0.3)
    }

    @Test
    fun cutsAttenuate() {
        val bank = EqualizerFilterBank(1, fs)
        bank.setGains(gainsWith(2, -10f)) // 125 Hz
        assertEquals(-10.0, measuredGainDb(bank, 125.0), 0.2)
    }

    @Test
    fun lowestBandStaysAccurateAtAHighSampleRate() {
        // 31 Hz at 96 kHz has poles extremely close to the unit circle -- the
        // case that needs double precision state.
        val hi = 96_000
        val bank = EqualizerFilterBank(1, hi)
        bank.setGains(gainsWith(0, 12f))
        val amp = 0.05
        val n = hi * 4
        var inSq = 0.0
        var outSq = 0.0
        for (i in 0 until n) {
            val x = amp * sin(2.0 * PI * 31.25 * i / hi)
            val y = bank.process(0, x)
            if (i >= n / 2) {
                inSq += x * x
                outSq += y * y
            }
        }
        assertEquals(12.0, 10.0 * log10(outSq / inSq), 0.3)
    }

    @Test
    fun channelsAreFilteredIndependently() {
        val bank = EqualizerFilterBank(2, fs)
        bank.setGains(gainsWith(5, 12f))
        var maxRight = 0.0
        for (i in 0 until fs / 2) {
            bank.process(0, 0.5 * sin(2.0 * PI * 1000.0 * i / fs))
            maxRight = maxOf(maxRight, abs(bank.process(1, 0.0)))
        }
        assertEquals(0.0, maxRight, 0.0)
    }

    @Test
    fun resetClearsTheFilterMemory() {
        val bank = EqualizerFilterBank(1, fs)
        bank.setGains(gainsWith(3, 12f))
        for (i in 0 until 2000) bank.process(0, sin(2.0 * PI * 250.0 * i / fs))
        bank.reset()
        assertEquals(0.0, bank.process(0, 0.0), 0.0)
    }

    // -- headroom -------------------------------------------------------------

    @Test
    fun peakBoostOfASingleBandIsItsGain() {
        val bank = EqualizerFilterBank(1, fs)
        bank.setGains(gainsWith(5, 6f))
        assertEquals(6.0, bank.peakBoostDb(), 0.15)
    }

    @Test
    fun overlappingBoostsAddUpInThePeak() {
        val bank = EqualizerFilterBank(1, fs)
        bank.setGains(FloatArray(EqualizerDsp.BAND_COUNT) { 6f })
        // Every neighbour's skirt adds to every band, so the loudest point of
        // the combined response is well above the 6 dB on the sliders.
        assertTrue(bank.peakBoostDb() > 8.0)
    }

    @Test
    fun cutsNeverNeedHeadroom() {
        val bank = EqualizerFilterBank(1, fs)
        bank.setGains(FloatArray(EqualizerDsp.BAND_COUNT) { -8f })
        assertEquals(0.0, bank.peakBoostDb(), 0.0)
    }

    // -- settings -------------------------------------------------------------

    @Test
    fun settingsAreSanitisedOnConstruction() {
        val s = EqualizerSettings(
            enabled = true,
            preampDb = 50f,
            bandGainsDb = floatArrayOf(Float.NaN, 20f, -20f, 3f),
            preventClipping = true,
        )
        assertEquals(EqualizerDsp.MAX_GAIN_DB, s.preampDb, 0f)
        assertEquals(EqualizerDsp.BAND_COUNT, s.bandGainsDb.size)
        assertEquals(0f, s.bandGainsDb[0], 0f)
        assertEquals(12f, s.bandGainsDb[1], 0f)
        assertEquals(-12f, s.bandGainsDb[2], 0f)
        assertEquals(3f, s.bandGainsDb[3], 0f)
        assertEquals(0f, s.bandGainsDb[9], 0f)
    }

    @Test
    fun extraBandValuesAreIgnored() {
        val s = EqualizerSettings(true, 0f, FloatArray(25) { 5f }, true)
        assertEquals(EqualizerDsp.BAND_COUNT, s.bandGainsDb.size)
    }

    @Test
    fun bypassWhenDisabledOrFlat() {
        assertTrue(EqualizerSettings.DISABLED.isBypass)
        assertTrue(EqualizerSettings(false, 6f, FloatArray(10) { 6f }, true).isBypass)
        assertTrue(EqualizerSettings(true, 0f, FloatArray(10), true).isBypass)
        assertFalse(EqualizerSettings(true, 3f, FloatArray(10), true).isBypass)
        assertFalse(EqualizerSettings(true, 0f, gainsWith(4, 2f), true).isBypass)
    }

    @Test
    fun fromMapParsesTheChannelPayload() {
        val s = EqualizerSettings.fromMap(
            mapOf(
                "enabled" to true,
                "preampDb" to -2.5,
                "bandGainsDb" to listOf(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0),
                "preventClipping" to false,
            ),
        )
        assertTrue(s.enabled)
        assertEquals(-2.5f, s.preampDb, 0f)
        assertEquals(6f, s.bandGainsDb[5], 0f)
        assertEquals(10f, s.bandGainsDb[9], 0f)
        assertFalse(s.preventClipping)
    }

    @Test
    fun fromMapToleratesMissingAndWrongTypedFields() {
        assertTrue(EqualizerSettings.fromMap(null).isBypass)
        val s = EqualizerSettings.fromMap(mapOf("enabled" to "yes", "bandGainsDb" to listOf("x", 2)))
        assertFalse(s.enabled)
        assertEquals(0f, s.bandGainsDb[0], 0f)
        assertEquals(2f, s.bandGainsDb[1], 0f)
        assertTrue(s.preventClipping)
    }

    @Test
    fun bandsAreOneOctaveApartAndQIsOneOctaveWide() {
        for (i in 1 until EqualizerDsp.BAND_COUNT) {
            assertEquals(2.0, EqualizerDsp.BAND_FREQUENCIES_HZ[i] / EqualizerDsp.BAND_FREQUENCIES_HZ[i - 1], 1e-9)
        }
        assertEquals(sqrt(2.0), EqualizerDsp.BAND_Q, 1e-12)
    }
}
