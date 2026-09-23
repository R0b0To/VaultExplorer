package com.aeidolon.vaultexplorer.automation

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.camera.VaultHeadlessCameraSession
import com.aeidolon.vaultexplorer.camera.VaultVideoQuality
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.service.VaultAutomationRecordingService
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Invisible trampoline Activity that satisfies Android 14+ (targetSDK 34+)
 * camera and microphone while-in-use restrictions for automation captures.
 *
 * Runs with [Theme.TransparentCapture], setShowWhenLocked(true), and no animations,
 * ensuring no visual disruption while bringing the process to the TOP / foreground
 * state.
 *
 * Can be launched:
 * 1. Indirectly via [VaultAutomationReceiver] (trampoline mode, finishes via [VaultAutomationActivityBridge]).
 * 2. Directly by an automation app like Tasker / MacroDroid (direct mode, replies via ACTION_AUTOMATION_RESULT).
 */
class VaultAutomationCaptureActivity : Activity() {

    companion object {
        private const val TAG = "VaultAutomationCaptureActivity"
        const val EXTRA_TRAMPOLINE = "com.aeidolon.vaultexplorer.extra.TRAMPOLINE"
        private const val SAFETY_TIMEOUT_MS = 15_000L
        private val activityExecutor = Executors.newSingleThreadExecutor()
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val started = AtomicBoolean(false)
    private var isTrampoline = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawableResource(android.R.color.transparent)
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        setContentView(R.layout.activity_automation_capture)
        window.setLayout(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT
        )
        window.setGravity(Gravity.CENTER)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
        isTrampoline = intent.getBooleanExtra(EXTRA_TRAMPOLINE, false)
        mainHandler.postDelayed({
            finishWithResult(false, "Capture activity timed out")
        }, SAFETY_TIMEOUT_MS)
    }

    override fun onResume() {
        super.onResume()
        if (started.compareAndSet(false, true)) {
            executeCapture()
        }
    }

    private fun executeCapture() {
        val action = intent.action
        val token = intent.getStringExtra(VaultAutomationReceiver.EXTRA_API_TOKEN)
        if (!AutomationSettings.isTokenValid(this, token)) {
            VeLog.w(TAG) { "Rejected $action: invalid or missing token" }
            finishSafely()
            return
        }

        val vaultUri = intent.getStringExtra(VaultAutomationReceiver.EXTRA_VAULT_URI)
        if (vaultUri.isNullOrEmpty()) {
            finishWithResult(false, "vault_uri is required")
            return
        }

        if (!AutomationSettings.canCapture(this, vaultUri)) {
            finishWithOutcome(VaultAutomationReceiver.Outcome("FORBIDDEN", "This vault is not opted in to automation camera capture"))
            return
        }

        val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
        if (volId == null) {
            finishWithOutcome(VaultAutomationReceiver.Outcome("NOT_MOUNTED", "Vault is not currently unlocked"))
            return
        }

        val facing = intent.getStringExtra(VaultAutomationReceiver.EXTRA_CAMERA_FACING) ?: "back"
        val cameraId = try {
            VaultAutomationReceiver.pickCameraId(this, facing)
        } catch (e: SecurityException) {
            finishWithOutcome(VaultAutomationReceiver.Outcome("CAMERA_UNAVAILABLE", "Camera disabled by system/device policy: ${e.message}"))
            return
        } ?: run {
            finishWithOutcome(VaultAutomationReceiver.Outcome("CAMERA_UNAVAILABLE", "No camera matches camera_facing=$facing"))
            return
        }

        when (action) {
            VaultAutomationReceiver.ACTION_TAKE_PHOTO -> handleTakePhoto(volId, cameraId)
            VaultAutomationReceiver.ACTION_START_RECORDING -> handleStartRecording(volId, cameraId, vaultUri)
            else -> finishWithOutcome(VaultAutomationReceiver.Outcome("INVALID_ARGS", "Unsupported capture action: $action"))
        }
    }

    private fun handleTakePhoto(volId: Int, cameraId: String) {
        val session = VaultHeadlessCameraSession(this)
        if (!session.hasPermissions()) {
            finishWithOutcome(
                VaultAutomationReceiver.Outcome(
                    "PERMISSION_DENIED",
                    "Camera/microphone permission not granted -- grant it once from the app's own camera screen first; automation can't prompt for it",
                )
            )
            return
        }

        val vaultPath = intent.getStringExtra(VaultAutomationReceiver.EXTRA_VAULT_PATH)?.takeIf { it.isNotEmpty() }
            ?: VaultAutomationReceiver.generateCaptureName(volId, isPhoto = true)

        try {
            session.capturePhotoAndClose(cameraId, volId, vaultPath) { ok, error ->
                val outcome = if (ok) {
                    VaultAutomationReceiver.Outcome("OK", "Photo saved to $vaultPath")
                } else {
                    VaultAutomationReceiver.outcomeForCameraError(error)
                }
                runOnUiThread { finishWithOutcome(outcome, vaultPath) }
            }
        } catch (e: SecurityException) {
            session.closeAll()
            finishWithOutcome(VaultAutomationReceiver.Outcome("CAMERA_UNAVAILABLE", "Camera access blocked by system policy: ${e.message}"))
        } catch (e: Exception) {
            session.closeAll()
            finishWithOutcome(VaultAutomationReceiver.Outcome("ERROR", "Photo capture setup error: ${e.message}"))
        }
    }

    private fun handleStartRecording(volId: Int, cameraId: String, vaultUri: String) {
        if (VaultAutomationRecordingService.isRecording) {
            finishWithOutcome(VaultAutomationReceiver.Outcome("BUSY", "An automation recording is already in progress"))
            return
        }

        val vaultPath = intent.getStringExtra(VaultAutomationReceiver.EXTRA_VAULT_PATH)?.takeIf { it.isNotEmpty() }
            ?: VaultAutomationReceiver.generateCaptureName(volId, isPhoto = false)
        val quality = when (intent.getStringExtra(VaultAutomationReceiver.EXTRA_VIDEO_QUALITY)?.lowercase(Locale.US)) {
            "hd" -> VaultVideoQuality.HD
            "uhd" -> VaultVideoQuality.UHD
            else -> VaultVideoQuality.FHD
        }
        val recordAudio = intent.getBooleanExtra(VaultAutomationReceiver.EXTRA_RECORD_AUDIO, true)
        val containerName = ContainerSessionRegistry.activeSessions[volId]?.displayName ?: vaultUri

        val latch = VaultAutomationCaptureBridge.arm()
        val serviceIntent = Intent(this, VaultAutomationRecordingService::class.java).apply {
            action = VaultAutomationRecordingService.ACTION_START
            putExtra(VaultAutomationRecordingService.EXTRA_VOL_ID, volId)
            putExtra(VaultAutomationRecordingService.EXTRA_VAULT_PATH, vaultPath)
            putExtra(VaultAutomationRecordingService.EXTRA_CAMERA_ID, cameraId)
            putExtra(VaultAutomationRecordingService.EXTRA_VIDEO_QUALITY, quality.name)
            putExtra(VaultAutomationRecordingService.EXTRA_RECORD_AUDIO, recordAudio)
            putExtra(VaultAutomationRecordingService.EXTRA_CONTAINER_NAME, containerName)
            putExtra("vaultUri", vaultUri)
        }

        try {
            ContextCompat.startForegroundService(this, serviceIntent)
        } catch (e: SecurityException) {
            finishWithOutcome(VaultAutomationReceiver.Outcome("CAMERA_UNAVAILABLE", "Recording service blocked by policy: ${e.message}"))
            return
        } catch (e: Exception) {
            finishWithOutcome(VaultAutomationReceiver.Outcome("ERROR", "Failed to start recording service: ${e.message}"))
            return
        }

        activityExecutor.execute {
            val result = VaultAutomationCaptureBridge.await(latch, 10_000L)
            val outcome = if (result == null) {
                VaultAutomationReceiver.Outcome("ERROR", "Timed out waiting for the camera to start")
            } else if (result.ok) {
                VaultAutomationReceiver.Outcome("OK", "Recording started: $vaultPath")
            } else {
                VaultAutomationReceiver.outcomeForCameraError(result.message)
            }
            runOnUiThread {
                finishWithOutcome(outcome, vaultPath)
            }
        }
    }

    private fun finishWithResult(ok: Boolean, message: String) {
        finishWithOutcome(VaultAutomationReceiver.Outcome(if (ok) "OK" else "ERROR", message))
    }

    private fun finishWithOutcome(outcome: VaultAutomationReceiver.Outcome, vaultPath: String? = null) {
        mainHandler.removeCallbacksAndMessages(null)
        if (isTrampoline) {
            VaultAutomationActivityBridge.complete(
                VaultAutomationActivityBridge.Result(
                    ok = outcome.code == "OK",
                    message = outcome.message,
                    vaultPath = vaultPath
                )
            )
        } else {
            val action = intent.action ?: VaultAutomationReceiver.ACTION_TAKE_PHOTO
            VaultAutomationReceiver.sendResult(this, action, outcome)
        }
        finishSafely()
    }

    private fun finishSafely() {
        mainHandler.removeCallbacksAndMessages(null)
        if (!isFinishing) {
            finishAndRemoveTask()
        }
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
