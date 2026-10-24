package com.aeidolon.vaultexplorer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.DocumentsContract
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.bridge.UsbBlockBridge
import com.aeidolon.vaultexplorer.bridge.VaultForceLockedBridge
import com.aeidolon.vaultexplorer.container.ContainerEngine
import com.aeidolon.vaultexplorer.container.ContainerLifecycleCore
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.engine.VaultPlaybackSession
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers
import com.aeidolon.vaultexplorer.pdf.PdfRendererRegistry
import com.aeidolon.vaultexplorer.pdf.VaultPdfSessionRegistry
import com.aeidolon.vaultexplorer.saf.MirrorPushEvents
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.withLock
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.util.NotificationLocale

private const val CONTAINER_DOCUMENTS_AUTHORITY = "com.aeidolon.vaultexplorer.documents"

/**
 * Foreground service backing the "keep vaults running in background"
 * setting (AppSettingsScreen), mirroring DroidFS's "keep volumes open"
 * feature. While it's running, its ongoing notification is what stops
 * Android from reclaiming the process just because [MainActivity] isn't
 * visible (or has been swiped from Recents) -- without it, the decrypted
 * vault key material and any active FUSE/DocumentsProvider sessions in
 * [ContainerSessionRegistry] simply vanish the moment the OS decides to
 * kill the process, with no chance to unmount cleanly.
 */
class VaultKeepAliveService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sessionRemovedListener: (Int) -> Unit = { refreshNotification() }
    private val autoCloseCallbacks = mutableMapOf<String, Runnable>()
    private val autoCloseInFlight = ConcurrentHashMap.newKeySet<String>()
    private val mirrorPushListener = MirrorPushEvents.Listener {
        if (isRunning && ContainerSessionRegistry.hasAnyActiveSessions()) {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification())
        }
    }

    companion object {
        private const val TAG = "VaultKeepAliveService"
        private const val CHANNEL_ID = "vault_keep_alive"
        private const val NOTIFICATION_ID = 4201
        private const val AUTO_CLOSE_FALLBACK_GRACE_MS = 5_000L
        private const val AUTO_CLOSE_RETRY_MS = 30_000L

        /** Fired by the notification's action button; also handled if it
         *  arrives as the Intent that starts the service fresh. */
        const val ACTION_LOCK_ALL = "com.aeidolon.vaultexplorer.action.LOCK_ALL_VAULTS"

        @Volatile
        private var instance: VaultKeepAliveService? = null

        private val pendingAutoCloseDeadlines = ConcurrentHashMap<String, Long>()

        @Volatile
        private var lockOnAppBackgroundUris: Set<String> = emptySet()

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var hasActiveOperations: Boolean = false
            private set

        @Volatile
        var currentProgressTitle: String? = null
            private set

        @Volatile
        var currentProgressText: String? = null
            private set

        @Volatile
        var currentProgress: Int? = null
            private set

        @Volatile
        var maxProgress: Int = 1000
            private set

        @Volatile
        var isIndeterminate: Boolean = false
            private set

        fun updateOperationProgress(
            context: Context,
            hasActive: Boolean,
            title: String?,
            text: String?,
            progress: Int?,
            max: Int = 1000,
            indeterminate: Boolean = false,
        ) {
            hasActiveOperations = hasActive
            currentProgressTitle = title
            currentProgressText = text
            currentProgress = progress
            maxProgress = max
            isIndeterminate = indeterminate
            val s = instance
            if (s != null && isRunning) {
                if (ContainerSessionRegistry.hasAnyActiveSessions() || hasActiveOperations) {
                    val nm = context.getSystemService(NotificationManager::class.java)
                    nm.notify(NOTIFICATION_ID, s.buildNotification())
                } else {
                    refreshNotification()
                }
            }
        }

        fun refreshNotification() {
            val service = instance ?: return
            service.mainHandler.post {
                service.refreshNotificationNow()
            }
        }

        fun scheduleContainerAutoClose(context: Context, uri: String, deadlineMillis: Long?) {
            if (uri.isBlank()) return
            ContainerAutoCloseAlarm.schedule(context, uri, deadlineMillis)
            if (deadlineMillis == null || deadlineMillis <= 0L) {
                pendingAutoCloseDeadlines.remove(uri)
                instance?.cancelAutoClose(uri)
                return
            }

            pendingAutoCloseDeadlines[uri] = deadlineMillis
            instance?.scheduleAutoClose(uri, deadlineMillis)
        }

        fun updateLockOnAppBackgroundUris(uris: List<String>?) {
            if (uris != null) lockOnAppBackgroundUris = uris.filter(String::isNotBlank).toSet()
        }

        fun onAutoCloseAlarm(context: Context, uri: String, deadlineMillis: Long) {
            val intent = Intent(context, VaultKeepAliveService::class.java)
                .setAction(ContainerAutoCloseAlarm.ACTION)
                .putExtra(ContainerAutoCloseAlarm.EXTRA_URI, uri)
                .putExtra(ContainerAutoCloseAlarm.EXTRA_DEADLINE, deadlineMillis)
            val service = instance
            if (service != null && isRunning) {
                service.handleAutoCloseAlarm(uri, deadlineMillis)
                return
            }
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (e: Exception) {
                VeLog.w(TAG) { "Could not restart keep-alive service for auto-close alarm: ${e.message}" }
            }
        }

        fun hasRunningInstance(): Boolean = instance != null && isRunning
    }

    private lateinit var executor: ExecutorService
    private var observingMirrorPush = false
    private var cachedContentIntent: PendingIntent? = null
    private var cachedLockAllIntent: PendingIntent? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        executor = Executors.newSingleThreadExecutor()
        ContainerSessionRegistry.addSessionRemovedListener(sessionRemovedListener)
        pendingAutoCloseDeadlines.forEach { (uri, deadlineMillis) ->
            scheduleAutoClose(uri, deadlineMillis)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        VeLog.d(TAG) {
            "onStartCommand: action=${intent?.action}, activeSessions=" +
                "${ContainerSessionRegistry.activeSessions.keys.toList()}"
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        if (!observingMirrorPush) {
            MirrorPushEvents.addListener(mirrorPushListener)
            observingMirrorPush = true
        }
        if (intent?.action == ACTION_LOCK_ALL) {
            VeLog.i(TAG) { "onStartCommand: ACTION_LOCK_ALL -> locking every active session" }
            lockAllAndMaybeStop()
        } else {
            if (intent?.action == ContainerAutoCloseAlarm.ACTION) {
                val uri = intent.getStringExtra(ContainerAutoCloseAlarm.EXTRA_URI)
                val deadlineMillis = intent.getLongExtra(ContainerAutoCloseAlarm.EXTRA_DEADLINE, 0L)
                if (uri != null && deadlineMillis > 0L) {
                    handleAutoCloseAlarm(uri, deadlineMillis)
                }
            }
            if (!ContainerSessionRegistry.hasAnyActiveSessions() && !hasActiveOperations) {
                VeLog.d(TAG) { "onStartCommand: no active sessions -> stopping service" }
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val targets = lockOnAppBackgroundUris
        if (targets.isNotEmpty()) {
            lockContainersAfterTaskRemoval(targets)
        } else {
            refreshNotificationNow()
        }
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        autoCloseCallbacks.values.forEach(mainHandler::removeCallbacks)
        autoCloseCallbacks.clear()
        ContainerSessionRegistry.removeSessionRemovedListener(sessionRemovedListener)
        if (observingMirrorPush) MirrorPushEvents.removeListener(mirrorPushListener)
        instance = null
        isRunning = false
        hasActiveOperations = false
        currentProgressTitle = null
        currentProgressText = null
        currentProgress = null
        isIndeterminate = false
        cachedContentIntent = null
        cachedLockAllIntent = null
        executor.shutdown()
        super.onDestroy()
    }

    private fun scheduleAutoClose(uri: String, deadlineMillis: Long) {
        mainHandler.post {
            if (pendingAutoCloseDeadlines[uri] != deadlineMillis) return@post
            cancelAutoCloseOnMain(uri)
            val fireAt = deadlineMillis + AUTO_CLOSE_FALLBACK_GRACE_MS
            val callback = Runnable {
                autoCloseCallbacks.remove(uri)
                if (pendingAutoCloseDeadlines[uri] != deadlineMillis) return@Runnable
                attemptAutoClose(uri, deadlineMillis)
            }
            autoCloseCallbacks[uri] = callback
            mainHandler.postDelayed(callback, (fireAt - System.currentTimeMillis()).coerceAtLeast(0L))
        }
    }

    private fun rescheduleAutoClose(uri: String, previousDeadlineMillis: Long) {
        mainHandler.post {
            if (pendingAutoCloseDeadlines[uri] != previousDeadlineMillis) return@post
            val retryDeadline = System.currentTimeMillis() + AUTO_CLOSE_RETRY_MS
            if (pendingAutoCloseDeadlines.replace(uri, previousDeadlineMillis, retryDeadline)) {
                ContainerAutoCloseAlarm.schedule(applicationContext, uri, retryDeadline)
                scheduleAutoClose(uri, retryDeadline)
            }
        }
    }

    private fun cancelAutoClose(uri: String) {
        mainHandler.post {
            cancelAutoCloseOnMain(uri)
        }
    }

    private fun cancelAutoCloseOnMain(uri: String) {
        autoCloseCallbacks.remove(uri)?.let(mainHandler::removeCallbacks)
    }

    private fun handleAutoCloseAlarm(uri: String, deadlineMillis: Long) {
        if (ContainerSessionRegistry.getVolumeIdByUri(uri) == null) {
            pendingAutoCloseDeadlines.remove(uri, deadlineMillis)
            ContainerAutoCloseAlarm.cancel(applicationContext, uri)
            refreshNotification()
            return
        }
        val currentDeadline = pendingAutoCloseDeadlines[uri]
        if (currentDeadline != null && currentDeadline != deadlineMillis) return
        if (currentDeadline == null) pendingAutoCloseDeadlines[uri] = deadlineMillis
        cancelAutoCloseOnMain(uri)
        attemptAutoClose(uri, deadlineMillis)
    }

    private fun lockContainersAfterTaskRemoval(uris: Set<String>) {
        for (uri in uris) {
            pendingAutoCloseDeadlines.remove(uri)
            ContainerAutoCloseAlarm.cancel(applicationContext, uri)
            cancelAutoCloseOnMain(uri)
        }

        val wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:ImmediateAutoClose")
            .apply {
                setReferenceCounted(false)
                acquire(2 * 60 * 1000L)
            }
        try {
            executor.execute {
                try {
                    for (uri in uris) {
                        val volId = ContainerSessionRegistry.getVolumeIdByUri(uri) ?: continue
                        if (ContainerLifecycleCore.lockContainer(applicationContext, uri)) {
                            VaultForceLockedBridge.reportLocked(volId)
                        } else {
                            scheduleImmediateAutoCloseRetry(uri)
                        }
                    }
                } finally {
                    mainHandler.post {
                        refreshNotificationNow()
                        if (wakeLock.isHeld) wakeLock.release()
                    }
                }
            }
        } catch (e: Exception) {
            if (wakeLock.isHeld) wakeLock.release()
            VeLog.w(TAG) { "Could not queue immediate auto-lock: ${e.message}" }
            refreshNotification()
        }
    }

    private fun scheduleImmediateAutoCloseRetry(uri: String) {
        val deadlineMillis = System.currentTimeMillis() + AUTO_CLOSE_RETRY_MS
        pendingAutoCloseDeadlines[uri] = deadlineMillis
        ContainerAutoCloseAlarm.schedule(applicationContext, uri, deadlineMillis)
        scheduleAutoClose(uri, deadlineMillis)
    }

    private fun attemptAutoClose(uri: String, deadlineMillis: Long) {
        if (pendingAutoCloseDeadlines[uri] != deadlineMillis) return
        if (!autoCloseInFlight.add(uri)) return
        if (shouldPostponeAutoClose(uri)) {
            autoCloseInFlight.remove(uri)
            rescheduleAutoClose(uri, deadlineMillis)
            return
        }

        val wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:AutoClose")
            .apply {
                setReferenceCounted(false)
                acquire(2 * 60 * 1000L)
            }
        var releaseAfterNotification = false
        try {
            executor.execute {
                try {
                    if (pendingAutoCloseDeadlines[uri] != deadlineMillis) return@execute
                    val volId = ContainerSessionRegistry.getVolumeIdByUri(uri)
                    if (volId == null) {
                        pendingAutoCloseDeadlines.remove(uri, deadlineMillis)
                        ContainerAutoCloseAlarm.cancel(applicationContext, uri)
                        refreshNotificationBeforeReleasingWakeLock(wakeLock)
                        releaseAfterNotification = true
                        return@execute
                    }

                    val locked = ContainerLifecycleCore.lockContainer(applicationContext, uri)
                    if (locked) {
                        pendingAutoCloseDeadlines.remove(uri, deadlineMillis)
                        ContainerAutoCloseAlarm.cancel(applicationContext, uri)
                        VaultForceLockedBridge.reportLocked(volId)
                        refreshNotificationBeforeReleasingWakeLock(wakeLock)
                        releaseAfterNotification = true
                    } else {
                        rescheduleAutoClose(uri, deadlineMillis)
                    }
                } finally {
                    autoCloseInFlight.remove(uri)
                    if (!releaseAfterNotification && wakeLock.isHeld) wakeLock.release()
                }
            }
        } catch (e: Exception) {
            autoCloseInFlight.remove(uri)
            if (wakeLock.isHeld) wakeLock.release()
            VeLog.w(TAG) { "Could not queue auto-close lock: ${e.message}" }
            rescheduleAutoClose(uri, deadlineMillis)
        }
    }

    private fun refreshNotificationNow() {
        if (instance !== this || !isRunning) return
        if (!ContainerSessionRegistry.hasAnyActiveSessions() && !hasActiveOperations) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } else {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification())
        }
    }

    private fun refreshNotificationBeforeReleasingWakeLock(wakeLock: PowerManager.WakeLock) {
        mainHandler.post {
            refreshNotificationNow()
            if (wakeLock.isHeld) wakeLock.release()
        }
    }

    private fun shouldPostponeAutoClose(uri: String): Boolean =
        uri !in lockOnAppBackgroundUris &&
            (VaultPlaybackSession.snapshot()?.playing == true ||
                hasActiveOperations ||
                MirrorPushEvents.snapshot().activeCount > 0 ||
                VaultCameraRecordingService.isRunning ||
                (VaultAutomationRecordingService.isRecording &&
                    VaultAutomationRecordingService.currentVaultUri == uri))

    private fun lockAllAndMaybeStop() {
        executor.execute {
            val volIds = ContainerSessionRegistry.activeSessions.keys.toList()
            VeLog.i(TAG) { "lockAllAndMaybeStop: locking every active session -> $volIds" }
            for (volId in volIds) {
                val session = ContainerSessionRegistry.activeSessions[volId]
                try {
                    PdfRendererRegistry.closeAllForVolume(volId)
                    VaultPdfSessionRegistry.revokeAllForVolume(volId)
                    ContainerSessionRegistry.locks[volId].writeLock().withLock {
                        ContainerEngine.lock(volId)
                    }
                    if (session?.isUsbSource == true) {
                        UsbBlockBridge.unregister(volId)
                    }
                    ContainerSessionRegistry.removeSession(volId)
                    VaultForceLockedBridge.reportLocked(volId)
                } catch (e: Exception) {
                    VeLog.w(TAG) { "Lock all: failed to lock volId=$volId: ${e.message}" }
                }
            }
            applicationContext.contentResolver.notifyChange(
                DocumentsContract.buildRootsUri(CONTAINER_DOCUMENTS_AUTHORITY), null,
            )
            if (ContainerSessionRegistry.hasAnyActiveSessions()) {
                val nm = applicationContext.getSystemService(NotificationManager::class.java)
                nm.notify(NOTIFICATION_ID, buildNotification())
            } else {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
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
            description = localized.getString(R.string.vault_keep_alive_channel_description)
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

    private fun getLockAllIntent(): PendingIntent {
        var pi = cachedLockAllIntent
        if (pi == null) {
            pi = PendingIntent.getService(
                this,
                0,
                Intent(this, VaultKeepAliveService::class.java).setAction(ACTION_LOCK_ALL),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            cachedLockAllIntent = pi
        }
        return pi
    }

    fun buildNotification(): Notification {
        ensureChannel()
        val localized = NotificationLocale.wrap(this)
        val decoyActive = DisguiseModeHandlers.isDecoyActive(this)

        val contentIntent = getContentIntent()
        val lockAllIntent = getLockAllIntent()
        val mirrorPushActive = !hasActiveOperations && MirrorPushEvents.snapshot().activeCount > 0
        val showingProgress = hasActiveOperations || mirrorPushActive

        val contentTitle: String
        val contentText: String
        val actionLabel: String
        val smallIcon: Int
        if (decoyActive) {
            contentTitle = localized.getString(R.string.decoy_app_name)
            contentText = if (showingProgress) {
                currentProgressText ?: localized.getString(R.string.vault_keep_alive_notification_text_decoy)
            } else {
                localized.getString(R.string.vault_keep_alive_notification_text_decoy)
            }
            actionLabel = localized.getString(R.string.vault_keep_alive_close_action_decoy)
            smallIcon = R.drawable.ic_notification_folder
        } else {
            val openCount = ContainerSessionRegistry.activeSessions.size
            if (hasActiveOperations) {
                contentTitle = currentProgressTitle ?: currentIdentityLabel()
                contentText = currentProgressText ?: localized.resources.getQuantityString(
                    R.plurals.vault_keep_alive_notification_text, openCount, openCount,
                )
            } else if (mirrorPushActive) {
                contentTitle = localized.getString(R.string.mirror_push_notification_title)
                contentText = localized.getString(R.string.mirror_push_notification_text)
            } else {
                contentTitle = currentIdentityLabel()
                contentText = localized.resources.getQuantityString(
                    R.plurals.vault_keep_alive_notification_text, openCount, openCount,
                )
            }
            actionLabel = localized.getString(R.string.vault_keep_alive_lock_all_action)
            smallIcon = R.drawable.ic_notification_vault
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle(contentTitle)
            .setContentText(contentText)
            .setContentIntent(contentIntent)
            .addAction(0, actionLabel, lockAllIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)

        if (showingProgress) {
            if (isIndeterminate) {
                builder.setProgress(0, 0, true)
            } else if (currentProgress != null) {
                builder.setProgress(maxProgress, currentProgress!!.coerceIn(0, maxProgress), false)
            } else if (mirrorPushActive) {
                builder.setProgress(0, 0, true)
            }
        } else {
            builder.setProgress(0, 0, false)
        }

        return builder.build()
    }
}
