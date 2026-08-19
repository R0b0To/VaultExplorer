package com.aeidolon.vaultexplorer.handlers

import android.content.Intent
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.service.VaultKeepAliveService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Starts/stops [VaultKeepAliveService] to mirror the "keep vaults running
 * in background" app setting. Dart calls handleSyncBackgroundService
 * (ChannelMethods.SYNC_BACKGROUND_SERVICE) from two places -- see
 * app_settings_screen.dart's toggle onChanged and
 * vault_dashboard_screen.dart's _syncSecureScreen -- so this stays in sync
 * both when the setting itself changes and whenever the set of unlocked
 * vaults changes, without either call site needing to know the other's
 * state.
 *
 * [ContainerSessionRegistry.hasAnyActiveSessions] is re-checked here
 * rather than trusted from Dart's [call] arguments on purpose: it's the
 * single source of truth for what's actually unlocked, and re-deriving it
 * natively means a stale/racy count from Dart can never start the service
 * with nothing for it to keep alive.
 */
class BackgroundServiceHandlers(private val activity: MainActivity) {
    fun handleSyncBackgroundService(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        val intent = Intent(activity, VaultKeepAliveService::class.java)
        if (enabled && ContainerSessionRegistry.hasAnyActiveSessions()) {
            ContextCompat.startForegroundService(activity, intent)
        } else {
            activity.stopService(intent)
        }
        result.success(null)
    }
}
