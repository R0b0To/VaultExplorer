package com.aeidolon.vaultexplorer.handlers

import android.content.Intent
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.service.VaultCameraRecordingService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CameraRecordingServiceHandlers(private val activity: MainActivity) {
    /**
     * True between this activity starting the recording service and stopping
     * it. The service's recording is owned by this activity's camera/audio
     * plugins, so when the activity goes away without Dart getting to call
     * [handleStopBackgroundRecording] (task swiped from Recents, activity
     * destroyed with the engine) the service has to be stopped from here.
     * Tracked per activity so another MainActivity subclass instance (share,
     * quick capture) being destroyed never stops a recording it didn't start.
     */
    private var serviceStarted = false

    fun handleStartBackgroundRecording(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Int>("volId") ?: -1
        val containerName = call.argument<String>("containerName") ?: ""
        val audioOnly = call.argument<Boolean>("audioOnly") ?: false
        val intent = Intent(activity, VaultCameraRecordingService::class.java).apply {
            putExtra(VaultCameraRecordingService.EXTRA_VOL_ID, volId)
            putExtra(VaultCameraRecordingService.EXTRA_CONTAINER_NAME, containerName)
            putExtra(VaultCameraRecordingService.EXTRA_AUDIO_ONLY, audioOnly)
        }
        // Reports whether the service really started. Android refuses to start
        // a camera/microphone foreground service from the background (and, on
        // 14+, without the matching permission), and a recording that is not
        // protected by one cannot be allowed to carry on once the app leaves
        // the screen: Dart uses this answer to decide.
        val started = try {
            ContextCompat.startForegroundService(activity, intent)
            true
        } catch (e: Exception) {
            false
        }
        if (started) serviceStarted = true
        result.success(started)
    }

    fun handleStopBackgroundRecording(call: MethodCall, result: MethodChannel.Result) {
        serviceStarted = false
        activity.stopService(Intent(activity, VaultCameraRecordingService::class.java))
        result.success(null)
    }

    /**
     * Called from MainActivity.onDestroy, after the camera/audio plugins have
     * been disposed (which ends any in-progress recording). If this activity
     * started the recording service and Dart never stopped it, stop it now so
     * its ongoing notification doesn't keep claiming a recording that is no
     * longer happening -- and so [VaultCameraRecordingService.isRunning]
     * stops suppressing screen-off and native auto-close handling.
     */
    fun onActivityDestroyed() {
        if (!serviceStarted) return
        serviceStarted = false
        activity.stopService(Intent(activity, VaultCameraRecordingService::class.java))
    }
}
