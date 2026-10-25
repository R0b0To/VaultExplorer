package com.aeidolon.vaultexplorer.camera

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.os.Build
import android.view.Surface
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import com.aeidolon.vaultexplorer.VeLog

class VaultChunkWriter(
    private val volId: Int,
    private val virtualPath: String
) : ChunkSink {
    private var currentOffset: Long = 0L

    override fun write(data: ByteArray): Boolean {
        if (data.isEmpty()) return true
        val ok = ContainerFileSystem.writeFileChunk(volId, virtualPath, currentOffset, data)
        if (ok) {
            currentOffset += data.size
        }
        return ok
    }

    fun write(data: ByteArray, off: Int, len: Int): Boolean {
        if (len <= 0) return true
        val chunk = data.copyOfRange(off, off + len)
        return write(chunk)
    }
}

class MemFile {
    fun writeAndDrain(bytes: ByteArray, writer: ChunkSink): Boolean {
        val chunkSize = 64 * 1024
        var written = 0
        while (written < bytes.size) {
            val len = minOf(chunkSize, bytes.size - written)
            val chunk = bytes.copyOfRange(written, written + len)
            if (!writer.write(chunk)) return false
            written += len
        }
        return true
    }

    fun close() {}
}

data class RecordingResult(val durationMs: Long)

/** One finished part of a segmented recording: a complete, playable temp file. */
data class VideoSegment(val path: String, val durationMs: Long)

private const val TAG = "VaultVideoRecorder"

// HEVC (H.265) needs roughly 40% less bitrate than H264 for the same
// perceived quality, which is the actual fix for large 1080p file sizes --
// checked once and cached, since enumerating MediaCodecList takes a few ms
// and this doesn't change while the process is alive. Falls back to H264 on
// the rare device with no hardware HEVC encoder rather than eating a
// software-encode performance/battery hit.
private val hevcEncoderAvailable: Boolean by lazy {
    if (Build.VERSION.SDK_INT < 24) {
        false
    } else {
        try {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
                info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, ignoreCase = true) }
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "HEVC capability probe failed, falling back to H264" }
            false
        }
    }
}

class VaultVideoRecorder(
    private val width: Int,
    private val height: Int,
    private val quality: VaultVideoQuality,
    private val recordAudio: Boolean = true,
    private val cacheDir: File? = null,
    /**
     * Above zero, the recording is cut into parts of about this many seconds.
     * Each part is closed as its own complete MP4 while the recorder keeps
     * running, so nothing is dropped at the seam and a crash can only ever
     * cost the part in progress.
     */
    private val segmentSeconds: Int = 0,
) {
    companion object {
        private const val TEMP_PREFIX = "vx_vid_"
        private const val TEMP_SUFFIX = ".mp4"
        private const val AUDIO_BITRATE = 128_000
        // MediaRecorder cannot honour a tiny size limit; never ask for less.
        private const val MIN_SEGMENT_BYTES = 1L * 1024 * 1024

        /**
         * Sweeps [cacheDir] for plaintext recording temp files left behind
         * by a previous process death -- a crash, force-stop, or OOM kill
         * between MediaRecorder writing one of these (see prepareEncoder())
         * and secureDeleteTempFile() wiping it in writeTo()/releaseEncoder()
         * only covers the normal completion paths, not the process simply
         * dying mid-recording. Left uncleaned, a leftover file is an
         * unencrypted copy of whatever was being recorded sitting on disk
         * indefinitely -- exactly what this app exists to avoid.
         *
         * Intended to run once at app startup (see MainActivity.onCreate),
         * off the main thread, before any camera session could plausibly
         * create a *new* temp file of this shape -- so there's no risk of
         * this sweep racing a legitimate in-progress recording.
         *
         * Returns how many orphaned files were found and wiped, for logging.
         */
        fun sweepOrphanedTempFiles(cacheDir: File?): Int {
            val dir = cacheDir ?: return 0
            val orphans = dir.listFiles { f ->
                f.isFile && f.name.startsWith(TEMP_PREFIX) && f.name.endsWith(TEMP_SUFFIX)
            } ?: return 0
            var wiped = 0
            for (file in orphans) {
                if (secureDeleteFile(file)) wiped++
            }
            if (wiped > 0) {
                VeLog.i(TAG) { "sweepOrphanedTempFiles: wiped $wiped orphaned recording temp file(s)" }
            }
            return wiped
        }

        /** Overwrites [file] with zeros before deleting it, so a leftover
         *  plaintext recording isn't just unlinked (which on most Android
         *  filesystems leaves the content readable until the blocks are
         *  reused). Shared by the per-recording cleanup below and by
         *  [sweepOrphanedTempFiles]. Returns false if the file couldn't be
         *  fully wiped -- the caller falls back to at least trying delete(). */
      internal fun zeroFillFile(file: File): Boolean {
            return try {
                if (file.exists()) {
                    val len = file.length()
                    if (len > 0) {
                        // Use "rw" with a 512KB buffer and a single physical sync at the end.
                        // "rws" forced a hardware fsync on every 64KB, causing massive flash write stalls.
                       RandomAccessFile(file, "rw").use { raf ->
                            val zeros = ByteArray(64 * 1024)
                            var remaining = len
                            while (remaining > 0) {
                                val writeLen = minOf(remaining, zeros.size.toLong()).toInt()
                                raf.write(zeros, 0, writeLen)
                                remaining -= writeLen
                            }
                            try { raf.fd.sync() } catch (_: Exception) {}
                        }
                    }
                    true
                } else {
                    true
                }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "zeroFillFile failed" }
                false
            }
        }

        internal fun secureDeleteFile(file: File): Boolean {
            return try {
                if (file.exists()) {
                    val zeroed = zeroFillFile(file)
                    val deleted = file.delete()
                    zeroed && deleted
                } else {
                    true
                }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "secureDeleteFile failed" }
                try { file.delete() } catch (_: Exception) {}
                false
            }
        }

        fun streamFileToSink(file: File, sink: ChunkSink): Boolean {
            if (!file.exists() || file.length() == 0L) return false
            try {
                java.io.BufferedInputStream(FileInputStream(file), 64 * 1024).use { bis ->
                    val buffer = ByteArray(64 * 1024)
                    var bytesRead: Int
                    while (bis.read(buffer).also { bytesRead = it } != -1) {
                        if (bytesRead > 0) {
                            val chunk = if (bytesRead == buffer.size) buffer else buffer.copyOf(bytesRead)
                            if (!sink.write(chunk)) return false
                        }
                    }
                }
                return sink.finish()
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "streamFileToSink failed" }
                return false
            }
        }

        fun streamFileToSinkAndWipe(file: File, sink: ChunkSink): Boolean {
            if (!file.exists() || file.length() == 0L) return false
            return try {
                streamFileToSink(file, sink)
            } finally {
                secureDeleteFile(file)
            }
        }

        fun trimVideo(sourcePath: String, startMs: Long, endMs: Long): String? {
            val srcFile = File(sourcePath)
            if (!srcFile.exists() || startMs >= endMs) return sourcePath
            val destFile = File.createTempFile("vx_vid_trim_", ".mp4", srcFile.parentFile)

            var extractor: MediaExtractor? = null
            var muxer: MediaMuxer? = null
            try {
                extractor = MediaExtractor()
                extractor.setDataSource(sourcePath)
                val trackCount = extractor.trackCount
                muxer = MediaMuxer(destFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

                val indexMap = HashMap<Int, Int>(trackCount)
                var maxBufferSize = 1024 * 1024
                for (i in 0 until trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("video/") || mime.startsWith("audio/")) {
                        val dstIndex = muxer.addTrack(format)
                        indexMap[i] = dstIndex
                        if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                            val inputSize = format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                            if (inputSize > maxBufferSize) maxBufferSize = inputSize
                        }
                        if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                            muxer.setOrientationHint(format.getInteger(MediaFormat.KEY_ROTATION))
                        }
                    }
                }

                muxer.start()

                val startUs = startMs * 1000L
                val endUs = endMs * 1000L
                val buffer = ByteBuffer.allocateDirect(maxBufferSize)
                val bufferInfo = MediaCodec.BufferInfo()

                for (i in 0 until trackCount) {
                    if (!indexMap.containsKey(i)) continue
                    val dstIndex = indexMap[i]!!
                    for (t in 0 until trackCount) {
                        try { extractor.unselectTrack(t) } catch (_: Exception) {}
                    }
                    extractor.selectTrack(i)
                    extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

                    var firstPtsUs = -1L
                    while (true) {
                        bufferInfo.offset = 0
                        bufferInfo.size = extractor.readSampleData(buffer, 0)
                        if (bufferInfo.size < 0) break

                        val sampleTimeUs = extractor.sampleTime
                        if (sampleTimeUs > endUs) break

                        if (sampleTimeUs >= startUs) {
                            if (firstPtsUs == -1L) firstPtsUs = sampleTimeUs
                            bufferInfo.presentationTimeUs = maxOf(0L, sampleTimeUs - firstPtsUs)
                            bufferInfo.flags = extractor.sampleFlags
                            muxer.writeSampleData(dstIndex, buffer, bufferInfo)
                        }
                        extractor.advance()
                    }
                }

                muxer.stop()
                secureDeleteFile(srcFile)
                return destFile.absolutePath
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "trimVideo failed" }
                secureDeleteFile(destFile)
                return sourcePath
            } finally {
                try { muxer?.release() } catch (_: Exception) {}
                try { extractor?.release() } catch (_: Exception) {}
            }
        }
    }

    var inputSurface: Surface? = null
        private set

    private var mediaRecorder: MediaRecorder? = null

    @Volatile
    private var tempFile: File? = null
    private var startTimeMs: Long = 0L
    private var stopTimeMs: Long = 0L

    // --- Segmented recording -------------------------------------------------
    private val segmentLock = Any()

    /** File handed to MediaRecorder.setNextOutputFile that has not started yet. */
    private var pendingNextFile: File? = null
    private var segmentStartMs: Long = 0L

    /**
     * Called whenever a part has been closed. Runs on the thread MediaRecorder
     * delivers its info callbacks on, so it must only queue the segment.
     */
    @Volatile
    var onSegmentFinished: ((VideoSegment) -> Unit)? = null

    private val infoListener = MediaRecorder.OnInfoListener { recorder, what, _ ->
        when (what) {
            MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_APPROACHING -> queueNextFile(recorder)
            MediaRecorder.MEDIA_RECORDER_INFO_NEXT_OUTPUT_FILE_STARTED -> onNextFileStarted()
            MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED ->
                // Only reached if the next file could not be set in time; the
                // recorder has stopped by itself. Everything up to here is a
                // valid file, so stopping normally still yields it.
                VeLog.w(TAG) { "segment size reached without a next file; recorder stopped" }
            else -> Unit
        }
    }

    fun prepareEncoder(orientationDegrees: Int = 0) {
        releaseEncoder()
        val temp = File.createTempFile(TEMP_PREFIX, TEMP_SUFFIX, cacheDir)
        tempFile = temp
        val useHevc = hevcEncoderAvailable
        val bitrate = if (useHevc) quality.bitrateHevc else quality.bitrateH264
        VeLog.d(TAG) { "prepareEncoder: ${width}x$height quality=$quality codec=${if (useHevc) "HEVC" else "H264"} bitrate=$bitrate orientation=$orientationDegrees audio=$recordAudio" }

        @Suppress("DEPRECATION")
        val recorder = MediaRecorder()

        if (recordAudio) {
            recorder.setAudioSource(MediaRecorder.AudioSource.CAMCORDER)
        }
        recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        // setOrientationHint() is only legal before prepare() -- calling it
        // afterwards (as beginRecording() used to) throws the recorder into
        // "setParameters is called in an invalid state: 8" (8 == PREPARED),
        // because prepare() has already moved it past the state where
        // parameter setters are allowed.
        recorder.setOrientationHint(orientationDegrees)
        recorder.setVideoEncoder(if (useHevc) MediaRecorder.VideoEncoder.HEVC else MediaRecorder.VideoEncoder.H264)
        if (recordAudio) {
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(128_000)
            recorder.setAudioSamplingRate(44100)
        }
        recorder.setVideoSize(width, height)
        recorder.setVideoEncodingBitRate(bitrate)
        recorder.setVideoFrameRate(TARGET_RECORDING_FPS)
        recorder.setOutputFile(temp.absolutePath)
        if (segmentSeconds > 0) {
            val bytesPerSecond = (bitrate + if (recordAudio) AUDIO_BITRATE else 0) / 8L
            val maxBytes = (bytesPerSecond * segmentSeconds).coerceAtLeast(MIN_SEGMENT_BYTES)
            recorder.setMaxFileSize(maxBytes)
            recorder.setOnInfoListener(infoListener)
            VeLog.d(TAG) { "prepareEncoder: segmented, ~${segmentSeconds}s parts, maxFileSize=$maxBytes" }
        }

        recorder.prepare()
        inputSurface = recorder.surface
        mediaRecorder = recorder
        VeLog.d(TAG) { "prepareEncoder: prepared ok, surface=$inputSurface" }
    }

    fun beginRecording() {
        val recorder = mediaRecorder ?: throw IllegalStateException("Encoder not prepared")
        VeLog.d(TAG) { "beginRecording: starting" }
        recorder.start()
        startTimeMs = System.currentTimeMillis()
        segmentStartMs = startTimeMs
        VeLog.d(TAG) { "beginRecording: started at $startTimeMs" }
    }

    fun requestStop(): RecordingResult {
        val recorder = mediaRecorder ?: return RecordingResult(0)
        stopTimeMs = System.currentTimeMillis()
        try {
            recorder.stop()
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "MediaRecorder.stop failed" }
        }
        val duration = maxOf(0L, stopTimeMs - startTimeMs)
        VeLog.d(TAG) { "requestStop: duration=${duration}ms" }
        return RecordingResult(duration)
    }

    fun writeTo(writer: ChunkSink): Boolean {
        val temp = tempFile ?: return false
        if (!temp.exists() || temp.length() == 0L) {
            VeLog.e(TAG) { "writeTo: temp file missing or empty (exists=${temp.exists()}, len=${temp.length()})" }
            return false
        }
        VeLog.d(TAG) { "writeTo: streaming ${temp.length()} bytes to vault" }

        val writeToStart = System.currentTimeMillis()
        try {
            java.io.BufferedInputStream(FileInputStream(temp), 64 * 1024).use { bis ->
                val buffer = ByteArray(64 * 1024)
                var bytesRead: Int
                while (bis.read(buffer).also { bytesRead = it } != -1) {
                    if (bytesRead > 0) {
                        val chunk = if (bytesRead == buffer.size) buffer else buffer.copyOf(bytesRead)
                        if (!writer.write(chunk)) {
                            return false
                        }
                    }
                }
            }
            val ok = writer.finish()
            VeLog.i(TAG) { "[PERF] VaultVideoRecorder.writeTo stream time: ${System.currentTimeMillis() - writeToStart}ms" }
            return ok
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "writeTo failed" }
            return false
        } finally {
            val wipeStart = System.currentTimeMillis()
            secureDeleteTempFile()
            VeLog.i(TAG) { "[PERF] VaultVideoRecorder.writeTo temp wipe time: ${System.currentTimeMillis() - wipeStart}ms" }
        }
    }

 val tempFilePath: String? get() = tempFile?.absolutePath

    fun releaseRecorderOnly() {
        try {
            mediaRecorder?.reset()
            mediaRecorder?.release()
        } catch (_: Exception) {}
        mediaRecorder = null
        inputSurface = null
    }

    fun releaseEncoder() {
        releaseRecorderOnly()
        secureDeleteTempFile()
        val next = synchronized(segmentLock) { pendingNextFile.also { pendingNextFile = null } }
        if (next != null) secureDeleteFile(next)
    }

    /**
     * Gives MediaRecorder the file to continue into once the current one is
     * full. Called when the recorder reports the size limit is near.
     */
    private fun queueNextFile(recorder: MediaRecorder) {
        synchronized(segmentLock) {
            if (pendingNextFile == null) {
                val next = try {
                    File.createTempFile(TEMP_PREFIX, TEMP_SUFFIX, cacheDir)
                } catch (e: Exception) {
                    VeLog.e(TAG, e) { "could not create the next segment file" }
                    null
                }
                if (next != null) {
                    try {
                        recorder.setNextOutputFile(next)
                        pendingNextFile = next
                    } catch (e: Exception) {
                        VeLog.e(TAG, e) { "setNextOutputFile failed" }
                        secureDeleteFile(next)
                    }
                }
            }
        }
    }

    /** The recorder has closed the previous file and moved on to the next. */
    private fun onNextFileStarted() {
        val segment = synchronized(segmentLock) {
            val closed = tempFile
            val next = pendingNextFile
            if (closed == null || next == null) {
                null
            } else {
                tempFile = next
                pendingNextFile = null
                val now = System.currentTimeMillis()
                val durationMs = maxOf(0L, now - segmentStartMs)
                segmentStartMs = now
                VideoSegment(closed.absolutePath, durationMs)
            }
        } ?: return
        VeLog.d(TAG) { "segment finished: ${segment.durationMs}ms" }
        onSegmentFinished?.invoke(segment)
    }

    /**
     * Call after [requestStop]. If the recorder had already moved on to the
     * next file when the stop arrived (before its "next file started" callback
     * was delivered), the file it was leaving is a finished part and the new
     * file holds the tail: this makes that switch and returns the finished
     * part. Otherwise the unused next file is wiped and null is returned.
     */
    fun finalizePendingSegment(): VideoSegment? = synchronized(segmentLock) {
        val next = pendingNextFile
        pendingNextFile = null
        val closed = tempFile
        when {
            next == null -> null
            closed == null || !next.exists() || next.length() == 0L -> {
                secureDeleteFile(next)
                null
            }
            else -> {
                tempFile = next
                VideoSegment(closed.absolutePath, maxOf(0L, System.currentTimeMillis() - segmentStartMs))
            }
        }
    }

    fun secureDeleteTempFile() {
        val temp = tempFile ?: return
        tempFile = null
        secureDeleteFile(temp)
    }
}
