package com.aeidolon.vaultexplorer.engine

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.ParserException
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.Util
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.SeekPoint
import androidx.media3.extractor.TrackOutput
import java.io.EOFException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Media3 [Extractor] for AIFF / AIFF-C (`.aif`, `.aiff`, `.aifc`).
 *
 * Media3 ships no AIFF extractor and the platform's `MediaExtractor` does not
 * read AIFF either. The format is plain PCM in a chunked container, and
 * Media3's audio sink already accepts big-endian PCM (it converts to 16-bit
 * little-endian in `ToInt16PcmAudioProcessor`), so this only has to parse the
 * header and hand the sound data over as `audio/raw`. No codec is involved.
 *
 * Supported:
 *  - AIFF: 1..32 bit integer PCM, big-endian (8/16/24/32 bit containers).
 *  - AIFF-C `NONE` / `twos` (big-endian PCM), `sowt` (little-endian PCM),
 *    `fl32`/`FL32` (32-bit float), `fl64`/`FL64` (64-bit float).
 *
 * Not supported (fails with a [ParserException], the caller shows the usual
 * playback error): compressed AIFF-C (`ulaw`, `alaw`, `ima4`, `MAC3`, ...).
 *
 * Chunk layout handled: `COMM` and `SSND` in either order, any other chunk is
 * skipped. Seeking is constant-rate maths over the SSND payload.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class AiffExtractor : Extractor {

    private companion object {
        const val UNSET = -1L
        const val UINT_MAX = 0xFFFFFFFFL

        const val FORM_HEADER_SIZE = 12
        const val CHUNK_HEADER_SIZE = 8
        const val MAX_COMM_SIZE = 1024L

        /** Chunks up to this size are skipped by reading through, larger ones by seeking. */
        const val MAX_SKIP_BYTES = 64L * 1024L

        /** Same ~100 ms sample grouping as Media3's WavExtractor. */
        const val TARGET_SAMPLES_PER_SECOND = 10

        const val MAX_CHANNELS = 8

        // Four-character codes, big-endian.
        const val ID_FORM = 0x464F524D // FORM
        const val ID_AIFF = 0x41494646 // AIFF
        const val ID_AIFC = 0x41494643 // AIFC
        const val ID_COMM = 0x434F4D4D // COMM
        const val ID_SSND = 0x53534E44 // SSND

        const val ID_NONE = 0x4E4F4E45 // NONE
        const val ID_TWOS = 0x74776F73 // twos
        const val ID_SOWT = 0x736F7774 // sowt
        const val ID_FL32_LOWER = 0x666C3332 // fl32
        const val ID_FL32_UPPER = 0x464C3332 // FL32
        const val ID_FL64_LOWER = 0x666C3634 // fl64
        const val ID_FL64_UPPER = 0x464C3634 // FL64

        const val STATE_READING_FILE_HEADER = 0
        const val STATE_READING_CHUNKS = 1
        const val STATE_READING_SAMPLES = 2
    }

    private class CommInfo(
        val channels: Int,
        val frames: Long,
        val bits: Int,
        val sampleRate: Int,
        val compression: Int,
    )

    private class PcmLayout(
        val encoding: Int,
        val bytesPerSample: Int,
        /** AIFF 8-bit is signed, Media3's `ENCODING_PCM_8BIT` is unsigned. */
        val flipSignBit: Boolean,
    )

    private var extractorOutput: ExtractorOutput? = null
    private var trackOutput: TrackOutput? = null
    private var state = STATE_READING_FILE_HEADER
    private var isAifc = false

    // Parsed header. SSND bounds are recorded as soon as the chunk is seen,
    // COMM may come before or after it.
    private var comm: CommInfo? = null
    private var ssndStart = UNSET
    private var ssndSize = UNSET

    // Set once the header is complete and the output has been configured.
    private var dataStartPosition = UNSET
    private var dataEndPosition = UNSET

    // Sample writer state (mirrors WavExtractor's passthrough writer).
    private var sampleRate = 0
    private var bytesPerFrame = 0
    private var targetSampleSizeBytes = 0
    private var flipSignBit = false
    private var signFlipScratch = ByteArray(0)
    private var startTimeUs = 0L
    private var pendingOutputBytes = 0
    private var outputFrameCount = 0L

    override fun sniff(input: ExtractorInput): Boolean {
        val header = ParsableByteArray(FORM_HEADER_SIZE)
        try {
            input.peekFully(header.data, 0, FORM_HEADER_SIZE)
        } catch (e: EOFException) {
            // Shorter than a FORM header: not an AIFF file.
            return false
        }
        return readFormType(header) != 0
    }

    override fun init(output: ExtractorOutput) {
        extractorOutput = output
        trackOutput = output.track(0, C.TRACK_TYPE_AUDIO)
        output.endTracks()
    }

    override fun seek(position: Long, timeUs: Long) {
        if (position == 0L) {
            state = STATE_READING_FILE_HEADER
            if (dataStartPosition == UNSET) {
                comm = null
                ssndStart = UNSET
                ssndSize = UNSET
            }
        } else if (dataStartPosition != UNSET) {
            state = STATE_READING_SAMPLES
        }
        startTimeUs = timeUs
        pendingOutputBytes = 0
        outputFrameCount = 0
    }

    override fun release() {
        // Nothing to release.
    }

    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int =
        when (state) {
            STATE_READING_FILE_HEADER -> readFileHeader(input, seekPosition)
            STATE_READING_CHUNKS -> readChunk(input, seekPosition)
            else -> readSampleData(input)
        }

    // ---- Header ------------------------------------------------------------

    /** Returns [ID_AIFF] / [ID_AIFC], or 0 when [header] is not an AIFF FORM header. */
    private fun readFormType(header: ParsableByteArray): Int {
        if (header.readInt() != ID_FORM) return 0
        header.skipBytes(4) // FORM size
        val formType = header.readInt()
        return if (formType == ID_AIFF || formType == ID_AIFC) formType else 0
    }

    private fun readFileHeader(input: ExtractorInput, seekPosition: PositionHolder): Int {
        if (dataStartPosition != UNSET) {
            // Restarted from position 0 after the header was already parsed.
            seekPosition.position = dataStartPosition
            state = STATE_READING_SAMPLES
            return Extractor.RESULT_SEEK
        }
        val header = ParsableByteArray(FORM_HEADER_SIZE)
        readFullyOrThrow(input, header.data, FORM_HEADER_SIZE, "Truncated AIFF header")
        val formType = readFormType(header)
        if (formType == 0) {
            throw ParserException.createForMalformedContainer("Not an AIFF file", null)
        }
        isAifc = formType == ID_AIFC
        state = STATE_READING_CHUNKS
        return Extractor.RESULT_CONTINUE
    }

    private fun readChunk(input: ExtractorInput, seekPosition: PositionHolder): Int {
        val chunkHeader = ParsableByteArray(CHUNK_HEADER_SIZE)
        readFullyOrThrow(input, chunkHeader.data, CHUNK_HEADER_SIZE, "Missing COMM or SSND chunk")
        val id = chunkHeader.readInt()
        val size = chunkHeader.readUnsignedInt()
        val bodyStart = input.position
        val paddedSize = size + (size and 1L)
        val inputLength = input.length

        when (id) {
            ID_COMM -> {
                val minSize = if (isAifc) 22L else 18L
                if (size < minSize || size > MAX_COMM_SIZE) {
                    throw ParserException.createForMalformedContainer("Invalid COMM chunk size: $size", null)
                }
                val body = ParsableByteArray(size.toInt())
                readFullyOrThrow(input, body.data, size.toInt(), "Truncated COMM chunk")
                comm = parseComm(body)
                if (ssndStart != UNSET) {
                    // SSND came first; the output can be set up now.
                    return startSampleData(input, seekPosition)
                }
                skipPadByte(input, size)
                return Extractor.RESULT_CONTINUE
            }

            ID_SSND -> {
                // Writers streaming to disk leave the size as 0 or 0xFFFFFFFF.
                val sizeUnknown = size == 0L || size == UINT_MAX
                if (!sizeUnknown && size < 8L) {
                    throw ParserException.createForMalformedContainer("Invalid SSND chunk size: $size", null)
                }
                val ssndHeader = ParsableByteArray(8)
                readFullyOrThrow(input, ssndHeader.data, 8, "Truncated SSND chunk")
                val offset = ssndHeader.readUnsignedInt()
                // The second field (blockSize) is only a hint for block-aligned
                // writers and does not change how the PCM is read.
                val payloadStart = input.position + offset
                val payloadSize: Long = if (sizeUnknown) {
                    if (inputLength == UNSET) {
                        throw ParserException.createForUnsupportedContainerFeature(
                            "AIFF with unknown SSND size and unknown stream length",
                        )
                    }
                    inputLength - payloadStart
                } else {
                    size - 8L - offset
                }
                if (payloadSize <= 0L) {
                    throw ParserException.createForMalformedContainer("Empty SSND chunk", null)
                }
                ssndStart = payloadStart
                ssndSize = payloadSize
                if (comm != null) {
                    return startSampleData(input, seekPosition)
                }
                // COMM follows the sound data: jump over it.
                if (sizeUnknown) {
                    throw ParserException.createForMalformedContainer("Missing COMM chunk", null)
                }
                val next = bodyStart + paddedSize
                if (inputLength != UNSET && next >= inputLength) {
                    throw ParserException.createForMalformedContainer("Missing COMM chunk", null)
                }
                seekPosition.position = next
                return Extractor.RESULT_SEEK
            }

            else -> {
                val next = bodyStart + paddedSize
                if (inputLength != UNSET && next > inputLength) {
                    throw ParserException.createForMalformedContainer("Missing COMM or SSND chunk", null)
                }
                if (paddedSize <= MAX_SKIP_BYTES) {
                    try {
                        input.skipFully(paddedSize.toInt())
                    } catch (e: EOFException) {
                        throw ParserException.createForMalformedContainer("Missing COMM or SSND chunk", e)
                    }
                    return Extractor.RESULT_CONTINUE
                }
                seekPosition.position = next
                return Extractor.RESULT_SEEK
            }
        }
    }

    private fun parseComm(body: ParsableByteArray): CommInfo {
        val channels = body.readUnsignedShort()
        val frames = body.readUnsignedInt()
        val bits = body.readUnsignedShort()
        val sampleRateHz = readExtendedSampleRate(body)
        val compression = if (isAifc) body.readInt() else ID_NONE
        if (channels < 1 || channels > MAX_CHANNELS) {
            throw ParserException.createForUnsupportedContainerFeature("AIFF channel count: $channels")
        }
        // Written as a negated range so NaN (the 0x7FFF exponent) is rejected too.
        if (!(sampleRateHz >= 1.0 && sampleRateHz <= 768_000.0)) {
            throw ParserException.createForMalformedContainer("Invalid AIFF sample rate: $sampleRateHz", null)
        }
        return CommInfo(channels, frames, bits, sampleRateHz.roundToInt(), compression)
    }

    /** Decodes the 80-bit IEEE 754 extended-precision sample rate. */
    private fun readExtendedSampleRate(body: ParsableByteArray): Double {
        val exponentAndSign = body.readUnsignedShort()
        val mantissaHigh = body.readUnsignedInt()
        val mantissaLow = body.readUnsignedInt()
        val exponent = exponentAndSign and 0x7FFF
        if (exponent == 0 && mantissaHigh == 0L && mantissaLow == 0L) return 0.0
        if (exponent == 0x7FFF) return Double.NaN
        val mantissa = mantissaHigh.toDouble() * 4_294_967_296.0 + mantissaLow.toDouble()
        return mantissa * 2.0.pow(exponent - 16383 - 63)
    }

    private fun resolveLayout(compression: Int, bits: Int): PcmLayout {
        when (compression) {
            ID_NONE, ID_TWOS, ID_SOWT -> {
                if (bits < 1 || bits > 32) {
                    throw ParserException.createForUnsupportedContainerFeature("AIFF sample size: $bits bits")
                }
                val littleEndian = compression == ID_SOWT
                return when ((bits + 7) / 8) {
                    1 -> PcmLayout(C.ENCODING_PCM_8BIT, 1, flipSignBit = true)
                    2 -> PcmLayout(
                        if (littleEndian) C.ENCODING_PCM_16BIT else C.ENCODING_PCM_16BIT_BIG_ENDIAN,
                        2,
                        flipSignBit = false,
                    )
                    3 -> PcmLayout(
                        if (littleEndian) C.ENCODING_PCM_24BIT else C.ENCODING_PCM_24BIT_BIG_ENDIAN,
                        3,
                        flipSignBit = false,
                    )
                    else -> PcmLayout(
                        if (littleEndian) C.ENCODING_PCM_32BIT else C.ENCODING_PCM_32BIT_BIG_ENDIAN,
                        4,
                        flipSignBit = false,
                    )
                }
            }

            ID_FL32_LOWER, ID_FL32_UPPER -> {
                if (bits != 32) {
                    throw ParserException.createForMalformedContainer("AIFF-C fl32 with $bits bits", null)
                }
                return PcmLayout(C.ENCODING_PCM_FLOAT_BIG_ENDIAN, 4, flipSignBit = false)
            }

            ID_FL64_LOWER, ID_FL64_UPPER -> {
                if (bits != 64) {
                    throw ParserException.createForMalformedContainer("AIFF-C fl64 with $bits bits", null)
                }
                return PcmLayout(C.ENCODING_PCM_DOUBLE_BIG_ENDIAN, 8, flipSignBit = false)
            }

            else -> throw ParserException.createForUnsupportedContainerFeature(
                "AIFF-C compression: ${fourCcToString(compression)}",
            )
        }
    }

    /** Called once both COMM and SSND are known. */
    private fun startSampleData(input: ExtractorInput, seekPosition: PositionHolder): Int {
        val info = checkNotNull(comm)
        val output = checkNotNull(extractorOutput)
        val track = checkNotNull(trackOutput)
        val layout = resolveLayout(info.compression, info.bits)

        val frameSize = info.channels * layout.bytesPerSample
        var dataEnd = ssndStart + ssndSize
        val inputLength = input.length
        if (inputLength != UNSET && dataEnd > inputLength) {
            dataEnd = inputLength
        }
        if (info.frames > 0L) {
            // The declared frame count is authoritative when the SSND chunk
            // carries trailing padding; a zero count (streamed file) is ignored.
            val declaredEnd = ssndStart + info.frames * frameSize
            if (declaredEnd < dataEnd) dataEnd = declaredEnd
        }
        if (dataEnd - ssndStart < frameSize) {
            throw ParserException.createForMalformedContainer("AIFF contains no audio frames", null)
        }

        sampleRate = info.sampleRate
        bytesPerFrame = frameSize
        targetSampleSizeBytes = max(frameSize, sampleRate * frameSize / TARGET_SAMPLES_PER_SECOND)
        flipSignBit = layout.flipSignBit
        signFlipScratch = if (flipSignBit) ByteArray(targetSampleSizeBytes) else ByteArray(0)
        dataStartPosition = ssndStart
        dataEndPosition = dataEnd
        pendingOutputBytes = 0
        outputFrameCount = 0

        val bitrate = sampleRate * frameSize * 8
        val format = Format.Builder()
            .setSampleMimeType(MimeTypes.AUDIO_RAW)
            .setAverageBitrate(bitrate)
            .setPeakBitrate(bitrate)
            .setMaxInputSize(targetSampleSizeBytes)
            .setChannelCount(info.channels)
            .setSampleRate(sampleRate)
            .setPcmEncoding(layout.encoding)
            .build()
        val seekMap = AiffSeekMap(sampleRate, frameSize, ssndStart, dataEnd)
        output.seekMap(seekMap)
        track.format(format)
        track.durationUs(seekMap.getDurationUs())

        state = STATE_READING_SAMPLES
        if (input.position != ssndStart) {
            seekPosition.position = ssndStart
            return Extractor.RESULT_SEEK
        }
        return Extractor.RESULT_CONTINUE
    }

    // ---- Samples -----------------------------------------------------------

    private fun readSampleData(input: ExtractorInput): Int {
        val track = checkNotNull(trackOutput)
        var bytesLeft = dataEndPosition - input.position
        if (bytesLeft <= 0L) return Extractor.RESULT_END_OF_INPUT

        // Group frames into ~100 ms samples, as WavExtractor does.
        while (bytesLeft > 0L && pendingOutputBytes < targetSampleSizeBytes) {
            val toRead = min((targetSampleSizeBytes - pendingOutputBytes).toLong(), bytesLeft).toInt()
            val appended = if (flipSignBit) {
                readSignedEightBit(input, track, toRead)
            } else {
                track.sampleData(input, toRead, true)
            }
            if (appended == C.RESULT_END_OF_INPUT) {
                bytesLeft = 0L
            } else {
                pendingOutputBytes += appended
                bytesLeft -= appended
            }
        }

        // Samples must be a whole number of frames; a truncated file may leave a partial one.
        val pendingFrames = pendingOutputBytes / bytesPerFrame
        if (pendingFrames > 0) {
            val timeUs = startTimeUs +
                Util.scaleLargeTimestamp(outputFrameCount, C.MICROS_PER_SECOND, sampleRate.toLong())
            val size = pendingFrames * bytesPerFrame
            val offset = pendingOutputBytes - size
            track.sampleMetadata(timeUs, C.BUFFER_FLAG_KEY_FRAME, size, offset, null)
            outputFrameCount += pendingFrames
            pendingOutputBytes = offset
        }
        return if (bytesLeft <= 0L) Extractor.RESULT_END_OF_INPUT else Extractor.RESULT_CONTINUE
    }

    /** AIFF 8-bit PCM is signed; Media3's 8-bit PCM is unsigned, so flip the sign bit. */
    private fun readSignedEightBit(input: ExtractorInput, track: TrackOutput, length: Int): Int {
        val read = input.read(signFlipScratch, 0, length)
        if (read == C.RESULT_END_OF_INPUT) return C.RESULT_END_OF_INPUT
        for (i in 0 until read) {
            signFlipScratch[i] = (signFlipScratch[i].toInt() xor 0x80).toByte()
        }
        track.sampleData(ParsableByteArray(signFlipScratch, read), read)
        return read
    }

    // ---- Helpers -----------------------------------------------------------

    private fun readFullyOrThrow(input: ExtractorInput, target: ByteArray, length: Int, message: String) {
        try {
            input.readFully(target, 0, length)
        } catch (e: EOFException) {
            throw ParserException.createForMalformedContainer(message, e)
        }
    }

    /** Chunk bodies are padded to an even size; the pad byte may be missing on the last chunk. */
    private fun skipPadByte(input: ExtractorInput, size: Long) {
        if ((size and 1L) != 0L) {
            try {
                input.skipFully(1)
            } catch (e: EOFException) {
                // Pad byte missing at end of file; the next chunk read reports it if it matters.
            }
        }
    }

    private fun fourCcToString(id: Int): String =
        String(
            charArrayOf(
                ((id shr 24) and 0xFF).toChar(),
                ((id shr 16) and 0xFF).toChar(),
                ((id shr 8) and 0xFF).toChar(),
                (id and 0xFF).toChar(),
            ),
        )

    /** Constant frame rate: time and byte position map linearly over the sound data. */
    private class AiffSeekMap(
        private val sampleRate: Int,
        private val bytesPerFrame: Int,
        private val dataStart: Long,
        dataEnd: Long,
    ) : SeekMap {
        private val frameCount = (dataEnd - dataStart) / bytesPerFrame
        private val duration = frameIndexToTimeUs(frameCount)

        override fun isSeekable(): Boolean = true

        override fun getDurationUs(): Long = duration

        override fun getSeekPoints(timeUs: Long): SeekMap.SeekPoints {
            val frameIndex = Util.constrainValue(
                (timeUs * sampleRate) / C.MICROS_PER_SECOND,
                0L,
                frameCount - 1,
            )
            val first = SeekPoint(frameIndexToTimeUs(frameIndex), dataStart + frameIndex * bytesPerFrame)
            if (first.timeUs >= timeUs || frameIndex == frameCount - 1) {
                return SeekMap.SeekPoints(first)
            }
            val next = frameIndex + 1
            val second = SeekPoint(frameIndexToTimeUs(next), dataStart + next * bytesPerFrame)
            return SeekMap.SeekPoints(first, second)
        }

        private fun frameIndexToTimeUs(frameIndex: Long): Long =
            Util.scaleLargeTimestamp(frameIndex, C.MICROS_PER_SECOND, sampleRate.toLong())
    }
}

/**
 * Puts [AiffExtractor] in front of [delegate]'s extractors.
 *
 * The AIFF sniff is a strict 12-byte `FORM....AIFF/AIFC` check, so it costs
 * nothing for other formats and cannot be mistaken for a loose sync-word
 * match (MP3's sniff scans for frame headers) by running first. The delegate's
 * own order is kept. Configure the delegate before wrapping it: the
 * [ExtractorsFactory] setters are deliberately not forwarded.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class AiffAwareExtractorsFactory(private val delegate: ExtractorsFactory) : ExtractorsFactory {

    override fun createExtractors(): Array<Extractor> =
        arrayOf<Extractor>(AiffExtractor()) + delegate.createExtractors()

    override fun createExtractors(
        uri: Uri,
        responseHeaders: Map<String, List<String>>,
    ): Array<Extractor> =
        arrayOf<Extractor>(AiffExtractor()) + delegate.createExtractors(uri, responseHeaders)
}
