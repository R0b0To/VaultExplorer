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
import java.util.concurrent.ConcurrentLinkedQueue

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
        // MediaRecorder cannot honour a tiny size limit; never ask for less.
        private const val MIN_SEGMENT_BYTES = 128L * 1024

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

    private class Detached(
        val recorder: MediaRecorder,
        val file: File,
        val wallMs: Long,
        val pendingNext: File?,
    )

    /** A closed part whose duration has not been measured yet. */
    private class FinishedPart(val file: File, val wallMs: Long)

    private val lock = Any()
    private var recorder: MediaRecorder? = null
    private var tempFile: File? = null
    private var segmentStartMs = 0L
    private var accumulatedMs = 0L

    // --- Segmented recording -------------------------------------------------
    /** File handed to setNextOutputFile that the recorder has not switched to yet. */
    private var pendingNextFile: File? = null

    /** Recorded time (pauses excluded) at the moment the current part began. */
    private var partStartRecordedMs = 0L

    /** Closed parts that have not been collected by [takeSegments] yet. */
    private val finishedParts = ConcurrentLinkedQueue<FinishedPart>()

    /** How many parts have been closed since [start], collected or not. */
    @Volatile
    private var closedPartCount = 0

    @Volatile
    private var errorWhat: Int? = null

    @Volatile
    var state: State = State.IDLE
        private set

    /** Starts a new recording with [params] (bitrate / sample rate, mono AAC).
     *  Throws if one is already in progress, or if the platform refuses to
     *  open the microphone. */
    fun start(params: AudioRecordingParams = AudioRecordingParams.DEFAULT, segmentSeconds: Int = 0) {
        synchronized(lock) {
            check(state == State.IDLE) { "already recording" }
        }
        discardFinishedParts()
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
            if (segmentSeconds > 0) {
                // The part length is enforced as a file size, which is what
                // MediaRecorder can roll over on without dropping audio.
                val maxBytes = ((params.bitrate / 8L) * segmentSeconds).coerceAtLeast(MIN_SEGMENT_BYTES)
                rec.setMaxFileSize(maxBytes)
                rec.setOnInfoListener { mr, what, _ -> onRecorderInfo(mr, what) }
            }
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
            pendingNextFile = null
            partStartRecordedMs = 0L
            closedPartCount = 0
            accumulatedMs = 0L
            segmentStartMs = SystemClock.elapsedRealtime()
            state = State.RECORDING
        }
        VeLog.d(TAG) { "start: recording to temp file (${params.bitrate / 1000} kbps, ${params.sampleRate} Hz, mono, segmentSeconds=$segmentSeconds)" }
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
    fun stop(): AudioRecordingResult =
        stopAllowingEmptyLastPart() ?: throw IllegalStateException("no audio was captured")

    /**
     * Like [stop], for segmented recordings: returns the last part (earlier
     * parts come from [takeSegments]). A segmented recording that already
     * closed at least one part has good earlier parts, so when its last part
     * turns out empty or unusable this returns null instead of throwing.
     * Without any closed part it behaves exactly like [stop].
     */
    fun stopAllowingEmptyLastPart(): AudioRecordingResult? {
        val detached = synchronized(lock) {
            val rec = recorder ?: throw IllegalStateException("not recording")
            val file = tempFile ?: throw IllegalStateException("no temp file")
            val wall = accumulatedMs +
                if (state == State.RECORDING) SystemClock.elapsedRealtime() - segmentStartMs else 0L
            val pending = pendingNextFile
            recorder = null
            tempFile = null
            pendingNextFile = null
            state = State.IDLE
            Detached(rec, file, wall, pending)
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

        // If the recorder had already switched to the next part when the stop
        // arrived (before its callback was delivered), the part it left is
        // finished and the new file holds the tail. The two lengths cannot be
        // told apart from here, so the time since the part began stands in for
        // both; it only matters if measuring the files fails.
        var lastFile = detached.file
        val sincePartStartMs = (detached.wallMs - partStartRecordedMs).coerceAtLeast(0L)
        var lastWallMs = if (closedPartCount > 0) sincePartStartMs else detached.wallMs
        val pending = detached.pendingNext
        if (pending != null) {
            if (stopped && pending.exists() && pending.length() > 0L) {
                finishedParts.add(FinishedPart(detached.file, sincePartStartMs))
                closedPartCount++
                lastFile = pending
                lastWallMs = sincePartStartMs
            } else {
                VaultVideoRecorder.secureDeleteFile(pending)
            }
        }

        val failedWith = errorWhat
        if (!stopped || failedWith != null || !lastFile.exists() || lastFile.length() == 0L) {
            VaultVideoRecorder.secureDeleteFile(lastFile)
            if (closedPartCount > 0) {
                VeLog.w(TAG) { "stop: last part unusable, keeping $closedPartCount earlier part(s)" }
                return null
            }
            throw IllegalStateException(
                if (failedWith != null) "recorder error $failedWith" else "no audio was captured",
            )
        }

        val duration = probeDurationMs(lastFile) ?: lastWallMs
        VeLog.d(TAG) { "stop: ${lastFile.length()} bytes, ${duration}ms" }
        return AudioRecordingResult(lastFile, duration)
    }

    /** Aborts any in-progress recording and wipes its file, any part that was
     *  closed but not collected yet, and the file waiting to be switched to.
     *  Safe to call when idle. */
    fun cancel() {
        val detached = synchronized(lock) {
            val rec = recorder
            val file = tempFile
            val pending = pendingNextFile
            recorder = null
            tempFile = null
            pendingNextFile = null
            state = State.IDLE
            if (rec != null && file != null) Detached(rec, file, 0L, pending) else null
        }
        discardFinishedParts()
        if (detached == null) return
        try {
            detached.recorder.stop()
        } catch (_: Exception) {
        }
        releaseQuietly(detached.recorder)
        VaultVideoRecorder.secureDeleteFile(detached.file)
        detached.pendingNext?.let { VaultVideoRecorder.secureDeleteFile(it) }
    }

    /**
     * Hands over (and forgets) every part closed since the last call, oldest
     * first, each as a finished, playable file. Blocks on file I/O (it measures
     * each part's duration), so call it off the main thread.
     */
    fun takeSegments(): List<AudioRecordingResult> {
        val out = ArrayList<AudioRecordingResult>()
        while (true) {
            val part = finishedParts.poll() ?: break
            if (!part.file.exists() || part.file.length() == 0L) {
                VaultVideoRecorder.secureDeleteFile(part.file)
                continue
            }
            out.add(AudioRecordingResult(part.file, probeDurationMs(part.file) ?: part.wallMs))
        }
        return out
    }

    /** True once at least one part of a segmented recording has been closed. */
    val hasClosedParts: Boolean get() = closedPartCount > 0

    private fun discardFinishedParts() {
        while (true) {
            val part = finishedParts.poll() ?: break
            VaultVideoRecorder.secureDeleteFile(part.file)
        }
    }

    // MediaRecorder info callback. Runs on the thread that started the
    // recording (the platform channel's), and only touches in-memory state
    // and a new empty temp file.
    private fun onRecorderInfo(rec: MediaRecorder, what: Int) {
        when (what) {
            MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_APPROACHING -> {
                synchronized(lock) {
                    if (recorder === rec && pendingNextFile == null) {
                        val next = try {
                            File.createTempFile(AUDIO_TEMP_PREFIX, AUDIO_TEMP_SUFFIX, context.cacheDir)
                        } catch (e: Exception) {
                            VeLog.e(TAG, e) { "could not create the next part file" }
                            null
                        }
                        if (next != null) {
                            try {
                                rec.setNextOutputFile(next)
                                pendingNextFile = next
                            } catch (e: Exception) {
                                VeLog.e(TAG, e) { "setNextOutputFile failed" }
                                VaultVideoRecorder.secureDeleteFile(next)
                            }
                        }
                    }
                }
            }
            MediaRecorder.MEDIA_RECORDER_INFO_NEXT_OUTPUT_FILE_STARTED -> {
                synchronized(lock) {
                    val closed = tempFile
                    val next = pendingNextFile
                    if (recorder === rec && closed != null && next != null) {
                        val recordedMs = accumulatedMs +
                            if (state == State.RECORDING) SystemClock.elapsedRealtime() - segmentStartMs else 0L
                        val partMs = (recordedMs - partStartRecordedMs).coerceAtLeast(0L)
                        partStartRecordedMs = recordedMs
                        tempFile = next
                        pendingNextFile = null
                        finishedParts.add(FinishedPart(closed, partMs))
                        closedPartCount++
                        VeLog.d(TAG) { "part $closedPartCount finished (~${partMs}ms)" }
                    }
                }
            }
            MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED ->
                VeLog.w(TAG) { "part size reached without a next file; recorder stopped" }
            else -> Unit
        }
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
