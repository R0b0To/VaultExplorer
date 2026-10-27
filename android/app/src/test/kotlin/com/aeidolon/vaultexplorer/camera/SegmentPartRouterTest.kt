package com.aeidolon.vaultexplorer.camera

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Segmented recording promises parts of an exact length, each one a complete
 * file whose video starts on a keyframe. These tests drive [SegmentPartRouter]
 * with a simulated camera + encoder + audio source and check those promises.
 *
 * The simulation models the things that make this hard in practice:
 *  - the video encoder delivers frames a few frames late, while audio arrives
 *    promptly, so audio for a moment is routinely *ahead* of the video clock;
 *  - the encoder only reacts to a "give me a keyframe" request a couple of
 *    frames after it was made (or never, if it ignores it);
 *  - natural keyframes come every GOP regardless;
 *  - timestamps are huge (a boot clock), not small numbers starting at zero.
 */
class SegmentPartRouterTest {

    private class Written(val track: SampleTrack, val relUs: Long, val absUs: Long, val key: Boolean)

    private class Part(val index: Int, val startUs: Long) {
        val samples = ArrayList<Written>()
        var durationUs = -1L
        var isLast = false
        val video get() = samples.filter { it.track == SampleTrack.VIDEO }
        val audio get() = samples.filter { it.track == SampleTrack.AUDIO }
    }

    private class RecordingSink : PartSink<Int> {
        val parts = ArrayList<Part>()
        private var open = false

        override fun openPart(index: Int, startUs: Long) {
            assertFalse("a part was opened while another was still open", open)
            open = true
            parts += Part(index, startUs)
        }

        override fun write(sample: RoutedSample<Int>, relativePtsUs: Long) {
            assertTrue("sample written with no open part", open)
            assertTrue("negative relative pts $relativePtsUs", relativePtsUs >= 0)
            parts.last().samples += Written(sample.track, relativePtsUs, sample.ptsUs, sample.isKeyFrame)
        }

        override fun closePart(durationUs: Long, isLast: Boolean) {
            assertTrue("closePart with no open part", open)
            open = false
            parts.last().durationUs = durationUs
            parts.last().isLast = isLast
        }
    }

    private class Result(
        val sink: RecordingSink,
        val router: SegmentPartRouter<Int>,
        val requests: Int,
        val deliveredAudioUs: List<Long>,
        val frameUs: Long,
        val totalFrames: Int,
    ) {
        val parts get() = sink.parts
    }

    /** Camera + encoder + audio simulation feeding a router. */
    private fun simulate(
        partSeconds: Int,
        totalSeconds: Int,
        fps: Int = 30,
        gopFrames: Int = 30,
        /** Frames until the encoder obeys a keyframe request; null = it ignores requests. */
        reactionFrames: Int? = 2,
        lagFrames: Int = 4,
        /** What the router is told the pipeline lag is (real value by default). */
        reportedLagFrames: Int = lagFrames,
        baseUs: Long = 5_000_000_000_000L,
        firstKeyAtFrame: Int = 0,
        audioStartOffsetUs: Long = 0L,
        payloadOf: (frame: Int) -> Int = { 1000 },
    ): Result {
        val frameUs = 1_000_000L / fps
        val sink = RecordingSink()
        var step = 0
        var forcedAt = Int.MAX_VALUE
        var requests = 0
        val router = SegmentPartRouter<Int>(
            partLengthUs = partSeconds * 1_000_000L,
            frameDurationUs = frameUs,
            sink = sink,
            requestSyncFrame = {
                requests++
                if (reactionFrames != null) forcedAt = minOf(forcedAt, step + 1 + reactionFrames)
            },
        )

        val frames = totalSeconds * fps
        val pipeline = ArrayDeque<RoutedSample<Int>>()
        var lastKey = Int.MIN_VALUE / 2
        var nextAudio = 0L
        val delivered = ArrayList<Long>()

        fun audioPts(k: Long) = baseUs + audioStartOffsetUs + k * 1024L * 1_000_000L / 44_100L
        val audioFrameUs = 1024L * 1_000_000L / 44_100L

        for (j in 0 until frames) {
            step = j
            val pts = baseUs + j * frameUs
            val key = j == firstKeyAtFrame ||
                (j > firstKeyAtFrame && (j - lastKey >= gopFrames || j >= forcedAt))
            if (key) {
                lastKey = j
                forcedAt = Int.MAX_VALUE
            }
            pipeline.addLast(RoutedSample(SampleTrack.VIDEO, pts, key, payloadOf(j)))

            // Audio is delivered as soon as it has been captured...
            val nowCam = baseUs + j * frameUs
            while (audioPts(nextAudio) + audioFrameUs <= nowCam) {
                val a = audioPts(nextAudio)
                delivered += a
                router.onAudio(RoutedSample(SampleTrack.AUDIO, a, true, 0))
                nextAudio++
            }
            // ...while video comes out of the encoder lagFrames later.
            if (pipeline.size > lagFrames) {
                router.onVideo(pipeline.removeFirst(), reportedLagFrames * frameUs)
            }
        }
        while (pipeline.isNotEmpty()) router.onVideo(pipeline.removeFirst(), reportedLagFrames * frameUs)
        val endCam = baseUs + frames * frameUs
        while (audioPts(nextAudio) + audioFrameUs <= endCam) {
            val a = audioPts(nextAudio)
            delivered += a
            router.onAudio(RoutedSample(SampleTrack.AUDIO, a, true, 0))
            nextAudio++
        }
        router.finish()
        return Result(sink, router, requests, delivered, frameUs, frames)
    }

    private fun closedParts(r: Result) = r.parts.filter { !it.isLast }

    @Test
    fun `parts are the requested length when the encoder honours keyframe requests`() {
        val r = simulate(partSeconds = 10, totalSeconds = 65)
        assertEquals(7, r.parts.size)
        for (p in closedParts(r)) {
            assertTrue(
                "part ${p.index} lasted ${p.durationUs} us",
                abs(p.durationUs - 10_000_000L) <= 3 * r.frameUs,
            )
        }
    }

    @Test
    fun `a part is never shorter than the request by more than the tolerance`() {
        for (reaction in listOf(0, 1, 2, 3, 5)) {
            for (lag in listOf(0, 2, 4, 8)) {
                val r = simulate(partSeconds = 20, totalSeconds = 70, reactionFrames = reaction, lagFrames = lag)
                for (p in closedParts(r)) {
                    assertTrue(
                        "reaction=$reaction lag=$lag part ${p.index} lasted ${p.durationUs}",
                        p.durationUs >= 20_000_000L - 2 * r.frameUs,
                    )
                    assertTrue(
                        "reaction=$reaction lag=$lag part ${p.index} lasted ${p.durationUs}",
                        p.durationUs <= 20_000_000L + 8 * r.frameUs,
                    )
                }
            }
        }
    }

    @Test
    fun `an encoder that ignores keyframe requests still cuts on its next natural keyframe`() {
        val gop = 45
        val r = simulate(partSeconds = 10, totalSeconds = 65, gopFrames = gop, reactionFrames = null)
        assertTrue(r.parts.size >= 6)
        for (p in closedParts(r)) {
            assertEquals("cut off a keyframe boundary", 0L, p.durationUs % (gop * r.frameUs))
            assertTrue(p.durationUs >= 10_000_000L - 2 * r.frameUs)
            assertTrue(p.durationUs < 10_000_000L + gop * r.frameUs)
        }
    }

    @Test
    fun `part length does not depend on how many bytes the encoder produced`() {
        val small = simulate(partSeconds = 10, totalSeconds = 65, payloadOf = { 10 })
        val huge = simulate(partSeconds = 10, totalSeconds = 65, payloadOf = { if (it % 30 == 0) 900_000 else 40_000 })
        assertEquals(small.parts.map { it.durationUs }, huge.parts.map { it.durationUs })
    }

    @Test
    fun `every part starts with a video keyframe at relative time zero`() {
        val r = simulate(partSeconds = 10, totalSeconds = 65)
        for (p in r.parts) {
            val first = p.video.first()
            assertTrue("part ${p.index} does not start on a keyframe", first.key)
            assertEquals(0L, first.relUs)
            assertEquals(p.startUs, first.absUs)
            // and no audio sample precedes it
            assertTrue(p.samples.first().track == SampleTrack.VIDEO)
        }
    }

    @Test
    fun `audio is split by timestamp with nothing lost or repeated`() {
        val r = simulate(partSeconds = 10, totalSeconds = 65, audioStartOffsetUs = -50_000L)
        val firstKey = r.parts.first().startUs
        val written = r.parts.flatMap { p -> p.audio.map { it.absUs } }
        assertEquals(r.deliveredAudioUs.filter { it >= firstKey }, written)
    }

    @Test
    fun `audio never leaks across a cut even though it arrives ahead of the video`() {
        val r = simulate(partSeconds = 10, totalSeconds = 65, lagFrames = 8)
        r.parts.forEachIndexed { i, p ->
            val end = r.parts.getOrNull(i + 1)?.startUs ?: Long.MAX_VALUE
            for (a in p.audio) {
                assertTrue("audio ${a.absUs} before part ${p.index} start ${p.startUs}", a.absUs >= p.startUs)
                assertTrue("audio ${a.absUs} after part ${p.index} end $end", a.absUs < end)
            }
        }
    }

    @Test
    fun `audio has no hole at the start of any part`() {
        val r = simulate(partSeconds = 10, totalSeconds = 65)
        val audioFrameUs = 1024L * 1_000_000L / 44_100L
        for (p in r.parts) {
            assertTrue("part ${p.index} first audio at ${p.audio.first().relUs}", p.audio.first().relUs < audioFrameUs)
        }
    }

    @Test
    fun `audio inside a part ends no later than the part itself`() {
        val r = simulate(partSeconds = 10, totalSeconds = 65)
        val audioFrameUs = 1024L * 1_000_000L / 44_100L
        for (p in r.parts) {
            assertTrue(p.audio.last().relUs < p.durationUs + audioFrameUs)
        }
    }

    @Test
    fun `parts add up to the whole recording`() {
        val r = simulate(partSeconds = 10, totalSeconds = 65)
        val total = r.parts.sumOf { it.durationUs }
        assertTrue("total $total", abs(total - r.totalFrames * r.frameUs) <= r.frameUs)
        assertTrue(r.parts.last().isLast)
        assertEquals(r.parts.size - 1, closedParts(r).size)
    }

    @Test
    fun `delta frames before the first keyframe are skipped and audio before it is dropped`() {
        val r = simulate(partSeconds = 10, totalSeconds = 25, firstKeyAtFrame = 7)
        assertEquals(7, r.router.skippedVideo)
        assertEquals(5_000_000_000_000L + 7 * r.frameUs, r.parts.first().startUs)
        assertTrue(r.router.droppedAudio > 0)
        assertEquals(0L, r.parts.first().video.first().relUs)
    }

    @Test
    fun `timestamps far from zero cause no overflow or rebasing error`() {
        val r = simulate(partSeconds = 10, totalSeconds = 35, baseUs = Long.MAX_VALUE / 4)
        for (p in r.parts) {
            assertTrue(p.video.all { it.relUs in 0..p.durationUs })
        }
        assertEquals(4, r.parts.size)
    }

    @Test
    fun `a keyframe is requested once per part, shortly before the cut`() {
        val r = simulate(partSeconds = 10, totalSeconds = 65)
        val cuts = closedParts(r).size
        assertTrue("requests=${r.requests} cuts=$cuts", r.requests >= cuts)
        assertTrue("requests=${r.requests} cuts=$cuts", r.requests <= cuts * 2)
    }

    @Test
    fun `a keyframe requested too early is asked for again and the cut still lands on time`() {
        // The router is told the pipeline is slower than it really is, so it
        // asks for the keyframe far too soon; that keyframe is too early to cut on.
        val r = simulate(partSeconds = 10, totalSeconds = 65, lagFrames = 1, reportedLagFrames = 15)
        for (p in closedParts(r)) {
            assertTrue("part ${p.index} lasted ${p.durationUs}", abs(p.durationUs - 10_000_000L) <= 6 * r.frameUs)
        }
        assertTrue(r.requests >= closedParts(r).size * 2)
    }

    @Test
    fun `an implausible lag does not move the request by more than the cap`() {
        val r = simulate(partSeconds = 10, totalSeconds = 65, reportedLagFrames = 3000)
        for (p in closedParts(r)) {
            assertTrue(p.durationUs >= 10_000_000L - 20 * r.frameUs)
        }
    }

    @Test
    fun `a stream with no keyframe produces no parts`() {
        val sink = RecordingSink()
        val router = SegmentPartRouter<Int>(10_000_000L, 33_333L, sink, {})
        for (i in 0 until 50) router.onVideo(RoutedSample(SampleTrack.VIDEO, i * 33_333L, false, 0))
        for (i in 0 until 10) router.onAudio(RoutedSample(SampleTrack.AUDIO, i * 23_000L, true, 0))
        router.finish()
        assertTrue(sink.parts.isEmpty())
        assertEquals(50, router.skippedVideo)
        assertEquals(10, router.droppedAudio)
    }

    @Test
    fun `a recording shorter than one part is a single last part`() {
        val r = simulate(partSeconds = 60, totalSeconds = 5)
        assertEquals(1, r.parts.size)
        assertTrue(r.parts.single().isLast)
        assertTrue(abs(r.parts.single().durationUs - 5_000_000L) <= r.frameUs)
        assertEquals(0, r.requests)
    }

    @Test
    fun `works at other frame rates`() {
        for (fps in listOf(24, 25, 60)) {
            val r = simulate(partSeconds = 10, totalSeconds = 45, fps = fps, gopFrames = fps, lagFrames = fps / 6)
            for (p in closedParts(r)) {
                assertTrue("fps=$fps part ${p.index} ${p.durationUs}", abs(p.durationUs - 10_000_000L) <= 6 * r.frameUs)
            }
        }
    }

    @Test
    fun `finish is safe to call twice`() {
        val r = simulate(partSeconds = 10, totalSeconds = 15)
        val before = r.parts.size
        r.router.finish()
        assertEquals(before, r.parts.size)
    }

    // --- Pausing ---------------------------------------------------------

    private val frameUs = 33_333L
    private val base = 5_000_000_000_000L

    /** Feeds [frames] video frames from frame [from] on (a keyframe every 30) plus matching audio. */
    private fun feed(router: SegmentPartRouter<Int>, from: Int, frames: Int) {
        for (j in from until from + frames) {
            val pts = base + j * frameUs
            router.onVideo(RoutedSample(SampleTrack.VIDEO, pts, j % 30 == 0, 0))
            router.onAudio(RoutedSample(SampleTrack.AUDIO, pts, true, 0))
        }
    }

    @Test
    fun `pausing closes the part in progress as a part that is not the last`() {
        val sink = RecordingSink()
        val router = SegmentPartRouter<Int>(600_000_000L, frameUs, sink, {})
        feed(router, 0, 90)
        router.pause()
        assertTrue(router.isPaused)
        assertFalse(router.isOpen)
        assertEquals(1, sink.parts.size)
        assertFalse(sink.parts.single().isLast)
        assertTrue(abs(sink.parts.single().durationUs - 90 * frameUs) <= 2 * frameUs)
    }

    @Test
    fun `nothing is written while paused, even a keyframe`() {
        val sink = RecordingSink()
        val router = SegmentPartRouter<Int>(600_000_000L, frameUs, sink, {})
        feed(router, 0, 60)
        router.pause()
        feed(router, 60, 120) // includes keyframes at 60, 90, 120, 150
        assertEquals(1, sink.parts.size)
        assertFalse(router.isOpen)
    }

    @Test
    fun `after resume the next keyframe opens a new part that starts at time zero`() {
        val sink = RecordingSink()
        var syncRequests = 0
        val router = SegmentPartRouter<Int>(600_000_000L, frameUs, sink, { syncRequests++ })
        feed(router, 0, 60)
        router.pause()
        feed(router, 60, 100)
        router.resume()
        assertEquals("resuming asks the encoder for a keyframe", 1, syncRequests)
        feed(router, 165, 60) // 165 is not a keyframe; 180 is
        router.finish()

        assertEquals(2, sink.parts.size)
        val second = sink.parts[1]
        assertTrue(second.isLast)
        assertEquals(base + 180 * frameUs, second.startUs)
        val firstVideo = second.video.first()
        assertTrue(firstVideo.key)
        assertEquals(0L, firstVideo.relUs)
        assertTrue(second.audio.all { it.absUs >= second.startUs })
    }

    @Test
    fun `audio heard while paused is not carried into the next part`() {
        val sink = RecordingSink()
        val router = SegmentPartRouter<Int>(600_000_000L, frameUs, sink, {})
        feed(router, 0, 60)
        router.pause()
        feed(router, 60, 100)
        router.resume()
        feed(router, 180, 30)
        router.finish()
        val lastOfFirst = sink.parts[0].audio.maxOf { it.absUs }
        val firstOfSecond = sink.parts[1].audio.minOf { it.absUs }
        assertTrue(lastOfFirst < base + 60 * frameUs + frameUs)
        assertTrue(firstOfSecond >= base + 180 * frameUs)
    }

    @Test
    fun `pausing before any keyframe, and pausing twice, are harmless`() {
        val sink = RecordingSink()
        val router = SegmentPartRouter<Int>(600_000_000L, frameUs, sink, {})
        router.pause()
        router.pause()
        router.resume()
        router.resume()
        feed(router, 1, 40) // frame 30 is the first keyframe
        router.finish()
        assertEquals(1, sink.parts.size)
        assertEquals(base + 30 * frameUs, sink.parts.single().startUs)
    }

    @Test
    fun `stopping while paused leaves every earlier part complete and no last part`() {
        val sink = RecordingSink()
        val router = SegmentPartRouter<Int>(600_000_000L, frameUs, sink, {})
        feed(router, 0, 90)
        router.pause()
        router.finish()
        assertEquals(1, sink.parts.size)
        assertFalse("the closed part was not reported as the last one", sink.parts.single().isLast)
    }

    @Test
    fun `part length counts from the start of each part after a pause`() {
        val sink = RecordingSink()
        val router = SegmentPartRouter<Int>(2_000_000L, frameUs, sink, {})
        feed(router, 0, 30)          // 1 s in the first part
        router.pause()
        feed(router, 30, 300)
        router.resume()
        feed(router, 330, 150)       // 5 s: the new part is cut at about 2 s of its own
        router.finish()
        assertTrue(sink.parts.size >= 3)
        for (part in sink.parts.drop(1).filter { !it.isLast }) {
            assertTrue(abs(part.durationUs - 2_000_000L) <= 3 * frameUs)
        }
    }
}
