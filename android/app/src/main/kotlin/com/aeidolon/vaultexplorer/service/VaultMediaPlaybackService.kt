package com.aeidolon.vaultexplorer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.media3.session.MediaStyleNotificationHelper
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.engine.VaultPlaybackSession
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers
import com.aeidolon.vaultexplorer.util.NotificationLocale

/**
 * Foreground service (type `mediaPlayback`) behind background playback of
 * media opened from an unlocked vault or from local storage. It owns nothing
 * but the notification and the foreground state; the player and the
 * `MediaSession` are owned by
 * [com.aeidolon.vaultexplorer.engine.NativePlayerManager] /
 * [VaultPlaybackSession], which tell this service when something changed.
 *
 * Why a plain [Service] rather than Media3's `MediaSessionService`: the
 * Dart media viewer releases and recreates the native player on every item
 * change, and Media3 would drop the foreground state in that gap -- after
 * which a background auto-advance could no longer get it back (Android 12+
 * refuses foreground-service starts from the background). Here the
 * foreground state is held explicitly: it is taken while playing and only
 * given up [FOREGROUND_LINGER_MS] after playback stops, which comfortably
 * spans an item change.
 *
 * The notification is a standard media-style notification built on the
 * session's token, so Android also derives the lock screen / quick settings
 * controls from the session (API 33+) or from this notification (older).
 * What it shows is generic unless the user opts in to publishing file names,
 * and follows Mask Mode's identity the same way
 * [VaultKeepAliveService]'s notification does.
 *
 * Everything here runs on the main thread.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class VaultMediaPlaybackService : Service() {

    companion object {
        private const val TAG = "VaultMediaPlaybackService"
        private const val CHANNEL_ID = "vault_media_playback"
        private const val NOTIFICATION_ID = 4204

        /** How long the service stays foreground after playback stops (spans item changes). */
        private const val FOREGROUND_LINGER_MS = 8_000L

        private const val ACTION_TOGGLE = "com.aeidolon.vaultexplorer.action.MEDIA_TOGGLE"
        private const val ACTION_PREVIOUS = "com.aeidolon.vaultexplorer.action.MEDIA_PREVIOUS"
        private const val ACTION_NEXT = "com.aeidolon.vaultexplorer.action.MEDIA_NEXT"
        private const val ACTION_STOP = "com.aeidolon.vaultexplorer.action.MEDIA_STOP"

        /** The notification was swiped away. Unlike Stop, it leaves the viewer open. */
        private const val ACTION_DISMISS = "com.aeidolon.vaultexplorer.action.MEDIA_DISMISS"

        @Volatile
        private var instance: VaultMediaPlaybackService? = null

        /**
         * Starts the service, or just refreshes it if it is already running.
         * Called while the app is in the foreground (the viewer's first play);
         * later item changes find it running. If Android refuses the start,
         * playback simply continues without a notification.
         */
        fun show(context: Context) {
            val running = instance
            if (running != null) {
                running.refreshNotification()
                return
            }
            try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, VaultMediaPlaybackService::class.java),
                )
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "Could not start the media playback service" }
            }
        }

        fun refresh() {
            instance?.refreshNotification()
        }

        fun stop() {
            instance?.shutdown()
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isForeground = false
    private var stopped = false
    private var detachRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val snapshot = VaultPlaybackSession.snapshot()

        if (action == null) {
            // Started through startForegroundService(): reaching
            // startForeground() promptly is mandatory, whatever else happens.
            promoteToForeground(snapshot)
            // No session (it ended between the start request and now): undo
            // the promotion. Not routed through shutdown(), whose guard would
            // skip this if the session's end() already ran it.
            if (snapshot == null) {
                stopped = true
                teardown()
            }
            return START_NOT_STICKY
        }

        if (snapshot == null) {
            // A notification action that outlived its session (the process
            // was restarted, or the playback window already closed).
            shutdown()
            return START_NOT_STICKY
        }

        when (action) {
            ACTION_TOGGLE -> VaultPlaybackSession.togglePlayPause()
            ACTION_PREVIOUS -> VaultPlaybackSession.skipToPrevious()
            ACTION_NEXT -> VaultPlaybackSession.skipToNext()
            ACTION_STOP -> VaultPlaybackSession.stopByUser()
            ACTION_DISMISS -> VaultPlaybackSession.dismissedByUser()
        }
        refreshNotification()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopped = true
        cancelDetach()
        if (instance === this) instance = null
        // A detached (non-foreground) notification would otherwise outlive us.
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        super.onDestroy()
    }

    // --- Foreground / notification state ---

    fun refreshNotification() {
        if (stopped) return
        // No snapshot means we are between two items (the session was
        // released, the next one has not started): keep what is posted.
        val snapshot = VaultPlaybackSession.snapshot() ?: return
        val notification = buildNotification(snapshot)
        val manager = getSystemService(NotificationManager::class.java)
        if (snapshot.playing) {
            cancelDetach()
            if (!isForeground) {
                promoteToForeground(snapshot, notification)
            } else {
                manager.notify(NOTIFICATION_ID, notification)
            }
        } else {
            manager.notify(NOTIFICATION_ID, notification)
            if (isForeground) scheduleDetach()
        }
    }

    private fun promoteToForeground(snapshot: VaultPlaybackSession.Snapshot?, built: Notification? = null) {
        val notification = built ?: buildNotification(snapshot)
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
            isForeground = true
        } catch (e: Exception) {
            // E.g. resumed from the background without an exemption: keep the
            // notification (so its controls still work) but as a plain one.
            VeLog.w(TAG, e) { "startForeground refused; posting a plain notification" }
            isForeground = false
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification)
        }
    }

    private fun scheduleDetach() {
        if (detachRunnable != null) return
        val runnable = Runnable {
            detachRunnable = null
            detachFromForeground()
        }
        detachRunnable = runnable
        mainHandler.postDelayed(runnable, FOREGROUND_LINGER_MS)
    }

    private fun cancelDetach() {
        detachRunnable?.let { mainHandler.removeCallbacks(it) }
        detachRunnable = null
    }

    /** Playback stayed stopped: leave the foreground but keep a dismissible notification. */
    private fun detachFromForeground() {
        if (stopped || !isForeground) return
        val snapshot = VaultPlaybackSession.snapshot() ?: return
        if (snapshot.playing) return
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
        isForeground = false
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(snapshot))
    }

    fun shutdown() {
        if (stopped) return
        stopped = true
        teardown()
    }

    private fun teardown() {
        cancelDetach()
        if (instance === this) instance = null
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "stopForeground failed during shutdown" }
        }
        isForeground = false
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        stopSelf()
    }

    // --- Notification content ---

    private fun ensureChannel() {
        val localized = NotificationLocale.wrap(this)
        val identity = if (DisguiseModeHandlers.isDecoyActive(this)) {
            localized.getString(R.string.decoy_app_name)
        } else {
            localized.getString(R.string.app_name)
        }
        val channel = NotificationChannel(CHANNEL_ID, identity, NotificationManager.IMPORTANCE_LOW).apply {
            description = localized.getString(R.string.vault_media_channel_description)
            setShowBadge(false)
            lockscreenVisibility = if (VaultPlaybackSession.areFileNamesVisible()) {
                Notification.VISIBILITY_PRIVATE
            } else {
                Notification.VISIBILITY_PUBLIC
            }
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun contentIntent(): PendingIntent =
        PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .setAction(MainActivity.ACTION_OPEN_MEDIA_PLAYER)
                .setFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                ),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun actionIntent(action: String): PendingIntent =
        PendingIntent.getService(
            this,
            0,
            Intent(this, VaultMediaPlaybackService::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun buildNotification(snapshot: VaultPlaybackSession.Snapshot?): Notification {
        ensureChannel()
        val localized = NotificationLocale.wrap(this)
        val smallIcon = if (DisguiseModeHandlers.isDecoyActive(this)) {
            R.drawable.ic_notification_folder
        } else {
            R.drawable.ic_notification_vault
        }
        val genericTitle = VaultPlaybackSession.genericTitle(this)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle(snapshot?.title ?: genericTitle)
            .setContentText(snapshot?.playlistPosition)
            .setContentIntent(contentIntent())
            .setDeleteIntent(actionIntent(ACTION_DISMISS))
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setOngoing(snapshot?.playing == true)

        if (VaultPlaybackSession.areFileNamesVisible()) {
            // The lock screen gets the generic version only.
            builder.setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            builder.setPublicVersion(
                NotificationCompat.Builder(this, CHANNEL_ID)
                    .setSmallIcon(smallIcon)
                    .setContentTitle(genericTitle)
                    .build(),
            )
        } else {
            builder.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        }

        if (snapshot == null) return builder.build()

        // Action order: [previous] toggle [next] stop. Stop stays out of the
        // compact view (at most three actions fit there).
        val compact = ArrayList<Int>(3)
        var index = 0
        if (snapshot.hasPrevious) {
            builder.addAction(
                R.drawable.ic_vault_media_previous,
                localized.getString(R.string.vault_media_action_previous),
                actionIntent(ACTION_PREVIOUS),
            )
            compact.add(index++)
        }
        if (snapshot.showsPause) {
            builder.addAction(
                R.drawable.ic_vault_media_pause,
                localized.getString(R.string.vault_media_action_pause),
                actionIntent(ACTION_TOGGLE),
            )
        } else {
            builder.addAction(
                R.drawable.ic_vault_media_play,
                localized.getString(R.string.vault_media_action_play),
                actionIntent(ACTION_TOGGLE),
            )
        }
        compact.add(index++)
        if (snapshot.hasNext) {
            builder.addAction(
                R.drawable.ic_vault_media_next,
                localized.getString(R.string.vault_media_action_next),
                actionIntent(ACTION_NEXT),
            )
            compact.add(index++)
        }
        builder.addAction(
            R.drawable.ic_vault_media_stop,
            localized.getString(R.string.vault_media_action_stop),
            actionIntent(ACTION_STOP),
        )

        builder.setStyle(
            MediaStyleNotificationHelper.MediaStyle(snapshot.session)
                .setShowActionsInCompactView(*compact.toIntArray()),
        )
        return builder.build()
    }
}
