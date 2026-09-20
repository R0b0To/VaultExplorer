package com.aeidolon.vaultexplorer.camera

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.aeidolon.vaultexplorer.VeLog
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

private const val METHOD_CHANNEL = "com.aeidolon.vaultexplorer/quickcapture"
private const val TAG = "QuickCaptureScratchpadPlugin"

/**
 * Owns the lifecycle of Quick Capture scratchpad sessions: an ephemeral
 * AES-256-GCM key (see [ScratchpadKeyStore]) plus the ciphertext file it's
 * paired with, from the moment capture starts -- before the person has
 * chosen a vault -- until they either save into one or discard.
 *
 * The actual photo/video bytes are written by
 * [VaultCameraSession.takePhotoToScratchpad]/[VaultCameraSession.startRecordingToScratchpad],
 * which look the key up in [ScratchpadKeyStore] directly (same process,
 * no channel round trip) by the token this plugin hands back from
 * [onMethodCall]'s "openSession" case -- the raw key never crosses this
 * or any other method channel.
 */
class QuickCaptureScratchpadPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val ioExecutor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "openSession" -> {
                    val token = ScratchpadKeyStore.createSession()
                    val file = ScratchpadTransfer.scratchpadFile(context.cacheDir, token)
                    result.success(
                        mapOf(
                            "sessionToken" to token,
                            "scratchpadPath" to file.absolutePath,
                        )
                    )
                }
                "finalizeSession" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val token = args["sessionToken"] as? String
                    val volId = (args["volId"] as? Number)?.toInt()
                    val virtualPath = args["virtualPath"] as? String
                    if (token == null || volId == null || virtualPath == null) {
                        result.error("bad_args", "sessionToken, volId and virtualPath are required", null)
                        return
                    }

                    ioExecutor.execute {
                        try {
                            val key = ScratchpadKeyStore.get(token)
                            if (key == null) {
                                VeLog.w(TAG) { "finalizeSession: no key for token (expired or already finalized/discarded)" }
                                mainHandler.post {
                                    result.success(mapOf("success" to false, "error" to "session expired"))
                                }
                                return@execute
                            }
                            val file = ScratchpadTransfer.scratchpadFile(context.cacheDir, token)
                            val ok = ScratchpadTransfer.finalizeIntoVault(file, key, volId, virtualPath)
                            ScratchpadKeyStore.forget(token)
                            mainHandler.post {
                                result.success(mapOf("success" to ok, "error" to if (ok) null else "vault write failed"))
                            }
                        } catch (e: Exception) {
                            VeLog.e(TAG, e) { "finalizeSession background task failed" }
                            mainHandler.post {
                                result.success(mapOf("success" to false, "error" to (e.message ?: "vault write failed")))
                            }
                        }
                    }
                }
                  "discardSession" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                        val token = args["sessionToken"] as? String
                        if (token == null) {
                            result.error("bad_args", "sessionToken required", null)
                            return
                        }
                        ioExecutor.execute {
                            try {
                                val file = ScratchpadTransfer.scratchpadFile(context.cacheDir, token)
                                ScratchpadTransfer.discard(file)
                                ScratchpadKeyStore.forget(token)
                                mainHandler.post {
                                    result.success(null)
                                }
                            } catch (e: Exception) {
                                VeLog.e(TAG, e) { "discardSession background task failed" }
                                mainHandler.post {
                                    result.success(null)
                                }
                            }
                        }
                    }
                    "showToast" -> {
                        val message = call.argument<String>("message") ?: ""
                        if (message.isNotEmpty()) {
                            mainHandler.post {
                                android.widget.Toast.makeText(
                                    context.applicationContext,
                                    message,
                                    android.widget.Toast.LENGTH_SHORT
                                ).show()
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
            }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "onMethodCall(${call.method}) failed" }
            result.error("quick_capture_error", e.message, null)
        }
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        ioExecutor.shutdown()
    }

    companion object {
        /** Call once at process startup, off the main thread, before any
         *  capture could plausibly create a new scratchpad file -- see
         *  [ScratchpadTransfer.sweepOrphaned]. */
        fun sweepOrphanedScratchpads(context: Context): Int =
            ScratchpadTransfer.sweepOrphaned(context.cacheDir)
    }
}