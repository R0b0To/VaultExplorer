package com.aeidolon.vaultexplorer.vlcplayer

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.atomic.AtomicLong

private const val METHOD_CHANNEL = "com.aeidolon.vaultexplorer/vlc_player"
private const val EVENT_CHANNEL_PREFIX = "com.aeidolon.vaultexplorer/vlc_player/events/"

/**
 * Owns every live [VlcPlayerEngine] for the app's media viewer and exposes
 * them to Dart over one shared [MethodChannel] plus one [EventChannel] per
 * player id.
 *
 * Wire this up once from `MainActivity.configureFlutterEngine()`:
 * ```kotlin
 * vlcPlayerPlugin = VlcPlayerPlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)
 * ```
 * and call `vlcPlayerPlugin?.disposeAll()` from `onDestroy()` / `cleanUpFlutterEngine`.
 */
class VlcPlayerPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textureRegistry: TextureRegistry,
) : MethodChannel.MethodCallHandler {

    private val nextId = AtomicLong(0)
    private val players = LinkedHashMap<Long, VlcPlayerEngine>()
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
                    val engine = VlcPlayerEngine(context, textureRegistry, id) { event ->
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
                    val uri = args["contentUri"] as? String
                        ?: return@withEngine result.error("bad_args", "contentUri is required", null)
                    val autoPlay = args["autoPlay"] as? Boolean ?: false
                    engine.setDataSource(uri, autoPlay)
                    result.success(null)
                }

                "play" -> withEngine(call, result) { engine, _ ->
                    engine.play(); result.success(null)
                }

                "pause" -> withEngine(call, result) { engine, _ ->
                    engine.pause(); result.success(null)
                }

                "stop" -> withEngine(call, result) { engine, _ ->
                    engine.stop(); result.success(null)
                }

                "seekTo" -> withEngine(call, result) { engine, args ->
                    val pos = (args["positionMs"] as? Number)?.toLong() ?: 0L
                    engine.seekTo(pos)
                    result.success(null)
                }

                "setVolume" -> withEngine(call, result) { engine, args ->
                    val vol = (args["volume"] as? Number)?.toInt() ?: 100
                    engine.setVolume(vol)
                    result.success(null)
                }

                "setRate" -> withEngine(call, result) { engine, args ->
                    val rate = (args["rate"] as? Number)?.toFloat() ?: 1.0f
                    engine.setRate(rate)
                    result.success(null)
                }

                "setLooping" -> withEngine(call, result) { engine, args ->
                    engine.setLooping(args["looping"] as? Boolean ?: false)
                    result.success(null)
                }

                "getSpuTracks" -> withEngine(call, result) { engine, _ ->
                    result.success(engine.getSpuTracks().mapKeys { it.key.toString() })
                }

                "setSpuTrack" -> withEngine(call, result) { engine, args ->
                    engine.setSpuTrack((args["trackId"] as? Number)?.toInt() ?: -1)
                    result.success(null)
                }

                "getAudioTracks" -> withEngine(call, result) { engine, _ ->
                    result.success(engine.getAudioTracks().mapKeys { it.key.toString() })
                }

                "setAudioTrack" -> withEngine(call, result) { engine, args ->
                    engine.setAudioTrack((args["trackId"] as? Number)?.toInt() ?: -1)
                    result.success(null)
                }

                "dispose" -> withEngine(call, result) { engine, _ ->
                    val id = (call.arguments as Map<*, *>)["playerId"] as Number
                    disposePlayer(id.toLong())
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("vlc_player_error", e.message, null)
        }
    }

    private inline fun withEngine(
        call: MethodCall,
        result: MethodChannel.Result,
        block: (VlcPlayerEngine, Map<*, *>) -> Unit,
    ) {
        val args = call.arguments as? Map<*, *>
        val id = (args?.get("playerId") as? Number)?.toLong()
        val engine = id?.let { players[it] }
        if (engine == null) {
            result.error("no_such_player", "No VlcPlayerEngine for id $id", null)
            return
        }
        block(engine, args)
    }

    private fun disposePlayer(id: Long) {
        players.remove(id)?.dispose()
        eventChannels.remove(id)?.setStreamHandler(null)
        eventSinks.remove(id)
    }

    /** Call from Activity teardown so nothing outlives the Flutter engine. */
    fun disposeAll() {
        players.keys.toList().forEach { disposePlayer(it) }
        methodChannel.setMethodCallHandler(null)
    }
}
