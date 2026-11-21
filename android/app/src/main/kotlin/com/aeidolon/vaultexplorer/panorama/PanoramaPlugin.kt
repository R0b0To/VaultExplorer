package com.aeidolon.vaultexplorer.panorama

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

private const val CHANNEL = "com.aeidolon.vaultexplorer/panorama"

/**
 * Dart-facing side of panorama capture. The camera plugin parks each fresh
 * photo in [PanoramaStore]; Dart commits it with the device pose, and finally
 * asks for the stitched result.
 */
class PanoramaPlugin(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "begin" -> {
                PanoramaStore.begin()
                result.success(null)
            }
            "discard" -> {
                PanoramaStore.discardPending()
                result.success(null)
            }
            "cancel" -> {
                PanoramaStore.begin()
                result.success(null)
            }
            "commit" -> {
                val rows = (call.argument<List<*>>("rows"))?.map { (it as Number).toFloat() }?.toFloatArray()
                val tan = call.argument<Number>("tanHalfLong")?.toDouble()
                if (rows == null || rows.size < 9 || tan == null) {
                    result.error("bad_args", "rows (9) and tanHalfLong are required", null)
                    return
                }
                worker.execute {
                    val error = try {
                        PanoramaStore.commitPending(rows, tan)
                    } catch (t: Throwable) {
                        t.message ?: "commit failed"
                    }
                    mainHandler.post {
                        result.success(
                            mapOf<String, Any?>(
                                "success" to (error == null),
                                "error" to error,
                                "count" to PanoramaStore.count(),
                            ),
                        )
                    }
                }
            }
            "finish" -> {
                val sphere = call.argument<Boolean>("sphere") ?: false
                worker.execute {
                    val response: Map<String, Any?> = try {
                        val frames = PanoramaStore.snapshot()
                        val stitched = PanoramaStitcher.stitch(frames, sphere)
                        if (stitched == null) {
                            mapOf("success" to false, "error" to "no frames")
                        } else {
                            mapOf(
                                "success" to true,
                                "bytes" to stitched.jpeg,
                                "thumbnail" to stitched.thumbnail,
                                "width" to stitched.width,
                                "height" to stitched.height,
                            )
                        }
                    } catch (t: Throwable) {
                        mapOf("success" to false, "error" to (t.message ?: "stitching failed"))
                    }
                    PanoramaStore.begin()
                    mainHandler.post { result.success(response) }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        PanoramaStore.begin()
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
    }
}
