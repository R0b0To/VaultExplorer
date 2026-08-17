package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

object HiddenVolumeProtectionBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportTriggered(volId: Int) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod("onHiddenVolumeProtectionTriggered", mapOf("volId" to volId))
        }
    }
}
