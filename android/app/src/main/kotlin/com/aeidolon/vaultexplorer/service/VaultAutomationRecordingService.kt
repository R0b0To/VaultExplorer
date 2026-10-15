package com.aeidolon.vaultexplorer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.audiocapture.VaultAudioRecorder
import com.aeidolon.vaultexplorer.automation.VaultAutomationCaptureBridge
import com.aeidolon.vaultexplorer.camera.VaultChunkWriter
import com.aeidolon.vaultexplorer.camera.VaultHeadlessCameraSession
import com.aeidolon.vaultexplorer.camera.VaultVideoQuality
import com.aeidolon.vaultexplorer.camera.VaultVideoRecorder
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.util.NotificationLocale
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "VaultAutomationRecordingService"

/**
 * Foreground service (type "camera|microphone") that owns the actual
 * headless camera + encoder session for automation-triggered recording --
 * unlike [VaultCameraRecordingService], which only exists to satisfy the
 * OS's foreground-service requirement for a recording the *UI* already
 * owns, this service *is* the recording: nothing else has a camera open,
 * because a broadcast-triggered START_RECORDING has no Activity and no
 * Flutter engine to own one.
 *
 * Started (ACTION_START) and stopped (ACTION_STOP) only by
 * VaultAutomationReceiver, which blocks briefly on
 * [VaultAutomationCaptureBridge] for this service's real outcome before
 * replying on ACTION_AUTOMATION_RESULT -- see that receiver's
 * handleStartRecording/handleStopRecording.
 *
 * A safety cap ([MAX_RECORDING_MS]) auto-stops (finalizing and writing out
 * whatever was captured so far, not discarding it) if STOP_RECORDING never
 * arrives -- an automation profile's trigger condition failing to fire is
 * exactly the kind of thing that shouldn't be able to leave a camera
 * recording indefinitely in the background.
 *
 * The same service also owns audio-only recording (START_AUDIO_RECORDING /
 * STOP_AUDIO_RECORDING), selected by [EXTRA_AUDIO_ONLY]. It deliberately
 * shares this class's single recording slot ([isRecording]) rather than
 * getting a service of its own: "only one automation recording at a time"
 * then holds across video *and* audio for free, with one notification, one
 * safety cap and one wake lock. In that mode the service
 *  - declares only the microphone foreground-service type -- claiming
 *    camera without a camera in use would be wrong, and on Android 14+ it
 *    throws when the camera permission was never granted, which is exactly
 *    the situation of someone who only wants audio (same reasoning as
 *    [VaultCameraRecordingService.EXTRA_AUDIO_ONLY]);
 *  - records with [VaultAudioRecorder] instead of a camera session. All of
 *    its blocking work (opening the mic, and streaming the finished take
 *    into the vault, which for a long recording is the slow part) runs on
 *    [audioExecutor], never on the main thread this service's callbacks
 *    arrive on.
 */
class VaultAutomationRecordingService : Service() {

    companion object {
        private const val CHANNEL_ID = "vault_automation_recording"
        private const val NOTIFICATION_ID = 4203
        private const val WAKE_LOCK_TAG = "com.aeidolon.vaultexplorer:AutomationRecordingWakeLock"
        private const val MAX_RECORDING_MS = 3 * 60 * 60 * 1000L // 3h safety cap, see class doc comment

        const val ACTION_START = "com.aeidolon.vaultexplorer.action.internal.START_AUTOMATION_RECORDING"
        const val ACTION_STOP = "com.aeidolon.vaultexplorer.action.internal.STOP_AUTOMATION_RECORDING"

        const val EXTRA_VOL_ID = "volId"
        const val EXTRA_VAULT_PATH = "vaultPath"
        const val EXTRA_CAMERA_ID = "cameraId"
        const val EXTRA_VIDEO_QUALITY = "videoQuality"     // VaultVideoQuality.name, e.g. "FHD"
        const val EXTRA_RECORD_AUDIO = "recordAudio"
        const val EXTRA_CONTAINER_NAME = "containerName"   // for the notification only
        const val EXTRA_AUDIO_ONLY = "audioOnly"            // true: mic-only recording, no camera session

        @Volatile
        var isRecording: Boolean = false
            private set

        /** The vault URI the current recording is writing into, or null when idle --
         *  lets STOP_RECORDING confirm it's stopping the recording it thinks it is. */
        @Volatile
        var currentVaultUri: String? = null
            private set

        /** True when the recording in progress is audio-only. Meaningful only
         *  while [isRecording]; lets STOP_RECORDING and STOP_AUDIO_RECORDING
         *  each refuse to end the other kind of recording. */
        @Volatile
        var currentIsAudioOnly: Boolean = false
            private set

        @Volatile
        private var instance: VaultAutomationRecordingService? = null

        fun refreshNotification() {
            val service = instance ?: return
            if (!isRecording) return
            service.getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, service.buildNotification())
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var session: VaultHeadlessCameraSession? = null
    private var containerName: String = ""
    private var safetyStopRunnable: Runnable? = null

    // Audio-only mode state; unused (null / defaults) for a video recording.
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private var audioRecorder: VaultAudioRecorder? = null
    private var audioVolId = -1
    private var audioVaultPath = ""
    private val audioStopping = AtomicBoolean(false)
    @Volatile private var audioStopResult: VaultAutomationCaptureBridge.Result? = null
    @Volatile private var destroyed = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        instance = this
        when (intent?.action) {
            ACTION_START -> handleStart(intent)
            ACTION_STOP -> handleStop()
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?) = null

    private fun handleStart(intent: Intent) {
        if (isRecording) {
            // Single-slot by design (see VaultAutomationCaptureBridge's doc
            // comment) -- a second START_RECORDING while one is already
            // running is rejected rather than silently replacing it.
            VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(false, "already recording"))
            return
        }
        val volId = intent.getIntExtra(EXTRA_VOL_ID, -1)
        val vaultPath = intent.getStringExtra(EXTRA_VAULT_PATH)
        val cameraId = intent.getStringExtra(EXTRA_CAMERA_ID)
        val vaultUri = intent.getStringExtra("vaultUri")
        containerName = intent.getStringExtra(EXTRA_CONTAINER_NAME) ?: ""
        val quality = try {
            VaultVideoQuality.valueOf(intent.getStringExtra(EXTRA_VIDEO_QUALITY) ?: VaultVideoQuality.FHD.name)
        } catch (e: Exception) {
            VaultVideoQuality.FHD
        }
        val recordAudio = intent.getBooleanExtra(EXTRA_RECORD_AUDIO, true)
        val audioOnly = intent.getBooleanExtra(EXTRA_AUDIO_ONLY, false)

        // An audio-only recording has no camera, so no camera id to require.
        if (volId == -1 || vaultPath.isNullOrEmpty() || (!audioOnly && cameraId.isNullOrEmpty())) {
            VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(false, "missing required extras"))
            stopSelf()
            return
        }

        currentVaultUri = vaultUri
        currentIsAudioOnly = audioOnly // before buildNotification(), which reads it
        try {
            val serviceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (audioOnly) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                } else {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
            } else {
                0
            }
            ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(), serviceType)
        } catch (e: SecurityException) {
            VeLog.e(TAG, e) { "startForeground failed: ${e.message}" }
            VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(false, "Recording blocked by OS security policy: ${e.message}"))
            stopSelf()
            return
        }
        acquireWakeLock()

        if (audioOnly) {
            startAudioRecording(volId, vaultPath)
            return
        }

        val newSession = VaultHeadlessCameraSession(applicationContext)
        session = newSession
        newSession.openForRecording(cameraId!!, quality, recordAudio) { openOk, openError ->
            if (!openOk) {
                VeLog.e(TAG) { "handleStart: openForRecording failed: $openError" }
                VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(false, openError ?: "open failed"))
                stopSelf()
                return@openForRecording
            }
            newSession.startRecording(volId, vaultPath) { startOk, startError ->
                if (!startOk) {
                    VeLog.e(TAG) { "handleStart: startRecording failed: $startError" }
                    VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(false, startError ?: "start failed"))
                    stopSelf()
                    return@startRecording
                }
                isRecording = true
                scheduleSafetyStop()
                VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(true, null))
            }
        }
    }

    private fun handleStop() {
        if (currentIsAudioOnly) {
            stopAudioRecording()
            return
        }
        val current = session
        if (!isRecording || current == null) {
            VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(false, "not recording"))
            stopSelf()
            return
        }
        cancelSafetyStop()
        current.stopRecordingAndClose { ok, durationMs, error ->
            VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(ok, error, durationMs))
            stopSelf()
        }
    }

    // ── Audio-only recording ────────────────────────────────────────────

    private fun startAudioRecording(volId: Int, vaultPath: String) {
        val recorder = VaultAudioRecorder(applicationContext)
        audioRecorder = recorder
        audioVolId = volId
        audioVaultPath = vaultPath
        audioStopping.set(false)
        audioStopResult = null
        audioExecutor.execute {
            try {
                recorder.start()
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "startAudioRecording: recorder.start failed" }
                VaultAutomationCaptureBridge.complete(
                    VaultAutomationCaptureBridge.Result(false, audioStartError(e)),
                )
                mainHandler.post { stopSelf() }
                return@execute
            }
            mainHandler.post {
                if (destroyed) {
                    // The service was torn down (panic purge, system) while the
                    // mic was opening. onDestroy already queued a cancel, but
                    // isRecording must not be left latched true by a recording
                    // nobody owns any more -- it would answer every later
                    // START with BUSY until the process died.
                    VaultAutomationCaptureBridge.complete(
                        VaultAutomationCaptureBridge.Result(false, "recording service stopped while starting"),
                    )
                    return@post
                }
                isRecording = true
                scheduleSafetyStop()
                VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(true, null))
            }
        }
    }

    /**
     * Classifies a [VaultAudioRecorder.start] failure into the same string
     * vocabulary the camera path reports (see
     * VaultAutomationReceiver.outcomeForAudioError). An IOException means
     * the temp file or encoder could not be prepared -- a storage problem,
     * not the microphone being unavailable -- so it stays a plain error.
     */
    private fun audioStartError(e: Exception): String = when (e) {
        is SecurityException -> "permission_denied"
        is IOException -> "audio recorder setup failed: ${e.message}"
        else -> "mic_unavailable: ${e.message}"
    }

    /**
     * Ends an audio recording: finalizes the M4A, streams it into the vault
     * and wipes the plaintext temp file, then reports the outcome and stops
     * the service. Runs on [audioExecutor]; guarded so the safety cap, the
     * notification's Stop button and a STOP_AUDIO_RECORDING arriving close
     * together can't finalize the same take twice.
     *
     * A failed vault write wipes the take rather than leaving it behind, the
     * same as the video path: there is no UI here to retry from, and a
     * plaintext recording sitting in the cache indefinitely is exactly what
     * this app exists to avoid.
     */
    private fun stopAudioRecording() {
        val recorder = audioRecorder
        if (!isRecording || recorder == null) {
            VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(false, "not recording"))
            stopSelf()
            return
        }
        if (!audioStopping.compareAndSet(false, true)) {
            // A stop is already finalizing (e.g. the notification's Stop button
            // tapped during a STOP_AUDIO_RECORDING). The bridge is a single
            // slot, so completing it here with a failure would answer the
            // waiting broadcast "failed" even though the in-flight save is
            // about to succeed. Stay quiet and let that stop report for
            // itself; if it has already finished, repeat its real outcome.
            audioStopResult?.let { VaultAutomationCaptureBridge.complete(it) }
            return
        }
        cancelSafetyStop()
        val volId = audioVolId
        val vaultPath = audioVaultPath
        audioExecutor.execute {
            var ok = false
            var durationMs = 0L
            var error: String? = null
            try {
                val take = recorder.stop() // throws (and wipes) if nothing usable was captured
                durationMs = take.durationMs
                // streamFileToSinkAndWipe wipes the temp file whether or not
                // the write succeeds. finishWrite is the commit step
                // directory vaults (Cryptomator/gocryptfs/CryFS) need and the
                // in-app path leaves to Dart -- there is no Dart layer here.
                ok = VaultVideoRecorder.streamFileToSinkAndWipe(take.file, VaultChunkWriter(volId, vaultPath)) &&
                    ContainerFileSystem.finishWrite(volId, vaultPath)
                if (!ok) error = "vault write failed"
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "stopAudioRecording failed" }
                error = e.message ?: "stop failed"
            }
            val result = VaultAutomationCaptureBridge.Result(ok, error, durationMs)
            audioStopResult = result
            VaultAutomationCaptureBridge.complete(result)
            mainHandler.post { stopSelf() }
        }
    }

    private fun scheduleSafetyStop() {
        val runnable = Runnable {
            VeLog.w(TAG) { "MAX_RECORDING_MS ($MAX_RECORDING_MS ms) reached -- auto-stopping and saving" }
            handleStop()
        }
        safetyStopRunnable = runnable
        mainHandler.postDelayed(runnable, MAX_RECORDING_MS)
    }

    private fun cancelSafetyStop() {
        safetyStopRunnable?.let { mainHandler.removeCallbacks(it) }
        safetyStopRunnable = null
    }

    override fun onDestroy() {
        destroyed = true
        if (instance === this) instance = null
        cancelSafetyStop()
        session?.closeAll()
        session = null
        audioRecorder?.let { recorder ->
            // Wiping zero-fills the whole take, which for a long recording is
            // too slow for the main thread. Queued behind any start/stop
            // already running on audioExecutor, and a no-op when stop() has
            // already detached the take. shutdown() still lets it run.
            audioExecutor.execute { recorder.cancel() }
        }
        audioRecorder = null
        audioExecutor.shutdown()
        isRecording = false
        currentIsAudioOnly = false
        currentVaultUri = null
        releaseWakeLock()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        val lock = wakeLock ?: pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            .apply { setReferenceCounted(false) }
            .also { wakeLock = it }
        if (!lock.isHeld) lock.acquire(MAX_RECORDING_MS + 5 * 60 * 1000L /* buffer past the safety cap */)
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun currentIdentityLabel(): String =
        if (DisguiseModeHandlers.isDecoyActive(this)) {
            NotificationLocale.wrap(this).getString(R.string.decoy_app_name)
        } else {
            NotificationLocale.wrap(this).getString(R.string.app_name)
        }

    private fun ensureChannel() {
        val identity = currentIdentityLabel()
        val localized = NotificationLocale.wrap(this)
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(CHANNEL_ID, identity, NotificationManager.IMPORTANCE_LOW).apply {
            description = localized.getString(R.string.camera_recording_channel_description)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun getContentIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    // Lets the user stop an automation-triggered recording by hand, in case
    // whatever was supposed to send STOP_RECORDING never does. Unlike
    // VaultCameraRecordingService's stop action (which has to round-trip
    // through Dart to finalize/encrypt), this service owns the whole
    // capture pipeline itself, so the button can target ACTION_STOP
    // directly -- VaultAutomationCaptureBridge.complete() still fires from
    // handleStop() when this runs, it just lands with nothing awaiting it
    // (the original START_RECORDING broadcast's reply already went out
    // long ago), which is harmless: completing an already-counted-down
    // latch is a no-op.
    private fun getStopIntent(): PendingIntent = PendingIntent.getService(
        this,
        0,
        Intent(this, VaultAutomationRecordingService::class.java).setAction(ACTION_STOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    // Reuses VaultCameraRecordingService's own notification strings/icons --
    // "a recording is in progress" reads the same to the user regardless of
    // what triggered it, so this deliberately doesn't add a second set of
    // near-duplicate string resources across every supported locale. The
    // audio-only title/icon are the ones its audio mode already uses.
    private fun buildNotification(): Notification {
        ensureChannel()
        val localized = NotificationLocale.wrap(this)
        val decoyActive = DisguiseModeHandlers.isDecoyActive(this)
        val contentTitle: String
        val contentText: String
        val actionLabel: String
        val smallIcon: Int
        if (decoyActive) {
            contentTitle = localized.getString(R.string.decoy_app_name)
            contentText = localized.getString(R.string.camera_recording_notification_text_decoy)
            actionLabel = localized.getString(R.string.camera_recording_stop_action_decoy)
            smallIcon = R.drawable.ic_notification_folder
        } else {
            val audioOnly = currentIsAudioOnly
            contentTitle = localized.getString(
                if (audioOnly) R.string.audio_recording_notification_title
                else R.string.camera_recording_notification_title,
            )
            contentText = localized.getString(R.string.camera_recording_notification_text, containerName)
            actionLabel = localized.getString(R.string.camera_recording_stop_action)
            smallIcon = if (audioOnly) R.drawable.ic_notification_mic else R.drawable.ic_notification_camera
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle(contentTitle)
            .setContentText(contentText)
            .setContentIntent(getContentIntent())
            .addAction(0, actionLabel, getStopIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .build()
    }
}
