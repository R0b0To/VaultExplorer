package com.aeidolon.vaultexplorer.automation

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.aeidolon.vaultexplorer.VeLog

/** Executes long automation actions as WorkManager foreground work. A plain
 * exported broadcast is not an Android exemption for starting an FGS. */
class VaultAutomationWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    companion object {
        const val KEY_PAYLOAD_ID = "automationPayloadId"
        const val KEY_ACTION = "automationAction"
        const val TAG = "vault-automation-action"
        const val UNIQUE_WORK_NAME = "vault-automation-actions"
        private const val LOG_TAG = "VaultExplorer_AutomationWorker"
    }

    override suspend fun doWork(): Result {
        val action = inputData.getString(KEY_ACTION) ?: return Result.failure()
        val payloadId = inputData.getString(KEY_PAYLOAD_ID) ?: return Result.failure()
        val receiver = VaultAutomationReceiver()
        val title = receiver.progressTitleForAction(applicationContext, action)
            ?: return Result.failure()

        try {
            setForeground(foregroundInfo(title))
        } catch (e: Exception) {
            VaultAutomationActionPayload.clear(applicationContext, payloadId)
            VeLog.e(LOG_TAG, e) { "WorkManager could not start foreground automation for $action" }
            VaultAutomationReceiver.sendResult(
                applicationContext,
                action,
                VaultAutomationReceiver.Outcome("ERROR", "Android could not start foreground work for this action"),
            )
            return Result.failure()
        }

        val intent = VaultAutomationActionPayload.consume(applicationContext, payloadId)
        if (intent == null) {
            VaultAutomationReceiver.sendResult(
                applicationContext,
                action,
                VaultAutomationReceiver.Outcome("ERROR", "Queued automation data could not be read"),
            )
            return Result.failure()
        }

        val progressId = VaultAutomationProgress.begin(applicationContext, title)
        return try {
            receiver.handleAction(applicationContext, action, intent, progressId)
            Result.success()
        } catch (e: Exception) {
            VeLog.e(LOG_TAG, e) { "Automation worker failed for $action" }
            VaultAutomationReceiver.sendResult(
                applicationContext,
                action,
                VaultAutomationReceiver.Outcome("ERROR", e.message ?: "Automation action failed"),
            )
            Result.failure()
        } finally {
            VaultAutomationProgress.finish(progressId)
        }
    }

    private fun foregroundInfo(title: String): ForegroundInfo {
        val notification = VaultAutomationNotification.build(
            applicationContext,
            title,
            applicationContext.getString(com.aeidolon.vaultexplorer.R.string.automation_progress_starting),
            indeterminate = true,
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                VaultAutomationNotification.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(VaultAutomationNotification.NOTIFICATION_ID, notification)
        }
    }
}
