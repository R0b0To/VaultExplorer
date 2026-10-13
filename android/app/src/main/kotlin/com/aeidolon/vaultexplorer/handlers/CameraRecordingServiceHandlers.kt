package com.aeidolon.vaultexplorer.handlers

import android.content.Intent
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.service.VaultCameraRecordingService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CameraRecordingServiceHandlers(private val activity: MainActivity) {
    fun handleStartBackgroundRecording(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Int>("volId") ?: -1
        val containerName = call.argument<String>("containerName") ?: ""
        val audioOnly = call.argument<Boolean>("audioOnly") ?: false
        val intent = Intent(activity, VaultCameraRecordingService::class.java).apply {
            putExtra(VaultCameraRecordingService.EXTRA_VOL_ID, volId)
            putExtra(VaultCameraRecordingService.EXTRA_CONTAINER_NAME, containerName)
            putExtra(VaultCameraRecordingService.EXTRA_AUDIO_ONLY, audioOnly)
        }
        ContextCompat.startForegroundService(activity, intent)
        result.success(null)
    }

    fun handleStopBackgroundRecording(call: MethodCall, result: MethodChannel.Result) {
        activity.stopService(Intent(activity, VaultCameraRecordingService::class.java))
        result.success(null)
    }
}
