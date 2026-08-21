package com.aeidolon.vaultexplorer.handlers

import android.content.Intent
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.service.VaultKeepAliveService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

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

    fun handleUpdateProgress(call: MethodCall, result: MethodChannel.Result) {
        val hasActive = call.argument<Boolean>("hasActive") ?: false
        val title = call.argument<String>("title")
        val text = call.argument<String>("text")
        val progress = call.argument<Number>("progress")?.toInt()
        val max = call.argument<Number>("max")?.toInt() ?: 1000
        val indeterminate = call.argument<Boolean>("indeterminate") ?: false

        VaultKeepAliveService.updateOperationProgress(
            context = activity,
            hasActive = hasActive,
            title = title,
            text = text,
            progress = progress,
            max = max,
            indeterminate = indeterminate,
        )
        result.success(null)
    }
}