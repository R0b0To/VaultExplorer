package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Notifies Dart when the user taps "Stop & Save" on the background video
 * recording notification (see [com.aeidolon.vaultexplorer.service.VaultCameraRecordingService]).
 * The actual stop/finalize/encrypt work has to happen in Dart -- it's the
 * only side that knows the in-flight virtual path and vault write session
 * -- so this just forwards the tap. Mirrors [VaultForceLockedBridge]:
 * best-effort only, silently drops the event if nothing is currently
 * listening (e.g. the Flutter engine was somehow torn down while the
 * foreground service was still alive).
 *
 * CameraCaptureScreen is the intended listener (see
 * addBackgroundRecordingStopRequestedListener in vault_explorer_api.dart).
 */
object VaultCameraStopRequestedBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportStopRequested(volId: Int) {
        val ch = channel ?: return
        mainHandler.post { ch.invokeMethod("onBackgroundRecordingStopRequested", mapOf("volId" to volId)) }
    }
}
