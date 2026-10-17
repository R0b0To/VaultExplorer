package com.aeidolon.vaultexplorer.camera

import android.hardware.camera2.CameraCharacteristics
import android.os.Build
import java.util.Locale

internal object CameraFlashQuirks {

    private val model: String get() = Build.MODEL.uppercase(Locale.US)

    // ImageCaptureFlashNotFireQuirk -- flash never fires with ON/AUTO.
    private val flashNeverFiresModels = setOf("ITEL W6004", "SM-J700M")
    private val flashNeverFiresFrontModels = setOf("SM-J700F", "SM-J710F")

    // ImageCaptureWashedOutImageQuirk -- Galaxy S7 / S7 edge back camera.
    private val washedOutModels = setOf(
        "SM-G9300", "SM-G930R", "SM-G930A", "SM-G930V", "SM-G930T", "SM-G930U", "SM-G930P",
        "SM-SC02H", "SM-SCV33",
        "SM-G9350", "SM-G935R", "SM-G935A", "SM-G935V", "SM-G935T", "SM-G935U", "SM-G935P",
    )

    // CameraNoResponseWhenEnablingFlashQuirk -- HAL hangs on flash ON/AUTO in the dark.
    private val hangsWithFlashModels = setOf(
        "SM-N9200", "SM-N9208", "SAMSUNG-SM-N920A", "SM-N920C", "SM-N920F", "SM-N920G",
        "SM-N920I", "SM-N920K", "SM-N920L", "SM-N920P", "SM-N920R4", "SM-N920R6",
        "SM-N920R7", "SM-N920S", "SM-N920T", "SM-N920V", "SM-N920W8", "SM-N920X",
        "SM-J510FN", "VIVO 1610",
    )

    // FlashTooSlowQuirk -- >1 s flash sequence -> blurred/dark/overexposed pictures.
    private val tooSlowModelPrefixes = listOf(
        "PIXEL 3A", "PIXEL 4", "PIXEL 5", "SM-A320", "MOTO G(20)", "ITEL L6006", "RMX3231",
    )

    // UltraWideFlashCaptureUnderexposureQuirk -- Galaxy S24, ultra-wide lens only.
    private val ultraWideUnderexposedPrefixes = listOf("SM-S921")

    // ImageCaptureFailWithAutoFlashQuirk (front camera) and
    // CrashWhenTakingPhotoWithAutoFlashAEModeQuirk (all cameras).
    private val autoFlashFailsFrontModels = setOf("SM-J700F", "SM-J710F", "SM-J700M")
    private val autoFlashCrashModels = setOf(
        "SM-A3000", "SM-A3009", "SM-A300F", "SM-A300FU", "SM-A300G", "SM-A300H", "SM-A300M",
        "SM-A300X", "SM-A300XU", "SM-A300XZ", "SM-A300Y", "SM-A300YZ", "SM-J510FN", "5059X",
    )

    /**
     * True when the still-capture flash sequence of this device is known to be
     * unreliable and the torch must be used as the flash instead.
     *
     * @param ultraWideActive whether the ultra-wide lens is the one currently
     *   producing the image (only relevant for the Galaxy S24 quirk).
     */
    fun shouldUseTorchAsFlash(c: CameraCharacteristics, ultraWideActive: Boolean): Boolean {
        val facing = c.get(CameraCharacteristics.LENS_FACING)
        val isBack = facing == CameraCharacteristics.LENS_FACING_BACK
        val isFront = facing == CameraCharacteristics.LENS_FACING_FRONT
        val m = model
        if (m in flashNeverFiresModels) return true
        if (isFront && m in flashNeverFiresFrontModels) return true
        if (isBack && m in washedOutModels) return true
        if (isBack && m in hangsWithFlashModels) return true
        if (isBack && tooSlowModelPrefixes.any { m.startsWith(it) }) return true
        if (isBack && ultraWideActive && ultraWideUnderexposedPrefixes.any { m.startsWith(it) }) return true
        return false
    }

    /**
     * CameraX only keeps the AE-precapture trigger on for the torch-as-flash
     * quirk it has verified it with (Galaxy S24 ultra-wide); every older quirk
     * just waits for AE to converge under the torch.
     */
    fun torchAsFlashAllowsAePrecapture(): Boolean =
        ultraWideUnderexposedPrefixes.any { model.startsWith(it) }

    fun shouldAvoidAutoFlashAeMode(c: CameraCharacteristics): Boolean {
        val m = model
        if (m in autoFlashCrashModels) return true
        val isFront = c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
        return isFront && m in autoFlashFailsFrontModels
    }
}
