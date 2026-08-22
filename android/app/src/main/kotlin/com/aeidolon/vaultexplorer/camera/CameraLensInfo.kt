package com.aeidolon.vaultexplorer.camera

import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import kotlin.math.sqrt
import com.aeidolon.vaultexplorer.VeLog

/**
 * Static per-lens info read straight from [android.hardware.camera2.CameraCharacteristics]
 * -- no camera is ever opened to build this list, unlike the old
 * package:camera-based probe that had to briefly open each physical lens
 * to read its zoom range (the source of the concurrent-camera
 * configuration races seen in capture logs).
 */
data class CameraLensInfo(
    val cameraId: String,
    val facing: String,      // "back" | "front" | "external"
    val isLogicalMultiCamera: Boolean,
    val zoomMin: Float,
    val zoomMax: Float,
    val sensorOrientationDegrees: Int,
    // Approximate optical zoom factor of this lens relative to the primary/
    // wide lens for its facing (e.g. ~0.5 for an ultrawide, 1.0 for the
    // main/logical lens, ~2-5 for a telephoto). Physical (non-logical)
    // camera ids each report their own CONTROL_ZOOM_RATIO_RANGE starting at
    // 1.0, so using zoomMin directly (the old behavior) made every lens
    // show up as "1x" in the UI -- this is derived from focal length vs
    // sensor size instead, which is what actually differs between lenses.
    val relativeZoom: Float,
)

enum class VaultFlashMode { OFF, AUTO, ON, TORCH }

// The frame rate the video encoder is configured for (see
// VaultVideoRecorder.prepareEncoder). VaultCameraSession locks the sensor's
// CONTROL_AE_TARGET_FPS_RANGE to match this same constant -- if the two
// were to drift apart (someone changing one without the other), the sensor
// would deliver frames at a different real rate than the encoder budgets
// bits for, silently bloating the output bitrate again (see
// VaultCameraSession.pickFixedFpsRange's comment for the mechanism).
const val TARGET_RECORDING_FPS = 30

enum class VaultVideoQuality(val targetLongEdge: Int, val bitrateH264: Int, val bitrateHevc: Int) {
    HD(1280, 8_000_000, 5_000_000),
    FHD(1920, 16_000_000, 10_000_000),
    UHD(3840, 45_000_000, 25_000_000),
}

private data class RawLens(
    val id: String,
    val facing: String,
    val isLogical: Boolean,
    val zoomMin: Float,
    val zoomMax: Float,
    val sensorOrientation: Int,
    // focalLengthMm / sensorDiagonalMm -- proportional to the 35mm-equivalent
    // focal length, so the ratio between two lenses' focalDensity approximates
    // their real-world optical zoom ratio regardless of each sensor's physical size.
    val focalDensity: Float?,
)

/** Callable before any camera is opened -- pure CameraCharacteristics reads. */
fun listCameraLenses(cameraManager: CameraManager): List<CameraLensInfo> {
    val raw = mutableListOf<RawLens>()
    for (id in cameraManager.cameraIdList) {
        try {
            val c = cameraManager.getCameraCharacteristics(id)
            val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: IntArray(0)

            // Some phones list auxiliary sensors (depth/mono/IR helpers used
            // internally for portrait mode, face auth, etc.) directly in
            // cameraIdList even though they can't be opened as a standalone
            // preview/capture stream -- attempting to do so is what produced
            // "Unsupported set of inputs/outputs provided" / "session
            // configuration failed" when switching to them. Lenses without
            // BACKWARD_COMPATIBLE aren't usable as a normal camera, so skip them.
            if (!caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE)) {
                VeLog.d("VaultCameraSession") { "skipping non-standalone lens $id (no BACKWARD_COMPATIBLE)" }
                continue
            }

            val facing = when (c.get(CameraCharacteristics.LENS_FACING)) {
                CameraCharacteristics.LENS_FACING_FRONT -> "front"
                CameraCharacteristics.LENS_FACING_BACK -> "back"
                else -> "external"
            }
            val isLogical = caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA)
            var zoomMin = 1f
            var zoomMax = c.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
            if (Build.VERSION.SDK_INT >= 30) {
                c.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)?.let { range ->
                    zoomMin = range.lower
                    zoomMax = range.upper
                }
            }
            val sensorOrientation = c.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

            val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull()
            val physSize = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            val focalDensity = if (focal != null && physSize != null) {
                val diagonal = sqrt(physSize.width * physSize.width + physSize.height * physSize.height)
                if (diagonal > 0f) focal / diagonal else null
            } else null

            raw.add(RawLens(id, facing, isLogical, zoomMin, zoomMax, sensorOrientation, focalDensity))
        } catch (e: Exception) {
            VeLog.w("VaultCameraSession", e) { "skipping unreadable lens $id" }
        }
    }

    val out = mutableListOf<CameraLensInfo>()
    for ((_, lensesForFacing) in raw.groupBy { it.facing }) {
        // Reference lens for this facing's "1x": prefer the logical
        // multi-camera (the id the OS treats as the default/main sensor,
        // which is what non-multi-lens zoom already treats as 1x), else
        // fall back to the lens with the largest focal density, which in
        // practice is the primary wide sensor (ultrawide/tele sit either
        // side of it).
        val primary = lensesForFacing.firstOrNull { it.isLogical }
            ?: lensesForFacing.maxByOrNull { it.focalDensity ?: 0f }
            ?: lensesForFacing.first()
        val primaryDensity = primary.focalDensity

        for (l in lensesForFacing) {
            val relativeZoom = if (l.focalDensity != null && primaryDensity != null && primaryDensity > 0f) {
                l.focalDensity / primaryDensity
            } else {
                1f
            }
            out.add(CameraLensInfo(l.id, l.facing, l.isLogical, l.zoomMin, l.zoomMax, l.sensorOrientation, relativeZoom))
        }
    }
    return out
}