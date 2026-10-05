package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import com.aeidolon.vaultexplorer.saf.MirrorPushEvents
import io.flutter.plugin.common.MethodChannel

/** Forwards mirror activity to Flutter while retaining the latest native state. */
object MirrorPushBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var channel: MethodChannel? = null

    private val listener = MirrorPushEvents.Listener { snapshot ->
        val args = mapOf("activeCount" to snapshot.activeCount)
        mainHandler.post {
            channel?.invokeMethod("onMirrorPushActivity", args)
        }
    }

    init {
        MirrorPushEvents.addListener(listener)
    }

    fun attach(channel: MethodChannel) {
        this.channel = channel
        val snapshot = MirrorPushEvents.snapshot()
        mainHandler.post {
            if (this.channel === channel) {
                channel.invokeMethod("onMirrorPushActivity", mapOf("activeCount" to snapshot.activeCount))
            }
        }
    }

    fun detach(channel: MethodChannel?) {
        if (channel != null && this.channel === channel) this.channel = null
    }
}
