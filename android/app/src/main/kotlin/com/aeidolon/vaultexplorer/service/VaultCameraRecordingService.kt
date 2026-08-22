package com.aeidolon.vaultexplorer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.bridge.VaultCameraStopRequestedBridge
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers

/**
 * Foreground service (type "camera|microphone") that keeps an in-progress
 * video recording alive when the screen turns off or the app is
 * backgrounded, instead of the recording being cut short.
 *
 * This exists only because the OS requires it: starting with Android 9,
 * an app that isn't in the foreground has its camera/mic connection torn
 * down by the system the moment it's backgrounded, *unless* the process
 * is running an active foreground service of the matching type. This
 * service's job is exactly that -- and nothing else. The actual
 * CameraDevice/recorder session it's protecting lives in
 * VaultCameraPlugin/VaultCameraSession (still owned by the Activity's
 * application context), which CameraCaptureScreen deliberately leaves
 * open rather than closing while this service is running -- see
 * CameraCaptureScreen._handleGoingInactive() in Dart.
 *
 * Only started when the "lock vaults on screen lock" setting is off for
 * the container being recorded into -- if it's on, the screen turning
 * off is expected to lock (and therefore should stop) the recording
 * instead, so this service is never started for that case.
 *
 * A partial wake lock is held for the service's lifetime so CPU-bound
 * encoding work isn't starved by Doze/App Standby on stricter OEM power
 * managers; the foreground-service exemption alone isn't reliable enough
 * across devices for something as continuous as video encoding.
 */
class VaultCameraRecordingService : Service() {

    companion object {
        private const val CHANNEL_ID = "vault_camera_recording"
        private const val NOTIFICATION_ID = 4202
        private const val WAKE_LOCK_TAG = "com.aeidolon.vaultexplorer:CameraRecordingWakeLock"

        /** Fired by the notification's action button. */
        const val ACTION_STOP_RECORDING = "com.aeidolon.vaultexplorer.action.STOP_BACKGROUND_RECORDING"

        const val EXTRA_VOL_ID = "volId"
        const val EXTRA_CONTAINER_NAME = "containerName"

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var currentVolId: Int = -1
    private var currentContainerName: String = ""
    private var lastChannelIdentity: String? = null
    private var cachedContentIntent: PendingIntent? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_RECORDING) {
            // Don't stop the service here -- the recording isn't actually
            // finalized/encrypted yet. Dart calls stopBackgroundRecording()
            // once _stopVideoRecording() completes, which is what tears
            // this service down (see the finally block there).
            VaultCameraStopRequestedBridge.reportStopRequested(currentVolId)
            startForeground(NOTIFICATION_ID, buildNotification())
            return START_NOT_STICKY
        }

        intent?.getIntExtra(EXTRA_VOL_ID, -1)?.let { if (it != -1) currentVolId = it }
        intent?.getStringExtra(EXTRA_CONTAINER_NAME)?.let { currentContainerName = it }

        startForeground(NOTIFICATION_ID, buildNotification())
        wakeLock?.let { if (!it.isHeld) it.acquire(6 * 60 * 60 * 1000L /* 6h safety cap */) }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        isRunning = false
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        currentVolId = -1
        currentContainerName = ""
        lastChannelIdentity = null
        cachedContentIntent = null
        super.onDestroy()
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
        val channel = NotificationChannel(
            CHANNEL_ID,
            identity,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.camera_recording_channel_description)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun getContentIntent(): PendingIntent {
        var pi = cachedContentIntent
        if (pi == null) {
            pi = PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            cachedContentIntent = pi
        }
        return pi
    }

    private fun getStopIntent(): PendingIntent = PendingIntent.getService(
        this,
        0,
        Intent(this, VaultCameraRecordingService::class.java).setAction(ACTION_STOP_RECORDING),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun buildNotification(): Notification {
        ensureChannel()
        val decoyActive = DisguiseModeHandlers.isDecoyActive(this)

        val contentTitle: String
        val contentText: String
        val actionLabel: String
        val smallIcon: Int
        if (decoyActive) {
            // Never reveal that a recording is in progress while decoy
            // mode is active -- same rationale as VaultKeepAliveService's
            // decoy text.
            contentTitle = getString(R.string.decoy_app_name)
            contentText = getString(R.string.camera_recording_notification_text_decoy)
            actionLabel = getString(R.string.camera_recording_stop_action_decoy)
            smallIcon = R.drawable.ic_notification_folder
        } else {
            contentTitle = getString(R.string.camera_recording_notification_title)
            contentText = getString(R.string.camera_recording_notification_text, currentContainerName)
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
