package com.aeidolon.vaultexplorer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Pushes Check & Repair tool step-by-step log lines from
 * container_repair.cpp to Dart's live log panel
 * ([ContainerRepairSheet]), mirroring [SplitJoinProgressBridge]. A single
 * opId identifies one diagnose/restore/check call -- Dart discards lines
 * for an opId it's no longer listening to (e.g. after leaving the sheet).
 */
object RepairLogBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportLog(opId: Int, message: String) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onRepairLog",
                mapOf("opId" to opId, "message" to message),
            )
        }
    }
}
