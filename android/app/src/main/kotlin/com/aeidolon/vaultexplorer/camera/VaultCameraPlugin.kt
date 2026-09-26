package com.aeidolon.vaultexplorer.camera

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.view.Surface
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.atomic.AtomicLong
import com.aeidolon.vaultexplorer.VeLog

private const val METHOD_CHANNEL = "com.aeidolon.vaultexplorer/camera"
private const val EVENT_CHANNEL_PREFIX = "com.aeidolon.vaultexplorer/camera/events/"
private const val ACCEL_EVENT_CHANNEL = "com.aeidolon.vaultexplorer/camera/accelerometer"
private const val TAG = "VaultCameraPlugin"
const val CAMERA_PERMISSION_REQUEST_CODE = 9821

class VaultCameraPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val textureRegistry: TextureRegistry,
) : MethodChannel.MethodCallHandler {
    private val context: Context = activity.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val nextId = AtomicLong(0)
    private val sessions = LinkedHashMap<Long, VaultCameraSession>()
    private val eventChannels = LinkedHashMap<Long, EventChannel>()
    private val eventSinks = LinkedHashMap<Long, EventChannel.EventSink?>()
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val accelEventChannel = EventChannel(messenger, ACCEL_EVENT_CHANNEL)
    private val messenger = messenger
    private val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var accelSensorEventListener: SensorEventListener? = null

    init {
        methodChannel.setMethodCallHandler(this)
        accelEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
                val listener = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        mainHandler.post {
                            sink.success(
                                mapOf(
                                    "x" to event.values[0].toDouble(),
                                    "y" to event.values[1].toDouble(),
                                    "z" to event.values[2].toDouble()
                                )
                            )
                        }
                    }
                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                }
                accelSensorEventListener = listener
                sensorManager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
            }

            override fun onCancel(arguments: Any?) {
                accelSensorEventListener?.let {
                    sensorManager.unregisterListener(it)
                    accelSensorEventListener = null
                }
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasPermissions" -> result.success(hasCameraPermissions())
                "getDisplayRotation" -> result.success(currentDisplayRotation())
                "requestPermissions" -> {
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO),
                        CAMERA_PERMISSION_REQUEST_CODE,
                    )
                    result.success(null)
                }
                "open" -> {
                    if (!hasCameraPermissions()) {
                        return result.error("permission_denied", "Camera/microphone permission not granted", null)
                    }
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val cameraId = args["cameraId"] as? String
                        ?: pickDefaultCameraId(args["facing"] as? String ?: "back")
                        ?: return result.error("no_camera", "No camera matches request", null)
                    val quality = parseQuality(args["quality"] as? String)
                    val photoRes = parsePhotoResolution(args["photoResolution"] as? String)

                    val id = nextId.getAndIncrement()
                    val session = VaultCameraSession(context, textureRegistry) { event ->
                        mainHandler.post { eventSinks[id]?.success(event) }
                    }
                    sessions[id] = session
                    val eventChannel = EventChannel(messenger, EVENT_CHANNEL_PREFIX + id)
                    eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                        override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { eventSinks[id] = sink }
                        override fun onCancel(arguments: Any?) { eventSinks[id] = null }
                    })
                    eventChannels[id] = eventChannel

                   val scanMode = (args["scanMode"] as? Boolean) ?: false
                    session.open(cameraId, quality, photoRes) { ok, error ->
                        if (ok && scanMode) {
                            session.setScanMode(true)
                        }
                        mainHandler.post {
                            if (ok) {
                                VeLog.d(TAG) { "open: ok camera=$cameraId preview=${session.previewWidth}x${session.previewHeight} sensorOrientation=${session.sensorOrientationDegrees}" }
                                result.success(mapOf(
                                    "sessionId" to id,
                                    "textureId" to session.textureId,
                                    "cameraId" to session.currentCameraId,
                                    "zoomMin" to session.currentZoomMin.toDouble(),
                                    "zoomMax" to session.currentZoomMax.toDouble(),
                                    "minExposureEv" to session.currentMinExposureEv,
                                    "maxExposureEv" to session.currentMaxExposureEv,
                                    "previewWidth" to session.previewWidth,
                                    "previewHeight" to session.previewHeight,
                                    "sensorOrientation" to session.sensorOrientationDegrees,
                                    "lenses" to listCameraLenses(cameraManager).map { it.toMap() },
                                ))
                            } else {
                                VeLog.e(TAG) { "open: failed camera=$cameraId error=$error" }
                                sessions.remove(id)
                                eventChannels.remove(id)?.setStreamHandler(null)
                                eventSinks.remove(id)
                                result.error("open_failed", error, null)
                            }
                        }
                    }
                }
                "setZoom" -> withSession(call, result) { session, args ->
                    val zoom = (args["zoom"] as? Number)?.toFloat() ?: 1f
                    session.setZoom(zoom)
                    result.success(null)
                }
                "setFlash" -> withSession(call, result) { session, args ->
                    val mode = when (args["mode"] as? String) {
                        "auto" -> VaultFlashMode.AUTO
                        "on" -> VaultFlashMode.ON
                        "torch" -> VaultFlashMode.TORCH
                        else -> VaultFlashMode.OFF
                    }
                    session.setFlash(mode)
                    result.success(null)
                }
                "setExposureOffset" -> withSession(call, result) { session, args ->
                    val ev = (args["ev"] as? Number)?.toDouble() ?: 0.0
                    session.setExposureOffsetEv(ev)
                    result.success(null)
                }
                "setFocusAndExposurePoint" -> withSession(call, result) { session, args ->
                    val nx = (args["x"] as? Number)?.toFloat() ?: 0.5f
                    val ny = (args["y"] as? Number)?.toFloat() ?: 0.5f
                    session.setFocusAndExposurePoint(nx, ny)
                    result.success(null)
                }
                "resetFocusAndExposure" -> withSession(call, result) { session, _ ->
                    session.resetFocusAndExposure()
                    result.success(null)
                }
                "setScanMode" -> withSession(call, result) { session, args ->
                    val enable = (args["enable"] as? Boolean) ?: false
                    session.setScanMode(enable)
                    result.success(null)
                }
                "setWhiteBalance" -> withSession(call, result) { session, args ->
                    val mode = args["mode"] as? String ?: "auto"
                    session.setWhiteBalance(mode)
                    result.success(null)
                }
                "setColorEffect" -> withSession(call, result) { session, args ->
                    val effect = args["effect"] as? String ?: "off"
                    session.setColorEffect(effect)
                    result.success(null)
                }
                "setOrientationDegrees" -> withSession(call, result) { session, args ->
                    val degrees = (args["degrees"] as? Number)?.toInt() ?: 0
                    session.setOrientationDegrees(degrees)
                    result.success(null)
                }
                  "capturePhoto" -> withSession(call, result) { session, _ ->
                    session.capturePhoto { ok, bytes, thumbBytes, error ->
                        mainHandler.post {
                            if (ok && bytes != null) {
                                result.success(
                                    mapOf<String, Any?>(
                                        "success" to true,
                                        "bytes" to bytes,
                                        "thumbnail" to thumbBytes,
                                    )
                                )
                            } else {
                                result.success(mapOf<String, Any?>("success" to false, "error" to error))
                            }
                        }
                    }
                }
                "savePhotoToVault" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val volId = (args["volId"] as? Number)?.toInt()
                    val virtualPath = args["virtualPath"] as? String
                    val bytes = args["bytes"] as? ByteArray
                    if (volId == null || virtualPath == null || bytes == null) {
                        result.error("bad_args", "volId, virtualPath and bytes are required", null)
                        return
                    }
                    val writer = VaultChunkWriter(volId, virtualPath)
                    val ok = writer.write(bytes) && writer.finish()
                    result.success(mapOf("success" to ok))
                }
                "takePhoto" -> withSession(call, result) { session, args ->
                    val volId = (args["volId"] as? Number)?.toInt() ?: return@withSession result.error("bad_args", "volId required", null)
                    val path = args["virtualPath"] as? String ?: return@withSession result.error("bad_args", "virtualPath required", null)
                    session.takePhoto(volId, path) { ok, error ->
                        mainHandler.post { result.success(mapOf("success" to ok, "error" to error)) }
                    }
                }
                "takePhotoToScratchpad" -> withSession(call, result) { session, args ->
                    val scratchpadPath = args["scratchpadPath"] as? String
                        ?: return@withSession result.error("bad_args", "scratchpadPath required", null)
                    val token = args["sessionToken"] as? String
                        ?: return@withSession result.error("bad_args", "sessionToken required", null)
                    val key = ScratchpadKeyStore.get(token)
                        ?: return@withSession result.error("no_such_session", "Scratchpad session expired", null)
                    session.takePhotoToScratchpad(java.io.File(scratchpadPath), key) { ok, error ->
                        mainHandler.post { result.success(mapOf("success" to ok, "error" to error)) }
                    }
                }
                "startVideoRecording" -> withSession(call, result) { session, args ->
                    val volId = (args["volId"] as? Number)?.toInt() ?: return@withSession result.error("bad_args", "volId required", null)
                    val path = args["virtualPath"] as? String ?: return@withSession result.error("bad_args", "virtualPath required", null)
                    VeLog.d(TAG) { "startVideoRecording (pathLen=${path.length})" }
                    session.startRecording(volId, path) { ok, error ->
                        mainHandler.post {
                            VeLog.d(TAG) { "startVideoRecording result: ok=$ok error=$error" }
                            result.success(mapOf("success" to ok, "error" to error))
                        }
                    }
                }
                "startVideoRecordingToScratchpad" -> withSession(call, result) { session, args ->
                    val scratchpadPath = args["scratchpadPath"] as? String
                        ?: return@withSession result.error("bad_args", "scratchpadPath required", null)
                    val token = args["sessionToken"] as? String
                        ?: return@withSession result.error("bad_args", "sessionToken required", null)
                    val key = ScratchpadKeyStore.get(token)
                        ?: return@withSession result.error("no_such_session", "Scratchpad session expired", null)
                    VeLog.d(TAG) { "startVideoRecordingToScratchpad" }
                    session.startRecordingToScratchpad(java.io.File(scratchpadPath), key) { ok, error ->
                        mainHandler.post {
                            VeLog.d(TAG) { "startVideoRecordingToScratchpad result: ok=$ok error=$error" }
                            result.success(mapOf("success" to ok, "error" to error))
                        }
                    }
                }
                   "stopVideoRecordingForReview" -> withSession(call, result) { session, _ ->
                    session.stopRecordingForReview { ok, videoPath, durationMs, thumbBytes, error ->
                        mainHandler.post {
                            result.success(
                                mapOf<String, Any?>(
                                    "success" to ok,
                                    "videoPath" to videoPath,
                                    "durationMs" to durationMs,
                                    "thumbnail" to thumbBytes,
                                    "error" to error,
                                )
                            )
                        }
                    }
                }
                 "trimVideo" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val videoPath = args["videoPath"] as? String
                    val startMs = (args["startMs"] as? Number)?.toLong() ?: 0L
                    val endMs = (args["endMs"] as? Number)?.toLong() ?: 0L
                    if (videoPath == null) {
                        result.error("bad_args", "videoPath required", null)
                        return
                    }
                    val trimmedPath = VaultVideoRecorder.trimVideo(videoPath, startMs, endMs)
                    result.success(mapOf<String, Any?>("videoPath" to trimmedPath))
                }
                "saveVideoToVault" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val volId = (args["volId"] as? Number)?.toInt()
                    val virtualPath = args["virtualPath"] as? String
                    val videoPath = args["videoPath"] as? String
                    if (volId == null || virtualPath == null || videoPath == null) {
                        result.error("bad_args", "volId, virtualPath and videoPath required", null)
                        return
                    }
                    val ok = VaultVideoRecorder.streamFileToSinkAndWipe(
                        java.io.File(videoPath),
                        VaultChunkWriter(volId, virtualPath)
                    )
                    result.success(mapOf<String, Any?>("success" to ok))
                }
                "saveVideoToScratchpad" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val token = args["sessionToken"] as? String
                    val scratchpadPath = args["scratchpadPath"] as? String
                    val videoPath = args["videoPath"] as? String
                    if (token == null || scratchpadPath == null || videoPath == null) {
                        result.error("bad_args", "sessionToken, scratchpadPath and videoPath required", null)
                        return
                    }
                    val key = ScratchpadKeyStore.get(token)
                    if (key == null) {
                        result.error("no_such_session", "Scratchpad session expired", null)
                        return
                    }
                    val ok = VaultVideoRecorder.streamFileToSinkAndWipe(
                        java.io.File(videoPath),
                        ScratchpadChunkWriter(java.io.File(scratchpadPath), key)
                    )
                    result.success(mapOf<String, Any?>("success" to ok))
                }
                "discardVideo" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val videoPath = args["videoPath"] as? String
                    if (videoPath != null) {
                        VaultVideoRecorder.secureDeleteFile(java.io.File(videoPath))
                    }
                    result.success(null)
                }
                "stopVideoRecording" -> withSession(call, result) { session, _ ->
                    VeLog.d(TAG) { "stopVideoRecording" }
                    session.stopRecording { ok, durationMs, error ->
                        mainHandler.post {
                            VeLog.d(TAG) { "stopVideoRecording result: ok=$ok durationMs=$durationMs error=$error" }
                            result.success(mapOf("success" to ok, "durationMs" to durationMs, "error" to error))
                        }
                    }
                }
                "close" -> {
                    val args = call.arguments as Map<*, *>
                    val id = (args["sessionId"] as? Number)?.toLong()
                    if (id != null) disposeSession(id)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("camera_error", e.message, null)
        }
    }

    private inline fun withSession(call: MethodCall, result: MethodChannel.Result, block: (VaultCameraSession, Map<*, *>) -> Unit) {
        val args = call.arguments as? Map<*, *>
        val id = (args?.get("sessionId") as? Number)?.toLong()
        val session = id?.let { sessions[it] }
        if (session == null) {
            result.error("no_such_session", "No camera session for id $id", null)
            return
        }
        block(session, args)
    }

    /**
     * Surface.ROTATION_0..3 of the activity's display, as 0..3. The preview
     * texture is delivered upright for the device's natural orientation, so
     * Dart needs this to counter-rotate it whenever the display is rotated.
     */
    private fun currentDisplayRotation(): Int {
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.rotation
        }
        return when (rotation) {
            Surface.ROTATION_90 -> 1
            Surface.ROTATION_180 -> 2
            Surface.ROTATION_270 -> 3
            else -> 0
        }
    }

    private fun hasCameraPermissions(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun pickDefaultCameraId(facing: String): String? {
        val lenses = listCameraLenses(cameraManager)
        return lenses.firstOrNull { it.facing == facing }?.cameraId
            ?: lenses.firstOrNull()?.cameraId
    }

    private fun parseQuality(wire: String?): VaultVideoQuality = when (wire) {
        "sd", "480p", "420p" -> VaultVideoQuality.SD
        "hd" -> VaultVideoQuality.HD
        "uhd" -> VaultVideoQuality.UHD
        else -> VaultVideoQuality.FHD
    }

    private fun disposeSession(id: Long) {
        sessions.remove(id)?.dispose()
        eventChannels.remove(id)?.setStreamHandler(null)
        eventSinks.remove(id)
    }

    fun disposeAll() {
        accelSensorEventListener?.let {
            sensorManager.unregisterListener(it)
            accelSensorEventListener = null
        }
        accelEventChannel.setStreamHandler(null)
        sessions.keys.toList().forEach { disposeSession(it) }
        methodChannel.setMethodCallHandler(null)
    }
}

private fun parsePhotoResolution(wire: String?): VaultPhotoResolution = when (wire) {
    "low" -> VaultPhotoResolution.LOW
    "med", "medium" -> VaultPhotoResolution.MEDIUM
    "high" -> VaultPhotoResolution.HIGH
    else -> VaultPhotoResolution.MAX
}

private fun CameraLensInfo.toMap(): Map<String, Any?> = mapOf(
    "cameraId" to cameraId,
    "facing" to facing,
    "isLogical" to isLogicalMultiCamera,
    "zoomMin" to zoomMin.toDouble(),
    "zoomMax" to zoomMax.toDouble(),
    "relativeZoom" to relativeZoom.toDouble(),
    "lensType" to lensType,
    "displayName" to displayName,
)