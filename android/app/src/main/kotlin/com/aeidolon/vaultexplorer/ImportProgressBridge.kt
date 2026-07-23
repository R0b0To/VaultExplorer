package com.aeidolon.vaultexplorer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

object ImportProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportProgress(
        opId: Int,
        done: Int,
        total: Int,
        currentName: String,
        transferredBytes: Long = 0L,
        totalBytes: Long = 0L,
    ) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onImportProgress",
                mapOf(
                    "opId" to opId,
                    "done" to done,
                    "total" to total,
                    "currentName" to currentName,
                    "transferredBytes" to transferredBytes,
                    "totalBytes" to totalBytes,
                ),
            )
        }
    }
}