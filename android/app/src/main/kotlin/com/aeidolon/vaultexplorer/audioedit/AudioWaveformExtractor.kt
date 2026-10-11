package com.aeidolon.vaultexplorer.audioedit

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import com.aeidolon.vaultexplorer.VeLog
import java.nio.ByteBuffer

/**
 * Decodes an audio file just far enough to draw its waveform: the loudest
 * sample in every 10 ms slice (or coarser for very long files, see
 * [AudioEditMath.peaksPerSecondFor]), as one byte per slice.
 *
 * The decode runs through `MediaCodec` straight off the extractor, so a vault
 * file is decrypted on demand and never written out in plaintext. It is
 * time-boxed: a very long file stops at [TIME_BUDGET_MS] and returns what it
 * has with [Waveform.complete] false (the editor draws the rest flat) -- the
 * same trade-off the video probe makes with `keyframesComplete`.
 */
object AudioWaveformExtractor {
    private const val TAG = "AudioWaveformExtractor"
    private const val TIME_BUDGET_MS = 60_000L
    private const val DEQUEUE_TIMEOUT_US = 10_000L

    class CancelledException : Exception("Waveform cancelled")

    class Waveform(
        /** One 0..255 level per slice, oldest first. */
        val peaks: ByteArray,
        val peaksPerSecond: Double,
        /** False when the time budget ran out before the end of the file. */
        val complete: Boolean,
    )

    fun extract(
        newExtractor: () -> MediaExtractor,
        isCancelled: () -> Boolean,
        onProgress: (Float) -> Unit,
    ): Waveform {
        val extractor = newExtractor()
        var codec: MediaCodec? = null
        try {
            val track = LosslessAudioCutter.firstAudioTrack(extractor)
            if (track < 0) throw IllegalStateException("No audio track found in this file")
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: throw IllegalStateException("Unknown audio format")
            val durationUs = LosslessAudioCutter.durationUsOf(format)
            if (durationUs <= 0L) throw IllegalStateException("Unknown audio length")

            val peaksPerSecond = AudioEditMath.peaksPerSecondFor(durationUs)
            val accumulator = PeakAccumulator(
                bucketCount = AudioEditMath.bucketCountFor(durationUs, peaksPerSecond),
                bucketsPerFrame = 0.0,
            )
            val reader = PcmPeakReader(accumulator)

            var sampleRate = LosslessAudioCutter.intValue(format, MediaFormat.KEY_SAMPLE_RATE) ?: 44_100
            reader.channels = LosslessAudioCutter.intValue(format, MediaFormat.KEY_CHANNEL_COUNT) ?: 2
            val isRaw = mime == AudioEditMath.MIME_RAW
            reader.encoding = if (isRaw) {
                LosslessAudioCutter.pcmEncodingOf(format) ?: AudioEditMath.PCM_16BIT
            } else {
                AudioEditMath.PCM_16BIT
            }
            if (AudioEditMath.bytesPerSample(reader.encoding) == null) {
                throw IllegalStateException("This PCM sample format isn't supported")
            }
            accumulator.bucketsPerFrame = peaksPerSecond / sampleRate

            extractor.selectTrack(track)
            val activeCodec = if (isRaw) {
                null
            } else {
                MediaCodec.createDecoderByType(mime).also {
                    it.configure(format, null, null, 0)
                    it.start()
                }
            }
            codec = activeCodec

            val deadline = SystemClock.elapsedRealtime() + TIME_BUDGET_MS
            var lastPermille = -1
            var complete = true

            fun report(timeUs: Long) {
                val permille = ((timeUs.toDouble() / durationUs) * 1000).toInt().coerceIn(0, 1000)
                if (permille != lastPermille) {
                    lastPermille = permille
                    onProgress(permille / 1000f)
                }
            }

            if (activeCodec == null) {
                // Raw PCM (WAV): the extractor already hands out samples, nothing to decode.
                var buffer = ByteBuffer.allocateDirect(64 * 1024)
                while (extractor.sampleTrackIndex >= 0) {
                    if (isCancelled()) throw CancelledException()
                    if (SystemClock.elapsedRealtime() > deadline) {
                        complete = false
                        break
                    }
                    var size = -1
                    while (true) {
                        try {
                            buffer.clear()
                            size = extractor.readSampleData(buffer, 0)
                            break
                        } catch (e: IllegalArgumentException) {
                            if (buffer.capacity() >= 16 * 1024 * 1024) throw e
                            buffer = ByteBuffer.allocateDirect(buffer.capacity() * 2)
                        }
                    }
                    if (size < 0) break
                    reader.consume(buffer, 0, size)
                    report(extractor.sampleTime)
                    extractor.advance()
                }
            } else {
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false
                while (!outputDone) {
                    if (isCancelled()) throw CancelledException()
                    if (SystemClock.elapsedRealtime() > deadline) {
                        complete = false
                        break
                    }

                    if (!inputDone) {
                        val inIndex = activeCodec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                        if (inIndex >= 0) {
                            val inBuffer = activeCodec.getInputBuffer(inIndex)
                            val size = if (inBuffer == null) -1 else extractor.readSampleData(inBuffer, 0)
                            if (size < 0) {
                                activeCodec.queueInputBuffer(inIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                val ts = extractor.sampleTime
                                activeCodec.queueInputBuffer(inIndex, 0, size, ts, 0)
                                report(ts)
                                extractor.advance()
                            }
                        }
                    }

                    val outIndex = activeCodec.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US)
                    when {
                        outIndex >= 0 -> {
                            val outBuffer = activeCodec.getOutputBuffer(outIndex)
                            if (outBuffer != null && info.size > 0) {
                                reader.consume(outBuffer, info.offset, info.size)
                            }
                            activeCodec.releaseOutputBuffer(outIndex, false)
                            if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true
                        }
                        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            // The decoder's real output layout (HE-AAC doubles the rate, for one).
                            val out = activeCodec.outputFormat
                            LosslessAudioCutter.intValue(out, MediaFormat.KEY_SAMPLE_RATE)?.let { sampleRate = it }
                            LosslessAudioCutter.intValue(out, MediaFormat.KEY_CHANNEL_COUNT)?.let { reader.channels = it }
                            reader.encoding = LosslessAudioCutter.pcmEncodingOf(out) ?: AudioEditMath.PCM_16BIT
                            accumulator.bucketsPerFrame = peaksPerSecond / sampleRate
                        }
                    }
                }
            }

            VeLog.d(TAG) { "extract: ${accumulator.bucketCount} peaks, complete=$complete" }
            onProgress(1f)
            return Waveform(accumulator.peaks, peaksPerSecond, complete)
        } finally {
            codec?.let {
                runCatching { it.stop() }
                runCatching { it.release() }
            }
            runCatching { extractor.release() }
        }
    }
}
