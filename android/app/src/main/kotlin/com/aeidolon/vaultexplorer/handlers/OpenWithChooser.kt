package com.aeidolon.vaultexplorer.handlers

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.aeidolon.vaultexplorer.VeLog

/**
 * Builds the system "Open with" chooser used by the file browser, and -- when
 * the caller wants to remember the person's pick -- asks the system to report
 * which app was chosen.
 *
 * Every storage type (vault, added folder, plain local storage) goes through
 * [build], so they all report a pick the same way: the chooser is given an
 * IntentSender that broadcasts [ACTION] with `EXTRA_CHOSEN_COMPONENT`, and
 * `MainActivity` forwards that to Dart as `onAppSelected`, tagged with the
 * [EXTRA_REQUEST_ID] the Dart side handed in. Matching on that id (rather than
 * on the file extension) means a pick is only ever credited to the open that
 * asked to remember it.
 */
object OpenWithChooser {
    /** Action of the broadcast the system sends when an app is picked. */
    const val ACTION = "com.aeidolon.vaultexplorer.ACTION_CHOOSER"
    const val EXTRA_EXTENSION = "extension"
    const val EXTRA_REQUEST_ID = "requestId"

    private const val TAG = "OpenWithChooser"

    /**
     * A chooser for [target]. With a non-empty [requestId] the pick is reported
     * back (see the class doc); without one it is a plain chooser and nothing
     * is broadcast.
     */
    fun build(
        context: Context,
        target: Intent,
        title: CharSequence?,
        extension: String,
        requestId: String?,
    ): Intent {
        if (requestId.isNullOrEmpty()) {
            return Intent.createChooser(target, title)
        }
        val receiverIntent = Intent(ACTION).apply {
            `package` = context.packageName
            putExtra(EXTRA_EXTENSION, extension)
            putExtra(EXTRA_REQUEST_ID, requestId)
        }
        // FLAG_MUTABLE is required: the system adds EXTRA_CHOSEN_COMPONENT to
        // this intent when it fires. The request code is unique per request so
        // two open-with calls never share (and overwrite) one PendingIntent.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pending = PendingIntent.getBroadcast(context, requestId.hashCode(), receiverIntent, flags)
        return Intent.createChooser(target, title, pending.intentSender)
    }

    /**
     * A remembered app could not open the file (uninstalled, disabled, or
     * installed only in another profile such as a work profile). The callers
     * fall back to the chooser; this just leaves a trace in the debug log.
     */
    fun logReplayFailure(packageName: String, error: Throwable) {
        VeLog.w(TAG, error) {
            "Remembered app $packageName could not open the file (${error.javaClass.simpleName}); showing the chooser instead"
        }
    }
}
