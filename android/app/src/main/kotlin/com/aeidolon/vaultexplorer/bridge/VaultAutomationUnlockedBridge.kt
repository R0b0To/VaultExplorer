package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Notifies Dart when a vault is unlocked from outside the normal
 * Dart-initiated unlockContainer()/unlockDirectoryVault() flow -- currently
 * only VaultAutomationReceiver's UNLOCK_VAULT action, which can run (and
 * mount a container) while no Activity -- and so no Flutter engine -- exists
 * at all. Mirrors [VaultForceLockedBridge] for the opposite direction:
 * best-effort only, silently drops the event if nothing is currently
 * listening.
 *
 * That drop case is expected, not a bug to fix here -- but unlike the
 * lock-direction mirror below, there is currently NO separate
 * reconciliation on dashboard load/resume for the mount case, so a vault
 * unlocked entirely while the app was closed (or backgrounded past the
 * point Android killed the engine) will show as locked in the dashboard
 * until the person does something else that reloads it (e.g. re-entering
 * the vault list). This bridge only covers the case the app happens to
 * already be open, with a live engine, when the broadcast lands. If that
 * gap matters, the fix is a real getActiveContainerSessions()-style
 * reconciliation call on init/resume -- not implemented yet.
 *
 * VaultDashboardScreen is the intended listener (see
 * addVaultAutomationUnlockedListener in vault_explorer_api.dart).
 */
object VaultAutomationUnlockedBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportUnlocked(
        volId: Int,
        uri: String,
        displayName: String,
        containerFormat: String,
        readOnly: Boolean,
        files: List<String>,
    ) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onVaultAutomationUnlocked",
                mapOf(
                    "volId" to volId,
                    "uri" to uri,
                    "displayName" to displayName,
                    "containerFormat" to containerFormat,
                    "readOnly" to readOnly,
                    "files" to files,
                ),
            )
        }
    }
}