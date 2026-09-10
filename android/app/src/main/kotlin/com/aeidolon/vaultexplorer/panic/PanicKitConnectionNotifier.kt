package com.aeidolon.vaultexplorer.panic

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers

/**
 * Posts a plain, always-visible notification whenever an external app
 * pairs or unpairs as this app's PanicKit trigger. Pairing itself happens
 * silently -- TOFU (Trust On First Use), per the PanicKit spec -- with no
 * confirmation dialog the user has to tap through, so this notification
 * is the only thing telling a user they've just been paired with an app,
 * and their one way to notice an unexpected pairing between visits to
 * Settings.
 *
 * Respects Mask Mode exactly like [com.aeidolon.vaultexplorer.service.VaultKeepAliveService]'s
 * own notifications do: when [DisguiseModeHandlers.isDecoyActive] is true,
 * the title/text shown are generic ("a connected app was added/removed"),
 * never naming PanicKit or this app's real identity -- a pairing
 * notification that blows Mask Mode's cover would defeat the very
 * disguise feature it's supposed to coexist with. The notification
 * *channel*'s own name is kept generic unconditionally (not decoy-gated)
 * for the same reason `vault_keep_alive`'s channel identity is: unlike a
 * single notification, a channel name is visible in system Settings
 * indefinitely, long after the notification itself is dismissed.
 *
 * Deliberately its own isolated notifier, not reused by anything
 * duress-related (Phase 5): a duress response must never surface a
 * notification that could tip someone off, and keeping this file scoped
 * to PanicKit pairing only makes that boundary obvious rather than
 * something a future edit could accidentally blur.
 */
object PanicKitConnectionNotifier {
    private const val TAG = "PanicKit_Notifier"
    private const val CHANNEL_ID = "panickit_connection"
    private const val NOTIFICATION_ID = 4301

    fun notifyPaired(context: Context, triggerPackageName: String) {
        val decoy = DisguiseModeHandlers.isDecoyActive(context)
        val title = context.getString(if (decoy) R.string.decoy_app_name else R.string.panickit_paired_notification_title)
        val text = if (decoy) {
            context.getString(R.string.panickit_paired_notification_text_decoy)
        } else {
            context.getString(R.string.panickit_paired_notification_text, appLabelOrPackageName(context, triggerPackageName))
        }
        post(context, title, text, decoy)
    }

    fun notifyUnpaired(context: Context, previousTriggerPackageName: String?) {
        val decoy = DisguiseModeHandlers.isDecoyActive(context)
        val title = context.getString(if (decoy) R.string.decoy_app_name else R.string.panickit_unpaired_notification_title)
        val text = if (decoy) {
            context.getString(R.string.panickit_unpaired_notification_text_decoy)
        } else {
            val label = previousTriggerPackageName?.let { appLabelOrPackageName(context, it) }
                ?: context.getString(R.string.panickit_unknown_app)
            context.getString(R.string.panickit_unpaired_notification_text, label)
        }
        post(context, title, text, decoy)
    }

    private fun appLabelOrPackageName(context: Context, packageName: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
    } catch (e: Exception) {
        packageName
    }

    private fun post(context: Context, title: String, text: String, decoy: Boolean) {
        try {
            val nm = context.getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.panickit_notification_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = context.getString(R.string.panickit_notification_channel_description)
            }
            nm.createNotificationChannel(channel)
            val contentIntent = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val smallIcon = if (decoy) R.drawable.ic_notification_folder else R.drawable.ic_notification_vault
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(smallIcon)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()
            nm.notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted -- the pairing/unpairing
            // itself already succeeded; the user just won't see this.
            VeLog.w(TAG, e) { "post: notification permission denied" }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "post: failed to show notification" }
        }
    }
}