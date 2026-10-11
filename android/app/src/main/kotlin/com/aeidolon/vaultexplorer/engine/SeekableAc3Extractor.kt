package com.aeidolon.vaultexplorer.engine

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.extractor.ConstantBitrateSeekMap
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.ts.Ac3Extractor

/**
 * Makes raw `.ac3` / `.eac3` files seekable in the player.
 *
 * Media3's [Ac3Extractor] declares every elementary stream unseekable with an unknown length, and
 * `ProgressiveMediaPeriod` treats every seek into unseekable media as a seek to 0:00. In the Audio
 * Editor that showed up as a timeline you couldn't tap or scrub (the playhead snapped back to the
 * start after every touch) and as "preview cut" playback that could never skip a gap. Nothing in
 * `DefaultExtractorsFactory.setConstantBitrateSeekingEnabled` helps: that flag is only passed to the
 * MP3 / ADTS / AMR extractors, not to this one.
 *
 * AC-3 is constant-bitrate by definition, so this wraps the stock extractor and, as soon as the
 * first frame has told its bitrate, replaces the "unseekable" map with a [ConstantBitrateSeekMap]
 * (which also gives the player the duration). Two details make that work:
 *
 *  - After a seek [Ac3Extractor] restarts its timestamps at 0 (it hands the reader a fixed
 *    `pesTimeUs = 0`), so the wrapper shifts every sample time by the time it was told to seek to.
 *  - The byte position a constant-bitrate map comes up with isn't frame-aligned; the stock reader
 *    resynchronises on the next sync word, as it does after any seek.
 *
 * It is exact for AC-3; for E-AC-3 streams whose frame size varies it is approximate. If the
 * bitrate or the length of the file is unknown it leaves the stock behaviour (unseekable) in place.
 *
 * Only the *player* uses this. The cutter reads raw AC-3 sequentially from the start through its own
 * extractor (see `AudioEditHandlers.openMedia3`), where exact frame timestamps matter more than seeking.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class SeekableAc3Extractor(private val inner: Ac3Extractor = Ac3Extractor()) : Extractor {

    private lateinit var output: ExtractorOutput
    private var heldSeekMap: SeekMap? = null
    private var seekMapSent = false
    private var firstReadDone = false
    private var firstFrameBytePosition = 0L
    private var inputLength = C.LENGTH_UNSET.toLong()

    /** Added to every sample time: the time the last seek asked for (the stock extractor restarts at 0). */
    private var timeOffsetUs = 0L

    override fun sniff(input: ExtractorInput): Boolean = inner.sniff(input)

    override fun init(output: ExtractorOutput) {
        this.output = output
        inner.init(HoldingOutput(output))
    }

    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int {
        if (!firstReadDone) {
            firstReadDone = true
            firstFrameBytePosition = input.position
            inputLength = input.length
        }
        return inner.read(input, seekPosition)
    }

    override fun seek(position: Long, timeUs: Long) {
        timeOffsetUs = timeUs
        inner.seek(position, timeUs)
    }

    override fun release() = inner.release()

    override fun getUnderlyingImplementation(): Extractor = inner

    /**
     * Sends the seek map once, right before the first format reaches the player -- the player only
     * finishes preparing when it has both, so it never sees the unseekable one it would act on.
     */
    private fun sendSeekMap(format: Format) {
        if (seekMapSent) return
        seekMapSent = true
        val bitrate = intArrayOf(format.averageBitrate, format.peakBitrate, format.bitrate)
            .firstOrNull { it > 0 } ?: C.RATE_UNSET_INT
        val seekMap = if (bitrate > 0 && inputLength > 0) {
            ConstantBitrateSeekMap(inputLength, firstFrameBytePosition, bitrate, C.LENGTH_UNSET)
        } else {
            heldSeekMap ?: SeekMap.Unseekable(C.TIME_UNSET)
        }
        output.seekMap(seekMap)
    }

    /** Swallows the extractor's own (unseekable) map and wraps its track so sample times can be shifted. */
    private inner class HoldingOutput(private val delegate: ExtractorOutput) : ExtractorOutput {
        override fun track(id: Int, type: Int): TrackOutput = ShiftedTrack(delegate.track(id, type))
        override fun endTracks() = delegate.endTracks()
        override fun seekMap(seekMap: SeekMap) {
            heldSeekMap = seekMap
        }
    }

    private inner class ShiftedTrack(private val delegate: TrackOutput) : TrackOutput {
        override fun format(format: Format) {
            sendSeekMap(format)
            delegate.format(format)
        }

        override fun durationUs(durationUs: Long) = delegate.durationUs(durationUs)

        override fun sampleData(
            input: DataReader,
            length: Int,
            allowEndOfInput: Boolean,
            sampleDataPart: Int,
        ): Int = delegate.sampleData(input, length, allowEndOfInput, sampleDataPart)

        override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) =
            delegate.sampleData(data, length, sampleDataPart)

        override fun sampleMetadata(
            timeUs: Long,
            flags: Int,
            size: Int,
            offset: Int,
            cryptoData: TrackOutput.CryptoData?,
        ) = delegate.sampleMetadata(timeUs + timeOffsetUs, flags, size, offset, cryptoData)
    }
}

/**
 * Swaps every [Ac3Extractor] [delegate] creates for a [SeekableAc3Extractor]; everything else is
 * passed through untouched. Configure the delegate before wrapping it, as with
 * [AiffAwareExtractorsFactory]: the [ExtractorsFactory] setters are deliberately not forwarded.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class SeekableAc3ExtractorsFactory(private val delegate: ExtractorsFactory) : ExtractorsFactory {

    override fun createExtractors(): Array<Extractor> = wrap(delegate.createExtractors())

    override fun createExtractors(
        uri: Uri,
        responseHeaders: Map<String, List<String>>,
    ): Array<Extractor> = wrap(delegate.createExtractors(uri, responseHeaders))

    private fun wrap(extractors: Array<Extractor>): Array<Extractor> =
        Array<Extractor>(extractors.size) { i ->
            val extractor = extractors[i]
            if (extractor is Ac3Extractor) SeekableAc3Extractor(extractor) else extractor
        }
}
