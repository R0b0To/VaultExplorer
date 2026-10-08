package com.aeidolon.vaultexplorer.automation

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.aeidolon.vaultexplorer.handlers.ScheduledSyncHandlers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Starts directly from the user's exact alarm so Android permits its foreground notification. */
class ScheduledVaultSyncService : Service() {
    companion object {
        private const val TAG = "ScheduledVaultSyncService"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var activeRuns = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val data = intent?.let { ScheduledSyncHandlers.inputFromServiceIntent(this, it) }
        val vaultUri = data?.getString(ScheduledVaultSyncWorker.KEY_VAULT_URI)
        if (data == null || vaultUri.isNullOrBlank() ||
            !ScheduledSyncHandlers.isScheduleActive(this, data) ||
            !NotificationManagerCompat.from(this).areNotificationsEnabled()
        ) {
            stopSelfResult(startId)
            return START_NOT_STICKY
        }

        try {
            val notification = ScheduledSyncNotification.create(this)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    ScheduledSyncNotification.NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(ScheduledSyncNotification.NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Could not start scheduled sync foreground service", e)
            stopSelfResult(startId)
            return START_NOT_STICKY
        }

        activeRuns++
        ScheduledSyncHandlers.cancelLegacyWorkForInput(this, data)
        runCatching { ScheduledSyncHandlers.scheduleNextOccurrence(this, data) }
            .onFailure { Log.e(TAG, "Could not schedule the next daily run", it) }

        scope.launch {
            try {
                if (!ScheduledVaultSyncRunner(applicationContext, data).run()) {
                    Log.e(TAG, "Scheduled sync failed for rule ${data.getString(ScheduledVaultSyncWorker.KEY_RULE_ID)}")
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Scheduled sync crashed", e)
            } finally {
                withContext(Dispatchers.Main) {
                    activeRuns = (activeRuns - 1).coerceAtLeast(0)
                    if (activeRuns == 0) {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        stopSelfResult(startId)
                    }
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
