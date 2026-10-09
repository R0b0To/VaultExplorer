package com.aeidolon.vaultexplorer.automation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.util.NotificationLocale

internal object VaultAutomationNotification {
    const val NOTIFICATION_ID = 4202
    private const val CHANNEL_ID = "vault_automation_progress"

    fun build(
        context: Context,
        title: String,
        text: String,
        progress: Int? = null,
        max: Int = 1000,
        indeterminate: Boolean = true,
    ): Notification {
        ensureChannel(context)
        val contentIntent = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            Intent(context, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_vault)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
        if (indeterminate) builder.setProgress(0, 0, true)
        else if (progress != null) builder.setProgress(max, progress.coerceIn(0, max), false)
        return builder.build()
    }

    fun notify(
        context: Context,
        title: String,
        text: String,
        progress: Int? = null,
        max: Int = 1000,
        indeterminate: Boolean = true,
    ) {
        context.getSystemService(NotificationManager::class.java).notify(
            NOTIFICATION_ID,
            build(context, title, text, progress, max, indeterminate),
        )
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val localized = NotificationLocale.wrap(context)
        val channel = NotificationChannel(
            CHANNEL_ID,
            localized.getString(R.string.automation_progress_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = localized.getString(R.string.automation_progress_channel_description)
            setShowBadge(false)
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
