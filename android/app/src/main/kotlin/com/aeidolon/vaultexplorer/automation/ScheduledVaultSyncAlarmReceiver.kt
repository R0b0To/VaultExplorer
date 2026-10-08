package com.aeidolon.vaultexplorer.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.handlers.ScheduledSyncHandlers

/** Exact-alarm entry point. Android permits this receiver to start the sync foreground service. */
class ScheduledVaultSyncAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ScheduledSyncHandlers.ACTION_DAILY_SYNC) return
        val vaultUri = intent.getStringExtra(ScheduledSyncHandlers.EXTRA_VAULT_URI)
            ?: return
        val ruleId = intent.getStringExtra(ScheduledSyncHandlers.EXTRA_RULE_ID)
            ?: return
        val scheduledFor = intent.getLongExtra(ScheduledSyncHandlers.EXTRA_SCHEDULED_FOR, 0L)
        val input = ScheduledSyncHandlers.getStoredInput(
            context,
            vaultUri,
            ruleId,
            scheduledFor,
        ) ?: return
        if (!ScheduledSyncHandlers.isScheduleActive(context, input)) return

        val serviceIntent = Intent(context, ScheduledVaultSyncService::class.java).apply {
            putExtra(ScheduledSyncHandlers.EXTRA_VAULT_URI, vaultUri)
            putExtra(ScheduledSyncHandlers.EXTRA_RULE_ID, ruleId)
            putExtra(ScheduledSyncHandlers.EXTRA_SCHEDULED_FOR, scheduledFor)
        }
        try {
            ContextCompat.startForegroundService(context, serviceIntent)
        } catch (e: Exception) {
            Log.e("ScheduledVaultSync", "Unable to start scheduled sync service", e)
        }
    }
}
