package com.aeidolon.vaultexplorer.handlers

import android.content.Context
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.aeidolon.vaultexplorer.automation.AutomationSettings
import com.aeidolon.vaultexplorer.automation.ScheduledVaultSyncWorker
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/** Schedules device-local daily sync work. No unlock secret enters WorkManager data. */
class ScheduledSyncHandlers(context: Context) {
    private val appContext = context.applicationContext

    companion object {
        private const val VAULT_TAG_PREFIX = "scheduled-vault-sync-vault-"

        fun cancelSchedulesForVault(context: Context, vaultUri: String) {
            WorkManager.getInstance(context.applicationContext)
                .cancelAllWorkByTag(vaultTag(vaultUri))
        }

        private fun vaultTag(vaultUri: String): String {
            val bytes = MessageDigest.getInstance("SHA-256")
                .digest(vaultUri.toByteArray(Charsets.UTF_8))
            val digest = bytes.take(12).joinToString("") { "%02x".format(it) }
            return "$VAULT_TAG_PREFIX$digest"
        }
    }

    fun handleSchedule(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") == true
        val vaultUri = call.argument<String>("vaultUri")
        val ruleId = call.argument<String>("ruleId")
        if (vaultUri.isNullOrBlank() || ruleId.isNullOrBlank()) {
            result.error("INVALID_ARGS", "vaultUri and ruleId are required", null)
            return
        }

        val workName = uniqueName(vaultUri, ruleId)
        val manager = WorkManager.getInstance(appContext)
        if (!enabled) {
            manager.cancelUniqueWork(workName).result.addListener(
                { result.success(true) },
                androidx.core.content.ContextCompat.getMainExecutor(appContext),
            )
            return
        }

        if (!AutomationSettings.canImportExport(appContext, vaultUri) ||
            AutomationSettings.getStoredPassword(appContext, vaultUri).isNullOrEmpty()
        ) {
            result.success(false)
            return
        }
        if (!NotificationManagerCompat.from(appContext).areNotificationsEnabled()) {
            result.success(false)
            return
        }

        val targetUri = call.argument<String>("targetUri")
        val targetSubPath = call.argument<String>("targetSubPath") ?: ""
        if (targetUri.isNullOrBlank()) {
            result.error("INVALID_ARGS", "targetUri is required", null)
            return
        }

        val request = PeriodicWorkRequestBuilder<ScheduledVaultSyncWorker>(
            24,
            TimeUnit.HOURS,
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiresBatteryNotLow(true)
                    .setRequiresStorageNotLow(true)
                    .build(),
            )
            .addTag(vaultTag(vaultUri))
            .setInputData(
                workDataOf(
                    ScheduledVaultSyncWorker.KEY_VAULT_URI to vaultUri,
                    ScheduledVaultSyncWorker.KEY_VAULT_NAME to
                        (call.argument<String>("vaultDisplayName") ?: "Vault"),
                    ScheduledVaultSyncWorker.KEY_RULE_ID to ruleId,
                    ScheduledVaultSyncWorker.KEY_TARGET_URI to targetUri,
                    ScheduledVaultSyncWorker.KEY_TARGET_SUB_PATH to targetSubPath,
                    ScheduledVaultSyncWorker.KEY_TARGET_NAME to
                        (call.argument<String>("targetDisplayName") ?: "Folder"),
                ),
            )
            .build()

        manager.enqueueUniquePeriodicWork(
            workName,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        ).result.addListener(
            { result.success(true) },
            androidx.core.content.ContextCompat.getMainExecutor(appContext),
        )
    }

    private fun uniqueName(vaultUri: String, ruleId: String): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest("$vaultUri\n$ruleId".toByteArray(Charsets.UTF_8))
        val digest = bytes.take(12).joinToString("") { "%02x".format(it) }
        return "scheduled-vault-sync-$digest"
    }
}
