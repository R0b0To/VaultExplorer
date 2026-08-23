package com.aeidolon.vaultexplorer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.automation.VaultAutomationCaptureBridge
import com.aeidolon.vaultexplorer.camera.VaultHeadlessCameraSession
import com.aeidolon.vaultexplorer.camera.VaultVideoQuality
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers
import com.aeidolon.vaultexplorer.VeLog

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

        @Volatile
        var isRecording: Boolean = false
            private set

        /** The vault URI the current recording is writing into, or null when idle --
         *  lets STOP_RECORDING confirm it's stopping the recording it thinks it is. */
        @Volatile
        var currentVaultUri: String? = null
            private set
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var session: VaultHeadlessCameraSession? = null
    private var containerName: String = ""
    private var lastChannelIdentity: String? = null
    private var safetyStopRunnable: Runnable? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
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

        if (volId == -1 || vaultPath.isNullOrEmpty() || cameraId.isNullOrEmpty()) {
            VaultAutomationCaptureBridge.complete(VaultAutomationCaptureBridge.Result(false, "missing required extras"))
            stopSelf()
            return
        }

        currentVaultUri = vaultUri
        startForeground(NOTIFICATION_ID, buildNotification())
        acquireWakeLock()

        val newSession = VaultHeadlessCameraSession(applicationContext)
        session = newSession
        newSession.openForRecording(cameraId, quality, recordAudio) { openOk, openError ->
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
        cancelSafetyStop()
        session?.closeAll()
        session = null
        isRecording = false
        currentVaultUri = null
        releaseWakeLock()
        lastChannelIdentity = null
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
            getString(R.string.decoy_app_name)
        } else {
            getString(R.string.app_name)
        }

    private fun ensureChannel() {
        val identity = currentIdentityLabel()
        if (identity == lastChannelIdentity) return
        lastChannelIdentity = identity
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(CHANNEL_ID, identity, NotificationManager.IMPORTANCE_LOW).apply {
            description = getString(R.string.camera_recording_channel_description)
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
    // near-duplicate string resources across every supported locale.
    private fun buildNotification(): Notification {
        ensureChannel()
        val decoyActive = DisguiseModeHandlers.isDecoyActive(this)
        val contentTitle: String
        val contentText: String
        val actionLabel: String
        val smallIcon: Int
        if (decoyActive) {
            contentTitle = getString(R.string.decoy_app_name)
            contentText = getString(R.string.camera_recording_notification_text_decoy)
            actionLabel = getString(R.string.camera_recording_stop_action_decoy)
            smallIcon = R.drawable.ic_notification_folder
        } else {
            contentTitle = getString(R.string.camera_recording_notification_title)
            contentText = getString(R.string.camera_recording_notification_text, containerName)
            actionLabel = getString(R.string.camera_recording_stop_action)
            smallIcon = R.drawable.ic_notification_camera
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
