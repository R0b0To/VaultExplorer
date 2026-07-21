package com.aeidolon.vaultexplorer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

object UnlockProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportProgress(volId: Int, attempted: Int, total: Int, hashId: Int, cipherId: Int, format: Int, slot: Int) {
        val ch = channel ?: return
        val formatStr = when (format) {
            1 -> "luks1"
            2 -> "luks2"
            else -> "veracrypt"
        }
        mainHandler.post {
            ch.invokeMethod(
                "onUnlockProgress",
                mapOf(
                    "volId" to volId,
                    "attempted" to attempted,
                    "total" to total,
                    "hashId" to hashId,
                    "cipherId" to cipherId,
                    "containerFormat" to formatStr,
                    "slot" to slot,
                ),
            )
        }
    }
}