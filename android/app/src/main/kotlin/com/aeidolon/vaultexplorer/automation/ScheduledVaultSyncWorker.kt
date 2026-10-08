package com.aeidolon.vaultexplorer.automation

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.aeidolon.vaultexplorer.handlers.ScheduledSyncHandlers

/** Compatibility worker for work scheduled by earlier app versions. */
class ScheduledVaultSyncWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    companion object {
        const val KEY_VAULT_URI = "vaultUri"
        const val KEY_VAULT_NAME = "vaultName"
        const val KEY_RULE_ID = "ruleId"
        const val KEY_TARGET_URI = "targetUri"
        const val KEY_TARGET_SUB_PATH = "targetSubPath"
        const val KEY_TARGET_NAME = "targetName"
        const val KEY_SCHEDULED_HOUR = "scheduledHour"
        const val KEY_SCHEDULED_MINUTE = "scheduledMinute"
        const val KEY_SCHEDULED_FOR = "scheduledForMillis"
    }

    override suspend fun doWork(): Result {
        val vaultUri = inputData.getString(KEY_VAULT_URI) ?: return Result.failure()
        val ruleId = inputData.getString(KEY_RULE_ID) ?: return Result.failure()
        ScheduledSyncHandlers.captureLegacyWorkerInput(applicationContext, inputData)
        if (!ScheduledSyncHandlers.isScheduleActive(applicationContext, inputData)) {
            return Result.success()
        }
        runCatching { ScheduledSyncHandlers.scheduleNextOccurrence(applicationContext, inputData) }

        if (!NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()) {
            return Result.failure()
        }
        try {
            setForeground(foregroundInfo())
        } catch (_: Exception) {
            return Result.failure()
        }

        val succeeded = ScheduledVaultSyncRunner(applicationContext, inputData).run()
        return if (succeeded) Result.success() else Result.failure()
    }

    private fun foregroundInfo(): ForegroundInfo {
        val notification = ScheduledSyncNotification.create(applicationContext)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                ScheduledSyncNotification.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(ScheduledSyncNotification.NOTIFICATION_ID, notification)
        }
    }
}
