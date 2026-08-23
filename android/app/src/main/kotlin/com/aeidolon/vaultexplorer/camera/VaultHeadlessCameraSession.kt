package com.aeidolon.vaultexplorer.camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.VeLog
import kotlin.math.abs

private const val TAG = "VaultHeadlessCameraSession"

// How long the repeating warm-up request runs before the still capture is
// actually issued -- long enough for AE/AF to settle a bit with no preview
// to judge convergence by (see the class doc comment's precapture note),
// short enough not to make TAKE_PHOTO feel broken to an automation profile
// waiting on the result broadcast.
private const val PRECAPTURE_SETTLE_MS = 350L

/**
 * Camera2 capture path for the automation receiver's TAKE_PHOTO /
 * START_RECORDING / STOP_RECORDING actions -- structurally similar to
 * [VaultCameraSession] but deliberately independent of it: this never
 * registers a preview surface (no [io.flutter.view.TextureRegistry], no
 * Flutter engine of any kind needs to be running), because nothing is
 * ever displaying the feed for a headless automation trigger. Every output
 * surface here is a capture/encode target only.
 *
 * One instance is single-use -- one photo, or one open-record-stop cycle --
 * then it closes itself; unlike VaultCameraSession it does not support
 * switching lenses or rearming for a second capture.
 *
 * Precapture: a still request fired the instant the session configures, on
 * a sensor that never had a preview to converge exposure/focus against,
 * often comes out dark or soft. [capturePhotoAndClose] runs a short
 * repeating warm-up request first (draining and discarding those frames)
 * before issuing the actual STILL_CAPTURE -- a simplified stand-in for
 * Camera2's full AF/AE precapture-trigger state machine (the one
 * google's camera2basic sample implements), good enough for a static or
 * mounted phone but not a substitute for it on a device in motion.
 *
 * Orientation is fixed to each lens's raw sensor orientation -- there is no
 * accelerometer/OrientationEventListener sampling here, since there's no
 * guarantee anything is watching the screen to make live device-rotation
 * tracking meaningful for a headless trigger, and a phone triggered by an
 * automation profile is more often sitting still (mounted, on a desk) than
 * being actively held. A capture taken while the device is physically
 * rotated may come out sideways; VaultCameraSession's UI flow remains the
 * right tool when live rotation tracking matters.
 */
class VaultHeadlessCameraSession(private val context: Context) {

    private val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val bgThread = HandlerThread("vx-automation-camera").apply { start() }
    private val bgHandler = Handler(bgThread.looper)

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var characteristics: CameraCharacteristics? = null
    private var jpegReader: ImageReader? = null
    private var videoRecorder: VaultVideoRecorder? = null
    private var isRecording = false
    private var recordingChunkWriter: VaultChunkWriter? = null
    private var recordingVolId: Int = -1
    private var recordingVaultPath: String = ""
    @Volatile private var closed = false

    fun hasPermissions(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun runOnCameraThread(block: () -> Unit) {
        if (Thread.currentThread() === bgThread) block() else bgHandler.post(block)
    }

    /** Same formula as VaultCameraSession.computeCaptureOrientation with device
     *  rotation fixed at 0 -- see the class doc comment on why. */
    private fun computeCaptureOrientation(): Int {
        val chars = characteristics ?: return 0
        return chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
    }

    private fun chooseSize(candidates: Array<Size>?, targetLongEdge: Int): Size =
        candidates?.filter { it.width > 0 && it.height > 0 }
            ?.minByOrNull { abs(maxOf(it.width, it.height) - targetLongEdge) }
            ?: Size(1920, 1080)

    private fun continuousAfModeIfSupported(chars: CameraCharacteristics, videoMode: Boolean): Int? {
        val available = chars.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: return null
        val wanted = if (videoMode) {
            CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO
        } else {
            CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
        }
        return if (available.contains(wanted)) wanted else null
    }

    // ── Photo: open, warm up 3A, capture one frame, close -- one call ─────

    /**
     * Opens [cameraId], captures a single JPEG frame, streams it into
     * [volId]/[virtualPath], and closes everything. [callback] fires
     * exactly once, on this session's own background thread. Safe to call
     * from any thread; [hasPermissions] is checked synchronously before
     * anything else happens.
     */
    fun capturePhotoAndClose(
        cameraId: String,
        volId: Int,
        virtualPath: String,
        callback: (Boolean, String?) -> Unit,
    ) {
        if (!hasPermissions()) {
            callback(false, "permission_denied")
            return
        }
        runOnCameraThread {
            try {
                val chars = cameraManager.getCameraCharacteristics(cameraId)
                characteristics = chars
                val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val size = chooseSize(map?.getOutputSizes(ImageFormat.JPEG), 1920)
                val reader = ImageReader.newInstance(size.width, size.height, ImageFormat.JPEG, 2)
                jpegReader = reader
                // Plain local var, not @Volatile: every read/write of it below
                // happens inside a callback posted to bgHandler, i.e. always on
                // this same bgThread, so there's no cross-thread race to guard
                // against here.
                var capturingStill = false

                reader.setOnImageAvailableListener({ r ->
                    val image: Image? = try { r.acquireLatestImage() } catch (e: Exception) { null }
                    if (image == null) return@setOnImageAvailableListener
                    if (!capturingStill) {
                        // Warm-up frame from the precapture repeating request -- drain and discard.
                        image.close()
                        return@setOnImageAvailableListener
                    }
                    finishPhotoCapture(image, volId, virtualPath, callback)
                }, bgHandler)

                @Suppress("MissingPermission")
                cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                    override fun onOpened(device: CameraDevice) {
                        cameraDevice = device
                        try {
                            device.createCaptureSession(
                                listOf(reader.surface),
                                object : CameraCaptureSession.StateCallback() {
                                    override fun onConfigured(session: CameraCaptureSession) {
                                        captureSession = session
                                        try {
                                            val warmup = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                                            warmup.addTarget(reader.surface)
                                            continuousAfModeIfSupported(chars, videoMode = false)?.let {
                                                warmup.set(CaptureRequest.CONTROL_AF_MODE, it)
                                            }
                                            session.setRepeatingRequest(warmup.build(), null, bgHandler)
                                            bgHandler.postDelayed({
                                                try {
                                                    session.stopRepeating()
                                                    capturingStill = true
                                                    val still = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                                                    still.addTarget(reader.surface)
                                                    still.set(CaptureRequest.JPEG_ORIENTATION, computeCaptureOrientation())
                                                    session.capture(still.build(), null, bgHandler)
                                                } catch (e: Exception) {
                                                    VeLog.e(TAG, e) { "capturePhotoAndClose: still capture failed" }
                                                    closeAll()
                                                    callback(false, e.message)
                                                }
                                            }, PRECAPTURE_SETTLE_MS)
                                        } catch (e: Exception) {
                                            VeLog.e(TAG, e) { "capturePhotoAndClose: warm-up request failed" }
                                            closeAll()
                                            callback(false, e.message)
                                        }
                                    }
                                    override fun onConfigureFailed(session: CameraCaptureSession) {
                                        VeLog.e(TAG) { "capturePhotoAndClose: session config failed" }
                                        closeAll()
                                        callback(false, "session configuration failed")
                                    }
                                },
                                bgHandler,
                            )
                        } catch (e: Exception) {
                            VeLog.e(TAG, e) { "capturePhotoAndClose: createCaptureSession failed" }
                            closeAll()
                            callback(false, e.message)
                        }
                    }
                    override fun onDisconnected(device: CameraDevice) {
                        closeAll()
                        callback(false, "camera disconnected")
                    }
                    override fun onError(device: CameraDevice, error: Int) {
                        VeLog.e(TAG) { "capturePhotoAndClose: open error=$error" }
                        closeAll()
                        callback(false, "camera_unavailable ($error)")
                    }
                }, bgHandler)
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "capturePhotoAndClose failed for $cameraId" }
                closeAll()
                callback(false, e.message)
            }
        }
    }

    private fun finishPhotoCapture(image: Image, volId: Int, virtualPath: String, callback: (Boolean, String?) -> Unit) {
        val ok = try {
            val buffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            val writer = VaultChunkWriter(volId, virtualPath)
            val memFile = MemFile()
            val wrote = memFile.writeAndDrain(bytes, writer)
            memFile.close()
            if (wrote) ContainerFileSystem.finishWrite(volId, virtualPath)
            wrote
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "finishPhotoCapture: vault write failed" }
            false
        } finally {
            image.close()
        }
        closeAll()
        callback(ok, if (ok) null else "vault write failed")
    }

    // ── Video: open once, start/stop possibly much later, then close ──────

    /**
     * Opens [cameraId] targeting only the video encoder's input surface (no
     * preview, no JPEG reader) and prepares [VaultVideoRecorder] at
     * [quality]. Recording doesn't start until [startRecording] is called
     * -- kept separate the same way VaultCameraSession separates
     * open()/startRecording(), so the owning service can confirm the
     * camera actually opened before START_RECORDING's automation reply
     * claims success.
     */
    fun openForRecording(
        cameraId: String,
        quality: VaultVideoQuality,
        recordAudio: Boolean,
        callback: (Boolean, String?) -> Unit,
    ) {
        if (!hasPermissions()) {
            callback(false, "permission_denied")
            return
        }
        runOnCameraThread {
            try {
                val chars = cameraManager.getCameraCharacteristics(cameraId)
                characteristics = chars
                val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val size = chooseSize(map?.getOutputSizes(MediaRecorder::class.java), quality.targetLongEdge)

                val recorder = VaultVideoRecorder(size.width, size.height, quality, recordAudio, context.cacheDir)
                recorder.prepareEncoder(orientationDegrees = computeCaptureOrientation())
                val surface = recorder.inputSurface
                    ?: throw IllegalStateException("encoder produced no input surface")
                videoRecorder = recorder

                @Suppress("MissingPermission")
                cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                    override fun onOpened(device: CameraDevice) {
                        cameraDevice = device
                        try {
                            device.createCaptureSession(
                                listOf(surface),
                                object : CameraCaptureSession.StateCallback() {
                                    override fun onConfigured(session: CameraCaptureSession) {
                                        captureSession = session
                                        try {
                                            val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                                            builder.addTarget(surface)
                                            continuousAfModeIfSupported(chars, videoMode = true)?.let {
                                                builder.set(CaptureRequest.CONTROL_AF_MODE, it)
                                            }
                                            session.setRepeatingRequest(builder.build(), null, bgHandler)
                                            callback(true, null)
                                        } catch (e: Exception) {
                                            VeLog.e(TAG, e) { "openForRecording: repeating request failed" }
                                            closeAll()
                                            callback(false, e.message)
                                        }
                                    }
                                    override fun onConfigureFailed(session: CameraCaptureSession) {
                                        VeLog.e(TAG) { "openForRecording: session config failed" }
                                        closeAll()
                                        callback(false, "session configuration failed")
                                    }
                                },
                                bgHandler,
                            )
                        } catch (e: Exception) {
                            VeLog.e(TAG, e) { "openForRecording: createCaptureSession failed" }
                            closeAll()
                            callback(false, e.message)
                        }
                    }
                    override fun onDisconnected(device: CameraDevice) {
                        closeAll()
                        callback(false, "camera disconnected")
                    }
                    override fun onError(device: CameraDevice, error: Int) {
                        VeLog.e(TAG) { "openForRecording: open error=$error" }
                        closeAll()
                        callback(false, "camera_unavailable ($error)")
                    }
                }, bgHandler)
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "openForRecording failed for $cameraId" }
                closeAll()
                callback(false, e.message)
            }
        }
    }

    fun startRecording(volId: Int, virtualPath: String, callback: (Boolean, String?) -> Unit) {
        runOnCameraThread {
            val recorder = videoRecorder
            if (recorder == null || isRecording) {
                callback(false, "not ready")
                return@runOnCameraThread
            }
            try {
                recorder.beginRecording()
                recordingChunkWriter = VaultChunkWriter(volId, virtualPath)
                recordingVolId = volId
                recordingVaultPath = virtualPath
                isRecording = true
                callback(true, null)
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "startRecording failed" }
                callback(false, e.message)
            }
        }
    }

    /**
     * Stops recording, streams the result into the vault, and closes the
     * camera entirely -- unlike VaultCameraSession, a headless session is
     * single-use and never rearms itself for a second recording.
     */
    fun stopRecordingAndClose(callback: (Boolean, Long, String?) -> Unit) {
        runOnCameraThread {
            val recorder = videoRecorder
            val writer = recordingChunkWriter
            if (recorder == null || !isRecording || writer == null) {
                closeAll()
                callback(false, 0, "not recording")
                return@runOnCameraThread
            }
            isRecording = false
            val result = recorder.requestStop()
            val ok = recorder.writeTo(writer)
            if (ok) ContainerFileSystem.finishWrite(recordingVolId, recordingVaultPath)
            recorder.releaseEncoder()
            closeAll()
            callback(ok, result.durationMs, if (ok) null else "vault write failed")
        }
    }

    /** Idempotent; safe to call more than once (every failure path above does). */
    fun closeAll() {
        runOnCameraThread {
            if (closed) return@runOnCameraThread
            closed = true
            try { captureSession?.close() } catch (_: Exception) {}
            try { cameraDevice?.close() } catch (_: Exception) {}
            try { jpegReader?.close() } catch (_: Exception) {}
            try { videoRecorder?.releaseEncoder() } catch (_: Exception) {}
            captureSession = null
            cameraDevice = null
            jpegReader = null
            videoRecorder = null
            recordingChunkWriter = null
            isRecording = false
            bgThread.quitSafely()
        }
    }
}
