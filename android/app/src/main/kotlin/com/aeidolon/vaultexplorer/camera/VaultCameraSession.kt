package com.aeidolon.vaultexplorer.camera

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.MeteringRectangle
import android.media.Image
import android.media.ImageReader
import android.media.MediaCodec
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import io.flutter.view.TextureRegistry
import kotlin.math.abs

private const val TAG = "VaultCameraSession"

/**
 * Owns one Camera2 device + one CameraCaptureSession for its whole
 * lifetime (until close()/lens switch). The session's output surfaces
 * are fixed at creation time -- preview, JPEG ImageReader, and the video
 * encoder's input Surface are ALL registered up front, so toggling
 * between photo/video mode or starting/stopping a recording only ever
 * changes which surfaces the *repeating request* targets (fast) rather
 * than reconfiguring the session (slow) -- that reconfigure was the
 * source of the multi-second "entering video mode" delay in the old
 * package:camera/CameraX implementation.
 *
 * Lens enumeration reads CameraCharacteristics directly and never opens
 * a camera to do it, which also removes the concurrent-camera race the
 * old zoom-range probing code could hit (opening one lens while another
 * was still asynchronously closing).
 */
class VaultCameraSession(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val onEvent: (Map<String, Any?>) -> Unit,
) {
    private val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val bgThread = HandlerThread("vx-camera-bg").apply { start() }
    private val bgHandler = Handler(bgThread.looper)

    private val textureEntry = textureRegistry.createSurfaceTexture()
    val textureId: Long get() = textureEntry.id()
    private val surfaceTexture: SurfaceTexture get() = textureEntry.surfaceTexture()
    private var previewSurface: Surface? = null

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var jpegReader: ImageReader? = null
    private var videoRecorder: VaultVideoRecorder? = null

    private var activeCameraId: String = ""
    private var characteristics: CameraCharacteristics? = null
    private var zoomRatioSupported = false
    private var zoomMinCurrent = 1f
    private var zoomMaxCurrent = 1f
    private var currentZoom = 1f
    private var sensorArraySize: Rect? = null

    private var flashMode = VaultFlashMode.OFF
    private var minExposureSteps = 0
    private var maxExposureSteps = 0
    private var exposureStepValue = 1.0 / 6.0
    private var currentExposureSteps = 0
    private var lastOrientationDegrees = 0
    // The orientation hint that was actually baked into `videoRecorder` at
    // prepare() time (MediaRecorder can't have its orientation hint changed
    // once prepared). Used to detect when the device has rotated since the
    // recorder was last (re)prepared, so the *next* recording picks up the
    // rotation the phone is actually being held in instead of a stale one
    // from whenever the session/lens was opened or the previous clip ended.
    private var lastPreparedOrientationDegrees: Int? = null
    private var photoSize: Size = Size(1920, 1080)
    private var videoSize: Size = Size(1920, 1080)
    private var pendingQuality: VaultVideoQuality = VaultVideoQuality.FHD
    private var currentPreviewWidth: Int = 1920
    private var currentPreviewHeight: Int = 1080

    private var isRecording = false
    private var recordingChunkWriter: VaultChunkWriter? = null

    private var pendingOpenResult: ((Boolean, String?) -> Unit)? = null
    private var pendingCloseCallback: (() -> Unit)? = null
    private var pendingPhotoCallback: ((Boolean, String?) -> Unit)? = null
    private var pendingPhotoTarget: Pair<Int, String>? = null

    val currentCameraId: String get() = activeCameraId
    val currentZoomMin: Float get() = zoomMinCurrent
    val currentZoomMax: Float get() = zoomMaxCurrent
    val currentMinExposureEv: Double get() = minExposureSteps * exposureStepValue
    val currentMaxExposureEv: Double get() = maxExposureSteps * exposureStepValue
    // Raw sensor-space preview dimensions (e.g. 1920x1080, always in the
    // camera's landscape sensor orientation regardless of how the phone is
    // held) plus the sensor's mounting angle, so Dart can work out the
    // correct on-screen aspect ratio for the Texture instead of stretching
    // it to whatever size the widget happens to be given.
    val previewWidth: Int get() = currentPreviewWidth
    val previewHeight: Int get() = currentPreviewHeight
    val sensorOrientationDegrees: Int get() = characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

    // ── Static enumeration -- no camera is opened for this ─────────────

    fun listLenses(): List<CameraLensInfo> = listCameraLenses(cameraManager)

    // ── Open / close ────────────────────────────────────────────────────

    fun open(cameraId: String, videoQuality: VaultVideoQuality, callback: (Boolean, String?) -> Unit) {
        closeCameraOnly {
            openInternal(cameraId, videoQuality, callback)
        }
    }

    fun switchLens(cameraId: String, callback: (Boolean, String?) -> Unit) {
        closeCameraOnly {
            openInternal(cameraId, pendingQuality, callback)
        }
    }

    fun dispose() {
        closeCameraOnly {
            jpegReader?.close()
            jpegReader = null
            previewSurface = null
            try { textureEntry.release() } catch (_: Exception) {}
            bgThread.quitSafely()
        }
    }

    private fun openInternal(cameraId: String, videoQuality: VaultVideoQuality, callback: (Boolean, String?) -> Unit) {
        try {
            @Suppress("MissingPermission")
            val chars = cameraManager.getCameraCharacteristics(cameraId)
            characteristics = chars
            activeCameraId = cameraId
            pendingQuality = videoQuality
            pendingOpenResult = callback
            configureSizesAndSurfacesLocked(chars, videoQuality)
            cameraManager.openCamera(cameraId, deviceStateCallback, bgHandler)
        } catch (e: Exception) {
            callback(false, e.message)
        }
    }

    private fun closeCameraOnly(then: () -> Unit) {
        val device = cameraDevice
        if (device == null) {
            then()
            return
        }
        try { captureSession?.close() } catch (_: Exception) {}
        captureSession = null
        videoRecorder?.releaseEncoder()
        videoRecorder = null
        // Wait for the real close callback before proceeding -- Android's
        // CameraDevice.close() is asynchronous at the HAL level (can take
        // 1-2s), and opening the next camera before it actually finishes
        // is what caused "Unsupported set of inputs/outputs provided"
        // configuration failures with a timer-based guess-delay approach.
        pendingCloseCallback = then
        device.close()
        cameraDevice = null
    }

    private val deviceStateCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(device: CameraDevice) {
            cameraDevice = device
            createSessionLocked()
        }
        override fun onDisconnected(device: CameraDevice) {
            device.close()
            cameraDevice = null
        }
        override fun onError(device: CameraDevice, error: Int) {
            device.close()
            cameraDevice = null
            pendingOpenResult?.invoke(false, "camera error $error")
            pendingOpenResult = null
            onEvent(mapOf("event" to "error", "message" to "camera error $error"))
        }
        override fun onClosed(device: CameraDevice) {
            pendingCloseCallback?.let { cb -> pendingCloseCallback = null; cb() }
        }
    }

    private fun configureSizesAndSurfacesLocked(chars: CameraCharacteristics, videoQuality: VaultVideoQuality) {
        val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?: throw IllegalStateException("no stream configuration map for $activeCameraId")

        zoomRatioSupported = Build.VERSION.SDK_INT >= 30 && chars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE) != null
        if (zoomRatioSupported) {
            val range = chars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)!!
            zoomMinCurrent = range.lower
            zoomMaxCurrent = range.upper
        } else {
            zoomMinCurrent = 1f
            zoomMaxCurrent = chars.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
        }
        currentZoom = currentZoom.coerceIn(zoomMinCurrent, zoomMaxCurrent).let { if (it.isNaN()) 1f else it }
        sensorArraySize = chars.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)

        val expRange = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
        minExposureSteps = expRange?.lower ?: 0
        maxExposureSteps = expRange?.upper ?: 0
        val stepRational = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP)
        exposureStepValue = if (stepRational != null && stepRational.denominator != 0) {
            stepRational.numerator.toDouble() / stepRational.denominator.toDouble()
        } else 1.0 / 6.0
        currentExposureSteps = 0

        val jpegSizes = map.getOutputSizes(ImageFormat.JPEG)?.toList().orEmpty().ifEmpty { listOf(Size(1920, 1080)) }
        photoSize = chooseSize(jpegSizes, 4000)

        val videoSizes = map.getOutputSizes(MediaCodec::class.java)?.toList().orEmpty().ifEmpty { listOf(Size(1920, 1080)) }
        videoSize = chooseSize(videoSizes, videoQuality.targetLongEdge)

        val previewSizes = map.getOutputSizes(SurfaceTexture::class.java)?.toList().orEmpty().ifEmpty { listOf(Size(1920, 1080)) }
        val previewSize = chooseSize(previewSizes, 1920)

        surfaceTexture.setDefaultBufferSize(previewSize.width, previewSize.height)
        previewSurface = Surface(surfaceTexture)

        jpegReader?.close()
        val reader = ImageReader.newInstance(photoSize.width, photoSize.height, ImageFormat.JPEG, 2)
        reader.setOnImageAvailableListener({ r -> onJpegAvailable(r) }, bgHandler)
        jpegReader = reader

        val recorder = VaultVideoRecorder(videoSize.width, videoSize.height, videoQuality, recordAudio = true, cacheDir = context.cacheDir)
        val orientation = computeCaptureOrientation()
        recorder.prepareEncoder(orientation)
        lastPreparedOrientationDegrees = orientation
        videoRecorder = recorder
        currentPreviewWidth = previewSize.width
        currentPreviewHeight = previewSize.height
    }

    private fun createSessionLocked() {
        val device = cameraDevice ?: return
        val outputs = listOfNotNull(previewSurface, jpegReader?.surface, videoRecorder?.inputSurface)
        try {
            device.createCaptureSession(outputs, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    isRecording = false
                    updateRepeatingRequest()
                    pendingOpenResult?.invoke(true, null)
                    pendingOpenResult = null
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    pendingOpenResult?.invoke(false, "session configuration failed")
                    pendingOpenResult = null
                }
            }, bgHandler)
        } catch (e: Exception) {
            pendingOpenResult?.invoke(false, e.message)
            pendingOpenResult = null
        }
    }

    // ── Repeating request / controls ───────────────────────────────────

    private fun updateRepeatingRequest() {
        val session = captureSession ?: return
        try {
            session.setRepeatingRequest(buildRequest(), null, bgHandler)
        } catch (e: Exception) {
            android.util.Log.e("VaultCameraSession", "updateRepeatingRequest failed", e)
        }
    }

    /** Shared by buildRequest() and setFocusAndExposurePoint() -- both need
     *  the same device/template/target-surface/control setup and previously
     *  duplicated it, which meant a future control had to be remembered in
     *  two places. Each caller adds whatever's specific to it (AF/AE region
     *  overrides, etc.) on top of the returned builder. */
    private fun newRequestBuilder(): CaptureRequest.Builder {
        val device = cameraDevice ?: throw IllegalStateException("no camera device")
        val template = if (isRecording) CameraDevice.TEMPLATE_RECORD else CameraDevice.TEMPLATE_PREVIEW
        val builder = device.createCaptureRequest(template)
        previewSurface?.let { builder.addTarget(it) }
        if (isRecording) videoRecorder?.inputSurface?.let { builder.addTarget(it) }
        applyControls(builder)
        return builder
    }

    private fun buildRequest(): CaptureRequest = newRequestBuilder().build()

    private fun applyControls(builder: CaptureRequest.Builder) {
        builder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
        builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
        builder.set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, currentExposureSteps)
        applyZoom(builder)
        applyFlash(builder)
    }

    fun setExposureOffsetEv(ev: Double) {
        val steps = if (exposureStepValue == 0.0) 0 else (ev / exposureStepValue).toInt()
        currentExposureSteps = steps.coerceIn(minExposureSteps, maxExposureSteps)
        updateRepeatingRequest()
    }

    /** [nx]/[ny] normalized (0..1) tap position within the preview. */
    fun setFocusAndExposurePoint(nx: Float, ny: Float) {
        val rect = sensorArraySize ?: return
        val session = captureSession ?: return
        val halfW = (rect.width() * 0.05f).toInt().coerceAtLeast(1)
        val halfH = (rect.height() * 0.05f).toInt().coerceAtLeast(1)
        val cx = (rect.left + (nx.coerceIn(0f, 1f) * rect.width()).toInt()).coerceIn(rect.left, rect.right)
        val cy = (rect.top + (ny.coerceIn(0f, 1f) * rect.height()).toInt()).coerceIn(rect.top, rect.bottom)
        val left = (cx - halfW).coerceIn(rect.left, rect.right - 1)
        val top = (cy - halfH).coerceIn(rect.top, rect.bottom - 1)
        val right = (cx + halfW).coerceIn(left + 1, rect.right)
        val bottom = (cy + halfH).coerceIn(top + 1, rect.bottom)
        val region = MeteringRectangle(left, top, right - left, bottom - top, MeteringRectangle.METERING_WEIGHT_MAX)
        try {
            val builder = newRequestBuilder()
            builder.set(CaptureRequest.CONTROL_AF_REGIONS, arrayOf(region))
            builder.set(CaptureRequest.CONTROL_AE_REGIONS, arrayOf(region))
            builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_START)
            session.capture(builder.build(), null, bgHandler)
        } catch (e: Exception) {
            android.util.Log.e("VaultCameraSession", "focus/expose failed", e)
        }
    }

    private fun applyZoom(builder: CaptureRequest.Builder) {
        if (zoomRatioSupported) {
            builder.set(CaptureRequest.CONTROL_ZOOM_RATIO, currentZoom)
            return
        }
        val rect = sensorArraySize ?: return
        val cropW = (rect.width() / currentZoom).toInt().coerceAtLeast(1)
        val cropH = (rect.height() / currentZoom).toInt().coerceAtLeast(1)
        val left = rect.left + (rect.width() - cropW) / 2
        val top = rect.top + (rect.height() - cropH) / 2
        builder.set(CaptureRequest.SCALER_CROP_REGION, Rect(left, top, left + cropW, top + cropH))
    }

    private fun applyFlash(builder: CaptureRequest.Builder) {
        when (flashMode) {
            VaultFlashMode.OFF -> {
                builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
            }
            VaultFlashMode.AUTO -> builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON_AUTO_FLASH)
            VaultFlashMode.ON -> builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON_ALWAYS_FLASH)
            VaultFlashMode.TORCH -> {
                builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH)
            }
        }
    }

    fun setZoom(zoom: Float) {
        currentZoom = zoom.coerceIn(zoomMinCurrent, zoomMaxCurrent)
        updateRepeatingRequest()
    }

    fun setFlash(mode: VaultFlashMode) {
        flashMode = mode
        updateRepeatingRequest()
    }

    /** [deviceRotationDegrees]: 0/90/180/270, how far the physical device is
     *  rotated from its natural (portrait) orientation -- the same value
     *  the old lockCaptureOrientation()-based Dart code already computed
     *  from the accelerometer. Applied to the next photo/video capture. */
    fun setOrientationDegrees(deviceRotationDegrees: Int) {
        val normalized = ((deviceRotationDegrees % 360) + 360) % 360
        if (normalized == lastOrientationDegrees) return
        lastOrientationDegrees = normalized

        // Bake the new orientation into the video encoder right away, while
        // the phone is just sitting in preview -- not only after a recording
        // stops. Previously the encoder's orientation hint was set once when
        // the session/lens was opened (or right after the *previous* clip
        // finished) and never touched again, so a video recorded after
        // rotating the phone kept the old, wrong rotation baked into its
        // MP4 metadata. Skipped mid-recording since MediaRecorder can't be
        // reconfigured once started -- that recording keeps the orientation
        // it began with, which is correct for it; the rotation will be
        // picked up for the recording after it via the same post-stop path.
        if (!isRecording) {
            reprepareVideoRecorder(force = false, reason = "orientation changed")
        }
    }

    /**
     * (Re)prepares the video encoder and reconfigures the capture session to
     * point at its fresh output Surface. A MediaRecorder can't be started
     * twice, or have its orientation hint changed, once prepare() has run --
     * so both "the previous clip just stopped and needs a fresh instance"
     * (called from stopRecording(), [force]=true since videoRecorder has
     * already been torn down and MUST be replaced regardless of orientation)
     * and "the phone rotated while idle and the baked-in orientation is now
     * stale" (called from setOrientationDegrees(), [force]=false so it's a
     * no-op when the orientation hasn't actually changed) need the same
     * fresh-instance-plus-session-reconfigure dance. Doing it here -- right
     * after a clip stops, or as soon as the phone rotates while idle --
     * hides that cost from the user instead of paying it the next time they
     * press record.
     */
    private fun reprepareVideoRecorder(force: Boolean, reason: String) {
        if (characteristics == null || cameraDevice == null) return
        val needed = computeCaptureOrientation()
        if (!force && needed == lastPreparedOrientationDegrees) return
        try {
            val fresh = VaultVideoRecorder(videoSize.width, videoSize.height, pendingQuality, recordAudio = true, cacheDir = context.cacheDir)
            fresh.prepareEncoder(needed)
            videoRecorder?.releaseEncoder()
            videoRecorder = fresh
            lastPreparedOrientationDegrees = needed
            android.util.Log.d(TAG, "reprepareVideoRecorder($reason): orientation=$needed, reconfiguring session")
            createSessionLocked()
        } catch (e: Exception) {
            android.util.Log.e(TAG, "reprepareVideoRecorder($reason) failed - next recording may fail to start or have wrong rotation", e)
        }
    }

    private fun computeCaptureOrientation(): Int {
        val chars = characteristics ?: return 0
        val sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        val front = chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
        return if (front) {
            (sensorOrientation + lastOrientationDegrees) % 360
        } else {
            (sensorOrientation - lastOrientationDegrees + 360) % 360
        }
    }

    // ── Photo capture ───────────────────────────────────────────────────

    fun takePhoto(volId: Int, virtualPath: String, callback: (Boolean, String?) -> Unit) {
        val device = cameraDevice
        val session = captureSession
        val reader = jpegReader
        if (device == null || session == null || reader == null) {
            callback(false, "camera not ready")
            return
        }
        pendingPhotoCallback = callback
        pendingPhotoTarget = volId to virtualPath
        try {
            val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            builder.addTarget(reader.surface)
            applyControls(builder)
            builder.set(CaptureRequest.JPEG_ORIENTATION, computeCaptureOrientation())
            session.capture(builder.build(), null, bgHandler)
        } catch (e: Exception) {
            pendingPhotoCallback = null
            pendingPhotoTarget = null
            callback(false, e.message)
        }
    }

    private fun onJpegAvailable(reader: ImageReader) {
        val image: Image = try {
            reader.acquireLatestImage()
        } catch (e: Exception) {
            null
        } ?: return
        try {
            val buffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            val target = pendingPhotoTarget
            val cb = pendingPhotoCallback
            pendingPhotoTarget = null
            pendingPhotoCallback = null
            if (target == null) return
            val (volId, virtualPath) = target
            val writer = VaultChunkWriter(volId, virtualPath)
            val memFile = MemFile()
            val ok = memFile.writeAndDrain(bytes, writer)
            memFile.close()
            cb?.invoke(ok, if (ok) null else "vault write failed")
        } finally {
            image.close()
        }
    }

    // ── Video recording ─────────────────────────────────────────────────

    fun startRecording(volId: Int, virtualPath: String, callback: (Boolean, String?) -> Unit) {
        val recorder = videoRecorder
        if (recorder == null || isRecording) {
            android.util.Log.w(TAG, "startRecording: not ready (recorder=$recorder, isRecording=$isRecording)")
            callback(false, "not ready")
            return
        }
        try {
            android.util.Log.d(TAG, "startRecording: $virtualPath")
            recorder.beginRecording()
            recordingChunkWriter = VaultChunkWriter(volId, virtualPath)
            isRecording = true
            updateRepeatingRequest()
            callback(true, null)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "startRecording failed", e)
            callback(false, e.message)
        }
    }

    fun stopRecording(callback: (Boolean, Long, String?) -> Unit) {
        val recorder = videoRecorder
        val writer = recordingChunkWriter
        if (recorder == null || !isRecording || writer == null) {
            android.util.Log.w(TAG, "stopRecording: not recording (recorder=$recorder, isRecording=$isRecording, writer=$writer)")
            callback(false, 0, "not recording")
            return
        }
        isRecording = false
        // Nothing else should target this recorder's surface once it stops
        // -- the repeating request falls back to preview-only immediately,
        // before the (blocking, native) stop()/write-out below even runs.
        videoRecorder = null
        updateRepeatingRequest()
        bgHandler.post {
            val result = recorder.requestStop()
            val ok = recorder.writeTo(writer)
            recordingChunkWriter = null
            recorder.releaseEncoder()
            android.util.Log.d(TAG, "stopRecording: ok=$ok durationMs=${result.durationMs}")
            callback(ok, result.durationMs, if (ok) null else "vault write failed")
            rearmVideoRecorder()
        }
    }

    /**
     * A MediaRecorder can't be start()ed again once stopped -- it needs a
     * fresh prepare(), which means a fresh output Surface (see
     * reprepareVideoRecorder()'s doc for why that also means a session
     * reconfigure). Doing this here, right after a recording finishes
     * (while Dart is still showing its "encrypting..." overlay), hides
     * that cost instead of paying it the next time the user presses
     * record.
     */
    private fun rearmVideoRecorder() {
        reprepareVideoRecorder(force = true, reason = "post-recording rearm")
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private fun chooseSize(candidates: List<Size>, targetLongEdge: Int): Size {
        return candidates.filter { it.width > 0 && it.height > 0 }
            .minByOrNull { abs(maxOf(it.width, it.height) - targetLongEdge) }
            ?: candidates.firstOrNull()
            ?: Size(1920, 1080)
    }
}