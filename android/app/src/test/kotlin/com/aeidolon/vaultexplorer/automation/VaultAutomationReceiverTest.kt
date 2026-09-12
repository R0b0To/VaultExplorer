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
}
