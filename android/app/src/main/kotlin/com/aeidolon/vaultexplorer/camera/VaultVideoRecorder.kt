package com.aeidolon.vaultexplorer.camera

import android.content.Context
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Build
import android.view.Surface
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import com.aeidolon.vaultexplorer.VeLog

class VaultChunkWriter(
    private val volId: Int,
    private val virtualPath: String
) {
    private var currentOffset: Long = 0L

    fun write(data: ByteArray): Boolean {
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
    fun writeAndDrain(bytes: ByteArray, writer: VaultChunkWriter): Boolean {
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
) {
    companion object {
        private const val TEMP_PREFIX = "vx_vid_"
        private const val TEMP_SUFFIX = ".mp4"

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
        internal fun secureDeleteFile(file: File): Boolean {
            return try {
                if (file.exists()) {
                    val len = file.length()
                    if (len > 0) {
                        RandomAccessFile(file, "rws").use { raf ->
                            val zeros = ByteArray(64 * 1024)
                            var remaining = len
                            while (remaining > 0) {
                                val writeLen = minOf(remaining, zeros.size.toLong()).toInt()
                                raf.write(zeros, 0, writeLen)
                                remaining -= writeLen
                            }
                        }
                    }
                    file.delete()
                } else {
                    true
                }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "secureDeleteFile failed" }
                try { file.delete() } catch (_: Exception) {}
                false
            }
        }
    }

    var inputSurface: Surface? = null
        private set

    private var mediaRecorder: MediaRecorder? = null
    private var tempFile: File? = null
    private var startTimeMs: Long = 0L
    private var stopTimeMs: Long = 0L

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

    fun writeTo(writer: VaultChunkWriter): Boolean {
        val temp = tempFile ?: return false
        if (!temp.exists() || temp.length() == 0L) {
            VeLog.e(TAG) { "writeTo: temp file missing or empty (exists=${temp.exists()}, len=${temp.length()})" }
            return false
        }
        VeLog.d(TAG) { "writeTo: streaming ${temp.length()} bytes to vault" }

        try {
            FileInputStream(temp).use { fis ->
                val buffer = ByteArray(64 * 1024)
                var bytesRead: Int
                while (fis.read(buffer).also { bytesRead = it } != -1) {
                    if (bytesRead > 0) {
                        val chunk = if (bytesRead == buffer.size) buffer else buffer.copyOf(bytesRead)
                        if (!writer.write(chunk)) {
                            return false
                        }
                    }
                }
            }
            return true
        } catch (e: Exception) {
            VeLog.e("VaultVideoRecorder", e) { "writeTo failed" }
            return false
        } finally {
            secureDeleteTempFile()
        }
    }

    fun releaseEncoder() {
        try {
            mediaRecorder?.reset()
            mediaRecorder?.release()
        } catch (_: Exception) {}
        mediaRecorder = null
        inputSurface = null
        secureDeleteTempFile()
    }

    private fun secureDeleteTempFile() {
        val temp = tempFile ?: return
        tempFile = null
        secureDeleteFile(temp)
    }
}