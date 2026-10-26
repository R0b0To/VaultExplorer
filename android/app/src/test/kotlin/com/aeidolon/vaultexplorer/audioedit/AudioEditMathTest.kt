package com.aeidolon.vaultexplorer.audioedit

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioEditMathTest {
    // ── planOutput ───────────────────────────────────────────────────────

    private fun supported(plan: AudioCutPlan): AudioCutPlan.Supported {
        assertTrue("expected a supported plan", plan is AudioCutPlan.Supported)
        return plan as AudioCutPlan.Supported
    }

    @Test
    fun aacGoesIntoM4a() {
        for (ext in listOf("m4a", "aac", "m4b", "mp4")) {
            val plan = supported(AudioEditMath.planOutput(AudioEditMath.MIME_AAC, ext, 34))
            assertEquals(AudioContainer.MP4, plan.container)
            assertEquals("m4a", plan.extension)
        }
    }

    @Test
    fun mp3StaysMp3() {
        val plan = supported(AudioEditMath.planOutput(AudioEditMath.MIME_MP3, "MP3", 34))
        assertEquals(AudioContainer.MP3, plan.container)
        assertEquals("mp3", plan.extension)
    }

    @Test
    fun opusUsesOggOnApi30AndWebmBefore() {
        val modern = supported(AudioEditMath.planOutput(AudioEditMath.MIME_OPUS, "ogg", 30))
        assertEquals(AudioContainer.OGG, modern.container)
        assertEquals("ogg", modern.extension)

        val opusExt = supported(AudioEditMath.planOutput(AudioEditMath.MIME_OPUS, "opus", 34))
        assertEquals("opus", opusExt.extension)

        // Any other source extension (a .weba or .mka holding Opus) is written as plain .ogg.
        val other = supported(AudioEditMath.planOutput(AudioEditMath.MIME_OPUS, "weba", 34))
        assertEquals("ogg", other.extension)

        val legacy = supported(AudioEditMath.planOutput(AudioEditMath.MIME_OPUS, "opus", 29))
        assertEquals(AudioContainer.WEBM, legacy.container)
        assertEquals("weba", legacy.extension)
    }

    @Test
    fun vorbisGoesIntoWebm() {
        val plan = supported(AudioEditMath.planOutput(AudioEditMath.MIME_VORBIS, "ogg", 34))
        assertEquals(AudioContainer.WEBM, plan.container)
        assertEquals("weba", plan.extension)
    }

    @Test
    fun rawPcmIsOnlyCutAsWav() {
        val wav = supported(AudioEditMath.planOutput(AudioEditMath.MIME_RAW, "wav", 34))
        assertEquals(AudioContainer.WAV, wav.container)
        assertEquals("wav", wav.extension)
        // PCM inside some other container has no WAV header to reuse: re-encode.
        assertTrue(AudioEditMath.planOutput(AudioEditMath.MIME_RAW, "mka", 34) is AudioCutPlan.Reencode)
    }

    @Test
    fun codecsThatCantBeCopiedAreReEncodedToM4a() {
        for (mime in listOf("audio/flac", "audio/amr-wb", "audio/3gpp", "audio/vnd.dts", "audio/x-ms-wma")) {
            val plan = AudioEditMath.planOutput(mime, "x", 34)
            assertTrue("$mime should be re-encoded", plan is AudioCutPlan.Reencode)
            assertEquals("m4a", (plan as AudioCutPlan.Reencode).extension)
        }
    }

    @Test
    fun copyingIsPreferredWheneverItIsPossible() {
        for (mime in listOf(
            AudioEditMath.MIME_AAC, AudioEditMath.MIME_MP3, AudioEditMath.MIME_OPUS, AudioEditMath.MIME_VORBIS,
        )) {
            assertTrue(AudioEditMath.planOutput(mime, "x", 34) is AudioCutPlan.Supported)
        }
        assertTrue(AudioEditMath.planOutput(AudioEditMath.MIME_RAW, "wav", 34) is AudioCutPlan.Supported)
    }

    @Test
    fun nonAudioIsUnsupported() {
        assertTrue(AudioEditMath.planOutput(null, "mp3", 34) is AudioCutPlan.Unsupported)
        val plan = AudioEditMath.planOutput("video/avc", "mp4", 34)
        assertTrue(plan is AudioCutPlan.Unsupported)
        assertTrue((plan as AudioCutPlan.Unsupported).reason.contains("video/avc"))
    }

    // ── Re-encode rules ──────────────────────────────────────────────────

    @Test
    fun reencodeAcceptsEveryAacSampleRate() {
        for (rate in AudioEditMath.AAC_SAMPLE_RATES) {
            assertNull("$rate Hz", AudioEditMath.reencodeIssue(rate, 2))
        }
    }

    @Test
    fun reencodeRefusesRatesTheEncoderCantTakeAndUnknownLayouts() {
        assertTrue(AudioEditMath.reencodeIssue(192_000, 2)!!.contains("192000"))
        assertTrue(AudioEditMath.reencodeIssue(176_400, 2) != null)
        assertTrue(AudioEditMath.reencodeIssue(null, 2) != null)
        assertTrue(AudioEditMath.reencodeIssue(0, 2) != null)
        assertTrue(AudioEditMath.reencodeIssue(44_100, null) != null)
        assertTrue(AudioEditMath.reencodeIssue(44_100, 0) != null)
    }

    @Test
    fun reencodeKeepsMonoAndCutsWiderAudioToStereo() {
        assertEquals(1, AudioEditMath.reencodeChannels(1))
        assertEquals(2, AudioEditMath.reencodeChannels(2))
        assertEquals(2, AudioEditMath.reencodeChannels(6))
    }

    @Test
    fun reencodeBitrateFollowsALossySourceAndIsBoundedForOthers() {
        // A lossy stereo source keeps its own bitrate.
        assertEquals(192_000, AudioEditMath.reencodeBitrate(192_000, 2))
        assertEquals(256_000, AudioEditMath.reencodeBitrate(256_000, 2))
        // Too low is lifted to 64 kbps per channel.
        assertEquals(128_000, AudioEditMath.reencodeBitrate(64_000, 2))
        assertEquals(64_000, AudioEditMath.reencodeBitrate(24_000, 1))
        // A lossless-sized or unknown bitrate gets 96 kbps per channel.
        assertEquals(192_000, AudioEditMath.reencodeBitrate(900_000, 2))
        assertEquals(192_000, AudioEditMath.reencodeBitrate(null, 2))
        assertEquals(96_000, AudioEditMath.reencodeBitrate(null, 1))
        // Wide audio is sized as the stereo it becomes.
        assertEquals(192_000, AudioEditMath.reencodeBitrate(null, 6))
    }

    @Test
    fun compressBitrateIsPerChannelAndIgnoresTheSource() {
        assertEquals(32_000, AudioEditMath.compressBitrate(32_000, 1))
        assertEquals(64_000, AudioEditMath.compressBitrate(32_000, 2))
        assertEquals(128_000, AudioEditMath.compressBitrate(64_000, 2))
        // Bounded to what the encoder handles well: 16..160 kbps per channel.
        assertEquals(16_000, AudioEditMath.compressBitrate(4_000, 1))
        assertEquals(320_000, AudioEditMath.compressBitrate(900_000, 2))
        // Never counts more than the stereo pair a wide source is cut down to.
        assertEquals(64_000, AudioEditMath.compressBitrate(32_000, 6))
    }

    // ── bytesPerSample / usToFrame ───────────────────────────────────────

    @Test
    fun bytesPerSampleCoversTheEncodings() {
        assertEquals(2, AudioEditMath.bytesPerSample(null))
        assertEquals(1, AudioEditMath.bytesPerSample(AudioEditMath.PCM_8BIT))
        assertEquals(2, AudioEditMath.bytesPerSample(AudioEditMath.PCM_16BIT))
        assertEquals(3, AudioEditMath.bytesPerSample(AudioEditMath.PCM_24BIT_PACKED))
        assertEquals(4, AudioEditMath.bytesPerSample(AudioEditMath.PCM_32BIT))
        assertEquals(4, AudioEditMath.bytesPerSample(AudioEditMath.PCM_FLOAT))
        assertNull(AudioEditMath.bytesPerSample(999))
    }

    @Test
    fun usToFrameRoundsToNearest() {
        assertEquals(0L, AudioEditMath.usToFrame(0L, 44_100))
        assertEquals(44_100L, AudioEditMath.usToFrame(1_000_000L, 44_100))
        assertEquals(22_050L, AudioEditMath.usToFrame(500_000L, 44_100))
        // One hour at 96 kHz stays well inside Long.
        assertEquals(345_600_000L, AudioEditMath.usToFrame(3_600_000_000L, 96_000))
    }

    // ── pcmSlice ─────────────────────────────────────────────────────────

    @Test
    fun pcmSliceKeepsAChunkThatIsFullyInside() {
        // 100 frames of 4 bytes (16-bit stereo), starting at frame 1000.
        assertEquals(Pair(0, 400), AudioEditMath.pcmSlice(1000, 400, 4, 0, Long.MAX_VALUE))
        assertEquals(Pair(0, 400), AudioEditMath.pcmSlice(1000, 400, 4, 1000, 1100))
    }

    @Test
    fun pcmSliceTrimsToTheWindowAtBothEnds() {
        // Window starts 10 frames in and ends 30 frames before the chunk's end.
        assertEquals(Pair(40, 280), AudioEditMath.pcmSlice(1000, 400, 4, 1010, 1070))
    }

    @Test
    fun pcmSliceIsNullWhenNothingOverlaps() {
        assertNull(AudioEditMath.pcmSlice(1000, 400, 4, 0, 1000)) // window ends where the chunk starts
        assertNull(AudioEditMath.pcmSlice(1000, 400, 4, 1100, 2000)) // window starts where it ends
        assertNull(AudioEditMath.pcmSlice(1000, 400, 4, 1050, 1050)) // empty window
    }

    @Test
    fun pcmSliceIgnoresATrailingPartialFrameAndBadLayouts() {
        // 402 bytes is 100 whole 4-byte frames plus 2 stray bytes.
        assertEquals(Pair(0, 400), AudioEditMath.pcmSlice(0, 402, 4, 0, Long.MAX_VALUE))
        assertNull(AudioEditMath.pcmSlice(0, 3, 4, 0, 10))
        assertNull(AudioEditMath.pcmSlice(0, 400, 0, 0, 10))
    }

    // ── wavHeader ────────────────────────────────────────────────────────

    @Test
    fun wavHeaderDescribes16BitStereoPcm() {
        val header = AudioEditMath.wavHeader(44_100, 2, 2, false, 1_000L)
        assertEquals(44, header.size)
        val b = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)

        assertEquals("RIFF", String(header, 0, 4, Charsets.US_ASCII))
        assertEquals(36 + 1_000, b.getInt(4))
        assertEquals("WAVE", String(header, 8, 4, Charsets.US_ASCII))
        assertEquals("fmt ", String(header, 12, 4, Charsets.US_ASCII))
        assertEquals(16, b.getInt(16))
        assertEquals(1, b.getShort(20).toInt()) // PCM
        assertEquals(2, b.getShort(22).toInt())
        assertEquals(44_100, b.getInt(24))
        assertEquals(44_100 * 4, b.getInt(28)) // byte rate
        assertEquals(4, b.getShort(32).toInt()) // block align
        assertEquals(16, b.getShort(34).toInt())
        assertEquals("data", String(header, 36, 4, Charsets.US_ASCII))
        assertEquals(1_000, b.getInt(40))
    }

    @Test
    fun wavHeaderMarksFloatPcmAndWritesAnEmptyDataChunkFirst() {
        val header = AudioEditMath.wavHeader(48_000, 1, 4, true, 0L)
        val b = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(3, b.getShort(20).toInt()) // IEEE float
        assertEquals(32, b.getShort(34).toInt())
        assertEquals(36, b.getInt(4))
        assertEquals(0, b.getInt(40))
    }

    @Test
    fun wavHeaderKeepsSizesUnsignedUpToTheFourGigabyteLimit() {
        val header = AudioEditMath.wavHeader(44_100, 2, 2, false, AudioEditMath.MAX_WAV_DATA_BYTES)
        val b = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(0xFFFF_FFFFL, b.getInt(4).toLong() and 0xFFFF_FFFFL)
        assertEquals(AudioEditMath.MAX_WAV_DATA_BYTES, b.getInt(40).toLong() and 0xFFFF_FFFFL)
    }

    // ── Waveform sizing ──────────────────────────────────────────────────

    @Test
    fun shortFilesGetTheFullTenMillisecondResolution() {
        assertEquals(100.0, AudioEditMath.peaksPerSecondFor(60_000_000L), 1e-9)
        assertEquals(100.0, AudioEditMath.peaksPerSecondFor(0L), 1e-9)
        assertEquals(6_000, AudioEditMath.bucketCountFor(60_000_000L, 100.0))
    }

    @Test
    fun longFilesGetCoarserPeaksSoTheListStaysBounded() {
        val twoHoursUs = 2L * 3_600_000_000L
        val pps = AudioEditMath.peaksPerSecondFor(twoHoursUs)
        assertTrue(pps < 100.0)
        assertTrue(AudioEditMath.bucketCountFor(twoHoursUs, pps) <= AudioEditMath.MAX_PEAKS)
        assertEquals(AudioEditMath.MAX_PEAKS, AudioEditMath.bucketCountFor(twoHoursUs, pps))
    }

    @Test
    fun bucketCountIsAtLeastOne() {
        assertEquals(1, AudioEditMath.bucketCountFor(1L, 100.0))
    }

    @Test
    fun aThreeHourFileKeepsAUsefulResolutionAndAllOfItsPeaks() {
        // Regression: this used to be capped at 100k peaks (~9 per second for 3 hours).
        val threeHoursUs = 3L * 3_600_000_000L
        val pps = AudioEditMath.peaksPerSecondFor(threeHoursUs)
        assertTrue("got $pps peaks/s", pps > 40.0)
        assertEquals(AudioEditMath.MAX_PEAKS, AudioEditMath.bucketCountFor(threeHoursUs, pps))
    }

    // ── Sparse sampling of long files ────────────────────────────────────

    @Test
    fun strideIsOneWhereEveryFrameIsStillCheap() {
        // 10 ms peaks at 44.1 / 48 kHz: 441 / 480 frames each.
        assertEquals(1, AudioEditMath.strideFor(44_100, 100.0))
        assertEquals(1, AudioEditMath.strideFor(48_000, 100.0))
        assertEquals(1, AudioEditMath.strideFor(0, 100.0))
        assertEquals(1, AudioEditMath.strideFor(44_100, 0.0))
    }

    @Test
    fun strideGrowsWithBucketWidthButKeepsEnoughLooksPerPeak() {
        val pps = AudioEditMath.peaksPerSecondFor(3L * 3_600_000_000L)
        val stride = AudioEditMath.strideFor(44_100, pps)
        assertTrue("stride $stride", stride > 1)
        val looksPerPeak = (44_100 / pps) / stride
        assertTrue("looks per peak $looksPerPeak", looksPerPeak >= AudioEditMath.MIN_FRAMES_PER_PEAK_SAMPLED)
        assertTrue(AudioEditMath.strideFor(192_000, 1.0) <= 64)
    }

    private fun sixteenBitMono(vararg samples: Int): ByteBuffer {
        val b = ByteBuffer.allocateDirect(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (v in samples) b.putShort(v.toShort())
        return b
    }

    @Test
    fun strideSkipsFramesButKeepsPeaksAtTheRightTime() {
        // 8 frames, 4 per bucket, stride 4: frames 0 and 4 are read. The loud frames 1 and 5 are skipped.
        val acc = PeakAccumulator(bucketCount = 2, bucketsPerFrame = 0.25)
        val reader = PcmPeakReader(acc).apply { channels = 1; encoding = AudioEditMath.PCM_16BIT; stride = 4 }
        reader.consume(sixteenBitMono(16384, 32767, 0, 0, 8192, 32767, 0, 0), 0, 16)
        assertEquals(8L, reader.frameIndex) // skipped frames still count
        assertEquals(128, acc.peaks[0].toInt() and 0xFF)
        assertEquals(64, acc.peaks[1].toInt() and 0xFF)
    }

    @Test
    fun strideIsCountedAcrossChunksNotRestartedAtEachOne() {
        // Same 8 frames delivered as 3 + 5: with stride 4 the frames read must still be 0 and 4.
        val samples = intArrayOf(16384, 32767, 0, 0, 8192, 32767, 0, 0)
        val acc = PeakAccumulator(bucketCount = 2, bucketsPerFrame = 0.25)
        val reader = PcmPeakReader(acc).apply { channels = 1; encoding = AudioEditMath.PCM_16BIT; stride = 4 }
        reader.consume(sixteenBitMono(*samples.copyOfRange(0, 3)), 0, 6)
        reader.consume(sixteenBitMono(*samples.copyOfRange(3, 8)), 0, 10)
        assertEquals(8L, reader.frameIndex)
        assertEquals(128, acc.peaks[0].toInt() and 0xFF)
        assertEquals(64, acc.peaks[1].toInt() and 0xFF)
    }

    @Test
    fun strideOneReadsEveryFrameAsBefore() {
        val acc = PeakAccumulator(bucketCount = 2, bucketsPerFrame = 0.25)
        val reader = PcmPeakReader(acc).apply { channels = 1; encoding = AudioEditMath.PCM_16BIT }
        reader.consume(sixteenBitMono(16384, 32767, 0, 0, 8192, 32767, 0, 0), 0, 16)
        assertEquals(255, acc.peaks[0].toInt() and 0xFF)
        assertEquals(255, acc.peaks[1].toInt() and 0xFF)
    }

    // ── Decoding a long file in parallel ─────────────────────────────────

    private val oneHourUs = 3_600_000_000L

    @Test
    fun parallelDecodeNeedsALongFileAnExactSeekingCodecAndSomeCores() {
        val aac = AudioEditMath.MIME_AAC
        assertEquals(4, AudioEditMath.parallelWorkersFor(aac, 3 * oneHourUs, 8))
        assertEquals(3, AudioEditMath.parallelWorkersFor(aac, 3 * oneHourUs, 6))
        assertEquals(1, AudioEditMath.parallelWorkersFor(aac, 3 * oneHourUs, 2)) // 1 worker is no parallelism
        assertEquals(1, AudioEditMath.parallelWorkersFor(aac, 10L * 60_000_000L, 8)) // 10 minutes: not worth it
        assertEquals(1, AudioEditMath.parallelWorkersFor(AudioEditMath.MIME_MP3, 3 * oneHourUs, 8))
        assertEquals(1, AudioEditMath.parallelWorkersFor(AudioEditMath.MIME_RAW, 3 * oneHourUs, 8))
        for (mime in listOf(AudioEditMath.MIME_OPUS, AudioEditMath.MIME_VORBIS, AudioEditMath.MIME_FLAC)) {
            assertEquals(4, AudioEditMath.parallelWorkersFor(mime, oneHourUs, 8))
        }
    }

    @Test
    fun chunksStartOnBucketBoundariesAndCoverEverything() {
        val pps = AudioEditMath.peaksPerSecondFor(3 * oneHourUs)
        val perChunk = AudioEditMath.chunkBuckets(pps)
        val total = AudioEditMath.bucketCountFor(3 * oneHourUs, pps)
        assertTrue("per chunk $perChunk", perChunk in 1000..20_000)
        val chunks = (total + perChunk - 1) / perChunk
        assertTrue(chunks * perChunk >= total)
        assertTrue((chunks - 1) * perChunk < total) // no empty chunk at the end
    }

    @Test
    fun bucketStartsAndFramePositionsAgree() {
        // Bucket 4600 of a 46 peaks/s file starts at 100 s, which at 44.1 kHz is frame 4,410,000.
        assertEquals(100_000_000L, AudioEditMath.bucketStartUs(4600, 46.0))
        assertEquals(4_410_000L, AudioEditMath.frameAtUs(100_000_000L, 44_100))
        assertEquals(0L, AudioEditMath.frameAtUs(-5L, 44_100)) // a negative timestamp is not a position
    }

    @Test
    fun accumulatorsInDifferentWindowsShareOneArrayWithoutTouchingEachOther() {
        val shared = ByteArray(10)
        val left = PeakAccumulator(10, 1.0, shared, firstBucket = 0, endBucket = 5)
        val right = PeakAccumulator(10, 1.0, shared, firstBucket = 5, endBucket = 10)
        for (frame in 0L until 10L) {
            left.add(frame, 1.0f)   // loud everywhere, but may only write 0..4
            right.add(frame, 0.5f)  // half as loud, may only write 5..9
        }
        assertArrayEquals(
            byteArrayOf(-1, -1, -1, -1, -1, 128.toByte(), 128.toByte(), 128.toByte(), 128.toByte(), 128.toByte()),
            shared,
        )
    }

    @Test
    fun aReaderCanStartInTheMiddleOfAFile() {
        // Frames 8..15 land in buckets 2 and 3 (4 frames per bucket); a decode that starts at frame 8
        // must put its peaks there, not at the start.
        val acc = PeakAccumulator(bucketCount = 4, bucketsPerFrame = 0.25)
        val reader = PcmPeakReader(acc).apply { channels = 1; encoding = AudioEditMath.PCM_16BIT }
        reader.frameIndex = 8
        reader.consume(sixteenBitMono(32767, 32767, 0, 0, 16384, 16384, 0, 0), 0, 16)
        assertEquals(16L, reader.frameIndex)
        assertEquals(0, acc.peaks[0].toInt() and 0xFF)
        assertEquals(0, acc.peaks[1].toInt() and 0xFF)
        assertEquals(255, acc.peaks[2].toInt() and 0xFF)
        assertEquals(128, acc.peaks[3].toInt() and 0xFF)
    }

    // ── Progressive waveform ─────────────────────────────────────────────

    @Test
    fun onlyFinishedBucketsAreReportedAsComplete() {
        val acc = PeakAccumulator(bucketCount = 10, bucketsPerFrame = 0.25) // 4 frames per bucket
        assertEquals(0, acc.completeBuckets(0))
        assertEquals(0, acc.completeBuckets(3)) // bucket 0 is still filling
        assertEquals(1, acc.completeBuckets(4))
        assertEquals(2, acc.completeBuckets(11))
        assertEquals(10, acc.completeBuckets(40))
        assertEquals(10, acc.completeBuckets(10_000)) // never past the end
    }

    // ── PeakAccumulator / PcmPeakReader ──────────────────────────────────

    @Test
    fun accumulatorKeepsTheLoudestSamplePerBucket() {
        // 4 frames per bucket.
        val acc = PeakAccumulator(bucketCount = 3, bucketsPerFrame = 0.25)
        acc.add(0, 0.2f)
        acc.add(1, 1.0f)
        acc.add(3, 0.5f) // still bucket 0
        acc.add(4, 0.1f) // bucket 1
        acc.add(11, 0.4f) // bucket 2
        assertEquals(255, acc.peaks[0].toInt() and 0xFF)
        assertEquals(26, acc.peaks[1].toInt() and 0xFF) // 0.1 * 255 + 0.5 = 26
        assertEquals(102, acc.peaks[2].toInt() and 0xFF)
    }

    @Test
    fun accumulatorIgnoresFramesOutsideTheBuckets() {
        val acc = PeakAccumulator(bucketCount = 2, bucketsPerFrame = 1.0)
        acc.add(-1, 1.0f)
        acc.add(2, 1.0f)
        assertArrayEquals(byteArrayOf(0, 0), acc.peaks)
    }

    @Test
    fun readerTakesTheLoudestChannelOf16BitFrames() {
        val acc = PeakAccumulator(bucketCount = 2, bucketsPerFrame = 0.5) // 2 frames per bucket
        val reader = PcmPeakReader(acc)
        reader.channels = 2
        reader.encoding = AudioEditMath.PCM_16BIT

        val data = ByteBuffer.allocateDirect(16).order(ByteOrder.LITTLE_ENDIAN)
        // frame 0: (1000, -16384)  frame 1: (0, 0)  frame 2: (-32768, 5)  frame 3: (100, 100)
        data.putShort(1000).putShort(-16384)
        data.putShort(0).putShort(0)
        data.putShort(-32768).putShort(5)
        data.putShort(100).putShort(100)

        reader.consume(data, 0, 16)

        assertEquals(4L, reader.frameIndex)
        assertEquals(128, acc.peaks[0].toInt() and 0xFF) // 16384 / 32768 = 0.5 -> 128
        assertEquals(255, acc.peaks[1].toInt() and 0xFF) // -32768 is full scale
    }

    @Test
    fun readerHonoursOffsetAndSizeAndCarriesTheFrameCountAcrossBuffers() {
        val acc = PeakAccumulator(bucketCount = 4, bucketsPerFrame = 1.0)
        val reader = PcmPeakReader(acc)
        reader.channels = 1
        reader.encoding = AudioEditMath.PCM_16BIT

        val data = ByteBuffer.allocateDirect(16).order(ByteOrder.LITTLE_ENDIAN)
        data.putShort(32767).putShort(16384).putShort(8192).putShort(4096)
        data.putShort(2048).putShort(1024).putShort(512).putShort(256)

        reader.consume(data, 2, 4) // frames 0 and 1: 16384, 8192
        reader.consume(data, 10, 4) // frames 2 and 3: 1024, 512
        assertEquals(4L, reader.frameIndex)
        assertEquals(128, acc.peaks[0].toInt() and 0xFF)
        assertEquals(64, acc.peaks[1].toInt() and 0xFF)
        assertEquals(8, acc.peaks[2].toInt() and 0xFF)
        assertEquals(4, acc.peaks[3].toInt() and 0xFF)
    }

    @Test
    fun readerHandles8BitUnsigned24BitAndFloat() {
        // 8-bit PCM is unsigned around 128.
        run {
            val acc = PeakAccumulator(1, 1.0)
            val r = PcmPeakReader(acc).apply { channels = 1; encoding = AudioEditMath.PCM_8BIT }
            r.consume(ByteBuffer.wrap(byteArrayOf(128.toByte())), 0, 1)
            assertEquals(0, acc.peaks[0].toInt() and 0xFF)

            val acc2 = PeakAccumulator(1, 1.0)
            val r2 = PcmPeakReader(acc2).apply { channels = 1; encoding = AudioEditMath.PCM_8BIT }
            r2.consume(ByteBuffer.wrap(byteArrayOf(0)), 0, 1) // 0 -> -128 -> full scale
            assertEquals(255, acc2.peaks[0].toInt() and 0xFF)
        }
        // 24-bit packed little-endian: 0x400000 is half of full scale; 0x800000 (negative) is full.
        run {
            val acc = PeakAccumulator(2, 1.0)
            val r = PcmPeakReader(acc).apply { channels = 1; encoding = AudioEditMath.PCM_24BIT_PACKED }
            r.consume(ByteBuffer.wrap(byteArrayOf(0x00, 0x00, 0x40, 0x00, 0x00, 0x80.toByte())), 0, 6)
            assertEquals(128, acc.peaks[0].toInt() and 0xFF)
            assertEquals(255, acc.peaks[1].toInt() and 0xFF)
        }
        // Float: -0.5 -> 128.
        run {
            val acc = PeakAccumulator(1, 1.0)
            val r = PcmPeakReader(acc).apply { channels = 1; encoding = AudioEditMath.PCM_FLOAT }
            val bb = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            bb.putFloat(-0.5f)
            r.consume(bb, 0, 4)
            assertEquals(128, acc.peaks[0].toInt() and 0xFF)
        }
    }

    @Test
    fun readerIgnoresAnUnsupportedEncodingInsteadOfCrashing() {
        val acc = PeakAccumulator(1, 1.0)
        val r = PcmPeakReader(acc).apply { channels = 1; encoding = 999 }
        r.consume(ByteBuffer.wrap(ByteArray(8)), 0, 8)
        assertEquals(0L, r.frameIndex)
        assertEquals(0, acc.peaks[0].toInt())
    }

    // ── PcmConvert ───────────────────────────────────────────────────────

    private fun le(size: Int) = ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN)

    @Test
    fun convertKeepsSixteenBitSamplesAndSelectsAWindowOfFrames() {
        val data = le(16)
        // 4 stereo frames: (1,2) (3,4) (5,6) (7,8)
        for (v in 1..8) data.putShort(v.toShort())
        val out = ShortArray(4)
        PcmConvert.toPcm16(data, 0, AudioEditMath.PCM_16BIT, 2, 2, 1, 2, out) // frames 1 and 2
        assertArrayEquals(shortArrayOf(3, 4, 5, 6), out)
    }

    @Test
    fun convertHonoursTheByteOffset() {
        val data = le(12)
        data.putShort(99).putShort(99) // 4 bytes of something else first
        data.putShort(10).putShort(20).putShort(30).putShort(40)
        val out = ShortArray(2)
        PcmConvert.toPcm16(data, 4, AudioEditMath.PCM_16BIT, 1, 1, 1, 2, out)
        assertArrayEquals(shortArrayOf(20, 30), out)
    }

    @Test
    fun convertDropsChannelsBeyondTheFrontPair() {
        val data = le(12)
        // 2 frames of 3 channels: (1,2,3) (4,5,6)
        for (v in 1..6) data.putShort(v.toShort())
        val out = ShortArray(4)
        PcmConvert.toPcm16(data, 0, AudioEditMath.PCM_16BIT, 3, 2, 0, 2, out)
        assertArrayEquals(shortArrayOf(1, 2, 4, 5), out)
    }

    @Test
    fun convertScalesOtherSampleFormatsToSixteenBit() {
        val out = ShortArray(1)

        // 8-bit is unsigned around 128: 255 -> +127 << 8, 0 -> -128 << 8.
        PcmConvert.toPcm16(ByteBuffer.wrap(byteArrayOf(255.toByte())), 0, AudioEditMath.PCM_8BIT, 1, 1, 0, 1, out)
        assertEquals((127 shl 8).toShort(), out[0])
        PcmConvert.toPcm16(ByteBuffer.wrap(byteArrayOf(0)), 0, AudioEditMath.PCM_8BIT, 1, 1, 0, 1, out)
        assertEquals((-128 shl 8).toShort(), out[0])

        // 24-bit keeps the top 16 bits (little-endian bytes 00 40 12 -> 0x124000 -> 0x1240).
        PcmConvert.toPcm16(
            ByteBuffer.wrap(byteArrayOf(0x00, 0x40, 0x12)), 0, AudioEditMath.PCM_24BIT_PACKED, 1, 1, 0, 1, out,
        )
        assertEquals(0x1240.toShort(), out[0])
        // ... and a negative one: 00 00 80 -> -0x800000 -> -0x8000.
        PcmConvert.toPcm16(
            ByteBuffer.wrap(byteArrayOf(0x00, 0x00, 0x80.toByte())), 0, AudioEditMath.PCM_24BIT_PACKED, 1, 1, 0, 1, out,
        )
        assertEquals(Short.MIN_VALUE, out[0])

        // 32-bit keeps the top 16 bits.
        val i32 = le(4)
        i32.putInt(0x12340000)
        PcmConvert.toPcm16(i32, 0, AudioEditMath.PCM_32BIT, 1, 1, 0, 1, out)
        assertEquals(0x1234.toShort(), out[0])

        // Float is scaled and clipped.
        val f = le(4)
        f.putFloat(0.5f)
        PcmConvert.toPcm16(f, 0, AudioEditMath.PCM_FLOAT, 1, 1, 0, 1, out)
        assertEquals(16383.toShort(), out[0]) // 0.5 * 32767 = 16383.5 -> 16383
        val loud = le(4)
        loud.putFloat(3f)
        PcmConvert.toPcm16(loud, 0, AudioEditMath.PCM_FLOAT, 1, 1, 0, 1, out)
        assertEquals(32767.toShort(), out[0])
    }

    @Test(expected = IllegalArgumentException::class)
    fun convertRejectsAnEncodingItDoesNotKnow() {
        PcmConvert.toPcm16(ByteBuffer.allocate(4), 0, 999, 1, 1, 0, 1, ShortArray(1))
    }

    // ── AC-3 / E-AC-3 / AIFF ─────────────────────────────────────────────

    @Test
    fun ac3AndEac3AreCopiedFrameByFrameWithoutADecoder() {
        val ac3 = supported(AudioEditMath.planOutput(AudioEditMath.MIME_AC3, "ac3", 34))
        assertEquals(AudioContainer.AC3, ac3.container)
        assertEquals("ac3", ac3.extension)
        // Whatever the source container (an MKV or MP4 carrying AC-3), the output is a raw stream.
        assertEquals("ac3", supported(AudioEditMath.planOutput(AudioEditMath.MIME_AC3, "mka", 34)).extension)

        for (mime in listOf(AudioEditMath.MIME_EAC3, AudioEditMath.MIME_EAC3_JOC)) {
            val eac3 = supported(AudioEditMath.planOutput(mime, "eac3", 34))
            assertEquals(AudioContainer.AC3, eac3.container)
            assertEquals("eac3", eac3.extension)
        }
    }

    @Test
    fun aiffAndBigEndianPcmAreCutToWavInsteadOfReEncoded() {
        // Extension alone is enough in the editor (".aif" -> losslessPcm), as is a big-endian layout.
        val plan = supported(AudioEditMath.planOutput(AudioEditMath.MIME_RAW, "aiff", 34, losslessPcm = true))
        assertEquals(AudioContainer.WAV, plan.container)
        assertEquals("wav", plan.extension)
        // Without the flag, PCM in an unrelated container is still re-encoded.
        assertTrue(AudioEditMath.planOutput(AudioEditMath.MIME_RAW, "mka", 34) is AudioCutPlan.Reencode)
        assertTrue(AudioEditMath.AIFF_EXTENSIONS.containsAll(listOf("aif", "aiff", "aifc")))
    }

    @Test
    fun bigEndianEncodingsAreSupportedAndMapToTheirLittleEndianTwins() {
        assertEquals(2, AudioEditMath.bytesPerSample(AudioEditMath.PCM_16BIT_BE))
        assertEquals(3, AudioEditMath.bytesPerSample(AudioEditMath.PCM_24BIT_BE))
        assertEquals(4, AudioEditMath.bytesPerSample(AudioEditMath.PCM_32BIT_BE))
        assertEquals(4, AudioEditMath.bytesPerSample(AudioEditMath.PCM_FLOAT_BE))

        assertTrue(AudioEditMath.isBigEndian(AudioEditMath.PCM_16BIT_BE))
        assertTrue(AudioEditMath.isBigEndian(AudioEditMath.PCM_FLOAT_BE))
        assertTrue(!AudioEditMath.isBigEndian(AudioEditMath.PCM_16BIT))
        assertTrue(!AudioEditMath.isBigEndian(null))

        assertTrue(AudioEditMath.isFloat(AudioEditMath.PCM_FLOAT))
        assertTrue(AudioEditMath.isFloat(AudioEditMath.PCM_FLOAT_BE))
        assertTrue(!AudioEditMath.isFloat(AudioEditMath.PCM_32BIT_BE))

        assertEquals(AudioEditMath.PCM_16BIT, AudioEditMath.littleEndianOf(AudioEditMath.PCM_16BIT_BE))
        assertEquals(AudioEditMath.PCM_24BIT_PACKED, AudioEditMath.littleEndianOf(AudioEditMath.PCM_24BIT_BE))
        assertEquals(AudioEditMath.PCM_32BIT, AudioEditMath.littleEndianOf(AudioEditMath.PCM_32BIT_BE))
        assertEquals(AudioEditMath.PCM_FLOAT, AudioEditMath.littleEndianOf(AudioEditMath.PCM_FLOAT_BE))
        assertEquals(AudioEditMath.PCM_16BIT, AudioEditMath.littleEndianOf(AudioEditMath.PCM_16BIT))
    }

    @Test
    fun swapSampleBytesReversesEachWholeSampleInPlace() {
        val sixteen = byteArrayOf(0x12, 0x34, 0x56, 0x78)
        AudioEditMath.swapSampleBytes(sixteen, 4, 2)
        assertArrayEquals(byteArrayOf(0x34, 0x12, 0x78, 0x56), sixteen)

        val twentyFour = byteArrayOf(1, 2, 3, 4, 5, 6)
        AudioEditMath.swapSampleBytes(twentyFour, 6, 3)
        assertArrayEquals(byteArrayOf(3, 2, 1, 6, 5, 4), twentyFour)

        val thirtyTwo = byteArrayOf(1, 2, 3, 4)
        AudioEditMath.swapSampleBytes(thirtyTwo, 4, 4)
        assertArrayEquals(byteArrayOf(4, 3, 2, 1), thirtyTwo)

        // Only the first `length` bytes count, and a trailing partial sample is left alone.
        val partial = byteArrayOf(1, 2, 3, 4, 5, 9)
        AudioEditMath.swapSampleBytes(partial, 5, 2)
        assertArrayEquals(byteArrayOf(2, 1, 4, 3, 5, 9), partial)

        // One-byte samples have no byte order.
        val eight = byteArrayOf(1, 2, 3)
        AudioEditMath.swapSampleBytes(eight, 3, 1)
        assertArrayEquals(byteArrayOf(1, 2, 3), eight)
    }

    private fun be(size: Int) = ByteBuffer.allocate(size).order(ByteOrder.BIG_ENDIAN)

    @Test
    fun readerReadsBigEndianSamplesTheSameAsLittleEndianOnes() {
        fun peak(encoding: Int, fill: (ByteBuffer) -> Unit, size: Int): Int {
            val acc = PeakAccumulator(1, 1.0)
            val r = PcmPeakReader(acc).apply { channels = 1; this.encoding = encoding }
            val b = be(size)
            fill(b)
            r.consume(b, 0, size)
            return acc.peaks[0].toInt() and 0xFF
        }
        // Half scale in each layout -> 128 of 255, same as the little-endian readings.
        assertEquals(128, peak(AudioEditMath.PCM_16BIT_BE, { it.putShort(0x4000) }, 2))
        assertEquals(128, peak(AudioEditMath.PCM_32BIT_BE, { it.putInt(0x40000000) }, 4))
        assertEquals(128, peak(AudioEditMath.PCM_FLOAT_BE, { it.putFloat(0.5f) }, 4))
        // 24-bit big-endian: 0x400000 = half scale; a negative one (0x800000) is full scale.
        assertEquals(128, peak(AudioEditMath.PCM_24BIT_BE, { it.put(0x40); it.put(0); it.put(0) }, 3))
        assertEquals(255, peak(AudioEditMath.PCM_24BIT_BE, { it.put(0x80.toByte()); it.put(0); it.put(0) }, 3))
    }

    @Test
    fun convertReadsBigEndianSamples() {
        val out = ShortArray(1)

        PcmConvert.toPcm16(be(2).apply { putShort(0x1234) }, 0, AudioEditMath.PCM_16BIT_BE, 1, 1, 0, 1, out)
        assertEquals(0x1234.toShort(), out[0])

        // 24-bit big-endian: 12 34 56 -> top 16 bits 0x1234; 80 00 00 -> Short.MIN_VALUE.
        PcmConvert.toPcm16(
            ByteBuffer.wrap(byteArrayOf(0x12, 0x34, 0x56)), 0, AudioEditMath.PCM_24BIT_BE, 1, 1, 0, 1, out,
        )
        assertEquals(0x1234.toShort(), out[0])
        PcmConvert.toPcm16(
            ByteBuffer.wrap(byteArrayOf(0x80.toByte(), 0x00, 0x00)), 0, AudioEditMath.PCM_24BIT_BE, 1, 1, 0, 1, out,
        )
        assertEquals(Short.MIN_VALUE, out[0])

        PcmConvert.toPcm16(be(4).apply { putInt(0x12340000) }, 0, AudioEditMath.PCM_32BIT_BE, 1, 1, 0, 1, out)
        assertEquals(0x1234.toShort(), out[0])

        PcmConvert.toPcm16(be(4).apply { putFloat(0.5f) }, 0, AudioEditMath.PCM_FLOAT_BE, 1, 1, 0, 1, out)
        assertEquals(16383.toShort(), out[0])
    }

    // ── StreamDurationMeter (raw .ac3 / .eac3 have no duration of their own) ──

    @Test
    fun meterAddsOneFrameToTheLastTimestamp() {
        val m = StreamDurationMeter()
        // AC-3 at 48 kHz: 1536 samples = 32 ms per frame.
        for (i in 0 until 100) m.add(i * 32_000L)
        assertEquals(100 * 32_000L, m.durationUs)
    }

    @Test
    fun meterNeedsTwoSamplesAndIgnoresMissingTimestamps() {
        val m = StreamDurationMeter()
        assertEquals(0L, m.durationUs)
        m.add(-1L)
        assertEquals(0L, m.durationUs)
        m.add(0L)
        assertEquals(0L, m.durationUs) // one timestamp can't tell the frame length
        m.add(32_000L)
        assertEquals(64_000L, m.durationUs)
    }
}
