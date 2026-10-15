package com.aeidolon.vaultexplorer.automation

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * VaultAutomationReceiver.outcomeForCameraError classifies a raw camera
 * error string (from the Dart-side camera plugin) into the automation
 * API's PERMISSION_DENIED/CAMERA_UNAVAILABLE/ERROR result codes -- getting
 * a case wrong here means an automation script gets misled about *why* a
 * TAKE_PHOTO/START_RECORDING action failed (e.g. told to retry a permission
 * problem, or told it's a hardware problem when the user just needs to grant
 * a permission once). This is the one piece of pure logic in an otherwise
 * heavily Context/CameraManager-dependent file (pickCameraId, listCameraLenses)
 * that's hard to reach from a host-JVM test -- see the tech-debt audit that
 * flagged this file's zero coverage.
 *
 * outcomeForAudioError is its audio-only counterpart and is covered the same
 * way below.
 *
 * outcomeForCameraError and the Outcome data class it returns are widened
 * from `private` to `internal` (visibility only, no logic touched) to make
 * this testable, same pattern as elsewhere in this pass.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class VaultAutomationReceiverTest {

    private val receiver = VaultAutomationReceiver()

    @Test
    fun `null error becomes a generic ERROR outcome`() {
        val outcome = receiver.outcomeForCameraError(null)

        assertEquals(VaultAutomationReceiver.Outcome("ERROR", "Unknown camera error"), outcome)
    }

    @Test
    fun `permission_denied becomes PERMISSION_DENIED with a specific message`() {
        val outcome = receiver.outcomeForCameraError("permission_denied")

        assertEquals("PERMISSION_DENIED", outcome.code)
        assertEquals(
            "Camera/microphone permission not granted -- grant it once from the app's own camera screen first",
            outcome.message,
        )
    }

    @Test
    fun `camera_unavailable prefix becomes CAMERA_UNAVAILABLE and echoes the original message`() {
        val outcome = receiver.outcomeForCameraError("camera_unavailable: lens busy")

        assertEquals("CAMERA_UNAVAILABLE", outcome.code)
        assertEquals("camera_unavailable: lens busy", outcome.message)
    }

    @Test
    fun `bare camera_unavailable with no suffix still matches the prefix check`() {
        val outcome = receiver.outcomeForCameraError("camera_unavailable")

        assertEquals("CAMERA_UNAVAILABLE", outcome.code)
    }

    @Test
    fun `camera disconnected becomes CAMERA_UNAVAILABLE`() {
        val outcome = receiver.outcomeForCameraError("camera disconnected")

        assertEquals("CAMERA_UNAVAILABLE", outcome.code)
        assertEquals("camera disconnected", outcome.message)
    }

    @Test
    fun `session configuration failed becomes CAMERA_UNAVAILABLE`() {
        val outcome = receiver.outcomeForCameraError("session configuration failed")

        assertEquals("CAMERA_UNAVAILABLE", outcome.code)
        assertEquals("session configuration failed", outcome.message)
    }

    @Test
    fun `an unrecognized error string falls through to a generic ERROR outcome, echoing the message`() {
        val outcome = receiver.outcomeForCameraError("some_new_error_code_this_app_has_never_seen")

        assertEquals("ERROR", outcome.code)
        assertEquals("some_new_error_code_this_app_has_never_seen", outcome.message)
    }

    // ── outcomeForAudioError (START_AUDIO_RECORDING / STOP_AUDIO_RECORDING) ──
    //
    // Same stakes as the camera cases above: a script branching on result_code
    // must not be told "microphone problem" for a storage failure, or be sent
    // to the camera screen to fix a missing microphone permission.

    @Test
    fun `audio null error becomes a generic ERROR outcome`() {
        val outcome = receiver.outcomeForAudioError(null)

        assertEquals(VaultAutomationReceiver.Outcome("ERROR", "Unknown audio recording error"), outcome)
    }

    @Test
    fun `audio permission_denied names the microphone, not the camera`() {
        val outcome = receiver.outcomeForAudioError("permission_denied")

        assertEquals("PERMISSION_DENIED", outcome.code)
        assertEquals(
            "Microphone permission not granted -- grant it once from the app's own audio recorder first",
            outcome.message,
        )
    }

    @Test
    fun `mic_unavailable prefix becomes MIC_UNAVAILABLE and echoes the original message`() {
        val outcome = receiver.outcomeForAudioError("mic_unavailable: start failed: -38")

        assertEquals("MIC_UNAVAILABLE", outcome.code)
        assertEquals("mic_unavailable: start failed: -38", outcome.message)
    }

    @Test
    fun `a camera error string is not classified as MIC_UNAVAILABLE`() {
        // Camera failures must never surface as a microphone problem.
        assertEquals("ERROR", receiver.outcomeForAudioError("camera_unavailable (4)").code)
    }

    @Test
    fun `audio recorder setup and vault write failures stay a plain ERROR`() {
        val setup = receiver.outcomeForAudioError("audio recorder setup failed: No space left on device")
        val write = receiver.outcomeForAudioError("vault write failed")

        assertEquals("ERROR", setup.code)
        assertEquals("ERROR", write.code)
        assertEquals("vault write failed", write.message)
    }

    @Test
    fun `the companion and instance audio classifiers agree`() {
        assertEquals(
            VaultAutomationReceiver.outcomeForAudioError("mic_unavailable"),
            receiver.outcomeForAudioError("mic_unavailable"),
        )
    }
}
