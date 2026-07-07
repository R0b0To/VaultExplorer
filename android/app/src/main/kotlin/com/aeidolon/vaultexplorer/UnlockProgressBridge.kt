package com.aeidolon.vaultexplorer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Upcall target for native unlock-progress reporting — called directly
 * from vaultexplorer.cpp's deriveAndValidateHeader() (see
 * g_progressBridgeClass/g_progressReportMethod there), via
 * reportProgress() below, every time it finishes trying one hash/cipher
 * combination during auto-detect.
 *
 * [channel] is set once from MainActivity.configureFlutterEngine, mirroring
 * how `methodChannel` itself is stored there. This deliberately does NOT
 * hold an Activity reference (unlike e.g. runOnUiThread elsewhere in this
 * codebase) because reportProgress() can be called from any of the native
 * worker threads spawned inside deriveAndValidateHeader() — never the
 * original JNI call's thread, and never the UI thread — so it needs its own
 * way to hop onto the main thread, via a plain Handler.
 *
 * Forwarded to Dart as the "onUnlockProgress" event on the same MethodChannel
 * used everywhere else in this file for native-to-Dart pushes (see
 * "onUsbContainerDetached"/"onAppSelected" in MainActivity.kt) — no separate
 * EventChannel needed.
 */
object UnlockProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportProgress(volId: Int, attempted: Int, total: Int, hashId: Int, cipherId: Int) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onUnlockProgress",
                mapOf(
                    "volId" to volId,
                    "attempted" to attempted,
                    "total" to total,
                    "hashId" to hashId,
                    "cipherId" to cipherId,
                ),
            )
        }
    }
}