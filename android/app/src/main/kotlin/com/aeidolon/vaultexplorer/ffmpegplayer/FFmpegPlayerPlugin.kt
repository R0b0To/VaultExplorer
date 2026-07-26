// File: android/app/src/main/kotlin/com/aeidolon/vaultexplorer/ffmpegplayer/FFmpegPlayerPlugin.kt
package com.aeidolon.vaultexplorer.ffmpegplayer

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.atomic.AtomicLong

private const val METHOD_CHANNEL = "com.aeidolon.vaultexplorer/ffmpeg_player"
private const val EVENT_CHANNEL_PREFIX = "com.aeidolon.vaultexplorer/ffmpeg_player/events/"

class FFmpegPlayerPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textureRegistry: TextureRegistry,
) : MethodChannel.MethodCallHandler {
    private val nextId = AtomicLong(0)
    private val players = LinkedHashMap<Long, FFmpegPlayerEngine>()
    private val eventChannels = LinkedHashMap<Long, EventChannel>()
    private val eventSinks = LinkedHashMap<Long, EventChannel.EventSink?>()
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val messenger = messenger

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> {
                    val id = nextId.getAndIncrement()
                    val engine = FFmpegPlayerEngine(context, textureRegistry, id) { event ->
                        eventSinks[id]?.success(event)
                    }
                    players[id] = engine
                    val eventChannel = EventChannel(messenger, EVENT_CHANNEL_PREFIX + id)
                    eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                        override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                            eventSinks[id] = sink
                        }
                        override fun onCancel(arguments: Any?) {
                            eventSinks[id] = null
                        }
                    })
                    eventChannels[id] = eventChannel
                    result.success(mapOf("playerId" to id, "textureId" to engine.textureId))
                }
                "setDataSource" -> withEngine(call, result) { engine, args ->
                    val uri = args["contentUri"] as? String ?: return@withEngine result.error("bad_args", "contentUri required", null)
                    val autoPlay = args["autoPlay"] as? Boolean ?: false
                    engine.setDataSource(uri, autoPlay)
                    result.success(null)
                }
                "play" -> withEngine(call, result) { engine, _ -> engine.play(); result.success(null) }
                "pause" -> withEngine(call, result) { engine, _ -> engine.pause(); result.success(null) }
                "stop" -> withEngine(call, result) { engine, _ -> engine.stop(); result.success(null) }
                "seekTo" -> withEngine(call, result) { engine, args ->
                    engine.seekTo((args["positionMs"] as? Number)?.toLong() ?: 0L)
                    result.success(null)
                }
                "setVolume" -> withEngine(call, result) { engine, args ->
                    engine.setVolume((args["volume"] as? Number)?.toInt() ?: 100)
                    result.success(null)
                }
                "setRate" -> withEngine(call, result) { engine, args ->
                    engine.setRate((args["rate"] as? Number)?.toFloat() ?: 1.0f)
                    result.success(null)
                }
                "setLooping" -> withEngine(call, result) { engine, args ->
                    engine.setLooping(args["looping"] as? Boolean ?: false)
                    result.success(null)
                }
                "getDiagnostics" -> withEngine(call, result) { engine, _ ->
                    // Unlike the fire-and-forget calls above, this one waits for
                    // engine.getDiagnostics' async callback before resolving --
                    // there's no separate event-channel notification for it, so
                    // the method result itself has to carry the answer.
                    engine.getDiagnostics { diagnostics -> result.success(diagnostics) }
                }
                "dispose" -> {
                    val id = (call.arguments as Map<*, *>)["playerId"] as Number
                    disposePlayer(id.toLong())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ffmpeg_player_error", e.message, null)
        }
    }

    private inline fun withEngine(call: MethodCall, result: MethodChannel.Result, block: (FFmpegPlayerEngine, Map<*, *>) -> Unit) {
        val args = call.arguments as? Map<*, *>
        val id = (args?.get("playerId") as? Number)?.toLong()
        val engine = id?.let { players[it] }
        if (engine == null) return result.error("no_such_player", "No player for id $id", null)
        block(engine, args)
    }

    private fun disposePlayer(id: Long) {
        players.remove(id)?.dispose()
        eventChannels.remove(id)?.setStreamHandler(null)
        eventSinks.remove(id)
    }

    fun disposeAll() {
        players.keys.toList().forEach { disposePlayer(it) }
        methodChannel.setMethodCallHandler(null)
    }
}