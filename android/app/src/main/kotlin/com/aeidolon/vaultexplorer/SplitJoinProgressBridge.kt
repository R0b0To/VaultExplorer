package com.aeidolon.vaultexplorer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Pushes Container Splitter/Joiner byte-progress from [SplitJoinHandlers]
 * to Dart, mirroring [ImportProgressBridge]. Kept as its own event
 * (`"onSplitJoinProgress"`) rather than reusing `"onImportProgress"` since
 * the two carry different shapes (bytes-only here; import also tracks a
 * per-entry `done`/`total` count and `currentName`) and belong to
 * independent opId spaces (see [SplitJoinCancellation]'s doc comment).
 */
object SplitJoinProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportProgress(opId: Int, bytesDone: Long, bytesTotal: Long) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onSplitJoinProgress",
                mapOf(
                    "opId" to opId,
                    "bytesDone" to bytesDone,
                    "bytesTotal" to bytesTotal,
                ),
            )
        }
    }
}
