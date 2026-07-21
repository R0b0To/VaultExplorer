package com.aeidolon.vaultexplorer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Upcall target for native import-progress reporting — called from
 * MainActivity's importEntryRecursive() every time a file finishes being
 * written into the container, mirroring UnlockProgressBridge's role for
 * unlock auto-detect progress.
 *
 * [channel] is set once from MainActivity.configureFlutterEngine, next to
 * UnlockProgressBridge.channel. Import runs on ioExecutor (never the UI
 * thread), so — like UnlockProgressBridge — this hops onto the main
 * thread itself via a plain Handler before invoking the channel, rather
 * than relying on an Activity reference that may not be current.
 *
 * Forwarded to Dart as the "onImportProgress" event on the same
 * MethodChannel used everywhere else in this file for native-to-Dart
 * pushes — no separate EventChannel needed.
 */
object ImportProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportProgress(opId: Int, done: Int, total: Int, currentName: String) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onImportProgress",
                mapOf(
                    "opId" to opId,
                    "done" to done,
                    "total" to total,
                    "currentName" to currentName,
                ),
            )
        }
    }
}
