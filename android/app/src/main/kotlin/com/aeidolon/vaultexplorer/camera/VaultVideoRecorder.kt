package com.aeidolon.vaultexplorer.camera

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.view.Surface
import com.aeidolon.vaultexplorer.ContainerFileSystem
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile

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

class VaultVideoRecorder(
    private val width: Int,
    private val height: Int,
    private val quality: VaultVideoQuality,
    private val recordAudio: Boolean = true,
    private val cacheDir: File? = null,
) {
    var inputSurface: Surface? = null
        private set

    private var mediaRecorder: MediaRecorder? = null
    private var tempFile: File? = null
    private var startTimeMs: Long = 0L
    private var stopTimeMs: Long = 0L

    fun prepareEncoder() {
        releaseEncoder()
        val temp = File.createTempFile("vx_vid_", ".mp4", cacheDir)
        tempFile = temp

        @Suppress("DEPRECATION")
        val recorder = MediaRecorder()

        if (recordAudio) {
            recorder.setAudioSource(MediaRecorder.AudioSource.CAMCORDER)
        }
        recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        if (recordAudio) {
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(128_000)
            recorder.setAudioSamplingRate(44100)
        }
        recorder.setVideoSize(width, height)
        recorder.setVideoEncodingBitRate(quality.bitrate)
        recorder.setVideoFrameRate(30)
        recorder.setOutputFile(temp.absolutePath)

        recorder.prepare()
        inputSurface = recorder.surface
        mediaRecorder = recorder
    }

    fun beginRecording(orientationDegrees: Int) {
        val recorder = mediaRecorder ?: throw IllegalStateException("Encoder not prepared")
        recorder.setOrientationHint(orientationDegrees)
        recorder.start()
        startTimeMs = System.currentTimeMillis()
    }

    fun requestStop(): RecordingResult {
        val recorder = mediaRecorder ?: return RecordingResult(0)
        stopTimeMs = System.currentTimeMillis()
        try {
            recorder.stop()
        } catch (e: Exception) {
            android.util.Log.e("VaultVideoRecorder", "MediaRecorder.stop failed", e)
        }
        val duration = maxOf(0L, stopTimeMs - startTimeMs)
        return RecordingResult(duration)
    }

    fun writeTo(writer: VaultChunkWriter): Boolean {
        val temp = tempFile ?: return false
        if (!temp.exists() || temp.length() == 0L) return false

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
            android.util.Log.e("VaultVideoRecorder", "writeTo failed", e)
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
        try {
            if (temp.exists()) {
                val len = temp.length()
                if (len > 0) {
                    RandomAccessFile(temp, "rws").use { raf ->
                        val zeros = ByteArray(64 * 1024)
                        var remaining = len
                        while (remaining > 0) {
                            val writeLen = minOf(remaining, zeros.size.toLong()).toInt()
                            raf.write(zeros, 0, writeLen)
                            remaining -= writeLen
                        }
                    }
                }
                temp.delete()
            }
        } catch (_: Exception) {
            try { temp.delete() } catch (_: Exception) {}
        }
    }
}
