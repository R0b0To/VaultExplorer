package com.aeidolon.vaultexplorer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.provider.DocumentsContract
import android.util.Log
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
 *
 * This class never decides *whether* it should be running -- that's
 * entirely driven from outside, by
 * [com.aeidolon.vaultexplorer.handlers.BackgroundServiceHandlers], every
 * time the setting is toggled or the set of unlocked vaults changes (see
 * that class's doc comment). The one exception is [ACTION_LOCK_ALL]: once
 * that finishes locking everything, this service stops itself rather than
 * waiting to be told.
 *
 * Never reveals vault identity, count, or the "Lock all vaults" wording in
 * its notification while decoy mode is active -- see
 * [DisguiseModeHandlers.isDecoyActive]. The whole point of decoy mode is
 * plausible deniability that any vault exists; a notification that leaks
 * "N vaults open" while the app is disguised as Archive Explorer would
 * defeat that outright.
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
        var isIndeterminate: Boolean = false
            private set

        fun updateOperationProgress(
            context: android.content.Context,
            hasActive: Boolean,
            title: String?,
            text: String?,
            progress: Int?,
            indeterminate: Boolean,
        ) {
            hasActiveOperations = hasActive
            currentProgressTitle = title
            currentProgressText = text
            currentProgress = progress
            isIndeterminate = indeterminate

            val s = instance
            if (s != null && isRunning && ContainerSessionRegistry.hasAnyActiveSessions()) {
                val nm = context.getSystemService(NotificationManager::class.java)
                nm.notify(NOTIFICATION_ID, s.buildNotification())
            }
        }
    }

    // Own executor rather than reusing MainActivity.ioExecutor: this
    // service must keep working even when no Activity -- and so no
    // ioExecutor -- exists at all.
    private lateinit var executor: ExecutorService

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        executor = Executors.newSingleThreadExecutor()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must promote to foreground immediately, regardless of action:
        // this service may have been started fresh via
        // startForegroundService() to handle ACTION_LOCK_ALL (e.g. the
        // notification action fired after the app process had already
        // been swept from Recents), and Android requires startForeground()
        // to be called within a few seconds of that or the process is
        // killed.
        startForeground(NOTIFICATION_ID, buildNotification())
        if (intent?.action == ACTION_LOCK_ALL) {
            lockAllAndMaybeStop()
        } else if (!ContainerSessionRegistry.hasAnyActiveSessions()) {
            // Defensive only: BackgroundServiceHandlers.sync() already
            // checks this before ever starting the service, so this
            // should be unreachable outside a race with the very last
            // vault being locked elsewhere at the same moment.
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        instance = null
        isRunning = false
        executor.shutdown()
        super.onDestroy()
    }

    /**
     * Locks every currently-unlocked vault, mirroring
     * VaultUnlockHandlers.handleLockContainer's cleanup sequence exactly
     * (that method can't be reused directly -- it completes a Dart
     * MethodChannel.Result this action has none of). A vault whose lock
     * call throws is left registered, same as that method's behavior, so
     * it's neither silently dropped nor falsely reported as closed.
     */
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
                    Log.w(TAG, "Lock all: failed to lock volId=$volId: ${e.message}")
                }
            }
            applicationContext.contentResolver.notifyChange(
                DocumentsContract.buildRootsUri(CONTAINER_DOCUMENTS_AUTHORITY), null,
            )
            if (ContainerSessionRegistry.hasAnyActiveSessions()) {
                // One or more vaults above failed to lock -- stay alive so
                // the notification (and its Lock all action) is still
                // there to retry, with an up-to-date open-vault count.
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

    /**
     * (Re-)creates the notification channel with a name matching the
     * current disguise-mode identity. Safe to call every time a
     * notification is built: createNotificationChannel with an ID that
     * already exists just updates its user-visible name/description in
     * place, it doesn't re-prompt the user or duplicate the channel.
     */
    private fun ensureChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            currentIdentityLabel(),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.vault_keep_alive_channel_description)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    fun buildNotification(): Notification {
        ensureChannel()
        val decoyActive = DisguiseModeHandlers.isDecoyActive(this)

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val lockAllIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, VaultKeepAliveService::class.java).setAction(ACTION_LOCK_ALL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

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
                builder.setProgress(100, currentProgress!!.coerceIn(0, 100), false)
            }
        } else {
            builder.setProgress(0, 0, false)
        }

        return builder.build()
    }
}
