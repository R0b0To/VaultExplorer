package com.aeidolon.vaultexplorer.audioedit

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The fallback of [LosslessAudioCutter] for audio it can't copy (FLAC, WMA,
 * AC-3, AMR, PCM in odd containers, ...): decode the requested ranges to PCM
 * with `MediaCodec`, trim them to the exact frame, and encode them as AAC-LC
 * into an `.m4a`. Segments are joined on one continuous timeline, so a merge
 * has no gaps.
 *
 * This loses a little quality (it is a second lossy generation for lossy
 * sources), which is why it is only used when copying is impossible, and why
 * the editor says so before exporting. Audio is cheap to decode and encode, so
 * unlike for video this is a reasonable thing to offer.
 *
 * Limits: more than two channels are cut down to the front pair, and sample
 * rates the AAC encoder doesn't take (176.4 / 192 kHz) are refused rather than
 * resampled; see [AudioEditMath.reencodeIssue].
 */
object AudioReencoder {
    private const val TIMEOUT_US = 10_000L

    /** Decoding starts this long before a range so the decoder is warmed up when it reaches it. */
    private const val PRE_ROLL_US = 150_000L

    /** An end within this of the media duration is treated as "to the end". */
    private const val END_EPSILON_US = 1_000L

    /** Consecutive empty polls (10 ms each) before a stuck encoder is given up on. */
    private const val MAX_IDLE_POLLS = 1_000

    private const val INITIAL_SAMPLE_BUFFER = 256 * 1024
    private const val MAX_SAMPLE_BUFFER = 16 * 1024 * 1024

    /** The AAC half: PCM in, `.m4a` samples out. */
    private class EncodeSession(
        outFile: File,
        private val sampleRate: Int,
        private val channels: Int,
        bitrate: Int,
    ) {
        private val encoder: MediaCodec
        private val muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        private val info = MediaCodec.BufferInfo()
        private var trackIndex = -1
        private var muxerStarted = false

        /** PCM frames queued so far: the encoder's timeline, whatever segment they came from. */
        var framesWritten = 0L
            private set

        init {
            val format = MediaFormat.createAudioFormat(AudioEditMath.MIME_AAC, sampleRate, channels).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            }
            encoder = try {
                MediaCodec.createEncoderByType(AudioEditMath.MIME_AAC).also {
                    it.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    it.start()
                }
            } catch (e: Exception) {
                runCatching { muxer.release() }
                throw LosslessAudioCutter.UnsupportedCutException("This device can't encode AAC audio")
            }
        }

        /** Queues [frames] interleaved 16-bit frames from [pcm]. */
        fun write(pcm: ShortArray, frames: Int) {
            val total = frames * channels
            var done = 0
            while (done < total) {
                val index = encoder.dequeueInputBuffer(TIMEOUT_US)
                if (index < 0) {
                    drain(untilEnd = false)
                    continue
                }
                val buffer = encoder.getInputBuffer(index)
                    ?: throw IOException("The AAC encoder gave no input buffer")
                buffer.clear()
                var n = minOf(total - done, buffer.capacity() / 2)
                n -= n % channels
                if (n <= 0) throw IOException("The AAC encoder's input buffer is too small")
                buffer.order(ByteOrder.nativeOrder()).asShortBuffer().put(pcm, done, n)
                val ptsUs = framesWritten * 1_000_000L / sampleRate
                encoder.queueInputBuffer(index, 0, n * 2, ptsUs, 0)
                framesWritten += n / channels
                done += n
                drain(untilEnd = false)
            }
        }

        /** Signals end of input, drains the encoder and closes the file. */
        fun finish() {
            var index = encoder.dequeueInputBuffer(TIMEOUT_US)
            var idle = 0
            while (index < 0) {
                drain(untilEnd = false)
                if (++idle > MAX_IDLE_POLLS) throw IOException("The AAC encoder stalled")
                index = encoder.dequeueInputBuffer(TIMEOUT_US)
            }
            val ptsUs = framesWritten * 1_000_000L / sampleRate
            encoder.queueInputBuffer(index, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drain(untilEnd = true)
            if (!muxerStarted) throw IOException("The AAC encoder produced no audio")
            encoder.stop()
            encoder.release()
            muxer.stop()
            muxerStarted = false
            muxer.release()
        }

        fun abort() {
            runCatching { encoder.stop() }
            runCatching { encoder.release() }
            if (muxerStarted) runCatching { muxer.stop() }
            muxerStarted = false
            runCatching { muxer.release() }
        }

        /** Moves finished AAC samples to the muxer; with [untilEnd], keeps going until the end-of-stream flag. */
        private fun drain(untilEnd: Boolean) {
            var idle = 0
            while (true) {
                val index = encoder.dequeueOutputBuffer(info, if (untilEnd) TIMEOUT_US else 0L)
                when {
                    index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        if (!untilEnd) return
                        if (++idle > MAX_IDLE_POLLS) throw IOException("The AAC encoder stalled")
                    }
                    index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        trackIndex = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                    index >= 0 -> {
                        idle = 0
                        val buffer = encoder.getOutputBuffer(index)
                        if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) info.size = 0
                        if (buffer != null && info.size > 0 && muxerStarted) {
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            muxer.writeSampleData(trackIndex, buffer, info)
                        }
                        encoder.releaseOutputBuffer(index, false)
                        if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return
                    }
                }
            }
        }
    }

    /**
     * Decodes [ranges] of the source and writes them to [outFile] as one AAC
     * `.m4a` (several ranges are joined in the order given). [onProgress]
     * receives 0..1 across the whole call.
     *
     * By default the bitrate follows the source ([AudioEditMath.reencodeBitrate]).
     * With [bitratePerChannel] set (the editor's "compress" export) that exact
     * per-channel bitrate is used instead, so the result can be much smaller
     * than the source; the sample rate and channel layout are unchanged.
     */
    fun reencode(
        newExtractor: () -> AudioSource,
        ranges: List<LosslessAudioCutter.Range>,
        outFile: File,
        isCancelled: () -> Boolean,
        onProgress: (Float) -> Unit,
        bitratePerChannel: Int? = null,
    ): LosslessAudioCutter.CutResult {
        require(ranges.isNotEmpty()) { "No ranges to cut" }

        val extractor = newExtractor()
        var decoder: MediaCodec? = null
        var session: EncodeSession? = null
        var finished = false
        try {
            val track = LosslessAudioCutter.firstAudioTrack(extractor)
            if (track < 0) throw LosslessAudioCutter.UnsupportedCutException("No audio track found in this file")
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME)
                ?: throw LosslessAudioCutter.UnsupportedCutException("Unknown audio format")
            val durationUs = LosslessAudioCutter.durationUsOf(format)
            val isRaw = mime == AudioEditMath.MIME_RAW

            var sampleRate = LosslessAudioCutter.intValue(format, MediaFormat.KEY_SAMPLE_RATE) ?: 0
            var channels = LosslessAudioCutter.intValue(format, MediaFormat.KEY_CHANNEL_COUNT) ?: 0
            var encoding = if (isRaw) {
                LosslessAudioCutter.pcmEncodingOf(format) ?: AudioEditMath.PCM_16BIT
            } else {
                AudioEditMath.PCM_16BIT
            }
            AudioEditMath.reencodeIssue(sampleRate, channels)?.let {
                throw LosslessAudioCutter.UnsupportedCutException(it)
            }
            if (AudioEditMath.bytesPerSample(encoding) == null) {
                throw LosslessAudioCutter.UnsupportedCutException("This PCM sample format can't be re-encoded")
            }
            val sourceBitrate = LosslessAudioCutter.intValue(format, MediaFormat.KEY_BIT_RATE)

            extractor.selectTrack(track)

            fun openDecoder(): MediaCodec = MediaCodec.createDecoderByType(mime).also {
                it.configure(format, null, null, 0)
                it.start()
            }
            if (!isRaw) decoder = openDecoder()

            // The encoder is created on the first PCM, once the decoder's real layout is known.
            fun sessionFor(): EncodeSession {
                session?.let { return it }
                AudioEditMath.reencodeIssue(sampleRate, channels)?.let {
                    throw LosslessAudioCutter.UnsupportedCutException(it)
                }
                val outChannels = AudioEditMath.reencodeChannels(channels)
                val bitrate = if (bitratePerChannel != null) {
                    AudioEditMath.compressBitrate(bitratePerChannel, outChannels)
                } else {
                    AudioEditMath.reencodeBitrate(sourceBitrate, channels)
                }
                return EncodeSession(
                    outFile,
                    sampleRate,
                    outChannels,
                    bitrate,
                ).also { session = it }
            }

            var pcm = ShortArray(0)
            fun encodeSlice(buffer: ByteBuffer, offset: Int, bufferStartFrame: Long, frames: Int, winStart: Long, winEnd: Long) {
                val slice = AudioEditMath.pcmSlice(bufferStartFrame, frames, 1, winStart, winEnd) ?: return
                val count = slice.second - slice.first
                val outChannels = AudioEditMath.reencodeChannels(channels)
                if (pcm.size < count * outChannels) pcm = ShortArray(count * outChannels)
                PcmConvert.toPcm16(buffer, offset, encoding, channels, outChannels, slice.first, count, pcm)
                sessionFor().write(pcm, count)
            }

            val info = MediaCodec.BufferInfo()
            var sample = ByteBuffer.allocateDirect(INITIAL_SAMPLE_BUFFER)
            var lastPermille = -1

            for ((segIndex, requested) in ranges.withIndex()) {
                if (isCancelled()) throw LosslessAudioCutter.CutCancelledException()

                val startUs = requested.startUs.coerceAtLeast(0L)
                val toEnd = durationUs > 0 && requested.endUs >= durationUs - END_EPSILON_US
                val endUs = if (toEnd) Long.MAX_VALUE else requested.endUs
                if (endUs <= startUs) {
                    throw LosslessAudioCutter.UnsupportedCutException("A segment is too short to cut")
                }
                val spanUs = when {
                    !toEnd -> endUs - startUs
                    durationUs > startUs -> durationUs - startUs
                    else -> 0L
                }

                fun report(timeUs: Long) {
                    if (spanUs <= 0) return
                    val within = ((timeUs - startUs).toDouble() / spanUs).coerceIn(0.0, 1.0)
                    val overall = ((segIndex + within) / ranges.size).toFloat()
                    val permille = (overall * 1000).toInt()
                    if (permille != lastPermille) {
                        lastPermille = permille
                        onProgress(overall)
                    }
                }

                extractor.seekTo((startUs - PRE_ROLL_US).coerceAtLeast(0L), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                var segmentDone = false
                var endedStream = false
                var wrote = false

                if (decoder == null) {
                    // Raw PCM: the extractor already hands out samples, nothing to decode.
                    while (!segmentDone) {
                        if (isCancelled()) throw LosslessAudioCutter.CutCancelledException()
                        if (extractor.sampleTrackIndex < 0) break
                        val ts = extractor.sampleTime
                        var size = -1
                        while (true) {
                            try {
                                sample.clear()
                                size = extractor.readSampleData(sample, 0)
                                break
                            } catch (e: IllegalArgumentException) {
                                if (sample.capacity() >= MAX_SAMPLE_BUFFER) throw e
                                sample = ByteBuffer.allocateDirect(sample.capacity() * 2)
                            }
                        }
                        if (size < 0) break
                        val bytesPerFrame = AudioEditMath.bytesPerSample(encoding)!! * channels
                        val chunkStartFrame = AudioEditMath.usToFrame(ts, sampleRate)
                        val winStart = AudioEditMath.usToFrame(startUs, sampleRate)
                        val winEnd = if (toEnd) Long.MAX_VALUE else AudioEditMath.usToFrame(endUs, sampleRate)
                        if (chunkStartFrame >= winEnd) break
                        encodeSlice(sample, 0, chunkStartFrame, size / bytesPerFrame, winStart, winEnd)
                        wrote = true
                        report(ts)
                        extractor.advance()
                    }
                } else {
                    val activeDecoder = decoder
                    var inputDone = false
                    var idle = 0
                    while (!segmentDone) {
                        if (isCancelled()) throw LosslessAudioCutter.CutCancelledException()

                        if (!inputDone) {
                            val inIndex = activeDecoder.dequeueInputBuffer(TIMEOUT_US)
                            if (inIndex >= 0) {
                                val inBuffer = activeDecoder.getInputBuffer(inIndex)
                                val size = if (inBuffer == null || extractor.sampleTrackIndex < 0) {
                                    -1
                                } else {
                                    extractor.readSampleData(inBuffer, 0)
                                }
                                if (size < 0) {
                                    activeDecoder.queueInputBuffer(inIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                    inputDone = true
                                } else {
                                    activeDecoder.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                                    extractor.advance()
                                }
                            }
                        }

                        val outIndex = activeDecoder.dequeueOutputBuffer(info, TIMEOUT_US)
                        when {
                            outIndex >= 0 -> {
                                idle = 0
                                val outBuffer = activeDecoder.getOutputBuffer(outIndex)
                                if (outBuffer != null && info.size > 0) {
                                    val bytesPerFrame = AudioEditMath.bytesPerSample(encoding)!! * channels
                                    val bufferStartFrame = AudioEditMath.usToFrame(info.presentationTimeUs, sampleRate)
                                    val winStart = AudioEditMath.usToFrame(startUs, sampleRate)
                                    val winEnd = if (toEnd) Long.MAX_VALUE else AudioEditMath.usToFrame(endUs, sampleRate)
                                    if (bufferStartFrame >= winEnd) {
                                        segmentDone = true
                                    } else {
                                        encodeSlice(outBuffer, info.offset, bufferStartFrame, info.size / bytesPerFrame, winStart, winEnd)
                                        wrote = true
                                        report(info.presentationTimeUs)
                                    }
                                }
                                activeDecoder.releaseOutputBuffer(outIndex, false)
                                if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                    endedStream = true
                                    segmentDone = true
                                }
                            }
                            outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                                // The decoder's real output layout (HE-AAC doubles the rate, for one).
                                val out = activeDecoder.outputFormat
                                val newRate = LosslessAudioCutter.intValue(out, MediaFormat.KEY_SAMPLE_RATE) ?: sampleRate
                                val newChannels = LosslessAudioCutter.intValue(out, MediaFormat.KEY_CHANNEL_COUNT) ?: channels
                                val newEncoding = LosslessAudioCutter.pcmEncodingOf(out) ?: AudioEditMath.PCM_16BIT
                                if (AudioEditMath.bytesPerSample(newEncoding) == null) {
                                    throw LosslessAudioCutter.UnsupportedCutException("This decoder's PCM format can't be re-encoded")
                                }
                                if (session != null &&
                                    (newRate != sampleRate || AudioEditMath.reencodeChannels(newChannels) != AudioEditMath.reencodeChannels(channels))
                                ) {
                                    throw LosslessAudioCutter.UnsupportedCutException("The audio changes format part-way through")
                                }
                                sampleRate = newRate
                                channels = newChannels
                                encoding = newEncoding
                            }
                            else -> {
                                // Nothing ready; if the input is finished the decoder is just still working.
                                if (++idle > MAX_IDLE_POLLS) throw IOException("The audio decoder stalled")
                            }
                        }
                    }
                }

                if (!wrote) {
                    throw LosslessAudioCutter.UnsupportedCutException("This part of the file contains no audio")
                }

                // Get the decoder ready for the next range: flushed after an early stop, or
                // replaced if it already saw end-of-stream (a decoder can't be reused after that).
                if (segIndex < ranges.size - 1) {
                    if (endedStream) {
                        runCatching { decoder?.stop() }
                        runCatching { decoder?.release() }
                        decoder = openDecoder()
                    } else {
                        decoder?.flush()
                    }
                }
            }

            onProgress(1f)
            val active = session ?: throw LosslessAudioCutter.UnsupportedCutException("This part of the file contains no audio")
            active.finish()
            finished = true
            return LosslessAudioCutter.CutResult("m4a")
        } finally {
            if (!finished) runCatching { session?.abort() }
            decoder?.let {
                runCatching { it.stop() }
                runCatching { it.release() }
            }
            runCatching { extractor.release() }
        }
    }
}
