package com.aeidolon.vaultexplorer.camera

import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import com.aeidolon.vaultexplorer.VeLog
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

data class CameraLensInfo(
    val cameraId: String,
    val facing: String,
    val isLogicalMultiCamera: Boolean,
    val zoomMin: Float,
    val zoomMax: Float,
    val sensorOrientationDegrees: Int,
    val relativeZoom: Float,
    val lensType: String,    // "main" | "ultrawide" | "telephoto"
    val displayName: String, // "0.5x", "1x", "3x"
    val zoomRatio: Float = 1f,
    val hasFlash: Boolean = false,
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

private const val TAG = "VaultCameraLenses"

/** A lens whose field of view is narrower than this (relative to main) counts as telephoto. */
private const val TELE_MIN_RATIO = 1.35f

/** ...and wider than this (relative to main) as ultra-wide. */
private const val ULTRAWIDE_MAX_RATIO = 0.85f

fun CameraCharacteristics.hasFlashUnit(): Boolean =
    try {
        get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "FLASH_INFO_AVAILABLE unreadable, assuming no flash" }
        false
    }

fun listCameraLenses(cameraManager: CameraManager): List<CameraLensInfo> {
    val out = mutableListOf<CameraLensInfo>()
    for (facing in listOf("back", "front")) {
        pickMainCamera(cameraManager, facing)?.let { out.add(it) }
    }
    return out
}

fun listCameraLensStops(cameraManager: CameraManager): List<CameraLensInfo> {
    val ids = try {
        cameraManager.cameraIdList
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "cameraIdList unavailable" }
        return emptyList()
    }
    val physicalOfLogical = collectPhysicalIds(cameraManager, ids)
    val out = mutableListOf<CameraLensInfo>()
    for (facing in listOf("back", "front")) {
        val main = pickMainCamera(cameraManager, facing) ?: continue
        out.add(main)
        try {
            out.addAll(extraStops(cameraManager, ids, main, physicalOfLogical).sortedBy { it.relativeZoom })
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "extra lens stops for $facing skipped" }
        }
    }
    return out
}

fun intrinsicZoomRatioFor(cameraManager: CameraManager, cameraId: String): Float {
    return try {
        val c = cameraManager.getCameraCharacteristics(cameraId)
        val facing = when (c.get(CameraCharacteristics.LENS_FACING)) {
            CameraCharacteristics.LENS_FACING_FRONT -> "front"
            CameraCharacteristics.LENS_FACING_BACK -> "back"
            else -> return 1f
        }
        val main = pickMainCamera(cameraManager, facing) ?: return 1f
        if (main.cameraId == cameraId) 1f
        else intrinsicRatio(c, cameraManager.getCameraCharacteristics(main.cameraId)) ?: 1f
    } catch (e: Exception) {
        1f
    }
}

// ── Main camera selection ───────────────────────────────────────────────────

private fun pickMainCamera(cameraManager: CameraManager, facing: String): CameraLensInfo? {
    val wantedFacing = if (facing == "front") {
        CameraCharacteristics.LENS_FACING_FRONT
    } else {
        CameraCharacteristics.LENS_FACING_BACK
    }

    val ids = try {
        cameraManager.cameraIdList
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "cameraIdList unavailable" }
        return null
    }

    for (id in ids) {
        try {
            val c = cameraManager.getCameraCharacteristics(id)
            if (c.get(CameraCharacteristics.LENS_FACING) != wantedFacing) continue
            if (!isUsableCamera(id, c, isDefaultCandidate = true)) continue

            val (zoomMin, zoomMax) = zoomRange(c)
            return CameraLensInfo(
                cameraId = id,
                facing = facing,
                isLogicalMultiCamera = isLogicalMultiCamera(c),
                zoomMin = zoomMin,
                zoomMax = zoomMax,
                sensorOrientationDegrees = c.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90,
                relativeZoom = 1f,
                lensType = "main",
                displayName = "1x",
                zoomRatio = 1f.coerceIn(zoomMin, zoomMax),
                hasFlash = c.hasFlashUnit(),
            )
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "skipping unreadable camera $id" }
        }
    }
    return null
}

private fun isUsableCamera(id: String, c: CameraCharacteristics, isDefaultCandidate: Boolean): Boolean {
    val map = c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return false
    val jpegSizes = map.getOutputSizes(ImageFormat.JPEG)
    val previewSizes = map.getOutputSizes(SurfaceTexture::class.java)
    // Must have both JPEG and preview output capabilities.
    if (jpegSizes.isNullOrEmpty() || previewSizes.isNullOrEmpty()) return false

    val isPrimaryId = isDefaultCandidate && (id == "0" || id == "1")
    if (isPrimaryId) return true

    val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: IntArray(0)
    if (!caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE)) return false
    if (caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MONOCHROME)) return false
    val colorFilter = c.get(CameraCharacteristics.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT)
    if (colorFilter == COLOR_FILTER_ARRANGEMENT_MONO || colorFilter == COLOR_FILTER_ARRANGEMENT_NIR) return false

    // Real cameras support at least a 640x480 preview; ghost calibration sensors often don't.
    val maxPreviewW = previewSizes.maxOfOrNull { it.width } ?: 0
    return maxPreviewW >= 640
}

private fun isLogicalMultiCamera(c: CameraCharacteristics): Boolean {
    if (Build.VERSION.SDK_INT < 28) return false
    val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: return false
    return caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA) &&
        c.physicalCameraIds.isNotEmpty()
}

private fun zoomRange(c: CameraCharacteristics): Pair<Float, Float> {
    if (Build.VERSION.SDK_INT >= 30) {
        c.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)?.let { return it.lower to it.upper }
    }
    return 1f to (c.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f)
}

// ── Extra lens stops ────────────────────────────────────────────────────────

/** Every physical camera id that belongs to some logical multi-camera. */
private fun collectPhysicalIds(cameraManager: CameraManager, ids: Array<String>): Set<String> {
    if (Build.VERSION.SDK_INT < 28) return emptySet()
    val out = HashSet<String>()
    for (id in ids) {
        try {
            val c = cameraManager.getCameraCharacteristics(id)
            if (isLogicalMultiCamera(c)) out.addAll(c.physicalCameraIds)
        } catch (_: Exception) {
        }
    }
    return out
}

private fun extraStops(
    cameraManager: CameraManager,
    ids: Array<String>,
    main: CameraLensInfo,
    physicalOfLogical: Set<String>,
): List<CameraLensInfo> {
    val mainChars = cameraManager.getCameraCharacteristics(main.cameraId)
    val wantedFacing = mainChars.get(CameraCharacteristics.LENS_FACING)
    val stops = ArrayList<CameraLensInfo>()
    // The HAL only switches lenses by zoom ratio from API 30 on.
    val canSwitchByZoomRatio = Build.VERSION.SDK_INT >= 30

    var hasUltraWide = false
    var hasTele = false

    if (canSwitchByZoomRatio && main.zoomMin <= 0.95f) {
        stops.add(stopOf(main, main.cameraId, main.zoomMin, main.zoomMin, "ultrawide"))
        hasUltraWide = true
    }

    if (canSwitchByZoomRatio && main.isLogicalMultiCamera) {
        val teleRatios = ArrayList<Float>()
        for (pid in mainChars.physicalCameraIds) {
            val pc = try {
                cameraManager.getCameraCharacteristics(pid)
            } catch (_: Exception) {
                continue
            }
            val ratio = intrinsicRatio(pc, mainChars) ?: continue
            if (ratio > TELE_MIN_RATIO && ratio <= main.zoomMax + 0.01f &&
                teleRatios.none { abs(it - ratio) / it < 0.15f }
            ) {
                teleRatios.add(ratio)
            }
        }
        for (ratio in teleRatios) {
            // Never program less than the label says, or the HAL may stay on the main lens.
            val target = max(ratio, snapLensRatio(ratio)).coerceIn(main.zoomMin, main.zoomMax)
            stops.add(stopOf(main, main.cameraId, ratio, target, "telephoto"))
            hasTele = true
        }
    }

    // Standalone auxiliary cameras (devices without a usable logical camera).
    var bestUltraWide: Pair<String, Float>? = null
    var bestTele: Pair<String, Float>? = null
    var bestUltraWideArea = 0L
    var bestTeleArea = 0L
    for (id in ids) {
        if (id == main.cameraId || id in physicalOfLogical) continue
        try {
            val c = cameraManager.getCameraCharacteristics(id)
            if (c.get(CameraCharacteristics.LENS_FACING) != wantedFacing) continue
            if (!isUsableCamera(id, c, isDefaultCandidate = false)) continue
            if (isLogicalMultiCamera(c)) continue
            val ratio = intrinsicRatio(c, mainChars) ?: continue
            val minFocus = c.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE)
            val fixedFocus = minFocus == null || minFocus == 0f
            val pixels = c.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
            val area = if (pixels != null) pixels.width.toLong() * pixels.height.toLong() else 0L

            if (ratio < ULTRAWIDE_MAX_RATIO && !hasUltraWide) {
                // Ultra-wides are frequently fixed focus; that is fine for them.
                if (area >= bestUltraWideArea) { bestUltraWide = id to ratio; bestUltraWideArea = area }
            } else if (ratio > TELE_MIN_RATIO && !hasTele && !fixedFocus) {
                // Fixed-focus "tele" candidates are macro/depth sensors, not zoom lenses.
                if (area >= bestTeleArea) { bestTele = id to ratio; bestTeleArea = area }
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "skipping auxiliary camera $id" }
        }
    }
    bestUltraWide?.let { (id, ratio) -> stops.add(auxStop(cameraManager, main, id, ratio, "ultrawide")) }
    bestTele?.let { (id, ratio) -> stops.add(auxStop(cameraManager, main, id, ratio, "telephoto")) }
    return stops
}

private fun stopOf(
    main: CameraLensInfo,
    cameraId: String,
    relativeZoom: Float,
    zoomRatio: Float,
    type: String,
) = CameraLensInfo(
    cameraId = cameraId,
    facing = main.facing,
    isLogicalMultiCamera = main.isLogicalMultiCamera,
    zoomMin = main.zoomMin,
    zoomMax = main.zoomMax,
    sensorOrientationDegrees = main.sensorOrientationDegrees,
    relativeZoom = relativeZoom,
    lensType = type,
    displayName = formatLensZoom(relativeZoom),
    zoomRatio = zoomRatio,
    hasFlash = main.hasFlash,
)

private fun auxStop(
    cameraManager: CameraManager,
    main: CameraLensInfo,
    id: String,
    ratio: Float,
    type: String,
): CameraLensInfo {
    val c = cameraManager.getCameraCharacteristics(id)
    val (zMin, zMax) = zoomRange(c)
    return CameraLensInfo(
        cameraId = id,
        facing = main.facing,
        isLogicalMultiCamera = false,
        zoomMin = zMin,
        zoomMax = zMax,
        sensorOrientationDegrees = c.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: main.sensorOrientationDegrees,
        relativeZoom = ratio,
        lensType = type,
        displayName = formatLensZoom(ratio),
        // An auxiliary camera is selected by opening it, at its own 1x.
        zoomRatio = 1f.coerceIn(zMin, zMax),
        hasFlash = c.hasFlashUnit(),
    )
}

// ── Intrinsic zoom ratio (port of CameraX IntrinsicZoomCalculator) ─────────

/** tan(horizontal field of view / 2) of [c] at its default focal length, or null. */
private fun halfFovTangent(c: CameraCharacteristics): Double? {
    val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull() ?: return null
    val physical = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE) ?: return null
    val active = c.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE) ?: return null
    val pixelArray = c.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE) ?: return null
    if (focal <= 0f || physical.width <= 0f || pixelArray.width <= 0) return null
    // Sensor width actually used for the image (the active area of the pixel array).
    val widthMm = physical.width.toDouble() * active.width().toDouble() / pixelArray.width.toDouble()
    if (widthMm <= 0.0) return null
    return widthMm / (2.0 * focal)
}

private fun intrinsicRatio(c: CameraCharacteristics, reference: CameraCharacteristics): Float? {
    val own = halfFovTangent(c) ?: return null
    val ref = halfFovTangent(reference) ?: return null
    val ratio = (ref / own).toFloat()
    if (ratio.isNaN() || ratio.isInfinite() || ratio <= 0f) return null
    return (ratio * 100f).roundToInt() / 100f
}

/** Nominal marketing value of a lens factor: 0.5, 1, 2, 3, 5... */
private fun snapLensRatio(ratio: Float): Float {
    val nearestHalf = (ratio * 2f).roundToInt() / 2f
    return if (abs(nearestHalf - ratio) <= 0.15f) nearestHalf else (ratio * 10f).roundToInt() / 10f
}

internal fun formatLensZoom(ratio: Float): String {
    val snapped = snapLensRatio(ratio)
    return if (abs(snapped - snapped.roundToInt()) < 0.01f) {
        "${snapped.roundToInt()}x"
    } else {
        String.format(Locale.US, "%.1fx", snapped)
    }
}

// CameraMetadata.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT_MONO / _NIR (API 29+),
// spelled as literals so this file compiles against any compileSdk.
private const val COLOR_FILTER_ARRANGEMENT_MONO = 5
private const val COLOR_FILTER_ARRANGEMENT_NIR = 6
