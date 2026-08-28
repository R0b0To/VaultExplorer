package com.aeidolon.vaultexplorer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.provider.DocumentsContract
import androidx.core.app.NotificationCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.bridge.UsbBlockBridge
import com.aeidolon.vaultexplorer.bridge.VaultForceLockedBridge
import com.aeidolon.vaultexplorer.container.ContainerEngine
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers
import com.aeidolon.vaultexplorer.pdf.PdfRendererRegistry
import com.aeidolon.vaultexplorer.pdf.VaultPdfSessionRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.concurrent.withLock
import com.aeidolon.vaultexplorer.VeLog

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

    companion object {
        private const val TAG = "VaultKeepAliveService"
        private const val CHANNEL_ID = "vault_keep_alive"
        private const val NOTIFICATION_ID = 4201

        /** Fired by the notification's action button; also handled if it
         *  arrives as the Intent that starts the service fresh. */
        const val ACTION_LOCK_ALL = "com.aeidolon.vaultexplorer.action.LOCK_ALL_VAULTS"

        @Volatile
        private var instance: VaultKeepAliveService? = null

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
            if (s != null && isRunning && ContainerSessionRegistry.hasAnyActiveSessions()) {
                val nm = context.getSystemService(NotificationManager::class.java)
                nm.notify(NOTIFICATION_ID, s.buildNotification())
            }
        }
    }

    private lateinit var executor: ExecutorService
    private var lastChannelIdentity: String? = null
    private var cachedContentIntent: PendingIntent? = null
    private var cachedLockAllIntent: PendingIntent? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        executor = Executors.newSingleThreadExecutor()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        if (intent?.action == ACTION_LOCK_ALL) {
            lockAllAndMaybeStop()
        } else if (!ContainerSessionRegistry.hasAnyActiveSessions()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (ContainerSessionRegistry.hasAnyActiveSessions()) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify(NOTIFICATION_ID, buildNotification())
        }
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        instance = null
        isRunning = false
        hasActiveOperations = false
        currentProgressTitle = null
        currentProgressText = null
        currentProgress = null
        isIndeterminate = false
        lastChannelIdentity = null
        cachedContentIntent = null
        cachedLockAllIntent = null
        executor.shutdown()
        super.onDestroy()
    }

    private fun lockAllAndMaybeStop() {
        executor.execute {
            val volIds = ContainerSessionRegistry.activeSessions.keys.toList()
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
            description = getString(R.string.vault_keep_alive_channel_description)
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
        val decoyActive = DisguiseModeHandlers.isDecoyActive(this)

        val contentIntent = getContentIntent()
        val lockAllIntent = getLockAllIntent()

        val contentTitle: String
        val contentText: String
        val actionLabel: String
        val smallIcon: Int
        if (decoyActive) {
            contentTitle = getString(R.string.decoy_app_name)
            contentText = if (hasActiveOperations) {
                currentProgressText ?: getString(R.string.vault_keep_alive_notification_text_decoy)
            } else {
                getString(R.string.vault_keep_alive_notification_text_decoy)
            }
            actionLabel = getString(R.string.vault_keep_alive_close_action_decoy)
            smallIcon = R.drawable.ic_notification_folder
        } else {
            val openCount = ContainerSessionRegistry.activeSessions.size
            if (hasActiveOperations) {
                contentTitle = currentProgressTitle ?: currentIdentityLabel()
                contentText = currentProgressText ?: resources.getQuantityString(
                    R.plurals.vault_keep_alive_notification_text, openCount, openCount,
                )
            } else {
                contentTitle = currentIdentityLabel()
                contentText = resources.getQuantityString(
                    R.plurals.vault_keep_alive_notification_text, openCount, openCount,
                )
            }
            actionLabel = getString(R.string.vault_keep_alive_lock_all_action)
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

        if (hasActiveOperations) {
            if (isIndeterminate) {
                builder.setProgress(0, 0, true)
            } else if (currentProgress != null) {
                builder.setProgress(maxProgress, currentProgress!!.coerceIn(0, maxProgress), false)
            }
        } else {
            builder.setProgress(0, 0, false)
        }

        return builder.build()
    }
}