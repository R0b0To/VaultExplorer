package com.aeidolon.vaultexplorer.service

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import java.security.MessageDigest

/** Wakes the keep-alive service when an inactivity deadline passes. */
internal object ContainerAutoCloseAlarm {
    const val ACTION = "com.aeidolon.vaultexplorer.action.CONTAINER_AUTO_CLOSE"
    const val EXTRA_URI = "vaultUri"
    const val EXTRA_DEADLINE = "deadlineMillis"

    fun schedule(context: Context, uri: String, deadlineMillis: Long?) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        if (deadlineMillis == null || deadlineMillis <= 0L) {
            cancel(context, uri)
            return
        }

        val intent = Intent(context, ContainerAutoCloseAlarmReceiver::class.java)
            .setAction(ACTION)
            .setData(alarmUri(uri))
            .putExtra(EXTRA_URI, uri)
            .putExtra(EXTRA_DEADLINE, deadlineMillis)
        val alarm = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val canScheduleExact =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
        try {
            if (canScheduleExact) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineMillis, alarm)
            } else {
                scheduleInexactWakeup(alarmManager, deadlineMillis, alarm)
            }
        } catch (_: SecurityException) {
            scheduleInexactWakeup(alarmManager, deadlineMillis, alarm)
        }
    }

    private fun scheduleInexactWakeup(
        alarmManager: AlarmManager,
        deadlineMillis: Long,
        alarm: PendingIntent,
    ) {
        // Still wake the process on devices where exact-alarm access was not
        // granted; Android may defer the alarm while in Doze.
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineMillis, alarm)
    }

    fun cancel(context: Context, uri: String) {
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent(context, uri))
    }

    private fun pendingIntent(context: Context, uri: String): PendingIntent {
        val intent = Intent(context, ContainerAutoCloseAlarmReceiver::class.java)
            .setAction(ACTION)
            .setData(alarmUri(uri))
            .putExtra(EXTRA_URI, uri)
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun alarmUri(uri: String): Uri {
        val digest = MessageDigest.getInstance("SHA-256").digest(uri.toByteArray())
        val identity = digest.take(16).joinToString("") { "%02x".format(it.toInt() and 0xff) }
        return Uri.parse("vaultexplorer-autoclose://$identity")
    }
}

class ContainerAutoCloseAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ContainerAutoCloseAlarm.ACTION) return
        val uri = intent.getStringExtra(ContainerAutoCloseAlarm.EXTRA_URI) ?: return
        val deadline = intent.getLongExtra(ContainerAutoCloseAlarm.EXTRA_DEADLINE, 0L)
        if (deadline <= 0L) return
        // Keep the CPU awake long enough for the foreground service to receive
        // the alarm intent and acquire its own lock-operation wake lock.
        if (!VaultKeepAliveService.hasRunningInstance()) {
            context.getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VaultExplorer:AutoCloseAlarm")
                .acquire(30_000L)
        }
        VaultKeepAliveService.onAutoCloseAlarm(context, uri, deadline)
    }
}
