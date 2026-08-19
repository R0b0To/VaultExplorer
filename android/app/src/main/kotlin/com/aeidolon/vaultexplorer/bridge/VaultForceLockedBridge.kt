package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Notifies Dart when a vault is locked from outside the normal
 * Dart-initiated lockContainer()/lock-all flow -- currently only the
 * "Lock all vaults" notification action on
 * [com.aeidolon.vaultexplorer.service.VaultKeepAliveService], which can
 * run (and lock vaults) while no Activity -- and so no Flutter engine --
 * exists at all. Mirrors [HiddenVolumeProtectionBridge]: best-effort
 * only, silently drops the event if nothing is currently listening.
 *
 * VaultDashboardScreen is the intended listener (see
 * addVaultForceLockedListener in vault_explorer_api.dart) and folds this
 * straight into the same cleanup path it already uses for USB-detach and
 * hidden-volume-protection lock events, so every other Dart screen that
 * reacts to "a container just got locked" keeps working unmodified.
 */
object VaultForceLockedBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportLocked(volId: Int) {
        val ch = channel ?: return
        mainHandler.post { ch.invokeMethod("onVaultForceLocked", mapOf("volId" to volId)) }
    }
}
