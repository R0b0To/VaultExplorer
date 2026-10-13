package com.aeidolon.vaultexplorer.engine

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * Immutable snapshot of the user's equalizer configuration, as pushed from
 * Dart (see `AudioEqualizerSettings.toChannelMap()`).
 *
 * Instances are cheap and never mutated: the audio thread compares them by
 * reference, so every settings change is simply a new object handed to
 * [AudioEqualizerProcessor.update].
 *
 * @property enabled master switch; when false the audio is passed through
 *   untouched regardless of the other fields.
 * @property preampDb broadband gain applied before the bands, in dB.
 * @property bandGainsDb gain of each of the [EqualizerDsp.BAND_COUNT] bands, in
 *   dB (see [EqualizerDsp.BAND_FREQUENCIES_HZ]). Normalised on construction:
 *   padded/truncated to the band count, NaN -> 0, clamped to +-[EqualizerDsp.MAX_GAIN_DB].
 * @property preventClipping when true the processor lowers the overall level by
 *   exactly as much as the combined filter response boosts its loudest
 *   frequency, so boosting a band can't push peaks past full scale.
 */
class EqualizerSettings(
    val enabled: Boolean,
    preampDb: Float,
    bandGainsDb: FloatArray,
    val preventClipping: Boolean,
) {
    val preampDb: Float = sanitize(preampDb)
    val bandGainsDb: FloatArray = FloatArray(EqualizerDsp.BAND_COUNT) { i ->
        if (i < bandGainsDb.size) sanitize(bandGainsDb[i]) else 0f
    }

    /** True when processing would be an exact no-op (so it can be skipped). */
    val isBypass: Boolean
        get() = !enabled ||
            (abs(preampDb) < EqualizerDsp.NEGLIGIBLE_GAIN_DB &&
                bandGainsDb.all { abs(it) < EqualizerDsp.NEGLIGIBLE_GAIN_DB })

    companion object {
        val DISABLED = EqualizerSettings(
            enabled = false,
            preampDb = 0f,
            bandGainsDb = FloatArray(EqualizerDsp.BAND_COUNT),
            preventClipping = true,
        )

        private fun sanitize(v: Float): Float =
            if (v.isNaN()) 0f else v.coerceIn(-EqualizerDsp.MAX_GAIN_DB, EqualizerDsp.MAX_GAIN_DB)

        /** Parses the map sent over the platform channel; null/garbage -> [DISABLED]. */
        fun fromMap(map: Map<*, *>?): EqualizerSettings {
            if (map == null) return DISABLED
            val gains = (map["bandGainsDb"] as? List<*>)
                ?.map { (it as? Number)?.toFloat() ?: 0f }
                ?.toFloatArray()
                ?: FloatArray(EqualizerDsp.BAND_COUNT)
            return EqualizerSettings(
                enabled = map["enabled"] as? Boolean ?: false,
                preampDb = (map["preampDb"] as? Number)?.toFloat() ?: 0f,
                bandGainsDb = gains,
                preventClipping = map["preventClipping"] as? Boolean ?: true,
            )
        }
    }
}

/**
 * Filter design for the 10-band graphic equalizer.
 *
 * Every band is an RBJ "Audio EQ Cookbook" peaking filter with a fixed Q of
 * sqrt(2) (one octave wide), centred on the ISO octave frequencies. A band's
 * gain at its own centre frequency equals its slider value (neighbours add a
 * little where their skirts overlap, as on any graphic EQ).
 */
object EqualizerDsp {
    const val BAND_COUNT = 10
    const val MAX_GAIN_DB = 12f

    /** Gains below this are treated as 0 dB (the band's filter is skipped). */
    const val NEGLIGIBLE_GAIN_DB = 0.05f

    /** Mirrors `kEqualizerBandFrequenciesHz` in audio_equalizer_settings.dart. */
    val BAND_FREQUENCIES_HZ = doubleArrayOf(
        31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0,
    )

    const val BAND_Q = 1.4142135623730951

    /** A band whose centre would sit above this fraction of fs is left out. */
    private const val MAX_CENTER_FRACTION_OF_FS = 0.45

    /** Doubles per band in a coefficient array: b0, b1, b2, a1, a2 (a0 == 1). */
    const val COEFFS_PER_BAND = 5

    fun isBandUsable(sampleRate: Int, band: Int): Boolean =
        sampleRate > 0 && BAND_FREQUENCIES_HZ[band] < MAX_CENTER_FRACTION_OF_FS * sampleRate

    /**
     * RBJ peaking-EQ biquad, normalised so a0 == 1. Returns
     * `[b0, b1, b2, a1, a2]`.
     */
    fun peaking(sampleRate: Int, centerHz: Double, gainDb: Double, q: Double = BAND_Q): DoubleArray {
        val a = 10.0.pow(gainDb / 40.0)
        val w0 = 2.0 * PI * centerHz / sampleRate
        val cosW0 = cos(w0)
        val alpha = sin(w0) / (2.0 * q)
        val a0 = 1.0 + alpha / a
        return doubleArrayOf(
            (1.0 + alpha * a) / a0,
            (-2.0 * cosW0) / a0,
            (1.0 - alpha * a) / a0,
            (-2.0 * cosW0) / a0,
            (1.0 - alpha / a) / a0,
        )
    }

    /** Magnitude (dB) of one normalised biquad at [freqHz]. */
    fun magnitudeDb(c: DoubleArray, offset: Int, sampleRate: Int, freqHz: Double): Double {
        val w = 2.0 * PI * freqHz / sampleRate
        val cw = cos(w)
        val sw = sin(w)
        val c2w = cos(2.0 * w)
        val s2w = sin(2.0 * w)
        val b0 = c[offset]
        val b1 = c[offset + 1]
        val b2 = c[offset + 2]
        val a1 = c[offset + 3]
        val a2 = c[offset + 4]
        // H(e^jw) = (b0 + b1 e^-jw + b2 e^-2jw) / (1 + a1 e^-jw + a2 e^-2jw)
        val numRe = b0 + b1 * cw + b2 * c2w
        val numIm = -(b1 * sw + b2 * s2w)
        val denRe = 1.0 + a1 * cw + a2 * c2w
        val denIm = -(a1 * sw + a2 * s2w)
        val num = numRe * numRe + numIm * numIm
        val den = denRe * denRe + denIm * denIm
        return 10.0 * log10(num / den)
    }
}

/**
 * The cascade of band filters for one stream (fixed channel count and sample
 * rate). Not thread-safe: owned and driven by the audio thread.
 *
 * Direct Form II Transposed in double precision -- the 31 Hz band at 48 kHz has
 * poles very close to the unit circle, where single-precision state would be
 * audibly noisy.
 */
class EqualizerFilterBank(val channelCount: Int, val sampleRate: Int) {
    private val coeffs = DoubleArray(EqualizerDsp.BAND_COUNT * EqualizerDsp.COEFFS_PER_BAND)
    private val active = BooleanArray(EqualizerDsp.BAND_COUNT)
    private val activeIndex = IntArray(EqualizerDsp.BAND_COUNT)
    private var activeCount = 0
    private val z1 = DoubleArray(channelCount * EqualizerDsp.BAND_COUNT)
    private val z2 = DoubleArray(channelCount * EqualizerDsp.BAND_COUNT)

    /**
     * Re-designs the bands for [gainsDb]. Filter state is kept so the change
     * is click-free, except for a band that was previously skipped: its state
     * is stale, so it starts from silence.
     */
    fun setGains(gainsDb: FloatArray) {
        activeCount = 0
        for (b in 0 until EqualizerDsp.BAND_COUNT) {
            val g = if (b < gainsDb.size) gainsDb[b].toDouble() else 0.0
            val usable = EqualizerDsp.isBandUsable(sampleRate, b) &&
                abs(g) >= EqualizerDsp.NEGLIGIBLE_GAIN_DB
            if (usable) {
                val c = EqualizerDsp.peaking(sampleRate, EqualizerDsp.BAND_FREQUENCIES_HZ[b], g)
                System.arraycopy(c, 0, coeffs, b * EqualizerDsp.COEFFS_PER_BAND, EqualizerDsp.COEFFS_PER_BAND)
                if (!active[b]) clearBandState(b)
                activeIndex[activeCount++] = b
            }
            active[b] = usable
        }
    }

    /**
     * How far (dB) the combined response of the current bands rises above
     * 0 dB at its loudest frequency; 0 if it never does. Used for the
     * clipping-prevention headroom.
     */
    fun peakBoostDb(): Double {
        if (activeCount == 0) return 0.0
        val top = min(20000.0, 0.45 * sampleRate)
        val lo = 20.0
        if (top <= lo) return 0.0
        val points = 192
        val ratio = (top / lo).pow(1.0 / (points - 1))
        var f = lo
        var peak = 0.0
        for (i in 0 until points) {
            var sum = 0.0
            for (k in 0 until activeCount) {
                sum += EqualizerDsp.magnitudeDb(
                    coeffs,
                    activeIndex[k] * EqualizerDsp.COEFFS_PER_BAND,
                    sampleRate,
                    f,
                )
            }
            peak = max(peak, sum)
            f *= ratio
        }
        return peak
    }

    /** True when no band is doing anything (every gain ~0 dB or unusable). */
    val isFlat: Boolean get() = activeCount == 0

    fun reset() {
        z1.fill(0.0)
        z2.fill(0.0)
    }

    /** Runs one sample of [channel] through every active band. */
    fun process(channel: Int, input: Double): Double {
        var x = input
        val base = channel * EqualizerDsp.BAND_COUNT
        for (k in 0 until activeCount) {
            val b = activeIndex[k]
            val o = b * EqualizerDsp.COEFFS_PER_BAND
            val s = base + b
            val y = coeffs[o] * x + z1[s]
            z1[s] = coeffs[o + 1] * x - coeffs[o + 3] * y + z2[s]
            z2[s] = coeffs[o + 2] * x - coeffs[o + 4] * y
            x = y
        }
        return x
    }

    /**
     * Snaps vanishingly small filter state to zero. Call once per buffer: a
     * decaying tail fed with digital silence otherwise ends up in the
     * denormal range, which is very slow on some CPUs.
     */
    fun flushDenormals() {
        for (i in z1.indices) {
            if (abs(z1[i]) < DENORMAL_FLOOR) z1[i] = 0.0
            if (abs(z2[i]) < DENORMAL_FLOOR) z2[i] = 0.0
        }
    }

    private fun clearBandState(band: Int) {
        for (ch in 0 until channelCount) {
            val s = ch * EqualizerDsp.BAND_COUNT + band
            z1[s] = 0.0
            z2[s] = 0.0
        }
    }

    private companion object {
        const val DENORMAL_FLOOR = 1e-18
    }
}

/** dB -> linear amplitude. */
internal fun dbToLinear(db: Double): Double = 10.0.pow(db / 20.0)
