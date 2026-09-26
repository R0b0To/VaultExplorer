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
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.Image
import android.media.ImageReader
import android.media.MediaCodec
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Range
import android.util.Size
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executor
import javax.crypto.SecretKey
import kotlin.math.abs
import com.aeidolon.vaultexplorer.VeLog

private const val TAG = "VaultCameraSession"

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
    private var recordingFpsRange: Range<Int>? = null

    // Hardware capability safeguards
    private var isFixedFocus = false
    private var maxAfRegions = 0
    private var maxAeRegions = 0
    private var isFlashSupported = false

    // Tap-to-focus & metering state
    private var activeAfRegions: Array<MeteringRectangle>? = null
    private var activeAeRegions: Array<MeteringRectangle>? = null
    private var isTapToFocusActive = false

    // Manual controls
    private var awbMode: Int = CaptureRequest.CONTROL_AWB_MODE_AUTO
    private var effectMode: Int = CaptureRequest.CONTROL_EFFECT_MODE_OFF

    private var flashMode = VaultFlashMode.OFF
    private var minExposureSteps = 0
    private var maxExposureSteps = 0
    private var exposureStepValue = 1.0 / 6.0
    private var currentExposureSteps = 0
    private var lastOrientationDegrees = 0
    private var photoSize: Size = Size(1920, 1080)
    private var videoSize: Size = Size(1920, 1080)
    private var pendingQuality: VaultVideoQuality = VaultVideoQuality.FHD
    private var pendingPhotoResolution: VaultPhotoResolution = VaultPhotoResolution.MAX
    private var currentPreviewWidth: Int = 1920
    private var currentPreviewHeight: Int = 1080

    private var isRecording = false
    private var recordingChunkWriter: ChunkSink? = null

    private var pendingOpenResult: ((Boolean, String?) -> Unit)? = null
    private var pendingCloseCallback: (() -> Unit)? = null
  private var pendingPhotoCallback: ((Boolean, String?) -> Unit)? = null
    private var pendingPhotoWriter: ChunkSink? = null
    private var pendingPhotoBytesCallback: ((Boolean, ByteArray?, ByteArray?, String?) -> Unit)? = null
    private var pendingRecordStart: ((Boolean, String?) -> Unit)? = null

    val currentCameraId: String get() = activeCameraId
    val currentZoomMin: Float get() = zoomMinCurrent
    val currentZoomMax: Float get() = zoomMaxCurrent
    val currentMinExposureEv: Double get() = minExposureSteps * exposureStepValue
    val currentMaxExposureEv: Double get() = maxExposureSteps * exposureStepValue
    val previewWidth: Int get() = currentPreviewWidth
    val previewHeight: Int get() = currentPreviewHeight
    val sensorOrientationDegrees: Int get() = characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

    fun listLenses(): List<CameraLensInfo> = listCameraLenses(cameraManager)

    private fun runOnCameraThread(block: () -> Unit) {
        if (Thread.currentThread() === bgThread) block() else bgHandler.post(block)
    }

    fun open(
        cameraId: String,
        videoQuality: VaultVideoQuality,
        photoResolution: VaultPhotoResolution = VaultPhotoResolution.MAX,
        callback: (Boolean, String?) -> Unit
    ) {
        runOnCameraThread {
            closeCameraOnly {
                openInternal(cameraId, videoQuality, photoResolution, callback)
            }
        }
    }

    fun dispose() {
        runOnCameraThread {
            closeCameraOnly {
                jpegReader?.close()
                jpegReader = null
                previewSurface?.release()
                previewSurface = null
                try { textureEntry.release() } catch (_: Exception) {}
                bgThread.quitSafely()
            }
        }
    }

    private fun openInternal(
        cameraId: String,
        videoQuality: VaultVideoQuality,
        photoResolution: VaultPhotoResolution,
        callback: (Boolean, String?) -> Unit
    ) {
        try {
            @Suppress("MissingPermission")
            val chars = cameraManager.getCameraCharacteristics(cameraId)
            characteristics = chars
            activeCameraId = cameraId
            pendingQuality = videoQuality
            pendingPhotoResolution = photoResolution
            pendingOpenResult = callback
            configureSizesAndSurfacesLocked(chars, videoQuality, photoResolution)
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
        isRecording = false
        recordingChunkWriter = null
        pendingRecordStart?.invoke(false, "camera closed")
        pendingRecordStart = null
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

        // Safeguard: Clean teardown on fatal hardware error so next open won't hang
        override fun onError(device: CameraDevice, error: Int) {
            VeLog.e(TAG) { "Camera device error $error on device ${device.id}" }
            try { captureSession?.close() } catch (_: Exception) {}
            try { videoRecorder?.releaseEncoder() } catch (_: Exception) {}
            captureSession = null
            videoRecorder = null
            isRecording = false
            recordingChunkWriter = null
            try { device.close() } catch (_: Exception) {}
            cameraDevice = null

            pendingOpenResult?.invoke(false, "camera error $error")
            pendingOpenResult = null
            pendingRecordStart?.invoke(false, "camera error $error")
            pendingRecordStart = null
            onEvent(mapOf("event" to "error", "message" to "camera error $error"))
        }

        override fun onClosed(device: CameraDevice) {
            pendingCloseCallback?.let { cb -> pendingCloseCallback = null; cb() }
        }
    }

    private fun configureSizesAndSurfacesLocked(
        chars: CameraCharacteristics,
        videoQuality: VaultVideoQuality,
        photoResolution: VaultPhotoResolution
    ) {
        val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?: throw IllegalStateException("no stream configuration map for $activeCameraId")

        // Safeguard: Detect fixed-focus lenses (Wide/IR/Macro)
        val minFocusDist = chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE)
        isFixedFocus = minFocusDist == null || minFocusDist == 0f
        maxAfRegions = chars.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) ?: 0
        maxAeRegions = chars.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE) ?: 0
        isFlashSupported = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false

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

        recordingFpsRange = pickFixedFpsRange(
            chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES),
            TARGET_RECORDING_FPS,
        )

        // Photo size strictly follows the chosen photo resolution
        val jpegSizes = map.getOutputSizes(ImageFormat.JPEG)?.toList().orEmpty().ifEmpty { listOf(Size(1920, 1080)) }
        photoSize = chooseSize(jpegSizes, photoResolution.targetLongEdge, capAt1080p = false)

        // Video size selects closest height (480p, 720p, 1080p, 2160p)
        val videoSizes = map.getOutputSizes(MediaCodec::class.java)?.toList().orEmpty().ifEmpty { listOf(Size(1920, 1080)) }
        videoSize = chooseVideoSizeByHeight(videoSizes, videoQuality.targetVideoHeight)

        // Safeguard: Cap preview size at 1920 to stay within CDD limits
        val previewSizes = map.getOutputSizes(SurfaceTexture::class.java)?.toList().orEmpty().ifEmpty { listOf(Size(1920, 1080)) }
        val photoAspect = photoSize.width.toFloat() / photoSize.height.toFloat()
        val previewSize = previewSizes
            .filter { abs((it.width.toFloat() / it.height.toFloat()) - photoAspect) < 0.05f }
            .ifEmpty { previewSizes }
            .let { chooseSize(it, 1920, capAt1080p = true) }

        previewSurface?.release()
        surfaceTexture.setDefaultBufferSize(previewSize.width, previewSize.height)
        previewSurface = Surface(surfaceTexture)

        jpegReader?.close()
        val reader = ImageReader.newInstance(photoSize.width, photoSize.height, ImageFormat.JPEG, 2)
        reader.setOnImageAvailableListener({ r -> onJpegAvailable(r) }, bgHandler)
        jpegReader = reader

        currentPreviewWidth = previewSize.width
        currentPreviewHeight = previewSize.height
    }

    private fun safePrepareRecorder(
        width: Int,
        height: Int,
        quality: VaultVideoQuality,
        orientation: Int
    ): VaultVideoRecorder {
        return try {
            val recorder = VaultVideoRecorder(width, height, quality, recordAudio = true, cacheDir = context.cacheDir)
            recorder.prepareEncoder(orientation)
            recorder
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Failed to prepare encoder at ${width}x$height, falling back to 1080p" }
            try {
                val fallback = VaultVideoRecorder(1920, 1080, VaultVideoQuality.FHD, recordAudio = true, cacheDir = context.cacheDir)
                fallback.prepareEncoder(orientation)
                fallback
            } catch (e2: Exception) {
                VeLog.w(TAG, e2) { "1080p fallback failed, falling back to 720p" }
                val fallback720 = VaultVideoRecorder(1280, 720, VaultVideoQuality.HD, recordAudio = true, cacheDir = context.cacheDir)
                fallback720.prepareEncoder(orientation)
                fallback720
            }
        }
    }

    /**
     * Builds the capture session for the current mode. Only two stream sets
     * are ever used, both inside what every Camera2 hardware level (LEGACY
     * included) guarantees:
     *   idle      -> [preview, JPEG]
     *   recording -> [preview, recorder surface]
     * The recorder is created (and its orientation hint fixed) right before
     * recording starts, so device rotation never forces a reconfiguration
     * while previewing -- that reconfiguration is what used to leave the
     * preview black after rotating on some devices.
     */
    private fun createSessionLocked() {
        val device = cameraDevice ?: return

        // Retire the previous session explicitly before configuring the next one.
        captureSession?.let { try { it.close() } catch (_: Exception) {} }
        captureSession = null

        val outputs = if (isRecording) {
            listOfNotNull(previewSurface, videoRecorder?.inputSurface)
        } else {
            listOfNotNull(previewSurface, jpegReader?.surface)
        }

        val stateCallback = object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(session: CameraCaptureSession) {
                if (cameraDevice !== device) {
                    // Device was closed/replaced while this session was configuring.
                    try { session.close() } catch (_: Exception) {}
                    return
                }
                captureSession = session
                updateRepeatingRequest()
                onSessionReady()
            }

            override fun onConfigureFailed(session: CameraCaptureSession) {
                try { session.close() } catch (_: Exception) {}
                onSessionFailed("session configuration failed")
            }
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val outputConfigs = outputs.map { OutputConfiguration(it) }
                device.createCaptureSession(
                    SessionConfiguration(
                        SessionConfiguration.SESSION_REGULAR,
                        outputConfigs,
                        Executor { command -> bgHandler.post(command) },
                        stateCallback,
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                device.createCaptureSession(outputs, stateCallback, bgHandler)
            }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "createCaptureSession threw" }
            onSessionFailed(e.message ?: "session configuration failed")
        }
    }

    /** A session (idle or recording) is configured and repeating. */
    private fun onSessionReady() {
        pendingOpenResult?.let { cb ->
            pendingOpenResult = null
            cb(true, null)
        }

        val startCb = pendingRecordStart ?: return
        pendingRecordStart = null
        val recorder = videoRecorder
        if (!isRecording || recorder == null) {
            startCb(false, "not ready")
            return
        }
        try {
            recorder.beginRecording()
            startCb(true, null)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "beginRecording failed" }
            abortRecordingAndRestorePreview()
            startCb(false, e.message ?: "recording failed to start")
        }
    }

    private fun onSessionFailed(reason: String) {
        val openCb = pendingOpenResult
        if (openCb != null) {
            pendingOpenResult = null
            openCb(false, reason)
            return
        }

        val startCb = pendingRecordStart
        if (startCb != null) {
            // Recording session could not be configured -- give the preview back.
            pendingRecordStart = null
            abortRecordingAndRestorePreview()
            startCb(false, reason)
            return
        }

        // A late failure with nobody waiting on it (e.g. after stopping a recording).
        onEvent(mapOf("event" to "error", "message" to reason))
    }

    private fun abortRecordingAndRestorePreview() {
        isRecording = false
        recordingChunkWriter = null
        videoRecorder?.releaseEncoder()
        videoRecorder = null
        createSessionLocked()
    }

    private fun updateRepeatingRequest() {
        val session = captureSession ?: return
        try {
            session.setRepeatingRequest(buildRequest(), null, bgHandler)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "updateRepeatingRequest failed" }
        }
    }

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

        // Safeguard: Fixed-focus lenses MUST be set to AF_MODE_OFF
        if (isFixedFocus) {
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_OFF)
        } else if (isTapToFocusActive && activeAfRegions != null && maxAfRegions > 0) {
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO)
            builder.set(CaptureRequest.CONTROL_AF_REGIONS, activeAfRegions)
        } else {
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
        }

        // Apply AE metering region only if hardware supports it
        if (isTapToFocusActive && activeAeRegions != null && maxAeRegions > 0) {
            builder.set(CaptureRequest.CONTROL_AE_REGIONS, activeAeRegions)
        }

        builder.set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, currentExposureSteps)
        if (isRecording) {
            recordingFpsRange?.let { builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, it) }
        }

        applyZoom(builder)
        applyFlash(builder)
        applyWhiteBalance(builder)
        applyColorEffect(builder)
    }

    // Safeguard: EV offset bounds check
    fun setExposureOffsetEv(ev: Double) {
        runOnCameraThread {
            if (minExposureSteps >= maxExposureSteps || exposureStepValue <= 0.0) {
                currentExposureSteps = 0
                return@runOnCameraThread
            }
            val steps = (ev / exposureStepValue).toInt()
            currentExposureSteps = steps.coerceIn(minExposureSteps, maxExposureSteps)
            updateRepeatingRequest()
        }
    }

    // Safeguard: Coordinate mapping accounting for 90°/270° sensor mounting and zoom
    fun setFocusAndExposurePoint(nx: Float, ny: Float) {
        runOnCameraThread {
            val session = captureSession ?: return@runOnCameraThread
            val chars = characteristics ?: return@runOnCameraThread
            val activeArray = sensorArraySize ?: return@runOnCameraThread

            val sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            val isFront = chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT

            // Rotate normalized portrait touch into sensor landscape space
            val (sensorNormX, sensorNormY) = when (sensorOrientation) {
                90 -> if (isFront) Pair(ny, nx) else Pair(ny, 1f - nx)
                270 -> if (isFront) Pair(1f - ny, 1f - nx) else Pair(1f - ny, nx)
                else -> Pair(nx, ny)
            }

            // Scale to active crop area
            val cropRect = if (zoomRatioSupported) {
                activeArray
            } else {
                val cropW = (activeArray.width() / currentZoom).toInt().coerceAtLeast(1)
                val cropH = (activeArray.height() / currentZoom).toInt().coerceAtLeast(1)
                val left = activeArray.left + (activeArray.width() - cropW) / 2
                val top = activeArray.top + (activeArray.height() - cropH) / 2
                Rect(left, top, left + cropW, top + cropH)
            }

            val focusX = cropRect.left + (sensorNormX.coerceIn(0f, 1f) * cropRect.width()).toInt()
            val focusY = cropRect.top + (sensorNormY.coerceIn(0f, 1f) * cropRect.height()).toInt()
            val boxHalfW = (cropRect.width() * 0.06f).toInt().coerceAtLeast(20)
            val boxHalfH = (cropRect.height() * 0.06f).toInt().coerceAtLeast(20)

            val left = (focusX - boxHalfW).coerceIn(cropRect.left, cropRect.right - 1)
            val top = (focusY - boxHalfH).coerceIn(cropRect.top, cropRect.bottom - 1)
            val right = (focusX + boxHalfW).coerceIn(left + 1, cropRect.right)
            val bottom = (focusY + boxHalfH).coerceIn(top + 1, cropRect.bottom)

            val region = MeteringRectangle(left, top, right - left, bottom - top, MeteringRectangle.METERING_WEIGHT_MAX)
            activeAfRegions = if (!isFixedFocus && maxAfRegions > 0) arrayOf(region) else null
            activeAeRegions = if (maxAeRegions > 0) arrayOf(region) else null
            isTapToFocusActive = true

            updateRepeatingRequest()

            if (!isFixedFocus) {
                try {
                    val builder = newRequestBuilder()
                    builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO)
                    activeAfRegions?.let { builder.set(CaptureRequest.CONTROL_AF_REGIONS, it) }
                    activeAeRegions?.let { builder.set(CaptureRequest.CONTROL_AE_REGIONS, it) }
                    builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_START)
                    session.capture(builder.build(), null, bgHandler)
                } catch (e: Exception) {
                    VeLog.e(TAG, e) { "Failed to trigger focus scan" }
                }
            }
        }
    }

    fun resetFocusAndExposure() {
        runOnCameraThread {
            if (!isTapToFocusActive) return@runOnCameraThread
            isTapToFocusActive = false
            activeAfRegions = null
            activeAeRegions = null
            updateRepeatingRequest()

            if (!isFixedFocus) {
                try {
                    val builder = newRequestBuilder()
                    builder.set(CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_CANCEL)
                    captureSession?.capture(builder.build(), null, bgHandler)
                } catch (_: Exception) {}
            }
        }
    }

    private fun applyWhiteBalance(builder: CaptureRequest.Builder) {
        builder.set(CaptureRequest.CONTROL_AWB_MODE, awbMode)
    }

    fun setWhiteBalance(modeStr: String) {
        runOnCameraThread {
            awbMode = when (modeStr.lowercase()) {
                "daylight" -> CaptureRequest.CONTROL_AWB_MODE_DAYLIGHT
                "cloudy" -> CaptureRequest.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT
                "incandescent" -> CaptureRequest.CONTROL_AWB_MODE_INCANDESCENT
                "fluorescent" -> CaptureRequest.CONTROL_AWB_MODE_FLUORESCENT
                else -> CaptureRequest.CONTROL_AWB_MODE_AUTO
            }
            updateRepeatingRequest()
        }
    }

    private fun applyColorEffect(builder: CaptureRequest.Builder) {
        builder.set(CaptureRequest.CONTROL_EFFECT_MODE, effectMode)
    }

    fun setColorEffect(effectStr: String) {
        runOnCameraThread {
            effectMode = when (effectStr.lowercase()) {
                "mono" -> CaptureRequest.CONTROL_EFFECT_MODE_MONO
                "negative" -> CaptureRequest.CONTROL_EFFECT_MODE_NEGATIVE
                "sepia" -> CaptureRequest.CONTROL_EFFECT_MODE_SEPIA
                "solarize" -> CaptureRequest.CONTROL_EFFECT_MODE_SOLARIZE
                else -> CaptureRequest.CONTROL_EFFECT_MODE_OFF
            }
            updateRepeatingRequest()
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

    // Safeguard: Check if physical flash unit actually exists
    private fun applyFlash(builder: CaptureRequest.Builder) {
        if (!isFlashSupported) {
            builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
            return
        }
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
        runOnCameraThread {
            currentZoom = zoom.coerceIn(zoomMinCurrent, zoomMaxCurrent)
            updateRepeatingRequest()
        }
    }

    fun setFlash(mode: VaultFlashMode) {
        runOnCameraThread {
            flashMode = mode
            updateRepeatingRequest()
        }
    }

    /**
     * Only remembers the device rotation. It is consumed when a photo is
     * captured (JPEG_ORIENTATION) and when a recording is prepared (the
     * MediaRecorder orientation hint), never by reconfiguring the session.
     */
    fun setOrientationDegrees(deviceRotationDegrees: Int) {
        runOnCameraThread {
            lastOrientationDegrees = ((deviceRotationDegrees % 360) + 360) % 360
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

    fun capturePhoto(callback: (Boolean, ByteArray?, ByteArray?, String?) -> Unit) {
        runOnCameraThread {
            val device = cameraDevice
            val session = captureSession
            val reader = jpegReader
            if (device == null || session == null || reader == null) {
                callback(false, null, null, "camera not ready")
                return@runOnCameraThread
            }
            if (isRecording) {
                callback(false, null, null, "cannot take photo while recording")
                return@runOnCameraThread
            }
            pendingPhotoBytesCallback = callback
            try {
                val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                builder.addTarget(reader.surface)
                applyControls(builder)
                builder.set(CaptureRequest.JPEG_ORIENTATION, computeCaptureOrientation())
                session.capture(builder.build(), null, bgHandler)
            } catch (e: Exception) {
                pendingPhotoBytesCallback = null
                callback(false, null, null, e.message)
            }
        }
    }

    fun takePhoto(volId: Int, virtualPath: String, callback: (Boolean, String?) -> Unit) {
        capturePhotoInternal(VaultChunkWriter(volId, virtualPath), callback)
    }

    fun takePhotoToScratchpad(
        scratchpadFile: File,
        key: SecretKey,
        callback: (Boolean, String?) -> Unit,
    ) {
        capturePhotoInternal(ScratchpadChunkWriter(scratchpadFile, key), callback)
    }

    private fun capturePhotoInternal(writer: ChunkSink, callback: (Boolean, String?) -> Unit) {
        runOnCameraThread {
            val device = cameraDevice
            val session = captureSession
            val reader = jpegReader
            if (device == null || session == null || reader == null) {
                callback(false, "camera not ready")
                return@runOnCameraThread
            }
            if (isRecording) {
                callback(false, "cannot take photo while recording")
                return@runOnCameraThread
            }
            pendingPhotoCallback = callback
            pendingPhotoWriter = writer
            try {
                val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                builder.addTarget(reader.surface)
                applyControls(builder)
                builder.set(CaptureRequest.JPEG_ORIENTATION, computeCaptureOrientation())
                session.capture(builder.build(), null, bgHandler)
            } catch (e: Exception) {
                pendingPhotoCallback = null
                pendingPhotoWriter = null
                callback(false, e.message)
            }
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

          val bytesCb = pendingPhotoBytesCallback
            if (bytesCb != null) {
                pendingPhotoBytesCallback = null
                val thumbBytes = try {
                    val opts = android.graphics.BitmapFactory.Options().apply {
                        inSampleSize = 8
                    }
                    val bmp = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                    if (bmp != null) {
                        val thumb = android.media.ThumbnailUtils.extractThumbnail(bmp, 160, 160)
                        val stream = java.io.ByteArrayOutputStream()
                        thumb.compress(android.graphics.Bitmap.CompressFormat.JPEG, 70, stream)
                        if (thumb !== bmp) thumb.recycle()
                        bmp.recycle()
                        stream.toByteArray()
                    } else null
                } catch (_: Exception) {
                    null
                }
                bytesCb.invoke(true, bytes, thumbBytes, null)
                return
            }

            val writer = pendingPhotoWriter
            val cb = pendingPhotoCallback
            pendingPhotoWriter = null
            pendingPhotoCallback = null
            if (writer == null) return
            val memFile = MemFile()
            val ok = memFile.writeAndDrain(bytes, writer) && writer.finish()
            memFile.close()
            cb?.invoke(ok, if (ok) null else "write failed")
        } finally {
            image.close()
        }
    }

    fun startRecording(volId: Int, virtualPath: String, callback: (Boolean, String?) -> Unit) {
        startRecordingInternal(VaultChunkWriter(volId, virtualPath), callback)
    }

    fun startRecordingToScratchpad(
        scratchpadFile: File,
        key: SecretKey,
        callback: (Boolean, String?) -> Unit,
    ) {
        startRecordingInternal(ScratchpadChunkWriter(scratchpadFile, key), callback)
    }

    private fun startRecordingInternal(writer: ChunkSink, callback: (Boolean, String?) -> Unit) {
        runOnCameraThread {
            if (cameraDevice == null || captureSession == null) {
                callback(false, "camera not ready")
                return@runOnCameraThread
            }
            if (isRecording || pendingRecordStart != null) {
                callback(false, "not ready")
                return@runOnCameraThread
            }
            val recorder = try {
                safePrepareRecorder(videoSize.width, videoSize.height, pendingQuality, computeCaptureOrientation())
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "prepare recorder failed" }
                callback(false, e.message ?: "recorder prepare failed")
                return@runOnCameraThread
            }
            videoRecorder = recorder
            recordingChunkWriter = writer
            isRecording = true
            // MediaRecorder.start() happens in onSessionReady() once the
            // [preview, recorder] session is configured and repeating.
            pendingRecordStart = callback
            createSessionLocked()
        }
    }

     fun stopRecordingForReview(callback: (Boolean, String?, Long, ByteArray?, String?) -> Unit) {
        runOnCameraThread {
            val recorder = videoRecorder
            if (recorder == null || !isRecording) {
                callback(false, null, 0, null, "not recording")
                return@runOnCameraThread
            }
            isRecording = false
            videoRecorder = null
            recordingChunkWriter = null
            try {
                captureSession?.stopRepeating()
                captureSession?.abortCaptures()
            } catch (_: Exception) {}
            val result = recorder.requestStop()
            val path = recorder.tempFilePath
            recorder.releaseRecorderOnly()

            val thumbBytes = if (path != null) {
                try {
                    val retriever = android.media.MediaMetadataRetriever()
                    retriever.setDataSource(path)
                    val frame = retriever.getFrameAtTime(0, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        ?: retriever.frameAtTime
                    retriever.release()
                    if (frame != null) {
                        val thumb = android.media.ThumbnailUtils.extractThumbnail(frame, 160, 160)
                        val stream = java.io.ByteArrayOutputStream()
                        thumb.compress(android.graphics.Bitmap.CompressFormat.JPEG, 70, stream)
                        if (thumb !== frame) thumb.recycle()
                        frame.recycle()
                        stream.toByteArray()
                    } else null
                } catch (e: Exception) {
                    VeLog.w(TAG, e) { "Failed to extract video thumbnail" }
                    null
                }
            } else null

            callback(true, path, result.durationMs, thumbBytes, null)
            createSessionLocked()
        }
    }

    fun stopRecording(callback: (Boolean, Long, String?) -> Unit) {
        runOnCameraThread {
            val recorder = videoRecorder
            val writer = recordingChunkWriter
            if (recorder == null || !isRecording || writer == null) {
                callback(false, 0, "not recording")
                return@runOnCameraThread
            }
            isRecording = false
            videoRecorder = null
            recordingChunkWriter = null
            try {
                captureSession?.stopRepeating()
                captureSession?.abortCaptures()
            } catch (_: Exception) {}
            val result = recorder.requestStop()
            val ok = recorder.writeTo(writer)
            recorder.releaseEncoder()
            callback(ok, result.durationMs, if (ok) null else "vault write failed")
            // Back to the [preview, JPEG] session.
            createSessionLocked()
        }
    }

    private fun chooseVideoSizeByHeight(candidates: List<Size>, targetHeight: Int): Size {
        return candidates.filter { it.width > 0 && it.height > 0 }
            .minByOrNull { abs(minOf(it.width, it.height) - targetHeight) }
            ?: candidates.firstOrNull()
            ?: Size(1920, 1080)
    }

    private fun chooseSize(candidates: List<Size>, targetLongEdge: Int, capAt1080p: Boolean = false): Size {
        val list = if (capAt1080p) {
            candidates.filter { it.width > 0 && it.height > 0 && maxOf(it.width, it.height) <= 1920 }
                .ifEmpty { candidates.filter { it.width > 0 && it.height > 0 } }
        } else {
            candidates.filter { it.width > 0 && it.height > 0 }
        }
        return list.minByOrNull { abs(maxOf(it.width, it.height) - targetLongEdge) }
            ?: list.firstOrNull()
            ?: Size(1920, 1080)
    }

    private fun pickFixedFpsRange(available: Array<Range<Int>>?, desiredFps: Int): Range<Int>? {
        val ranges = available?.toList().orEmpty()
        if (ranges.isEmpty()) return null
        ranges.firstOrNull { it.lower == desiredFps && it.upper == desiredFps }?.let { return it }
        ranges.filter { it.lower == it.upper }
            .minByOrNull { abs(it.lower - desiredFps) }
            ?.let { return it }
        return ranges.filter { desiredFps in it.lower..it.upper }
            .minByOrNull { it.upper - it.lower }
            ?: ranges.minByOrNull { abs(it.lower - desiredFps) + abs(it.upper - desiredFps) }
    }
}