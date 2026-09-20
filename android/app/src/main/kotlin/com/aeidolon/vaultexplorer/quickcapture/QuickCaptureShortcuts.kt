package com.aeidolon.vaultexplorer.quickcapture

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.VaultQuickCaptureActivity
import com.aeidolon.vaultexplorer.VeLog

private const val TAG = "QuickCaptureShortcuts"
private const val SHORTCUT_ID = "quick_capture"

/**
 * The static/dynamic launcher shortcut and the "pin to home screen"
 * request for Quick Capture (see [VaultQuickCaptureActivity]). Uses
 * ShortcutManagerCompat throughout rather than the raw framework API so
 * pin-support detection and pre-O_MR1 fallbacks are handled for free.
 *
 * Deliberately not decoy-aware: the shortcut shows up under whichever
 * launcher identity (real or decoy) is currently active without any
 * special-casing here, matching how the Android Share Sheet target
 * already behaves under both identities today.
 */
object QuickCaptureShortcuts {

    private fun buildIntent(context: Context): Intent =
        Intent(context, VaultQuickCaptureActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK
        }

    private fun buildShortcutInfo(context: Context): ShortcutInfoCompat {
        val label = context.getString(R.string.quick_capture_shortcut_label)
        return ShortcutInfoCompat.Builder(context, SHORTCUT_ID)
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(IconCompat.createWithResource(context, R.drawable.ic_quick_capture))
            .setIntent(buildIntent(context))
            .build()
    }

    /**
     * Registers/refreshes the dynamic shortcut shown when the person
     * long-presses the launcher icon. Cheap and idempotent -- safe to
     * call on every app start (see MainActivity.onCreate) and again
     * immediately after the person flips the Settings toggle, so
     * disabling Quick Capture also removes the shortcut without waiting
     * for the next launch.
     */
    fun refreshDynamicShortcut(context: Context) {
        try {
            if (QuickCaptureSettings.isTileEnabled(context)) {
                ShortcutManagerCompat.pushDynamicShortcut(context, buildShortcutInfo(context))
            } else {
                ShortcutManagerCompat.removeDynamicShortcuts(context, listOf(SHORTCUT_ID))
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "refreshDynamicShortcut failed" }
        }
    }

    /**
     * Requests the launcher pin a Quick Capture icon to the home screen,
     * from the in-app "Add to Home screen" settings button. The
     * accept/decline itself happens in a system dialog this call gets no
     * result from; the boolean only reflects whether the request could be
     * made at all (false on a launcher with no pinning support).
     */
    fun requestPinShortcut(context: Context): Boolean = try {
        if (ShortcutManagerCompat.isRequestPinShortcutSupported(context)) {
            ShortcutManagerCompat.requestPinShortcut(context, buildShortcutInfo(context), null)
        } else {
            false
        }
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "requestPinShortcut failed" }
        false
    }
}
