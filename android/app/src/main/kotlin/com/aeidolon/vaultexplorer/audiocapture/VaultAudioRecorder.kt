package com.aeidolon.vaultexplorer.audiocapture

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.media.MediaRecorder
import android.os.Build
import android.os.SystemClock
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.camera.VaultVideoRecorder
import java.io.File

private const val TAG = "VaultAudioRecorder"

internal const val AUDIO_TEMP_PREFIX = "vx_aud_"
internal const val AUDIO_TEMP_SUFFIX = ".m4a"

data class AudioRecordingResult(val file: File, val durationMs: Long)

/**
 * Audio-only counterpart of [VaultVideoRecorder]: records the microphone
 * to a temporary AAC/M4A file in the app cache directory, which the caller
 * then reviews and either streams into a vault or wipes.
 *
 * It follows the exact same at-rest model as the video recorder -- a
 * plaintext temp file that exists only between "start" and
 * "save"/"discard", zero-filled before deletion (see
 * [VaultVideoRecorder.secureDeleteFile]) and swept at app startup if a
 * process death orphaned one (see [sweepOrphanedTempFiles]). MediaRecorder
 * needs a seekable file to write the MP4 `moov` atom on stop, so streaming
 * straight into a vault while recording isn't an option here either.
 *
 * Public methods are safe to call from different threads. Nothing blocking
 * ever runs while the instance lock is held: [stop] only detaches state
 * under the lock and finalizes the file outside it, so [amplitude] polling
 * from the UI thread can never stall behind a stop.
 */
class VaultAudioRecorder(private val context: Context) {

    enum class State { IDLE, RECORDING, PAUSED }

    companion object {
        /**
         * Whether RECORD_AUDIO is granted. Audio-only capture needs nothing
         * else -- notably not CAMERA, which [com.aeidolon.vaultexplorer.camera.VaultHeadlessCameraSession.hasPermissions]
         * also demands and which someone who only records audio may never
         * have granted.
         */
        fun hasMicPermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED

        /**
         * Wipes recording temp files left behind by a previous process
         * death -- same rationale and same startup call site as
         * [VaultVideoRecorder.sweepOrphanedTempFiles]. Returns how many
         * files were wiped, for logging.
         */
        fun sweepOrphanedTempFiles(cacheDir: File?): Int {
            val dir = cacheDir ?: return 0
            val orphans = dir.listFiles { f ->
                f.isFile && f.name.startsWith(AUDIO_TEMP_PREFIX) && f.name.endsWith(AUDIO_TEMP_SUFFIX)
            } ?: return 0
            var wiped = 0
            for (file in orphans) {
                if (VaultVideoRecorder.secureDeleteFile(file)) wiped++
            }
            if (wiped > 0) {
                VeLog.i(TAG) { "sweepOrphanedTempFiles: wiped $wiped orphaned audio temp file(s)" }
            }
            return wiped
        }
    }

    private class Detached(val recorder: MediaRecorder, val file: File, val wallMs: Long)

    private val lock = Any()
    private var recorder: MediaRecorder? = null
    private var tempFile: File? = null
    private var segmentStartMs = 0L
    private var accumulatedMs = 0L

    @Volatile
    private var errorWhat: Int? = null

    @Volatile
    var state: State = State.IDLE
        private set

    /** Starts a new recording with [params] (bitrate / sample rate, mono AAC).
     *  Throws if one is already in progress, or if the platform refuses to
     *  open the microphone. */
    fun start(params: AudioRecordingParams = AudioRecordingParams.DEFAULT) {
        synchronized(lock) {
            check(state == State.IDLE) { "already recording" }
        }
        val temp = File.createTempFile(AUDIO_TEMP_PREFIX, AUDIO_TEMP_SUFFIX, context.cacheDir)
        val rec = createMediaRecorder()
        try {
            errorWhat = null
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setAudioEncodingBitRate(params.bitrate)
            rec.setAudioSamplingRate(params.sampleRate)
            rec.setAudioChannels(1)
            rec.setOutputFile(temp.absolutePath)
            rec.setOnErrorListener { _, what, extra ->
                // Fires for things like the media server dying or the mic
                // being taken over (incoming call). The take is unusable
                // from here, so stop() reports failure instead of handing
                // back a truncated file as if it were good.
                errorWhat = what
                VeLog.e(TAG) { "MediaRecorder error what=$what extra=$extra" }
            }
            rec.prepare()
            rec.start()
        } catch (e: Exception) {
            releaseQuietly(rec)
            VaultVideoRecorder.secureDeleteFile(temp)
            throw e
        }
        synchronized(lock) {
            recorder = rec
            tempFile = temp
            accumulatedMs = 0L
            segmentStartMs = SystemClock.elapsedRealtime()
            state = State.RECORDING
        }
        VeLog.d(TAG) { "start: recording to temp file (${params.bitrate / 1000} kbps, ${params.sampleRate} Hz, mono)" }
    }

    fun pause() {
        synchronized(lock) {
            val rec = recorder ?: throw IllegalStateException("not recording")
            if (state != State.RECORDING) return
            rec.pause()
            accumulatedMs += SystemClock.elapsedRealtime() - segmentStartMs
            state = State.PAUSED
        }
    }

    fun resume() {
        synchronized(lock) {
            val rec = recorder ?: throw IllegalStateException("not recording")
            if (state != State.PAUSED) return
            rec.resume()
            segmentStartMs = SystemClock.elapsedRealtime()
            state = State.RECORDING
        }
    }

    /** Peak amplitude since the previous call, 0..32767. 0 whenever nothing
     *  is actively recording. */
    fun amplitude(): Int {
        synchronized(lock) {
            val rec = recorder ?: return 0
            if (state != State.RECORDING) return 0
            return try {
                rec.maxAmplitude
            } catch (_: Exception) {
                0
            }
        }
    }

    /**
     * Stops recording and returns the finished temp file. On any failure the
     * partial file is wiped and an exception is thrown -- the caller never
     * receives a path to a corrupt take.
     */
    fun stop(): AudioRecordingResult {
        val detached = synchronized(lock) {
            val rec = recorder ?: throw IllegalStateException("not recording")
            val file = tempFile ?: throw IllegalStateException("no temp file")
            val wall = accumulatedMs +
                if (state == State.RECORDING) SystemClock.elapsedRealtime() - segmentStartMs else 0L
            recorder = null
            tempFile = null
            state = State.IDLE
            Detached(rec, file, wall)
        }

        var stopped = true
        try {
            detached.recorder.stop()
        } catch (e: RuntimeException) {
            // MediaRecorder.stop() throws when no valid audio data was
            // captured (stopped right after start, mic never delivered).
            stopped = false
            VeLog.w(TAG, e) { "MediaRecorder.stop failed" }
        } finally {
            releaseQuietly(detached.recorder)
        }

        val failedWith = errorWhat
        if (!stopped || failedWith != null || !detached.file.exists() || detached.file.length() == 0L) {
            VaultVideoRecorder.secureDeleteFile(detached.file)
            throw IllegalStateException(
                if (failedWith != null) "recorder error $failedWith" else "no audio was captured",
            )
        }

        val duration = probeDurationMs(detached.file) ?: detached.wallMs
        VeLog.d(TAG) { "stop: ${detached.file.length()} bytes, ${duration}ms" }
        return AudioRecordingResult(detached.file, duration)
    }

    /** Aborts any in-progress recording and wipes its file. Safe to call
     *  when idle. */
    fun cancel() {
        val detached = synchronized(lock) {
            val rec = recorder
            val file = tempFile
            recorder = null
            tempFile = null
            state = State.IDLE
            if (rec != null && file != null) Detached(rec, file, 0L) else null
        } ?: return
        try {
            detached.recorder.stop()
        } catch (_: Exception) {
        }
        releaseQuietly(detached.recorder)
        VaultVideoRecorder.secureDeleteFile(detached.file)
    }

    private fun createMediaRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

    private fun releaseQuietly(rec: MediaRecorder) {
        try {
            rec.reset()
        } catch (_: Exception) {
        }
        try {
            rec.release()
        } catch (_: Exception) {
        }
    }

    /** The muxed file's own duration is more accurate than wall-clock time
     *  (which includes the encoder's startup latency). Falls back to the
     *  wall clock if the retriever can't read it. */
    private fun probeDurationMs(file: File): Long? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?.takeIf { it > 0 }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "duration probe failed" }
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }
}
