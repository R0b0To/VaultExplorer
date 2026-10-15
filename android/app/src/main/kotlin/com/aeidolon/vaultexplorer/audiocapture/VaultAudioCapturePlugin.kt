package com.aeidolon.vaultexplorer.audiocapture

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.camera.VaultChunkWriter
import com.aeidolon.vaultexplorer.camera.VaultVideoRecorder
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors

private const val METHOD_CHANNEL = "com.aeidolon.vaultexplorer/audio_capture"
private const val TAG = "VaultAudioCapturePlugin"
const val AUDIO_CAPTURE_PERMISSION_REQUEST_CODE = 9824

// VaultVideoRecorder.trimVideo() writes its output next to the source with
// this prefix. Audio takes the same trim path (MediaExtractor/MediaMuxer
// handle audio-only tracks), so those files are legitimate inputs here too.
private const val TRIMMED_TEMP_PREFIX = "vx_vid_trim_"

/**
 * Audio-only counterpart of [com.aeidolon.vaultexplorer.camera.VaultCameraPlugin]'s
 * video recording path, on its own channel because it has no camera
 * session to hang off.
 *
 * Flow, mirroring the camera: start -> (pause/resume) -> stop returns a
 * plaintext temp file for review -> optional trim -> save streams it into
 * the vault and wipes it, or discard wipes it. See [VaultAudioRecorder] for
 * the temp-file lifecycle.
 *
 * Only paths that [VaultAudioRecorder] / trim created inside the app cache
 * directory are accepted by save/trim/discard: those operations delete
 * their input, so a bad argument must not be able to point them at an
 * arbitrary file.
 */
class VaultAudioCapturePlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val context: Context = activity.applicationContext
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val recorder = VaultAudioRecorder(context)
    private var pendingPermissionResult: MethodChannel.Result? = null

    init {
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasPermission" -> result.success(hasMicPermission())
                "requestPermission" -> requestMicPermission(result)
                "start" -> {
                    if (!hasMicPermission()) {
                        result.success(mapOf("success" to false, "error" to "permission_denied"))
                        return
                    }
                    try {
                        val args = call.arguments as? Map<*, *>
                        val params = AudioRecordingParams.sanitize(
                            bitrate = (args?.get("bitrate") as? Number)?.toInt(),
                            sampleRate = (args?.get("sampleRate") as? Number)?.toInt(),
                        )
                        recorder.start(params)
                        result.success(mapOf("success" to true))
                    } catch (e: Exception) {
                        VeLog.e(TAG, e) { "start failed" }
                        result.success(mapOf("success" to false, "error" to (e.message ?: "start failed")))
                    }
                }
                "pause" -> {
                    try {
                        recorder.pause()
                        result.success(mapOf("success" to true))
                    } catch (e: Exception) {
                        VeLog.e(TAG, e) { "pause failed" }
                        result.success(mapOf("success" to false, "error" to (e.message ?: "pause failed")))
                    }
                }
                "resume" -> {
                    try {
                        recorder.resume()
                        result.success(mapOf("success" to true))
                    } catch (e: Exception) {
                        VeLog.e(TAG, e) { "resume failed" }
                        result.success(mapOf("success" to false, "error" to (e.message ?: "resume failed")))
                    }
                }
                "amplitude" -> result.success(recorder.amplitude())
                "stop" -> ioExecutor.execute {
                    val reply: Map<String, Any?> = try {
                        val res = recorder.stop()
                        mapOf(
                            "success" to true,
                            "path" to res.file.absolutePath,
                            "durationMs" to res.durationMs,
                        )
                    } catch (e: Exception) {
                        VeLog.e(TAG, e) { "stop failed" }
                        mapOf("success" to false, "error" to (e.message ?: "stop failed"))
                    }
                    mainHandler.post { result.success(reply) }
                }
                "cancel" -> ioExecutor.execute {
                    recorder.cancel()
                    mainHandler.post { result.success(null) }
                }
                "trim" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val path = args["path"] as? String
                    val startMs = (args["startMs"] as? Number)?.toLong() ?: 0L
                    val endMs = (args["endMs"] as? Number)?.toLong() ?: 0L
                    val file = path?.let { ownedTempFile(it) }
                    if (file == null) {
                        result.error("bad_args", "path must be a recording temp file", null)
                        return
                    }
                    ioExecutor.execute {
                        // trimVideo() returns the source path unchanged on
                        // failure and wipes the source on success, so the
                        // returned path is always the file to keep using.
                        val trimmed = try {
                            VaultVideoRecorder.trimVideo(file.absolutePath, startMs, endMs)
                        } catch (e: Exception) {
                            VeLog.e(TAG, e) { "trim failed" }
                            file.absolutePath
                        }
                        mainHandler.post { result.success(mapOf("path" to trimmed)) }
                    }
                }
                "save" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val path = args["path"] as? String
                    val volId = (args["volId"] as? Number)?.toInt()
                    val virtualPath = args["virtualPath"] as? String
                    val file = path?.let { ownedTempFile(it) }
                    if (file == null || volId == null || virtualPath == null) {
                        result.error("bad_args", "path, volId and virtualPath are required", null)
                        return
                    }
                    ioExecutor.execute {
                        val ok = try {
                            streamIntoVault(file, volId, virtualPath)
                        } catch (e: Exception) {
                            VeLog.e(TAG, e) { "save failed" }
                            false
                        }
                        mainHandler.post { result.success(mapOf("success" to ok)) }
                    }
                }
                "discard" -> {
                    val path = (call.arguments as? Map<*, *>)?.get("path") as? String
                    val file = path?.let { ownedTempFile(it) }
                    if (file == null) {
                        result.success(null)
                        return
                    }
                    ioExecutor.execute {
                        VaultVideoRecorder.secureDeleteFile(file)
                        mainHandler.post { result.success(null) }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "onMethodCall(${call.method}) failed" }
            result.error("audio_capture_error", e.message, null)
        }
    }

    /** Called from MainActivity.onRequestPermissionsResult. */
    fun onPermissionResult(granted: Boolean) {
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        pending.success(granted)
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
        // Wipe an in-flight take rather than leave a plaintext file behind;
        // the executor is shut down only after the cancel has run.
        ioExecutor.execute { recorder.cancel() }
        ioExecutor.shutdown()
    }

    private fun hasMicPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestMicPermission(result: MethodChannel.Result) {
        if (hasMicPermission()) {
            result.success(true)
            return
        }
        // A newer request supersedes an unanswered older one.
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            AUDIO_CAPTURE_PERMISSION_REQUEST_CODE,
        )
    }

    /** Resolves [path] to a file only if it is one of this feature's temp
     *  files directly inside the cache directory. */
    private fun ownedTempFile(path: String): File? {
        return try {
            val file = File(path).canonicalFile
            val cache = context.cacheDir.canonicalFile
            val name = file.name
            val inCache = file.parentFile == cache
            val ours = (name.startsWith(AUDIO_TEMP_PREFIX) && name.endsWith(AUDIO_TEMP_SUFFIX)) ||
                name.startsWith(TRIMMED_TEMP_PREFIX)
            if (inCache && ours) file else null
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Streams [file] into the vault at [virtualPath] and wipes it -- but only
     * once the whole write succeeded. [VaultVideoRecorder.streamFileToSinkAndWipe]
     * wipes in a `finally`, so a failed vault write there loses the take;
     * for a recording that cannot be redone, the temp file is kept on
     * failure so the person can retry the save.
     */
    private fun streamIntoVault(file: File, volId: Int, virtualPath: String): Boolean {
        if (!file.exists() || file.length() == 0L) return false
        val sink = VaultChunkWriter(volId, virtualPath)
        BufferedInputStream(FileInputStream(file), 64 * 1024).use { input ->
            val buffer = ByteArray(64 * 1024)
            var read: Int
            while (input.read(buffer).also { read = it } != -1) {
                if (read > 0) {
                    val chunk = if (read == buffer.size) buffer else buffer.copyOf(read)
                    if (!sink.write(chunk)) return false
                }
            }
        }
        if (!sink.finish()) return false
        VaultVideoRecorder.secureDeleteFile(file)
        return true
    }
}
