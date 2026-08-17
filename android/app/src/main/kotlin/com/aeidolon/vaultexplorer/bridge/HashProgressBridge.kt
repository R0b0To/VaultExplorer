package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import com.aeidolon.vaultexplorer.handlers.HashVerifierHandlers

/**
 * Pushes [HashVerifierHandlers.handleComputeExternalFileHash] byte-progress
 * to Dart as `"onHashProgress"`, mirroring [SplitJoinProgressBridge]. Vault
 * (non-external) hashing never reaches this bridge at all -- it runs
 * entirely in Dart via [readFileChunk] and reports progress through a
 * plain callback, with no platform-channel event needed.
 */
object HashProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportProgress(opId: Int, bytesDone: Long, bytesTotal: Long) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onHashProgress",
                mapOf(
                    "opId" to opId,
                    "bytesDone" to bytesDone,
                    "bytesTotal" to bytesTotal,
                ),
            )
        }
    }
}
