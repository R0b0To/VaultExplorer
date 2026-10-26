package com.aeidolon.vaultexplorer.camera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.MeteringRectangle
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.ExifInterface
import android.media.Image
import android.media.ImageReader
import android.media.MediaCodec
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Range
import android.util.Size
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executor
import javax.crypto.SecretKey
import kotlin.math.abs
import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.VeLog

private const val TAG = "VaultCameraSession"

// CameraX capture-pipeline time limits (Camera2CapturePipeline): wait up to 5 s for AE to
// settle when a flash is involved, then shoot anyway.
private const val FLASH_3A_TIMEOUT_MS = 5_000L
// Torch-as-flash: the torch has to be lit and AE must have re-metered under it.
private const val TORCH_SETTLE_MS = 200L
private const val TORCH_CONVERGED_FRAMES = 2
// Whole still (3A + exposure + JPEG) must never leave the session "busy" forever.
private const val STILL_WATCHDOG_MS = 12_000L
private const val ERROR_IN_USE = CameraDevice.StateCallback.ERROR_CAMERA_IN_USE
private const val ERROR_MAX_IN_USE = CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE
private const val ERROR_DEVICE = CameraDevice.StateCallback.ERROR_CAMERA_DEVICE
private const val ERROR_SERVICE = CameraDevice.StateCallback.ERROR_CAMERA_SERVICE
private const val MAX_OPEN_ATTEMPTS = 3
private const val OPEN_RETRY_DELAY_MS = 700L

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
    private var analysisReader: ImageReader? = null
    private var videoRecorder: VaultVideoRecorder? = null
    private var isScanMode = false
    private var isScanningFrame = false
    private var lastScanTime = 0L

    // Scan mode flavour: false = QR codes, true = live document-edge detection.
    @Volatile private var isDocumentScan = false
    private var wasDocumentFound = false

    private external fun nativeScanQrCode(
        yBytes: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
        rotationDegrees: Int
    ): String?

    /**
     * Set when a native analysis call could not be resolved at runtime. Live analysis then
     * stays off for the rest of this session; the camera itself keeps working.
     */
    @Volatile private var nativeAnalysisUnavailable = false

    /** Live document quad from a Y plane, in the upright frame: [x0,y0,..,x3,y3,score] or null. */
    private external fun nativeDetectDocument(
        yBytes: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
        rotationDegrees: Int
    ): FloatArray?

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
    // Modes the HAL actually advertises. Requesting one it doesn't list is how
    // flash/AE/AF requests end up silently ignored (or capture-failing) on
    // some devices, so every mode goes through the matching `supported*()`.
    private var availableAeModes = IntArray(0)
    private var availableAfModes = IntArray(0)
    private var availableAwbModes = IntArray(0)
    private var availableEffects = IntArray(0)
    private var avoidAutoFlashAeMode = false

    /** Field of view relative to the main camera of this facing (CameraX "intrinsic zoom ratio"). */
    private var intrinsicZoom = 1f

    // Latest 3A state seen on the live preview; decides whether AUTO flash fires
    // (CONTROL_AE_STATE_FLASH_REQUIRED) exactly like CameraX's capture pipeline.
    private var lastAeState: Int? = null
    private var lastAfState: Int? = null
    @Volatile private var lastActivePhysicalId: String? = null

    // Flash-photo state (camera thread only).
    private var stillFlow: StillFlow? = null
    /** Torch is lit as the flash of the capture currently in flight ("torch as flash"). */
    private var torchForFlash = false
    /** Set once a regular flash capture came out black: from then on use torch-as-flash. */
    private var forceTorchAsFlash = false
    private var openAttempts = 0
    private var lastOpenArgs: OpenArgs? = null

    private class OpenArgs(
        val cameraId: String,
        val quality: VaultVideoQuality,
        val photo: VaultPhotoResolution,
    )

    private enum class StillPhase { WAIT_TORCH, WAIT_PRECAPTURE, MAIN }

    /** State of the one still capture in flight (CameraX capture pipeline, ported to Camera2). */
    private class StillFlow(
        val flashRequired: Boolean,
        val useTorch: Boolean,
        /** AE precapture trigger is sent (always for regular flash; only S24 UW with torch). */
        val triggerPrecapture: Boolean,
        val retried: Boolean,
        val captureOrientationDegrees: Int,
    ) {
        var phase = if (useTorch) StillPhase.WAIT_TORCH else StillPhase.WAIT_PRECAPTURE
        var triggerFrame = -1L
        var torchRequestedAt = 0L
        var torchLitAt = 0L
        var convergedFrames = 0
        var postDone = false
        var timeout: Runnable? = null
        var watchdog: Runnable? = null
    }

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

    private val availablePhotoResolutions = LinkedHashMap<String, String>()
    private val availableVideoQualities = LinkedHashMap<String, String>()

    val photoResolutions: Map<String, String> get() = availablePhotoResolutions
    val videoQualities: Map<String, String> get() = availableVideoQualities
    val currentPhotoResolution: String get() = "${maxOf(photoSize.width, photoSize.height)}x${minOf(photoSize.width, photoSize.height)}"
    val currentVideoResolution: String get() = "${maxOf(videoSize.width, videoSize.height)}x${minOf(videoSize.width, videoSize.height)}"

    private var isRecording = false

    /** Finished parts of a segmented recording that Dart has not collected yet. */
    private val finishedSegments = java.util.concurrent.ConcurrentLinkedQueue<VideoSegment>()

    /** Hands over (and forgets) every finished part collected so far, oldest first. */
    fun takeVideoSegments(): List<VideoSegment> {
        val out = ArrayList<VideoSegment>()
        while (true) {
            out.add(finishedSegments.poll() ?: break)
        }
        return out
    }
    private var recordingChunkWriter: ChunkSink? = null

    private var pendingOpenResult: ((Boolean, String?) -> Unit)? = null
    private var pendingCloseCallback: (() -> Unit)? = null
    private var pendingPhotoCallback: ((Boolean, String?) -> Unit)? = null
    private var pendingPhotoWriter: ChunkSink? = null
    private var pendingPhotoBytesCallback: ((Boolean, ByteArray?, ByteArray?, String?) -> Unit)? = null
    private var pendingPhotoAspectRatio: Float? = null
    private var pendingPhotoOrientationDegrees: Int? = null
    private var pendingRecordStart: ((Boolean, String?) -> Unit)? = null

    val currentCameraId: String get() = activeCameraId
    val hasFlash: Boolean get() = isFlashSupported
    val intrinsicZoomRatio: Float get() = intrinsicZoom
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

    fun setScanMode(enable: Boolean, document: Boolean = false) {
        runOnCameraThread {
            // The JNI entry points below live in libvaultexplorer, which this class does not
            // load by itself: NativeEngine's initialiser does, but only once a vault operation
            // has touched it. Opening the camera from Local Storage before any vault was
            // unlocked in this process would otherwise throw UnsatisfiedLinkError on the first
            // analysis frame (an Error, so it was never caught and killed the app).
            if (enable && (nativeAnalysisUnavailable || !NativeEngine.isLoaded)) {
                nativeAnalysisUnavailable = true
                VeLog.w(TAG) { "native library unavailable; live scan analysis disabled" }
                return@runOnCameraThread
            }
            val wantDocument = enable && document
            if (isScanMode == enable && isDocumentScan == wantDocument) return@runOnCameraThread
            isScanMode = enable
            isDocumentScan = wantDocument
            wasDocumentFound = false
            updateRepeatingRequest()
        }
    }

    private fun onAnalysisFrameAvailable(reader: ImageReader) {
        val image = try { reader.acquireLatestImage() } catch (_: Exception) { null } ?: return
        try {
            if (!isScanMode || isScanningFrame || nativeAnalysisUnavailable) return
            val now = System.currentTimeMillis()
            val documentScan = isDocumentScan
            if (now - lastScanTime < (if (documentScan) 100 else 140)) return
            lastScanTime = now
            isScanningFrame = true

            val plane = image.planes[0]
            val buffer = plane.buffer
            val yBytes = ByteArray(buffer.remaining())
            buffer.get(yBytes)
            val w = image.width
            val h = image.height
            val stride = plane.rowStride
            val rot = sensorOrientationDegrees

            bgHandler.post {
                try {
                    if (documentScan) {
                        val quad = nativeDetectDocument(yBytes, w, h, stride, rot)
                        if (quad != null && quad.size >= 9) {
                            wasDocumentFound = true
                            onEvent(
                                mapOf(
                                    "event" to "document_quad",
                                    "found" to true,
                                    "points" to List(8) { quad[it].toDouble() },
                                    "score" to quad[8].toDouble(),
                                )
                            )
                        } else if (wasDocumentFound) {
                            // Only report the loss once, so the overlay can clear immediately.
                            wasDocumentFound = false
                            onEvent(mapOf("event" to "document_quad", "found" to false))
                        }
                    } else {
                        val text = nativeScanQrCode(yBytes, w, h, stride, rot)
                        if (text != null && text.isNotEmpty()) {
                            onEvent(mapOf("event" to "qr_code", "data" to text))
                        }
                    }
                } catch (e: UnsatisfiedLinkError) {
                    // An Error, not an Exception: without this it is fatal on this thread.
                    nativeAnalysisUnavailable = true
                    VeLog.e(TAG, e) { "native analysis unavailable; disabling live scan analysis" }
                } catch (e: Exception) {
                    VeLog.w(TAG, e) { "analysis frame failed" }
                } finally {
                    isScanningFrame = false
                }
            }
        } finally {
            image.close()
        }
    }

    fun dispose() {
        runOnCameraThread {
            closeCameraOnly {
                jpegReader?.close()
                jpegReader = null
                analysisReader?.close()
                analysisReader = null
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
            if (cameraId != activeCameraId) {
                // A different sensor: whatever flash workaround was learned does not carry over.
                forceTorchAsFlash = false
                lastAeState = null
                lastAfState = null
                lastActivePhysicalId = null
            }
            characteristics = chars
            activeCameraId = cameraId
            pendingQuality = videoQuality
            pendingPhotoResolution = photoResolution
            pendingOpenResult = callback
            torchForFlash = false
            openAttempts = 0
            lastOpenArgs = OpenArgs(cameraId, videoQuality, photoResolution)
            configureSizesAndSurfacesLocked(chars, videoQuality, photoResolution)
            openDeviceWithRetry(cameraId)
        } catch (e: Exception) {
            pendingOpenResult = null
            callback(false, e.message)
        }
    }

    private fun openDeviceWithRetry(cameraId: String) {
        try {
            @Suppress("MissingPermission")
            cameraManager.openCamera(cameraId, deviceStateCallback, bgHandler)
        } catch (e: CameraAccessException) {
            val busy = e.reason == CameraAccessException.CAMERA_IN_USE ||
                e.reason == CameraAccessException.MAX_CAMERAS_IN_USE
            if (!scheduleOpenRetry(busy, "openCamera threw ${e.reason}")) failOpen(e.message ?: "camera access failed")
        } catch (e: Exception) {
            failOpen(e.message ?: "camera open failed")
        }
    }

    private fun scheduleOpenRetry(retryable: Boolean, why: String): Boolean {
        val args = lastOpenArgs
        if (!retryable || args == null || pendingOpenResult == null || openAttempts >= MAX_OPEN_ATTEMPTS) return false
        openAttempts++
        VeLog.w(TAG) { "$why; retrying open ($openAttempts/$MAX_OPEN_ATTEMPTS)" }
        bgHandler.postDelayed({
            if (pendingOpenResult != null && cameraDevice == null && activeCameraId == args.cameraId) {
                openDeviceWithRetry(args.cameraId)
            }
        }, OPEN_RETRY_DELAY_MS)
        return true
    }

    private fun failOpen(reason: String) {
        val cb = pendingOpenResult ?: return
        pendingOpenResult = null
        cb(false, reason)
    }

    private fun closeCameraOnly(then: () -> Unit) {
        dropStillFlow("camera closed")
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
            // Another app took the camera, or the HAL dropped it. Previously this closed the
            // device silently and left the UI on a frozen preview with a dead shutter button.
            VeLog.w(TAG) { "Camera device ${device.id} disconnected" }
            releaseAfterDeviceLoss(device, "camera disconnected")
            failOpen("camera disconnected")
            pendingRecordStart?.invoke(false, "camera disconnected")
            pendingRecordStart = null
            onEvent(mapOf("event" to "error", "message" to "camera disconnected"))
        }

        override fun onError(device: CameraDevice, error: Int) {
            VeLog.e(TAG) { "Camera device error $error on device ${device.id}" }
            releaseAfterDeviceLoss(device, "camera error $error")

            // IN_USE / MAX_CAMERAS_IN_USE / CAMERA_DEVICE / CAMERA_SERVICE while opening are
            // frequently transient (CameraX retries them too).
            val transient = error == ERROR_IN_USE || error == ERROR_MAX_IN_USE ||
                error == ERROR_DEVICE || error == ERROR_SERVICE
            if (scheduleOpenRetry(transient, "camera error $error")) return

            failOpen("camera error $error")
            pendingRecordStart?.invoke(false, "camera error $error")
            pendingRecordStart = null
            onEvent(mapOf("event" to "error", "message" to "camera error $error"))
        }

        override fun onClosed(device: CameraDevice) {
            pendingCloseCallback?.let { cb -> pendingCloseCallback = null; cb() }
        }
    }

    /** Common teardown when the device goes away underneath us (disconnect / error). */
    private fun releaseAfterDeviceLoss(device: CameraDevice, @Suppress("UNUSED_PARAMETER") why: String) {
        dropStillFlow("camera unavailable")
        try { captureSession?.close() } catch (_: Exception) {}
        try { videoRecorder?.releaseEncoder() } catch (_: Exception) {}
        captureSession = null
        videoRecorder = null
        isRecording = false
        recordingChunkWriter = null
        torchForFlash = false
        try { device.close() } catch (_: Exception) {}
        cameraDevice = null
    }

    private fun configureSizesAndSurfacesLocked(
        chars: CameraCharacteristics,
        videoQuality: VaultVideoQuality,
        photoResolution: VaultPhotoResolution
    ) {
        val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?: throw IllegalStateException("no stream configuration map for $activeCameraId")

        val minFocusDist = chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE)
        isFixedFocus = minFocusDist == null || minFocusDist == 0f
        maxAfRegions = chars.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) ?: 0
        maxAeRegions = chars.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE) ?: 0
        isFlashSupported = chars.hasFlashUnit()
        availableAeModes = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_MODES) ?: IntArray(0)
        availableAfModes = chars.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: IntArray(0)
        availableAwbModes = chars.get(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES) ?: IntArray(0)
        availableEffects = chars.get(CameraCharacteristics.CONTROL_AVAILABLE_EFFECTS) ?: IntArray(0)
        avoidAutoFlashAeMode = CameraFlashQuirks.shouldAvoidAutoFlashAeMode(chars)
        intrinsicZoom = try { intrinsicZoomRatioFor(cameraManager, activeCameraId) } catch (_: Exception) { 1f }

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

        val jpegSizes = map.getOutputSizes(ImageFormat.JPEG)?.toList().orEmpty().ifEmpty { listOf(Size(1920, 1080)) }
        val maxJpegSize = jpegSizes.maxByOrNull { it.width.toLong() * it.height.toLong() } ?: jpegSizes.first()
        val photoTiers = photoTierSizes(jpegSizes, maxJpegSize)
        // A tier the camera has no distinct size for is not offered; if one of
        // those was saved as the choice, use the closest tier that is.
        photoSize = photoTiers[photoResolution]
            ?: photoTiers.entries
                .minByOrNull { abs(it.key.targetLongEdge - photoResolution.targetLongEdge) }
                ?.value
            ?: maxJpegSize

        val videoSizes = map.getOutputSizes(MediaCodec::class.java)?.toList().orEmpty().ifEmpty { listOf(Size(1920, 1080)) }
        videoSize = chooseVideoSizeByHeight(videoSizes, videoQuality.targetVideoHeight)

        availablePhotoResolutions.clear()
        // Largest first, so the map (and the menu built from it) reads top-down.
        for (res in VaultPhotoResolution.values().sortedByDescending { it.targetLongEdge }) {
            val s = photoTiers[res] ?: continue
            val key = when (res) {
                VaultPhotoResolution.LOW -> "low"
                VaultPhotoResolution.MEDIUM -> "med"
                VaultPhotoResolution.HIGH -> "high"
                VaultPhotoResolution.MAX -> "max"
            }
            availablePhotoResolutions[key] = "${maxOf(s.width, s.height)}x${minOf(s.width, s.height)}"
        }

        availableVideoQualities.clear()
        for (q in VaultVideoQuality.values()) {
            val s = chooseVideoSizeByHeight(videoSizes, q.targetVideoHeight)
            val key = when (q) {
                VaultVideoQuality.SD -> "sd"
                VaultVideoQuality.HD -> "hd"
                VaultVideoQuality.FHD -> "fhd"
                VaultVideoQuality.UHD -> "uhd"
            }
            availableVideoQualities[key] = "${maxOf(s.width, s.height)}x${minOf(s.width, s.height)}"
        }

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

        analysisReader?.close()
        val yuvSizes = map.getOutputSizes(ImageFormat.YUV_420_888)?.toList().orEmpty()
        // Same aspect as the photo/preview, so a quad detected here maps 1:1 onto the
        // preview (a different aspect would be a differently cropped field of view).
        val matchingYuv = yuvSizes
            .filter { abs((it.width.toFloat() / it.height.toFloat()) - photoAspect) < 0.05f }
            .ifEmpty { yuvSizes }
        val scanSize = chooseSize(matchingYuv, 720, capAt1080p = true)
        val aReader = ImageReader.newInstance(scanSize.width, scanSize.height, ImageFormat.YUV_420_888, 2)
        aReader.setOnImageAvailableListener({ r -> onAnalysisFrameAvailable(r) }, bgHandler)
        analysisReader = aReader

        currentPreviewWidth = previewSize.width
        currentPreviewHeight = previewSize.height
    }

    private fun safePrepareRecorder(
        width: Int,
        height: Int,
        quality: VaultVideoQuality,
        orientation: Int,
        segmentSeconds: Int = 0,
    ): VaultVideoRecorder {
        return try {
            val recorder = VaultVideoRecorder(width, height, quality, recordAudio = true, cacheDir = context.cacheDir, segmentSeconds = segmentSeconds)
            recorder.prepareEncoder(orientation)
            recorder
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Failed to prepare encoder at ${width}x$height, falling back to 1080p" }
            try {
                val fallback = VaultVideoRecorder(1920, 1080, VaultVideoQuality.FHD, recordAudio = true, cacheDir = context.cacheDir, segmentSeconds = segmentSeconds)
                fallback.prepareEncoder(orientation)
                fallback
            } catch (e2: Exception) {
                VeLog.w(TAG, e2) { "1080p fallback failed, falling back to 720p" }
                val fallback720 = VaultVideoRecorder(1280, 720, VaultVideoQuality.HD, recordAudio = true, cacheDir = context.cacheDir, segmentSeconds = segmentSeconds)
                fallback720.prepareEncoder(orientation)
                fallback720
            }
        }
    }

    private fun createSessionLocked() {
        val device = cameraDevice ?: return

        dropStillFlow("camera session restarted")
        captureSession?.let { try { it.close() } catch (_: Exception) {} }
        captureSession = null

        val outputs = if (isRecording) {
            listOfNotNull(previewSurface, videoRecorder?.inputSurface)
        } else {
            listOfNotNull(previewSurface, jpegReader?.surface, analysisReader?.surface)
        }

        val stateCallback = object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(session: CameraCaptureSession) {
                if (cameraDevice !== device) {
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
            pendingRecordStart = null
            abortRecordingAndRestorePreview()
            startCb(false, reason)
            return
        }

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
            session.setRepeatingRequest(buildRequest(), repeatingCallback, bgHandler)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "updateRepeatingRequest failed" }
        }
    }

    /**
     * Watches every preview frame. CameraX bases the "does AUTO flash fire" decision and the
     * wait-for-AE-to-settle logic on these results; without them a flash photo is taken blind.
     */
    private val repeatingCallback = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureCompleted(
            session: CameraCaptureSession,
            request: CaptureRequest,
            result: TotalCaptureResult,
        ) {
            lastAeState = result.get(CaptureResult.CONTROL_AE_STATE)
            lastAfState = result.get(CaptureResult.CONTROL_AF_STATE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                lastActivePhysicalId = result.get(CaptureResult.LOGICAL_MULTI_CAMERA_ACTIVE_PHYSICAL_ID)
            }
            val flow = stillFlow ?: return
            onStillFrame(flow, result)
        }
    }

    private fun newRequestBuilder(): CaptureRequest.Builder {
        val device = cameraDevice ?: throw IllegalStateException("no camera device")
        val template = if (isRecording) CameraDevice.TEMPLATE_RECORD else CameraDevice.TEMPLATE_PREVIEW
        val builder = device.createCaptureRequest(template)
        previewSurface?.let { builder.addTarget(it) }
        if (isRecording) videoRecorder?.inputSurface?.let { builder.addTarget(it) }
        if (isScanMode) analysisReader?.surface?.let { builder.addTarget(it) }
        applyControls(builder)
        return builder
    }

    private fun buildRequest(): CaptureRequest = newRequestBuilder().build()

    private fun applyControls(builder: CaptureRequest.Builder) {
        builder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)

        if (isFixedFocus) {
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_OFF)
        } else if (isTapToFocusActive && activeAfRegions != null && maxAfRegions > 0) {
            builder.set(CaptureRequest.CONTROL_AF_MODE, supportedAfMode(CaptureRequest.CONTROL_AF_MODE_AUTO))
            builder.set(CaptureRequest.CONTROL_AF_REGIONS, activeAfRegions)
        } else {
            // CameraX: CONTINUOUS_PICTURE for preview/stills, CONTINUOUS_VIDEO only while recording.
            val wanted = if (isRecording) CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO
            else CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
            builder.set(CaptureRequest.CONTROL_AF_MODE, supportedAfMode(wanted))
        }

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

    fun setFocusAndExposurePoint(nx: Float, ny: Float) {
        runOnCameraThread {
            val session = captureSession ?: return@runOnCameraThread
            val chars = characteristics ?: return@runOnCameraThread
            val activeArray = sensorArraySize ?: return@runOnCameraThread

            val sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            val isFront = chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT

            val (sensorNormX, sensorNormY) = when (sensorOrientation) {
                90 -> if (isFront) Pair(ny, nx) else Pair(ny, 1f - nx)
                270 -> if (isFront) Pair(1f - ny, 1f - nx) else Pair(1f - ny, nx)
                else -> Pair(nx, ny)
            }

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
        val mode = if (availableAwbModes.isEmpty() || awbMode in availableAwbModes) awbMode
        else CaptureRequest.CONTROL_AWB_MODE_AUTO
        builder.set(CaptureRequest.CONTROL_AWB_MODE, mode)
    }

    // CameraX CameraMetadata.getSupportedAeMode/AfMode: never put a mode on a request that the
    // HAL doesn't advertise -- some devices ignore the whole 3A block (flash included) then.
    private fun supportedAeMode(preferred: Int): Int {
        if (availableAeModes.isEmpty() || preferred in availableAeModes) return preferred
        if (CaptureRequest.CONTROL_AE_MODE_ON in availableAeModes) return CaptureRequest.CONTROL_AE_MODE_ON
        return availableAeModes.firstOrNull { it == CaptureRequest.CONTROL_AE_MODE_OFF } ?: preferred
    }

    private fun supportedAfMode(preferred: Int): Int {
        if (availableAfModes.isEmpty() || preferred in availableAfModes) return preferred
        val continuous = intArrayOf(
            CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE,
            CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO,
        )
        if (preferred == CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE ||
            preferred == CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO
        ) {
            continuous.firstOrNull { it in availableAfModes }?.let { return it }
        }
        if (CaptureRequest.CONTROL_AF_MODE_AUTO in availableAfModes) return CaptureRequest.CONTROL_AF_MODE_AUTO
        return CaptureRequest.CONTROL_AF_MODE_OFF
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
        val mode = if (availableEffects.isEmpty() || effectMode in availableEffects) effectMode
        else CaptureRequest.CONTROL_EFFECT_MODE_OFF
        builder.set(CaptureRequest.CONTROL_EFFECT_MODE, mode)
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

    private fun applyFlash(builder: CaptureRequest.Builder) {
        if (!isFlashSupported) {
            // No flash unit: don't send FLASH_MODE at all, some HALs reject it.
            builder.set(CaptureRequest.CONTROL_AE_MODE, supportedAeMode(CaptureRequest.CONTROL_AE_MODE_ON))
            return
        }
        // The torch is lit either because the user asked for it, or because a flash photo is
        // being taken with "torch as flash" (device quirk / black-frame fallback).
        val torch = torchForFlash || flashMode == VaultFlashMode.TORCH
        if (torch) {
            builder.set(CaptureRequest.CONTROL_AE_MODE, supportedAeMode(CaptureRequest.CONTROL_AE_MODE_ON))
            builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH)
            return
        }
        // While recording, flash ON/AUTO mean nothing (a still-flash would fire mid-video).
        val aeMode = if (isRecording) {
            CaptureRequest.CONTROL_AE_MODE_ON
        } else when (flashMode) {
            VaultFlashMode.ON -> CaptureRequest.CONTROL_AE_MODE_ON_ALWAYS_FLASH
            VaultFlashMode.AUTO ->
                if (avoidAutoFlashAeMode) CaptureRequest.CONTROL_AE_MODE_ON
                else CaptureRequest.CONTROL_AE_MODE_ON_AUTO_FLASH
            else -> CaptureRequest.CONTROL_AE_MODE_ON
        }
        val chosen = supportedAeMode(aeMode)
        builder.set(CaptureRequest.CONTROL_AE_MODE, chosen)
        if (chosen == CaptureRequest.CONTROL_AE_MODE_ON || chosen == CaptureRequest.CONTROL_AE_MODE_OFF) {
            builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
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

    fun setOrientationDegrees(deviceRotationDegrees: Int) {
        runOnCameraThread {
            lastOrientationDegrees = ((deviceRotationDegrees % 360) + 360) % 360
        }
    }

    private fun computeCaptureOrientation(rotationDegrees: Int = lastOrientationDegrees): Int {
        val chars = characteristics ?: return 0
        val sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        val front = chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
        return if (front) {
            (sensorOrientation + rotationDegrees) % 360
        } else {
            (sensorOrientation - rotationDegrees + 360) % 360
        }
    }

    /** Common gate for both photo entry points; reports the reason through [onError]. */
    private fun stillPreconditionsOk(onError: (String) -> Unit): Boolean {
        if (cameraDevice == null || captureSession == null || jpegReader == null) {
            onError("camera not ready")
            return false
        }
        if (isRecording) {
            onError("cannot take photo while recording")
            return false
        }
        if (stillFlow != null) {
            onError("capture already in progress")
            return false
        }
        return true
    }

    fun capturePhoto(
        aspectRatio: Float? = null,
        orientationDegrees: Int? = null,
        callback: (Boolean, ByteArray?, ByteArray?, String?) -> Unit,
    ) {
        runOnCameraThread {
            if (!stillPreconditionsOk { callback(false, null, null, it) }) return@runOnCameraThread
            pendingPhotoBytesCallback = callback
            pendingPhotoAspectRatio = aspectRatio
            pendingPhotoOrientationDegrees = orientationDegrees
            startStill(retried = false)
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
            if (!stillPreconditionsOk { callback(false, it) }) return@runOnCameraThread
            pendingPhotoCallback = callback
            pendingPhotoWriter = writer
            startStill(retried = false)
        }
    }

    private fun isFlashRequiredForStill(): Boolean {
        if (!isFlashSupported || isRecording) return false
        return when (flashMode) {
            VaultFlashMode.ON -> true
            VaultFlashMode.AUTO -> lastAeState == CaptureResult.CONTROL_AE_STATE_FLASH_REQUIRED
            else -> false // OFF, or the torch is already lit
        }
    }

    /** Is the ultra-wide sensor the one producing the image? (Only matters for the S24 quirk.) */
    private fun isUltraWideActive(): Boolean {
        val phys = lastActivePhysicalId
        if (phys != null) {
            return try { intrinsicZoomRatioFor(cameraManager, phys) < 1f } catch (_: Exception) { true }
        }
        if (intrinsicZoom < 0.95f) return true
        if (zoomRatioSupported) return currentZoom < 0.95f
        return true // unknown -> be safe, like CameraX
    }

    private fun startStill(retried: Boolean) {
        val chars = characteristics
        if (cameraDevice == null || captureSession == null || jpegReader == null || chars == null) {
            failPendingPhoto("camera not ready")
            return
        }
        val flashRequired = isFlashRequiredForStill()
        val useTorch = flashRequired &&
            (forceTorchAsFlash || CameraFlashQuirks.shouldUseTorchAsFlash(chars, isUltraWideActive()))
        val triggerPrecapture = when {
            !flashRequired -> false
            !useTorch -> true
            forceTorchAsFlash -> false
            else -> CameraFlashQuirks.torchAsFlashAllowsAePrecapture()
        }
        // Freeze orientation at capture start. Sensor updates can arrive while
        // flash metering is running; the JPEG must keep the orientation chosen
        // by the caller for the preview frame.
        val captureRotation = pendingPhotoOrientationDegrees ?: lastOrientationDegrees
        val flow = StillFlow(
            flashRequired,
            useTorch,
            triggerPrecapture,
            retried,
            computeCaptureOrientation(captureRotation),
        )
        stillFlow = flow
        VeLog.d(TAG) { "still: flashRequired=$flashRequired torch=$useTorch precapture=$triggerPrecapture retried=$retried" }

        flow.watchdog = Runnable {
            if (stillFlow === flow) {
                VeLog.w(TAG) { "still capture timed out in phase ${flow.phase}" }
                abortStill("capture timed out")
            }
        }.also { bgHandler.postDelayed(it, STILL_WATCHDOG_MS) }

        when {
            !flashRequired -> submitMainCapture(flow)
            useTorch -> {
                flow.torchRequestedAt = SystemClock.elapsedRealtime()
                torchForFlash = true
                updateRepeatingRequest()
                armThreeATimeout(flow)
            }
            else -> {
                sendPrecaptureTrigger(flow)
                armThreeATimeout(flow)
            }
        }
    }

    /** CameraX waits at most 5 s for 3A when a flash is involved, then shoots anyway. */
    private fun armThreeATimeout(flow: StillFlow) {
        flow.timeout = Runnable {
            if (stillFlow === flow && flow.phase != StillPhase.MAIN) {
                VeLog.w(TAG) { "3A did not settle in ${FLASH_3A_TIMEOUT_MS}ms; shooting anyway" }
                submitMainCapture(flow)
            }
        }.also { bgHandler.postDelayed(it, FLASH_3A_TIMEOUT_MS) }
    }

    private fun sendPrecaptureTrigger(flow: StillFlow) {
        val session = captureSession
        if (session == null) {
            submitMainCapture(flow)
            return
        }
        try {
            val builder = newRequestBuilder()
            builder.set(
                CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER,
                CameraMetadata.CONTROL_AE_PRECAPTURE_TRIGGER_START,
            )
            session.capture(builder.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureStarted(
                    session: CameraCaptureSession,
                    request: CaptureRequest,
                    timestamp: Long,
                    frameNumber: Long,
                ) {
                    if (stillFlow === flow) flow.triggerFrame = frameNumber
                }

                override fun onCaptureFailed(
                    session: CameraCaptureSession,
                    request: CaptureRequest,
                    failure: CaptureFailure,
                ) {
                    // Metering failed; a flash shot without it is still better than no photo.
                    if (stillFlow === flow && flow.phase != StillPhase.MAIN) submitMainCapture(flow)
                }
            }, bgHandler)
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "AE precapture trigger failed" }
            submitMainCapture(flow)
        }
    }

    /** Preview-frame hook: decides when the 3A wait of the current still is over. */
    private fun onStillFrame(flow: StillFlow, result: TotalCaptureResult) {
        when (flow.phase) {
            StillPhase.MAIN -> Unit
            StillPhase.WAIT_PRECAPTURE -> {
                if (flow.triggerFrame < 0 || result.frameNumber <= flow.triggerFrame) return
                if (isPrecaptureSettled(result)) submitMainCapture(flow)
            }
            StillPhase.WAIT_TORCH -> {
                // 1) the torch really is on: the request echo says so (and the flash fired)
                val echo = result.get(CaptureResult.FLASH_MODE)
                if (echo != null && echo != CaptureResult.FLASH_MODE_TORCH) return
                val now = SystemClock.elapsedRealtime()
                val fs = result.get(CaptureResult.FLASH_STATE)
                // Some HALs never report FIRED for the torch: don't wait on it for more than a second.
                if (fs != null && fs != CaptureResult.FLASH_STATE_FIRED && now - flow.torchRequestedAt < 1_000L) return
                if (flow.torchLitAt == 0L) {
                    flow.torchLitAt = now
                    if (flow.triggerPrecapture) sendPrecaptureTrigger(flow)
                }
                // 2) AE has re-metered under the torch
                if (flow.triggerPrecapture) {
                    if (flow.triggerFrame >= 0 && result.frameNumber > flow.triggerFrame && isPrecaptureSettled(result)) {
                        submitMainCapture(flow)
                    }
                    return
                }
                flow.convergedFrames = if (isTorchConverged(result)) flow.convergedFrames + 1 else 0
                if (now - flow.torchLitAt >= TORCH_SETTLE_MS && flow.convergedFrames >= TORCH_CONVERGED_FRAMES) {
                    submitMainCapture(flow)
                }
            }
        }
    }

    // CameraX Controller3A.createLock3AForCaptureExitConditions
    private fun isPrecaptureSettled(result: CaptureResult): Boolean {
        val aeMode = result.get(CaptureResult.CONTROL_AE_MODE)
        val aeState = result.get(CaptureResult.CONTROL_AE_STATE)
        val aeReady = aeMode == null || aeMode == CaptureResult.CONTROL_AE_MODE_OFF || aeState == null ||
            aeState == CaptureResult.CONTROL_AE_STATE_CONVERGED ||
            aeState == CaptureResult.CONTROL_AE_STATE_FLASH_REQUIRED ||
            aeState == CaptureResult.CONTROL_AE_STATE_LOCKED
        return aeReady && isAfSettled(result)
    }

    // CameraX ConvergenceUtils.is3AConverged(isTorchAsFlash = true): FLASH_REQUIRED and
    // UNKNOWN are *not* accepted here (some devices report FLASH_REQUIRED the whole time
    // the torch is lit).
    private fun isTorchConverged(result: CaptureResult): Boolean {
        val aeMode = result.get(CaptureResult.CONTROL_AE_MODE)
        val aeState = result.get(CaptureResult.CONTROL_AE_STATE)
        val aeReady = aeMode == CaptureResult.CONTROL_AE_MODE_OFF ||
            aeState == CaptureResult.CONTROL_AE_STATE_CONVERGED
        val awbMode = result.get(CaptureResult.CONTROL_AWB_MODE)
        val awbState = result.get(CaptureResult.CONTROL_AWB_STATE)
        val awbReady = awbMode == CaptureResult.CONTROL_AWB_MODE_OFF || awbState == null ||
            awbState == CaptureResult.CONTROL_AWB_STATE_CONVERGED
        return aeReady && awbReady && isAfSettled(result)
    }

    private fun isAfSettled(result: CaptureResult): Boolean {
        val afMode = result.get(CaptureResult.CONTROL_AF_MODE)
        val continuous = afMode == CaptureResult.CONTROL_AF_MODE_CONTINUOUS_PICTURE ||
            afMode == CaptureResult.CONTROL_AF_MODE_CONTINUOUS_VIDEO
        if (!continuous) return true
        val afState = result.get(CaptureResult.CONTROL_AF_STATE) ?: return true
        return afState == CaptureResult.CONTROL_AF_STATE_PASSIVE_FOCUSED ||
            afState == CaptureResult.CONTROL_AF_STATE_PASSIVE_UNFOCUSED ||
            afState == CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED ||
            afState == CaptureResult.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED
    }

    private fun submitMainCapture(flow: StillFlow) {
        if (stillFlow !== flow || flow.phase == StillPhase.MAIN) return
        flow.phase = StillPhase.MAIN
        flow.timeout?.let { bgHandler.removeCallbacks(it) }
        flow.timeout = null

        val device = cameraDevice
        val session = captureSession
        val reader = jpegReader
        if (device == null || session == null || reader == null) {
            abortStill("camera not ready")
            return
        }
        try {
            val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            builder.addTarget(reader.surface)
            applyControls(builder)
            builder.set(CaptureRequest.JPEG_ORIENTATION, flow.captureOrientationDegrees)
            session.capture(builder.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(
                    session: CameraCaptureSession,
                    request: CaptureRequest,
                    result: TotalCaptureResult,
                ) {
                    // Exposure is done: torch off / precapture cancel. The JPEG follows via the reader.
                    postStillCapture(flow)
                }

                override fun onCaptureFailed(
                    session: CameraCaptureSession,
                    request: CaptureRequest,
                    failure: CaptureFailure,
                ) {
                    VeLog.w(TAG) { "still capture failed, reason=${failure.reason}" }
                    if (stillFlow === flow) abortStill("capture failed (reason ${failure.reason})")
                }
            }, bgHandler)
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "still capture submit failed" }
            abortStill(e.message ?: "capture failed")
        }
    }

    /** CameraX POST_CAPTURE: put the torch back and reset the AE state machine. */
    private fun postStillCapture(flow: StillFlow) {
        if (flow.postDone) return
        flow.postDone = true
        if (flow.useTorch && torchForFlash) {
            torchForFlash = false
            updateRepeatingRequest()
        }
        if (flow.flashRequired && (!flow.useTorch || flow.triggerPrecapture)) {
            val session = captureSession ?: return
            try {
                val builder = newRequestBuilder()
                builder.set(
                    CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER,
                    CameraMetadata.CONTROL_AE_PRECAPTURE_TRIGGER_CANCEL,
                )
                session.capture(builder.build(), null, bgHandler)
            } catch (_: Exception) {
            }
        }
    }

    /** Ends the flow (successfully or not) and releases timers. Does not touch callbacks. */
    private fun finishStill(flow: StillFlow) {
        flow.watchdog?.let { bgHandler.removeCallbacks(it) }
        flow.timeout?.let { bgHandler.removeCallbacks(it) }
        flow.watchdog = null
        flow.timeout = null
        postStillCapture(flow)
        if (stillFlow === flow) stillFlow = null
    }

    private fun abortStill(reason: String) {
        val flow = stillFlow ?: return
        finishStill(flow)
        failPendingPhoto(reason)
    }

    /** Session/device went away: release the torch and fail whoever was waiting. */
    private fun dropStillFlow(reason: String) {
        val flow = stillFlow
        if (flow != null) finishStill(flow)
        if (torchForFlash) torchForFlash = false
        if (flow != null) failPendingPhoto(reason)
    }

    private fun failPendingPhoto(reason: String) {
        pendingPhotoBytesCallback?.let {
            pendingPhotoBytesCallback = null
            pendingPhotoAspectRatio = null
            pendingPhotoOrientationDegrees = null
            it(false, null, null, reason)
        }
        pendingPhotoCallback?.let {
            pendingPhotoCallback = null
            pendingPhotoWriter = null
            it(false, reason)
        }
    }

    /**
     * A flash photo that came out (near-)black is the failure the user reported on some
     * devices. Real dark scenes still have sensor noise; a black frame is flat ~0.
     */
    private fun isBlackJpeg(bytes: ByteArray): Boolean {
        return try {
            val opts = BitmapFactory.Options().apply { inSampleSize = 16 }
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) ?: return false
            val w = bmp.width
            val h = bmp.height
            val px = IntArray(w * h)
            bmp.getPixels(px, 0, w, 0, 0, w, h)
            bmp.recycle()
            if (px.isEmpty()) return false
            var sum = 0L
            var bright = 0
            for (c in px) {
                val luma = (((c shr 16) and 0xFF) * 299 + ((c shr 8) and 0xFF) * 587 + (c and 0xFF) * 114) / 1000
                sum += luma
                if (luma > 24) bright++
            }
            val mean = sum.toDouble() / px.size
            mean < 3.0 && bright < px.size / 200
        } catch (_: Throwable) {
            false
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

            val flow = stillFlow
            if (flow != null) {
                if (flow.flashRequired && !flow.useTorch && !flow.retried && isBlackJpeg(bytes)) {
                    // The regular flash sequence produced a black frame on this device. Shoot it
                    // again once with the torch as the flash (and keep doing so on this camera).
                    VeLog.w(TAG) { "flash photo is black; retrying with torch-as-flash" }
                    forceTorchAsFlash = true
                    finishStill(flow)
                    startStill(retried = true)
                    return
                }
                // Release the session *before* handing the photo out: the callback may
                // immediately ask for the next one.
                finishStill(flow)
            }

            val bytesCb = pendingPhotoBytesCallback
            if (bytesCb != null) {
                pendingPhotoBytesCallback = null
                val aspectRatio = pendingPhotoAspectRatio
                pendingPhotoAspectRatio = null
                pendingPhotoOrientationDegrees = null
                val photoBytes = if (aspectRatio != null) {
                    cropJpegToAspectRatio(bytes, aspectRatio)
                } else {
                    bytes
                }
                val thumbBytes = try {
                    val opts = BitmapFactory.Options().apply {
                        inSampleSize = 8
                    }
                    val bmp = BitmapFactory.decodeByteArray(photoBytes, 0, photoBytes.size, opts)
                    if (bmp != null) {
                        // Correctly extract EXIF orientation and apply it to the thumbnail bitmap
                        val exif = ExifInterface(ByteArrayInputStream(photoBytes))
                        val orientation = exif.getAttributeInt(
                            ExifInterface.TAG_ORIENTATION,
                            ExifInterface.ORIENTATION_NORMAL
                        )
                        val matrix = Matrix()
                        when (orientation) {
                            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                            ExifInterface.ORIENTATION_TRANSPOSE -> {
                                matrix.postRotate(90f)
                                matrix.postScale(-1f, 1f)
                            }
                            ExifInterface.ORIENTATION_TRANSVERSE -> {
                                matrix.postRotate(270f)
                                matrix.postScale(-1f, 1f)
                            }
                        }

                        val orientedBmp = if (!matrix.isIdentity) {
                            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
                            if (rotated !== bmp) bmp.recycle()
                            rotated
                        } else {
                            bmp
                        }

                        val thumb = ThumbnailUtils.extractThumbnail(orientedBmp, 160, 160)
                        val stream = ByteArrayOutputStream()
                        thumb.compress(Bitmap.CompressFormat.JPEG, 70, stream)
                        if (thumb !== orientedBmp) thumb.recycle()
                        orientedBmp.recycle()
                        stream.toByteArray()
                    } else null
                } catch (_: Exception) {
                    null
                }
                bytesCb.invoke(true, photoBytes, thumbBytes, null)
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

    /**
     * Crop the saved still to the same aspect ratio used by the on-screen preview.
     * The preview uses a centered cover crop, so a centered still crop keeps the
     * captured framing consistent with what the user saw. Scans bypass this path.
     */
    private fun cropJpegToAspectRatio(bytes: ByteArray, targetAspectRatio: Float): ByteArray {
        if (!targetAspectRatio.isFinite() || targetAspectRatio <= 0f) return bytes

        var cropped: Bitmap? = null
        var temporaryFile: File? = null
        try {
            val sourceExif = ExifInterface(ByteArrayInputStream(bytes))
            val orientation = sourceExif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
            val orientationSwapsAxes = orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                orientation == ExifInterface.ORIENTATION_ROTATE_270 ||
                orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
                orientation == ExifInterface.ORIENTATION_TRANSVERSE
            val rawTargetAspectRatio = if (orientationSwapsAxes) {
                1f / targetAspectRatio
            } else {
                targetAspectRatio
            }

            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            val sourceWidth = bounds.outWidth
            val sourceHeight = bounds.outHeight
            if (sourceWidth <= 0 || sourceHeight <= 0) return bytes

            val sourceAspectRatio = sourceWidth.toFloat() / sourceHeight.toFloat()
            if (abs(sourceAspectRatio - rawTargetAspectRatio) / rawTargetAspectRatio < 0.005f) {
                return bytes
            }

            val cropWidth: Int
            val cropHeight: Int
            if (sourceAspectRatio > rawTargetAspectRatio) {
                cropWidth = (sourceHeight * rawTargetAspectRatio).toInt().coerceIn(1, sourceWidth)
                cropHeight = sourceHeight
            } else {
                cropWidth = sourceWidth
                cropHeight = (sourceWidth / rawTargetAspectRatio).toInt().coerceIn(1, sourceHeight)
            }
            val left = (sourceWidth - cropWidth) / 2
            val top = (sourceHeight - cropHeight) / 2
            val decoder = BitmapRegionDecoder.newInstance(bytes, 0, bytes.size)
            try {
                cropped = decoder.decodeRegion(
                    Rect(left, top, left + cropWidth, top + cropHeight),
                    BitmapFactory.Options(),
                ) ?: return bytes
            } finally {
                decoder.recycle()
            }

            val encoded = ByteArrayOutputStream().use { stream ->
                if (!cropped.compress(Bitmap.CompressFormat.JPEG, 95, stream)) return bytes
                stream.toByteArray()
            }

            // Bitmap compression drops EXIF. Restore the original orientation so
            // Android's JPEG_ORIENTATION continues to display the crop upright.
            val croppedFile = File.createTempFile("camera-crop-", ".jpg", context.cacheDir)
            temporaryFile = croppedFile
            croppedFile.writeBytes(encoded)
            ExifInterface(croppedFile.absolutePath).apply {
                setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
                sourceExif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)?.let {
                    setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, it)
                }
                sourceExif.getAttribute(ExifInterface.TAG_GPS_LATITUDE)?.let {
                    setAttribute(ExifInterface.TAG_GPS_LATITUDE, it)
                }
                sourceExif.getAttribute(ExifInterface.TAG_GPS_LATITUDE_REF)?.let {
                    setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, it)
                }
                sourceExif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE)?.let {
                    setAttribute(ExifInterface.TAG_GPS_LONGITUDE, it)
                }
                sourceExif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF)?.let {
                    setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, it)
                }
                saveAttributes()
            }
            return croppedFile.readBytes()
        } catch (e: Throwable) {
            VeLog.w(TAG, e) { "could not crop still to preview aspect ratio" }
            return bytes
        } finally {
            if (cropped != null && !cropped.isRecycled) cropped.recycle()
            temporaryFile?.delete()
        }
    }

    /**
     * [segmentSeconds] above zero records in parts of exactly that length (see
     * [SegmentedVideoEngine]); each finished part is queued for [takeVideoSegments]
     * and announced with a `video_segment` event.
     */
    fun startRecording(
        volId: Int,
        virtualPath: String,
        segmentSeconds: Int = 0,
        callback: (Boolean, String?) -> Unit,
    ) {
        startRecordingInternal(VaultChunkWriter(volId, virtualPath), segmentSeconds, callback)
    }

    fun startRecordingToScratchpad(
        scratchpadFile: File,
        key: SecretKey,
        callback: (Boolean, String?) -> Unit,
    ) {
        startRecordingInternal(ScratchpadChunkWriter(scratchpadFile, key), 0, callback)
    }

    private fun startRecordingInternal(writer: ChunkSink, segmentSeconds: Int, callback: (Boolean, String?) -> Unit) {
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
                safePrepareRecorder(videoSize.width, videoSize.height, pendingQuality, computeCaptureOrientation(), segmentSeconds)
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "prepare recorder failed" }
                callback(false, e.message ?: "recorder prepare failed")
                return@runOnCameraThread
            }
            if (segmentSeconds > 0) {
                recorder.onSegmentFinished = { segment ->
                    finishedSegments.add(segment)
                    // Only a nudge: the parts themselves stay queued here until
                    // Dart collects them, so a missed event loses nothing.
                    onEvent(mapOf("event" to "video_segment"))
                }
            }
            videoRecorder = recorder
            recordingChunkWriter = writer
            isRecording = true
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
            // For a segmented recording every earlier part has been queued in
            // finishedSegments by the time this returns, and the result is the
            // length of the last part (the file at tempFilePath) only.
            val result = recorder.requestStop()
            val path = recorder.tempFilePath
            recorder.releaseRecorderOnly()

            // A recording stopped before anything was encoded leaves an empty
            // file (or, segmented, no file at all: no keyframe ever arrived);
            // report it as "no video" instead of handing it on.
            if (path == null || File(path).let { !it.exists() || it.length() == 0L }) {
                if (path != null) VaultVideoRecorder.secureDeleteFile(File(path))
                callback(false, null, 0, null, "no video was captured")
                createSessionLocked()
                return@runOnCameraThread
            }

            val thumbBytes = if (path != null) {
                try {
                    val retriever = MediaMetadataRetriever()
                    retriever.setDataSource(path)
                    val rotationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    val rotation = rotationStr?.toIntOrNull() ?: 0
                    var frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        ?: retriever.frameAtTime
                    retriever.release()
                    if (frame != null) {
                        // Apply video rotation hint to the extracted video frame
                        if (rotation != 0) {
                            val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
                            val rotated = Bitmap.createBitmap(frame, 0, 0, frame.width, frame.height, matrix, true)
                            if (rotated !== frame) {
                                frame.recycle()
                                frame = rotated
                            }
                        }
                        val thumb = ThumbnailUtils.extractThumbnail(frame, 160, 160)
                        val stream = ByteArrayOutputStream()
                        thumb.compress(Bitmap.CompressFormat.JPEG, 70, stream)
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
            createSessionLocked()
        }
    }

    private fun chooseVideoSizeByHeight(candidates: List<Size>, targetHeight: Int): Size {
        return candidates.filter { it.width > 0 && it.height > 0 }
            .minByOrNull { abs(minOf(it.width, it.height) - targetHeight) }
            ?: candidates.firstOrNull()
            ?: Size(1920, 1080)
    }

    /**
     * One distinct JPEG size per photo tier, largest first.
     *
     * Picking each tier's nearest size on its own lets two tiers land on the
     * same size (shown twice in the menu) while sizes in between are never
     * offered. Here each tier only considers sizes strictly smaller than the
     * tier above it, so the sizes always descend; a tier with nothing left to
     * pick is left out.
     */
    private fun photoTierSizes(
        jpegSizes: List<Size>,
        maxJpegSize: Size,
    ): Map<VaultPhotoResolution, Size> {
        fun area(s: Size) = s.width.toLong() * s.height.toLong()
        val valid = jpegSizes.filter { it.width > 0 && it.height > 0 }.distinct()
        val tiers = LinkedHashMap<VaultPhotoResolution, Size>()
        var ceiling = Long.MAX_VALUE
        for (res in VaultPhotoResolution.values().sortedByDescending { it.targetLongEdge }) {
            val pick = if (res == VaultPhotoResolution.MAX) {
                maxJpegSize
            } else {
                valid.filter { area(it) < ceiling }
                    .minByOrNull { abs(maxOf(it.width, it.height) - res.targetLongEdge) }
            } ?: continue
            tiers[res] = pick
            ceiling = area(pick)
        }
        return tiers
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
