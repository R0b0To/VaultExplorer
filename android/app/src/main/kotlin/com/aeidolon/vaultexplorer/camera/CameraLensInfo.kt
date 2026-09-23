package com.aeidolon.vaultexplorer.camera

import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.util.Size
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

/**
 * Returns at most two cameras: the device's main back camera and its main
 * front camera. Auxiliary sensors (ultra-wide/tele/macro/depth/IR/mono ids
 * that some OEMs expose as standalone camera ids) are deliberately ignored
 * -- they are what made session configuration fail on a long tail of
 * devices. Ultra-wide / tele reach on logical multi-cameras still works
 * through the zoom ratio of the main camera (see zoomMin/zoomMax).
 *
 * "Main" = the first usable camera of that facing in
 * CameraManager.cameraIdList order, which is the ordering CameraX also
 * relies on for its default back/front selectors.
 */
fun listCameraLenses(cameraManager: CameraManager): List<CameraLensInfo> {
    val out = mutableListOf<CameraLensInfo>()
    for (facing in listOf("back", "front")) {
        pickMainCamera(cameraManager, facing)?.let { out.add(it) }
    }
    return out
}

private fun pickMainCamera(cameraManager: CameraManager, facing: String): CameraLensInfo? {
    val wantedFacing = if (facing == "front") {
        CameraCharacteristics.LENS_FACING_FRONT
    } else {
        CameraCharacteristics.LENS_FACING_BACK
    }

    for (id in cameraManager.cameraIdList) {
        try {
            val c = cameraManager.getCameraCharacteristics(id)
            if (c.get(CameraCharacteristics.LENS_FACING) != wantedFacing) continue

            val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: IntArray(0)

            // Must support the standard Camera2 colour pipeline (skips depth-only,
            // monochrome and other special-purpose ids).
            if (!caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE)) continue
            if (caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MONOCHROME)) continue
            val colorFilter = c.get(CameraCharacteristics.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT)
            if (colorFilter == COLOR_FILTER_ARRANGEMENT_MONO || colorFilter == COLOR_FILTER_ARRANGEMENT_NIR) continue

            val map = c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: continue
            val jpegSizes = map.getOutputSizes(android.graphics.ImageFormat.JPEG) ?: emptyArray<Size>()
            val previewSizes = map.getOutputSizes(android.graphics.SurfaceTexture::class.java) ?: emptyArray<Size>()

            // Must have both JPEG and preview output capabilities
            if (jpegSizes.isEmpty() || previewSizes.isEmpty()) continue

            // Real cameras support at least a 640x480 preview; ghost calibration sensors often don't.
            val maxPreviewW = previewSizes.maxOfOrNull { it.width } ?: 0
            if (maxPreviewW < 640 && id != "0" && id != "1") continue

            var zoomMin = 1f
            var zoomMax = c.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
            if (Build.VERSION.SDK_INT >= 30) {
                c.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)?.let { range ->
                    zoomMin = range.lower
                    zoomMax = range.upper
                }
            }

            return CameraLensInfo(
                cameraId = id,
                facing = facing,
                isLogicalMultiCamera = caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA),
                zoomMin = zoomMin,
                zoomMax = zoomMax,
                sensorOrientationDegrees = c.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90,
                relativeZoom = 1f,
                lensType = if (facing == "front") "front" else "main",
                displayName = if (facing == "front") "Front" else "1x",
            )
        } catch (e: Exception) {
            VeLog.w("VaultCameraSession", e) { "skipping unreadable camera $id" }
        }
    }
    return null
}

// CameraMetadata.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_MONO / _NIR (API 29+),
// spelled as literals so this file compiles against any compileSdk.
private const val COLOR_FILTER_ARRANGEMENT_MONO = 5
private const val COLOR_FILTER_ARRANGEMENT_NIR = 6
