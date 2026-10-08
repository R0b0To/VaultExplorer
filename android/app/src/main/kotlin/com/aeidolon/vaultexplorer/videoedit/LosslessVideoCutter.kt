package com.aeidolon.vaultexplorer.videoedit

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.SystemClock
import com.aeidolon.vaultexplorer.VeLog
import java.io.File
import java.nio.ByteBuffer


object LosslessVideoCutter {
    private const val TAG = "LosslessVideoCutter"

    /** Sentinel for "to the end of the file". */
    private const val EOF_US = Long.MAX_VALUE

    /** An end within this of the media duration is treated as "to the end". */
    private const val END_EPSILON_US = 1_000L

    private const val MAX_KEYFRAMES = 60_000
    private const val KEYFRAME_SCAN_BUDGET_MS = 8_000L

    private const val INITIAL_SAMPLE_BUFFER = 2 * 1024 * 1024
    private const val MAX_SAMPLE_BUFFER = 64 * 1024 * 1024

    class CutCancelledException : Exception("Cut cancelled")

    /** The source can't be cut without re-encoding (codec/container the muxer can't take). */
    class UnsupportedCutException(message: String) : Exception(message)

    class Probe(
        val durationUs: Long,
        val width: Int,
        val height: Int,
        val rotationDegrees: Int,
        val hasVideo: Boolean,
        val hasAudio: Boolean,
        val videoMime: String?,
        val audioMime: String?,
        val videoBitrate: Int? = null,
        val audioBitrate: Int? = null,
        val frameRate: Float? = null,
        val audioSampleRate: Int? = null,
        val audioChannels: Int? = null,
        /** Sync-sample times of the video track, ascending, in microseconds. */
        val keyframesUs: LongArray,
        /** False when the scan hit its time/size budget before reaching the end. */
        val keyframesComplete: Boolean,
        /** File extension (no dot) the output container will use: "mp4" or "webm". */
        val outputExtension: String,
        val hasSubtitles: Boolean = false,
        val subtitleTracks: Int = 0,
    )

    class Range(val startUs: Long, val endUs: Long)

    class CutResult(
        val outputExtension: String,
        val droppedAudioTracks: Int,
        /** Each requested range after snapping; end is the media duration when it ran to EOF. */
        val actualRanges: List<Range>,
    )

    // ── Track planning ───────────────────────────────────────────────────

    private class TrackPlan(
        val videoTrack: Int,
        val audioTracks: List<Int>,
        val formats: Map<Int, MediaFormat>,
    )

    private fun planTracks(extractor: MediaExtractor): TrackPlan {
        var video = -1
        val audio = ArrayList<Int>()
        val formats = HashMap<Int, MediaFormat>()
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("video/") && video < 0) {
                video = i
                formats[i] = format
            } else if (mime.startsWith("audio/")) {
                audio.add(i)
                formats[i] = format
            }
        }
        return TrackPlan(video, audio, formats)
    }

    private fun durationOf(plan: TrackPlan): Long {
        var d = 0L
        for (f in plan.formats.values) {
            if (f.containsKey(MediaFormat.KEY_DURATION)) {
                d = maxOf(d, f.getLong(MediaFormat.KEY_DURATION))
            }
        }
        return d
    }

    private fun intFormatValue(format: MediaFormat?, key: String): Int? {
        if (format == null || !format.containsKey(key)) return null
        return runCatching { format.getInteger(key) }.getOrNull()
            ?: runCatching { format.getLong(key).toInt() }.getOrNull()
    }

    private fun floatFormatValue(format: MediaFormat?, key: String): Float? {
        if (format == null || !format.containsKey(key)) return null
        return runCatching { format.getFloat(key) }.getOrNull()
            ?: runCatching { format.getInteger(key).toFloat() }.getOrNull()
    }

    private fun isWebmCompatible(mime: String): Boolean =
        mime == "video/x-vnd.on2.vp8" ||
            mime == "video/x-vnd.on2.vp9" ||
            mime == "audio/vorbis" ||
            mime == "audio/opus"

    /** WebM only when every track is a codec WebM can hold; otherwise MP4. */
    private fun chooseContainer(plan: TrackPlan): Pair<Int, String> {
        val mimes = plan.formats.values.mapNotNull { it.getString(MediaFormat.KEY_MIME) }
        return if (mimes.isNotEmpty() && mimes.all { isWebmCompatible(it) }) {
            MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM to "webm"
        } else {
            MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4 to "mp4"
        }
    }

    private fun unselectAll(extractor: MediaExtractor) {
        for (i in 0 until extractor.trackCount) {
            try {
                extractor.unselectTrack(i)
            } catch (_: Exception) {
                // Not selected -- nothing to undo.
            }
        }
    }

    // ── Probe ────────────────────────────────────────────────────────────

    fun probe(newExtractor: () -> MediaExtractor, includeKeyframes: Boolean = true): Probe {
        val extractor = newExtractor()
        try {
            val plan = planTracks(extractor)
            if (plan.videoTrack < 0 && plan.audioTracks.isEmpty()) {
                throw UnsupportedCutException("No audio or video track found in this file")
            }
            val durationUs = durationOf(plan)
            val videoFormat = plan.formats[plan.videoTrack]
            val audioFormat = plan.audioTracks.firstOrNull()?.let { plan.formats[it] }

            val width = videoFormat?.takeIf { it.containsKey(MediaFormat.KEY_WIDTH) }
                ?.getInteger(MediaFormat.KEY_WIDTH) ?: 0
            val height = videoFormat?.takeIf { it.containsKey(MediaFormat.KEY_HEIGHT) }
                ?.getInteger(MediaFormat.KEY_HEIGHT) ?: 0
            val rotation = videoFormat?.takeIf { it.containsKey(MediaFormat.KEY_ROTATION) }
                ?.getInteger(MediaFormat.KEY_ROTATION) ?: 0

            val (keyframes, complete) = if (includeKeyframes && plan.videoTrack >= 0) {
                scanKeyframes(extractor, plan.videoTrack)
            } else {
                LongArray(0) to false
            }

            var subtitleTracks = 0
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("text/") || mime.contains("subtitle") || mime.contains("subrip") || mime.contains("vtt")) {
                    subtitleTracks++
                }
            }

            return Probe(
                durationUs = durationUs,
                width = width,
                height = height,
                rotationDegrees = rotation,
                hasVideo = plan.videoTrack >= 0,
                hasAudio = plan.audioTracks.isNotEmpty(),
                videoMime = videoFormat?.getString(MediaFormat.KEY_MIME),
                audioMime = audioFormat?.getString(MediaFormat.KEY_MIME),
                videoBitrate = intFormatValue(videoFormat, MediaFormat.KEY_BIT_RATE),
                audioBitrate = intFormatValue(audioFormat, MediaFormat.KEY_BIT_RATE),
                frameRate = floatFormatValue(videoFormat, MediaFormat.KEY_FRAME_RATE),
                audioSampleRate = intFormatValue(audioFormat, MediaFormat.KEY_SAMPLE_RATE),
                audioChannels = intFormatValue(audioFormat, MediaFormat.KEY_CHANNEL_COUNT),
                keyframesUs = keyframes,
                keyframesComplete = complete,
                outputExtension = chooseContainer(plan).second,
                hasSubtitles = subtitleTracks > 0,
                subtitleTracks = subtitleTracks,
            )
        } finally {
            runCatching { extractor.release() }
        }
    }

    /**
     * Walks the video track keyframe to keyframe with `seekTo(NEXT_SYNC)`
     * instead of reading every sample -- for MP4/MOV that only consults the
     * sample tables, so it stays cheap even on a large, encrypted file.
     * Returns the times found and whether the whole file was covered.
     */
    private fun scanKeyframes(extractor: MediaExtractor, videoTrack: Int): Pair<LongArray, Boolean> {
        extractor.selectTrack(videoTrack)
        val out = ArrayList<Long>(256)
        val deadline = SystemClock.elapsedRealtime() + KEYFRAME_SCAN_BUDGET_MS
        var complete = true

        extractor.seekTo(0L, MediaExtractor.SEEK_TO_NEXT_SYNC)
        var current = extractor.sampleTime
        while (current >= 0) {
            if (out.isNotEmpty() && current <= out[out.size - 1]) break // no forward progress: done
            out.add(current)
            if (out.size >= MAX_KEYFRAMES || SystemClock.elapsedRealtime() > deadline) {
                complete = false
                break
            }
            extractor.seekTo(current + 1, MediaExtractor.SEEK_TO_NEXT_SYNC)
            current = extractor.sampleTime
        }
        VeLog.d(TAG) { "scanKeyframes: ${out.size} keyframes, complete=$complete" }
        return out.toLongArray() to complete
    }

    // ── Cut ──────────────────────────────────────────────────────────────

    /**
     * Snaps [range] to keyframes using [plan]'s video track, returning the
     * `(baseUs, endKeyUs)` pair described in the class comment. For a file
     * with no video track (audio only) every sample is a sync sample, so
     * the range is used as given.
     */
    private fun resolveRange(
        extractor: MediaExtractor,
        plan: TrackPlan,
        range: Range,
        durationUs: Long,
    ): Range {
        val toEnd = durationUs > 0 && range.endUs >= durationUs - END_EPSILON_US
        if (plan.videoTrack < 0) {
            return Range(range.startUs.coerceAtLeast(0L), if (toEnd) EOF_US else range.endUs)
        }
        unselectAll(extractor)
        extractor.selectTrack(plan.videoTrack)
        extractor.seekTo(range.startUs.coerceAtLeast(0L), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        val base = extractor.sampleTime.let { if (it < 0) 0L else it }

        val endKey = if (toEnd) {
            EOF_US
        } else {
            extractor.seekTo(range.endUs, MediaExtractor.SEEK_TO_NEXT_SYNC)
            val t = extractor.sampleTime
            if (t < 0) EOF_US else t
        }
        return Range(base, endKey)
    }

    /**
     * Stream-copies [ranges] from the source into [outFile]. One range gives
     * a plain cut; several ranges are concatenated in the order given.
     * [onProgress] receives 0..1 across the whole call.
     */
    fun cut(
        newExtractor: () -> MediaExtractor,
        ranges: List<Range>,
        outFile: File,
        isCancelled: () -> Boolean,
        onProgress: (Float) -> Unit,
    ): CutResult {
        require(ranges.isNotEmpty()) { "No ranges to cut" }

        val extractor = newExtractor()
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            val plan = planTracks(extractor)
            val durationUs = durationOf(plan)
            val (containerFormat, extension) = chooseContainer(plan)

            val activeMuxer = MediaMuxer(outFile.absolutePath, containerFormat)
            muxer = activeMuxer

            // src track index -> muxer track index
            val dstIndex = HashMap<Int, Int>()
            var maxInput = INITIAL_SAMPLE_BUFFER
            var droppedAudio = 0

            if (plan.videoTrack >= 0) {
                val format = plan.formats.getValue(plan.videoTrack)
                try {
                    dstIndex[plan.videoTrack] = activeMuxer.addTrack(format)
                } catch (e: Exception) {
                    throw UnsupportedCutException(
                        "This video's codec (${format.getString(MediaFormat.KEY_MIME)}) " +
                            "can't be cut without re-encoding on this device",
                    )
                }
                if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                    try {
                        activeMuxer.setOrientationHint(format.getInteger(MediaFormat.KEY_ROTATION))
                    } catch (_: Exception) {
                        // Odd rotation value: leave the output un-rotated rather than fail the cut.
                    }
                }
            }
            for (track in plan.audioTracks) {
                try {
                    dstIndex[track] = activeMuxer.addTrack(plan.formats.getValue(track))
                } catch (e: Exception) {
                    droppedAudio++
                    VeLog.w(TAG, e) { "Audio track $track can't be muxed; dropping it" }
                }
            }
            if (dstIndex.isEmpty()) {
                throw UnsupportedCutException("This file's tracks can't be copied without re-encoding")
            }
            for (track in dstIndex.keys) {
                val f = plan.formats.getValue(track)
                if (f.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    maxInput = maxOf(maxInput, f.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
            }

            activeMuxer.start()
            muxerStarted = true

            var buffer = ByteBuffer.allocateDirect(maxInput)
            val info = MediaCodec.BufferInfo()
            val needVideo = plan.videoTrack >= 0 && dstIndex.containsKey(plan.videoTrack)
            val audioMapped = dstIndex.keys.count { it != plan.videoTrack }

            var offsetUs = 0L
            var lastPermille = -1
            val actual = ArrayList<Range>(ranges.size)

            for ((segIndex, requested) in ranges.withIndex()) {
                if (isCancelled()) throw CutCancelledException()

                val resolved = resolveRange(extractor, plan, requested, durationUs)
                val baseUs = resolved.startUs
                val endKeyUs = resolved.endUs
                if (endKeyUs != EOF_US && endKeyUs <= baseUs) {
                    throw UnsupportedCutException("A segment is too short to cut losslessly")
                }
                val segLenUs = when {
                    endKeyUs != EOF_US -> endKeyUs - baseUs
                    durationUs > baseUs -> durationUs - baseUs
                    else -> 0L
                }
                actual.add(Range(baseUs, if (endKeyUs == EOF_US) durationUs else endKeyUs))

                unselectAll(extractor)
                for (track in dstIndex.keys) extractor.selectTrack(track)
                extractor.seekTo(baseUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

                var videoDone = false
                val audioDone = HashSet<Int>()
                var lastRelUs = 0L

                while (true) {
                    if (isCancelled()) throw CutCancelledException()

                    val trackIdx = extractor.sampleTrackIndex
                    if (trackIdx < 0) break
                    val dst = dstIndex[trackIdx]
                    val ts = extractor.sampleTime
                    val isVideo = trackIdx == plan.videoTrack

                    var skip = dst == null || ts < baseUs
                    if (!skip && endKeyUs != EOF_US) {
                        if (isVideo) {
                            if (videoDone) {
                                skip = true
                            } else if (ts >= endKeyUs &&
                                (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0
                            ) {
                                videoDone = true
                                skip = true
                            }
                        } else if (ts >= endKeyUs) {
                            audioDone.add(trackIdx)
                            skip = true
                        }
                    }

                    if (!skip) {
                        var size = -1
                        while (true) {
                            try {
                                buffer.clear()
                                size = extractor.readSampleData(buffer, 0)
                                break
                            } catch (e: IllegalArgumentException) {
                                // Sample bigger than the buffer (4K keyframes, say): grow and retry.
                                if (buffer.capacity() >= MAX_SAMPLE_BUFFER) throw e
                                buffer = ByteBuffer.allocateDirect(buffer.capacity() * 2)
                            }
                        }
                        if (size < 0) break

                        val rel = ts - baseUs
                        val flags = if ((extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) {
                            MediaCodec.BUFFER_FLAG_KEY_FRAME
                        } else {
                            0
                        }
                        info.set(0, size, rel + offsetUs, flags)
                        activeMuxer.writeSampleData(dst!!, buffer, info)
                        if (rel > lastRelUs) lastRelUs = rel

                        if (segLenUs > 0) {
                            val within = (rel.toDouble() / segLenUs).coerceIn(0.0, 1.0)
                            val overall = ((segIndex + within) / ranges.size).toFloat()
                            val permille = (overall * 1000).toInt()
                            if (permille != lastPermille) {
                                lastPermille = permille
                                onProgress(overall)
                            }
                        }
                    }

                    extractor.advance()

                    if (endKeyUs != EOF_US &&
                        (!needVideo || videoDone) &&
                        audioDone.size >= audioMapped
                    ) {
                        break
                    }
                }

                offsetUs += if (segLenUs > 0) segLenUs else lastRelUs + 1
            }

            onProgress(1f)
            activeMuxer.stop()
            muxerStarted = false
            return CutResult(extension, droppedAudio, actual)
        } finally {
            if (muxerStarted) runCatching { muxer?.stop() }
            runCatching { muxer?.release() }
            runCatching { extractor.release() }
        }
    }
}
