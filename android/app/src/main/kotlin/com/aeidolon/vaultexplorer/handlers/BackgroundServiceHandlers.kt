package com.aeidolon.vaultexplorer.handlers

import android.content.Intent
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.service.VaultKeepAliveService
import com.aeidolon.vaultexplorer.service.VaultCameraRecordingService
import com.aeidolon.vaultexplorer.service.VaultAutomationRecordingService
import com.aeidolon.vaultexplorer.util.NotificationLocale
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BackgroundServiceHandlers(private val activity: MainActivity) {
    fun handleSetNotificationLocale(call: MethodCall, result: MethodChannel.Result) {
        NotificationLocale.save(activity, call.argument<String>("languageCode"))
        VaultKeepAliveService.refreshNotification()
        VaultCameraRecordingService.refreshNotification()
        VaultAutomationRecordingService.refreshNotification()
        result.success(null)
    }

    fun handleSyncBackgroundService(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        VaultKeepAliveService.updateLockOnAppBackgroundUris(
            call.argument<List<String>>("lockOnAppBackgroundUris"),
        )
        val hasSessions = ContainerSessionRegistry.hasAnyActiveSessions()
        val intent = Intent(activity, VaultKeepAliveService::class.java)
        if (enabled && hasSessions) {
            VeLog.d(TAG) { "handleSyncBackgroundService: enabled=true, hasSessions=true -> startForegroundService" }
            ContextCompat.startForegroundService(activity, intent)
        } else {
            VeLog.d(TAG) {
                "handleSyncBackgroundService: enabled=$enabled, hasSessions=$hasSessions -> stopService " +
                    "(activeSessions=${ContainerSessionRegistry.activeSessions.keys.toList()})"
            }
            activity.stopService(intent)
        }
        result.success(null)
    }

    fun handleScheduleContainerAutoClose(call: MethodCall, result: MethodChannel.Result) {
        val vaultUri = call.argument<String>("vaultUri")
        if (vaultUri.isNullOrBlank()) {
            result.error("INVALID_ARGS", "vaultUri is required", null)
            return
        }
        val deadlineMillis = call.argument<Number>("deadlineMillis")?.toLong()
        VaultKeepAliveService.scheduleContainerAutoClose(activity, vaultUri, deadlineMillis)
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

    private companion object {
        const val TAG = "BackgroundServiceHandlers"
    }
}
