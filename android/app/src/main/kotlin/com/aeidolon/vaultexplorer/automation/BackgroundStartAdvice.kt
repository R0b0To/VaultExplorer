package com.aeidolon.vaultexplorer.automation

import android.content.Context
import android.os.Build
import android.os.PowerManager

/**
 * Wording for the "Android won't let a background-started process start a
 * foreground service" situation.
 *
 * When an automation broadcast cold-starts this app (nothing running, no
 * Activity), Android 12+ refuses to start a foreground service from that
 * background process unless the app has an exemption. One exemption the
 * user controls is the app's battery usage being set to Unrestricted
 * ([PowerManager.isIgnoringBatteryOptimizations]). Two places hit this:
 * VaultAutomationWorker's setForeground() and VaultAutomationReceiver's
 * startKeepAlive().
 *
 * These messages are sent to the automation app in RESULT_MESSAGE, so they
 * are plain English like every other Outcome message in this package. The
 * battery hint is left out when the app is already Unrestricted, because
 * telling the user to change a setting that is already set would send them
 * looking in the wrong place.
 */
internal object BackgroundStartAdvice {
    private const val BATTERY_HINT =
        "Set VaultExplorer's battery usage to Unrestricted " +
            "(Settings > Apps > VaultExplorer > Battery) so Android lets it " +
            "run when an automation starts it in the background."

    fun isUnrestricted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = context.getSystemService(PowerManager::class.java) ?: return true
        return powerManager.isIgnoringBatteryOptimizations(context.packageName)
    }

    /** RESULT_MESSAGE when the worker's foreground service start is refused. */
    fun foregroundWorkBlockedMessage(context: Context): String {
        val base = "Android refused to start foreground work for this action " +
            "while the app was in the background"
        return if (isUnrestricted(context)) base else "$base. $BATTERY_HINT"
    }

    /**
     * RESULT_MESSAGE when the vault unlocked but the keep-alive service
     * could not start. [base] is the normal success text ("Unlocked").
     */
    fun keepAliveNotStartedMessage(context: Context, base: String): String {
        val message = "$base, but the keep-alive service could not start, " +
            "so the vault may re-lock if Android stops the app"
        return if (isUnrestricted(context)) message else "$message. $BATTERY_HINT"
    }
}
