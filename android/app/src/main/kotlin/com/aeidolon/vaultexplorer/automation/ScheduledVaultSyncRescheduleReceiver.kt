package com.aeidolon.vaultexplorer.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.aeidolon.vaultexplorer.handlers.ScheduledSyncHandlers
import java.util.concurrent.Executors

/** Restores daily alarms after boot, app replacement, timezone changes, or access grant. */
class ScheduledVaultSyncRescheduleReceiver : BroadcastReceiver() {
    companion object {
        private val executor = Executors.newSingleThreadExecutor()
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED,
                ScheduledSyncHandlers.ACTION_EXACT_ALARM_PERMISSION_CHANGED,
            )
        ) return

        val pending = goAsync()
        executor.execute {
            try {
                ScheduledSyncHandlers.rescheduleAll(context)
            } catch (e: Exception) {
                Log.e("ScheduledVaultSync", "Could not restore scheduled sync alarms", e)
            } finally {
                pending.finish()
            }
        }
    }
}
