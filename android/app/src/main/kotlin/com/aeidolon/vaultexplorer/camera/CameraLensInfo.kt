package com.aeidolon.vaultexplorer.camera

import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaRecorder
import android.os.Build
import android.util.Size
import kotlin.math.sqrt
import com.aeidolon.vaultexplorer.VeLog

data class CameraLensInfo(
    val cameraId: String,
    val facing: String,
    val isLogicalMultiCamera: Boolean,
    val zoomMin: Float,
    val zoomMax: Float,
    val sensorOrientationDegrees: Int,
    val relativeZoom: Float,
    val lensType: String,    // "main" | "wide" | "infrared" | "telephoto" | "front"
    val displayName: String, // "1x", "Wide", "IR", "Front"
)

enum class VaultFlashMode { OFF, AUTO, ON, TORCH }

const val TARGET_RECORDING_FPS = 30

/** Explicit user-selected photo resolution */
enum class VaultPhotoResolution(val targetLongEdge: Int, val label: String) {
    LOW(1280, "1.2 MP (Low)"),
    MEDIUM(1920, "2 MP (Med)"),
    HIGH(2560, "5 MP (High)"),
    MAX(4500, "Full (Max)");
}

/** Explicit user-selected video resolution */
enum class VaultVideoQuality(
    val targetVideoHeight: Int,
    val bitrateH264: Int,
    val bitrateHevc: Int,
    val label: String
) {
    SD(480, 3_000_000, 1_800_000, "480p (SD)"),
    HD(720, 8_000_000, 5_000_000, "720p (HD)"),
    FHD(1080, 16_000_000, 10_000_000, "1080p (FHD)"),
    UHD(2160, 45_000_000, 25_000_000, "4K (UHD)");

    val targetVideoLongEdge: Int get() = when (this) {
        SD -> 720
        HD -> 1280
        FHD -> 1920
        UHD -> 3840
    }
    val targetLongEdge: Int get() = targetVideoLongEdge
}

private data class RawLens(
    val id: String,
    val facing: String,
    val isLogical: Boolean,
    val zoomMin: Float,
    val zoomMax: Float,
    val sensorOrientation: Int,
    val focalDensity: Float?,
    val isMonochromeOrInfrared: Boolean,
)

// In-memory blacklist for cameras that fail to configure on this device
val blacklistedCameraIds = mutableSetOf<String>()

fun listCameraLenses(cameraManager: CameraManager): List<CameraLensInfo> {
    val raw = mutableListOf<RawLens>()

    for (id in cameraManager.cameraIdList) {
        if (blacklistedCameraIds.contains(id)) {
            VeLog.d("VaultCameraSession") { "skipping blacklisted faulty lens $id" }
            continue
        }

        try {
            val c = cameraManager.getCameraCharacteristics(id)
            val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: IntArray(0)

            // Must support standard Camera2 pipeline
            if (!caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE)) {
                continue
            }

            val map = c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: continue
            val jpegSizes = map.getOutputSizes(android.graphics.ImageFormat.JPEG) ?: emptyArray<Size>()
            val previewSizes = map.getOutputSizes(android.graphics.SurfaceTexture::class.java) ?: emptyArray<Size>()

            // Must have both JPEG and preview output capabilities
            if (jpegSizes.isEmpty() || previewSizes.isEmpty()) {
                continue
            }

            // Real cameras must support at least 640x480 preview. Ghost calibration sensors often don't.
            val maxPreviewW = previewSizes.maxOfOrNull { it.width } ?: 0
            if (maxPreviewW < 640 && id != "0" && id != "1") {
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

            // Detect Infrared / Night Vision sensors
            val colorFilter = c.get(CameraCharacteristics.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT)
            val isMonoOrIr = caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MONOCHROME)
                || colorFilter == 4 // SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_MONO
                || colorFilter == 5 // SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_NIR

            raw.add(RawLens(id, facing, isLogical, zoomMin, zoomMax, sensorOrientation, focalDensity, isMonoOrIr))
        } catch (e: Exception) {
            VeLog.w("VaultCameraSession", e) { "skipping unreadable lens $id" }
        }
    }

    val out = mutableListOf<CameraLensInfo>()
    for ((facing, lensesForFacing) in raw.groupBy { it.facing }) {
        val primary = lensesForFacing.firstOrNull { it.id == "0" || it.id == "1" }
            ?: lensesForFacing.firstOrNull { it.isLogical }
            ?: lensesForFacing.first()
        val primaryDensity = primary.focalDensity

        for (l in lensesForFacing) {
            val relativeZoom = if (l.focalDensity != null && primaryDensity != null && primaryDensity > 0f) {
                l.focalDensity / primaryDensity
            } else {
                1f
            }

            val (lensType, displayName) = when {
                facing == "front" -> "front" to "Front"
                l.isMonochromeOrInfrared -> "infrared" to "IR"
                l.id == "0" -> "main" to "1x"
                relativeZoom < 0.85f -> "wide" to "Wide"
                relativeZoom > 1.8f -> "telephoto" to "${relativeZoom.roundToOneDecimal()}x"
                else -> "auxiliary" to "Lens ${l.id}"
            }

            out.add(CameraLensInfo(
                l.id,
                l.facing,
                l.isLogical,
                l.zoomMin,
                l.zoomMax,
                l.sensorOrientation,
                relativeZoom,
                lensType,
                displayName
            ))
        }
    }
    return out
}

private fun Float.roundToOneDecimal(): Float = (this * 10).toInt() / 10f