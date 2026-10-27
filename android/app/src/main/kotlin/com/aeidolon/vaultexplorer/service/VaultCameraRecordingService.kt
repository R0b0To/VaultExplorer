package com.aeidolon.vaultexplorer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.bridge.VaultCameraStopRequestedBridge
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers
import com.aeidolon.vaultexplorer.util.NotificationLocale

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
 * The same service also keeps an audio-only recording (see
 * AudioCaptureScreen / VaultAudioCapturePlugin) alive. In that mode
 * [EXTRA_AUDIO_ONLY] is set and the service declares only the microphone
 * type: claiming the camera type without a camera in use would be wrong,
 * and on Android 14+ it fails outright when the camera permission has not
 * been granted -- which is exactly the situation of someone who only wants
 * to record audio.
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
        private const val TAG = "VaultCameraRecordingService"
        private const val CHANNEL_ID = "vault_camera_recording"
        private const val NOTIFICATION_ID = 4202
        private const val WAKE_LOCK_TAG = "com.aeidolon.vaultexplorer:CameraRecordingWakeLock"

        /** Fired by the notification's action button. */
        const val ACTION_STOP_RECORDING = "com.aeidolon.vaultexplorer.action.STOP_BACKGROUND_RECORDING"

        const val EXTRA_VOL_ID = "volId"
        const val EXTRA_CONTAINER_NAME = "containerName"

        /** True when the recording being kept alive is audio-only. */
        const val EXTRA_AUDIO_ONLY = "audioOnly"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        private var instance: VaultCameraRecordingService? = null

        fun refreshNotification() {
            val service = instance ?: return
            service.getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, service.buildNotification())
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var currentVolId: Int = -1
    private var currentContainerName: String = ""
    private var audioOnly: Boolean = false
    private var cachedContentIntent: PendingIntent? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
        }
    }

     private fun startForegroundCompat() {
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
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_RECORDING) {
            // Don't stop the service here -- the recording isn't actually
            // finalized/encrypted yet. Dart calls stopBackgroundRecording()
            // once _stopVideoRecording() completes, which is what tears
            // this service down (see the finally block there).
            VaultCameraStopRequestedBridge.reportStopRequested(currentVolId)
            startForegroundCompat()
            return START_NOT_STICKY
        }

        intent?.getIntExtra(EXTRA_VOL_ID, -1)?.let { if (it != -1) currentVolId = it }
        intent?.getStringExtra(EXTRA_CONTAINER_NAME)?.let { currentContainerName = it }
        audioOnly = intent?.getBooleanExtra(EXTRA_AUDIO_ONLY, false) ?: audioOnly

        startForegroundCompat()
        wakeLock?.let { if (!it.isHeld) it.acquire(6 * 60 * 60 * 1000L /* 6h safety cap */) }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?) = null

    /**
     * The app's task was swiped away from Recents. This service is declared
     * `stopWithTask="false"` so a recording survives the screen turning off
     * or the app being backgrounded, but the recording it protects belongs
     * to the Activity's camera/audio plugins, which are torn down when that
     * task goes away -- so there is nothing left to keep alive. Without this
     * the ongoing notification stays up claiming a recording that has
     * already stopped, and [isRunning] stays true, which suppresses
     * screen-off handling and postpones native auto-close indefinitely.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        VeLog.i(TAG) { "onTaskRemoved: app task removed, stopping recording service and its notification" }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        isRunning = false
        if (instance === this) instance = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        currentVolId = -1
        currentContainerName = ""
        audioOnly = false
        cachedContentIntent = null
        super.onDestroy()
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
        val channel = NotificationChannel(
            CHANNEL_ID,
            identity,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = localized.getString(R.string.camera_recording_channel_description)
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
        val localized = NotificationLocale.wrap(this)
        val decoyActive = DisguiseModeHandlers.isDecoyActive(this)

        val contentTitle: String
        val contentText: String
        val actionLabel: String
        val smallIcon: Int
        if (decoyActive) {
            // Never reveal that a recording is in progress while decoy
            // mode is active -- same rationale as VaultKeepAliveService's
            // decoy text.
            contentTitle = localized.getString(R.string.decoy_app_name)
            contentText = localized.getString(R.string.camera_recording_notification_text_decoy)
            actionLabel = localized.getString(R.string.camera_recording_stop_action_decoy)
            smallIcon = R.drawable.ic_notification_folder
        } else {
            contentTitle = localized.getString(
                if (audioOnly) R.string.audio_recording_notification_title
                else R.string.camera_recording_notification_title,
            )
            // Quick Capture records before any vault is chosen, so there is no
            // name to say it is saving to; the title alone says enough then.
            contentText = if (currentContainerName.isEmpty()) {
                ""
            } else {
                localized.getString(R.string.camera_recording_notification_text, currentContainerName)
            }
            actionLabel = localized.getString(R.string.camera_recording_stop_action)
            smallIcon = if (audioOnly) R.drawable.ic_notification_mic else R.drawable.ic_notification_camera
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle(contentTitle)
            .setContentText(contentText.ifEmpty { null })
            .setContentIntent(getContentIntent())
            .addAction(0, actionLabel, getStopIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .build()
    }
}
