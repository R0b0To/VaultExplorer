package com.aeidolon.vaultexplorer.camera

import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build

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
)

enum class VaultFlashMode { OFF, AUTO, ON, TORCH }

enum class VaultVideoQuality(val targetLongEdge: Int, val bitrate: Int) {
    HD(1280, 8_000_000),
    FHD(1920, 16_000_000),
    UHD(3840, 45_000_000),
}

/** Callable before any camera is opened -- pure CameraCharacteristics reads. */
fun listCameraLenses(cameraManager: CameraManager): List<CameraLensInfo> {
    val out = mutableListOf<CameraLensInfo>()
    for (id in cameraManager.cameraIdList) {
        try {
            val c = cameraManager.getCameraCharacteristics(id)
            val facing = when (c.get(CameraCharacteristics.LENS_FACING)) {
                CameraCharacteristics.LENS_FACING_FRONT -> "front"
                CameraCharacteristics.LENS_FACING_BACK -> "back"
                else -> "external"
            }
            val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: IntArray(0)
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
            out.add(CameraLensInfo(id, facing, isLogical, zoomMin, zoomMax, sensorOrientation))
        } catch (e: Exception) {
            android.util.Log.w("VaultCameraSession", "skipping unreadable lens $id", e)
        }
    }
    return out
}
