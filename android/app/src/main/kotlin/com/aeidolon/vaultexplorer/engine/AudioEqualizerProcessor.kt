package com.aeidolon.vaultexplorer.engine

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.Buffer
import java.nio.ByteBuffer

/**
 * Software 10-band equalizer that runs on the decoded PCM inside ExoPlayer's
 * `DefaultAudioSink`.
 *
 * Why a processor rather than `android.media.audiofx.Equalizer`: the platform
 * effect has a device-specific band layout (often 5 bands, sometimes absent or
 * ignored by OEM audio stacks), so the same preset sounds different -- or does
 * nothing -- from phone to phone. This one is identical everywhere, works for
 * every decoder (MediaCodec and FFmpeg alike, since both feed the same sink)
 * and costs a few multiply-adds per sample.
 *
 * Behaviour notes:
 *  - Stays *active* for every 16-bit PCM stream even while the equalizer is
 *    off, so toggling it never forces the sink to rebuild its audio pipeline;
 *    when off (or flat) the input is copied through unchanged.
 *  - Turning it on/off, and preamp changes, are cross-faded over one buffer
 *    (a few tens of ms) so they don't click.
 *  - [update] may be called from any thread; everything else runs on the
 *    playback thread.
 *  - `DefaultAudioSink` only runs custom processors on its 16-bit path (it
 *    converts 24/32-bit/float input to 16-bit first), which is why float
 *    output is kept off in [NativePlayerManager]'s sink and why other
 *    encodings are left inactive here.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class AudioEqualizerProcessor : BaseAudioProcessor() {

    @Volatile
    private var settings: EqualizerSettings = EqualizerSettings.DISABLED

    // Everything below is touched only from the playback thread.
    private var appliedSettings: EqualizerSettings? = null
    private var bank: EqualizerFilterBank? = null
    private var gain = 1.0
    private var targetGain = 1.0
    private var wet = 0.0
    private var targetWet = 0.0

    /** Hands the processor a new configuration; effective from the next buffer. */
    fun update(newSettings: EqualizerSettings) {
        settings = newSettings
    }

    override fun onConfigure(
        inputAudioFormat: AudioProcessor.AudioFormat,
    ): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT ||
            inputAudioFormat.channelCount !in 1..MAX_CHANNELS ||
            inputAudioFormat.sampleRate <= 0
        ) {
            return AudioProcessor.AudioFormat.NOT_SET
        }
        return inputAudioFormat
    }

    override fun onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        // New stream or a seek: start the filters from silence and jump
        // straight to the current settings rather than ramping from stale ones.
        bank = EqualizerFilterBank(inputAudioFormat.channelCount, inputAudioFormat.sampleRate)
        appliedSettings = null
        refreshSettings(snapToTarget = true)
    }

    override fun onReset() {
        bank = null
        appliedSettings = null
        gain = 1.0
        targetGain = 1.0
        wet = 0.0
        targetWet = 0.0
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val format = inputAudioFormat
        val bytesPerFrame = format.bytesPerFrame
        val remaining = inputBuffer.remaining()
        val frames = remaining / bytesPerFrame
        if (frames == 0) {
            // Less than one whole frame can't be processed; consume it so the
            // caller doesn't wait on bytes that will never be taken.
            inputBuffer.moveTo(inputBuffer.limit())
            return
        }

        var filters = bank
        if (filters == null ||
            filters.channelCount != format.channelCount ||
            filters.sampleRate != format.sampleRate
        ) {
            filters = EqualizerFilterBank(format.channelCount, format.sampleRate)
            bank = filters
            appliedSettings = null
            refreshSettings(snapToTarget = true)
        } else {
            refreshSettings(snapToTarget = false)
        }

        val out = replaceOutputBuffer(remaining)
        val startWet = wet
        val endWet = targetWet
        val startGain = gain
        val endGain = targetGain

        val limit = inputBuffer.limit()
        if (startWet == 0.0 && endWet == 0.0) {
            // Exact copy of the whole frames (a trailing partial frame, never
            // produced in practice, is dropped like in the processing path).
            inputBuffer.limitTo(inputBuffer.position() + frames * bytesPerFrame)
            out.put(inputBuffer)
            inputBuffer.limitTo(limit)
            inputBuffer.moveTo(limit)
            out.flipBuffer()
            return
        }

        if (startWet == 0.0) {
            // Coming out of bypass the filter state is stale.
            filters.reset()
        }

        val channels = format.channelCount
        for (i in 0 until frames) {
            val t = (i + 1).toDouble() / frames
            val w = startWet + (endWet - startWet) * t
            val g = startGain + (endGain - startGain) * t
            for (ch in 0 until channels) {
                val dry = inputBuffer.getShort() / PCM16_SCALE
                val processed = filters.process(ch, dry * g)
                out.putShort(toPcm16(dry + (processed - dry) * w))
            }
        }
        inputBuffer.moveTo(limit)
        out.flipBuffer()

        filters.flushDenormals()
        wet = endWet
        gain = endGain
    }

    private fun refreshSettings(snapToTarget: Boolean) {
        val filters = bank ?: return
        val s = settings
        if (s !== appliedSettings) {
            appliedSettings = s
            if (s.isBypass) {
                targetWet = 0.0
                targetGain = 1.0
            } else {
                filters.setGains(s.bandGainsDb)
                val headroomDb = if (s.preventClipping) filters.peakBoostDb() else 0.0
                targetGain = dbToLinear(s.preampDb - headroomDb)
                targetWet = 1.0
            }
        }
        if (snapToTarget) {
            wet = targetWet
            gain = targetGain
        }
    }

    private fun toPcm16(v: Double): Short {
        val scaled = Math.rint(v * PCM16_SCALE)
        return when {
            scaled >= 32767.0 -> Short.MAX_VALUE
            scaled <= -32768.0 -> Short.MIN_VALUE
            else -> scaled.toInt().toShort()
        }
    }

    // ByteBuffer's position()/flip() have covariant ByteBuffer overloads on
    // newer runtimes only; going through java.nio.Buffer binds to the method
    // every Android version has.
    private fun Buffer.moveTo(newPosition: Int) {
        position(newPosition)
    }

    private fun Buffer.limitTo(newLimit: Int) {
        limit(newLimit)
    }

    private fun Buffer.flipBuffer() {
        flip()
    }

    private companion object {
        const val MAX_CHANNELS = 8
        const val PCM16_SCALE = 32768.0
    }
}
