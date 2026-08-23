package com.aeidolon.vaultexplorer.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.UriNameResolver
import com.aeidolon.vaultexplorer.bridge.VaultAutomationUnlockedBridge
import com.aeidolon.vaultexplorer.camera.VaultHeadlessCameraSession
import com.aeidolon.vaultexplorer.camera.VaultVideoQuality
import com.aeidolon.vaultexplorer.camera.listCameraLenses
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerLifecycleCore
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.service.VaultAutomationRecordingService
import com.aeidolon.vaultexplorer.service.VaultKeepAliveService
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import com.aeidolon.vaultexplorer.VeLog

/**
 * Headless entry point for any automation app to unlock, lock, import into,
 * export out of, and (with an extra opt-in) photograph/record into a vault
 * without opening the app UI. Every action needs the per-install API token
 * (AutomationSettings) AND the specific vault opted in to the tier that
 * action needs (AutomationSettings.AutomationTier) -- both are checked
 * before any vault state is touched, and a bad/missing token gets no reply
 * at all (see handleAction) so a probing app can't even learn the feature
 * is configured.
 *
 * UNLOCK_VAULT/LOCK_VAULT need only the LIFECYCLE tier. IMPORT_FILE/
 * EXPORT_FILE/IMPORT_FOLDER/EXPORT_FOLDER need FULL, since they read/write
 * arbitrary filesystem paths -- a materially bigger trust decision than
 * lifecycle control alone, hence two separate opt-in switches rather than
 * one. TAKE_PHOTO/START_RECORDING/STOP_RECORDING need FULL *and* the
 * separate AutomationSettings.canCapture opt-in -- see that function's doc
 * comment for why silent camera/mic capture gets its own switch on top of
 * FULL rather than riding along with file import/export.
 *
 * No hidden-volume support and no keyfile support here, by design -- see
 * ContainerLifecycleCore.unlockContainer's doc comment. UNLOCK_VAULT
 * covers all four unlock paths -- standard block-device containers plus
 * Cryptomator/gocryptfs/CryFS -- dispatched on AutomationSettings.getFormat
 * for the given vault (see handleUnlock). USB-attached containers are not
 * covered by any action here yet.
 *
 * IMPORT_FILE/EXPORT_FILE/IMPORT_FOLDER/EXPORT_FOLDER accept either a plain
 * filesystem path (this app already holds MANAGE_EXTERNAL_STORAGE) or a
 * `content://` SAF Uri -- see VaultAutomationFolderOps's doc comment for
 * the real limitation on the latter: it only works for a Uri this app
 * already holds a persisted grant for, since Android doesn't let a sending
 * app confer that grant onto an arbitrary broadcast extra string the way
 * it can for an Intent's own `data`.
 *
 * Every action replies on ACTION_AUTOMATION_RESULT with RESULT_CODE /
 * RESULT_MESSAGE so an automation profile listening for that broadcast (an
 * ordinary "Intent Received" event, not a special reply mechanism) can
 * branch a task chain on success/failure instead of assuming success.
 * RESULT_MESSAGE additionally carries EXTRA_DURATION_MS for a successful
 * STOP_RECORDING.
 */
class VaultAutomationReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "VaultExplorer_Automation"

        const val ACTION_UNLOCK_VAULT = "com.aeidolon.vaultexplorer.action.UNLOCK_VAULT"
        const val ACTION_LOCK_VAULT = "com.aeidolon.vaultexplorer.action.LOCK_VAULT"
        const val ACTION_IMPORT_FILE = "com.aeidolon.vaultexplorer.action.IMPORT_FILE"
        const val ACTION_EXPORT_FILE = "com.aeidolon.vaultexplorer.action.EXPORT_FILE"
        const val ACTION_IMPORT_FOLDER = "com.aeidolon.vaultexplorer.action.IMPORT_FOLDER"
        const val ACTION_EXPORT_FOLDER = "com.aeidolon.vaultexplorer.action.EXPORT_FOLDER"
        const val ACTION_TAKE_PHOTO = "com.aeidolon.vaultexplorer.action.TAKE_PHOTO"
        const val ACTION_START_RECORDING = "com.aeidolon.vaultexplorer.action.START_RECORDING"
        const val ACTION_STOP_RECORDING = "com.aeidolon.vaultexplorer.action.STOP_RECORDING"
        const val ACTION_WIPE_FILE = "com.aeidolon.vaultexplorer.action.WIPE_FILE"
        const val ACTION_AUTOMATION_RESULT = "com.aeidolon.vaultexplorer.action.AUTOMATION_RESULT"

        const val EXTRA_API_TOKEN = "api_token"
        const val EXTRA_VAULT_URI = "vault_uri"
        const val EXTRA_PASSWORD = "password"            // optional; falls back to the stored automation password
        const val EXTRA_READ_ONLY = "read_only"
        const val EXTRA_SOURCE_PATH = "source_path"       // IMPORT_FILE/IMPORT_FOLDER/WIPE_FILE: real path or content:// Uri
        const val EXTRA_DEST_PATH = "dest_path"           // EXPORT_FILE/EXPORT_FOLDER: real path or content:// Uri to write to
        const val EXTRA_VAULT_PATH = "vault_path"         // path *inside* the vault; optional for TAKE_PHOTO/START_RECORDING
        const val EXTRA_DELETE_SOURCE = "delete_source"   // IMPORT_FILE/IMPORT_FOLDER: wipe/delete source after import

        // TAKE_PHOTO / START_RECORDING
        const val EXTRA_CAMERA_FACING = "camera_facing"   // optional: "back" (default) | "front"
        const val EXTRA_VIDEO_QUALITY = "video_quality"   // START_RECORDING only, optional: "hd" | "fhd" (default) | "uhd"
        const val EXTRA_RECORD_AUDIO = "record_audio"     // START_RECORDING only, optional, default true

        const val EXTRA_ORIGINAL_ACTION = "original_action"
        const val RESULT_CODE = "result_code"       // see the full list in this class's own doc comment below
        const val RESULT_MESSAGE = "result_message"
        const val EXTRA_DURATION_MS = "duration_ms" // STOP_RECORDING only, present when RESULT_CODE is OK

        // Result codes across every action in this receiver:
        //   OK | AUTH_FAIL | NOT_MOUNTED | FORBIDDEN | INVALID_ARGS | ERROR
        //   PARTIAL           -- IMPORT_FOLDER/EXPORT_FOLDER: some files failed, see RESULT_MESSAGE
        //   PERMISSION_DENIED -- TAKE_PHOTO/START_RECORDING: camera/mic permission not granted; automation
        //                        can't request it, grant it once from the app's own camera screen first
        //   CAMERA_UNAVAILABLE-- TAKE_PHOTO/START_RECORDING: camera busy (e.g. the in-app camera screen has
        //                        it open) or a hardware/driver error opening it
        //   BUSY              -- START_RECORDING: an automation recording is already in progress
        //   NOT_RECORDING     -- STOP_RECORDING: nothing is currently recording (or it's for a different vault)

        // Automation actions must run in the order automation fires them --
        // unlock, then import, then lock is a common chain -- and this
        // receiver has no Activity to hand work off to the way
        // MainActivity's handlers use its ioExecutor, so it gets its own
        // strictly-serial executor rather than a shared/parallel pool.
        private val automationExecutor = Executors.newSingleThreadExecutor()
        private val fuseThread = HandlerThread("automation-split-fuse").apply { start() }
        private val fuseHandler = Handler(fuseThread.looper)

        private const val PHOTO_TIMEOUT_MS = 8_000L
        private const val START_RECORDING_TIMEOUT_MS = 10_000L
        // Generous on purpose: this is how long the receiver waits before
        // giving up and reporting ERROR, not a cap on the save itself -- a
        // very long recording's finalize can still outlive it, in which case
        // the service keeps writing in the background regardless and the
        // file lands in the vault either way; only the result broadcast
        // would be a false-negative ERROR/timeout in that case, not the data.
        private const val STOP_RECORDING_TIMEOUT_MS = 60_000L
    }

    private data class Outcome(val code: String, val message: String, val durationMs: Long? = null)

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val knownActions = setOf(
            ACTION_UNLOCK_VAULT, ACTION_LOCK_VAULT,
            ACTION_IMPORT_FILE, ACTION_EXPORT_FILE,
            ACTION_IMPORT_FOLDER, ACTION_EXPORT_FOLDER,
            ACTION_TAKE_PHOTO, ACTION_START_RECORDING, ACTION_STOP_RECORDING,
            ACTION_WIPE_FILE,
        )
        if (action !in knownActions) {
            return
        }
        val appContext = context.applicationContext
        val pending = goAsync()
        automationExecutor.execute {
            try {
                handleAction(appContext, action, intent)
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "Unhandled automation error for $action" }
            } finally {
                pending.finish()
            }
        }
    }

    private fun handleAction(context: Context, action: String, intent: Intent) {
        val token = intent.getStringExtra(EXTRA_API_TOKEN)
        if (!AutomationSettings.isTokenValid(context, token)) {
            VeLog.w(TAG) { "Rejected $action: invalid or missing token" }
            return // No reply broadcast on a bad token -- don't confirm to an
                   // unauthenticated caller that automation is even configured.
        }
        val vaultUri = intent.getStringExtra(EXTRA_VAULT_URI)
        val outcome = if (vaultUri.isNullOrEmpty() && action != ACTION_WIPE_FILE) {
            Outcome("INVALID_ARGS", "vault_uri is required")
        } else when (action) {
            ACTION_UNLOCK_VAULT -> handleUnlock(context, vaultUri!!, intent)
            ACTION_LOCK_VAULT -> handleLock(context, vaultUri!!)
            ACTION_IMPORT_FILE -> handleImport(context, vaultUri!!, intent)
            ACTION_EXPORT_FILE -> handleExport(context, vaultUri!!, intent)
            ACTION_IMPORT_FOLDER -> handleImportFolder(context, vaultUri!!, intent)
            ACTION_EXPORT_FOLDER -> handleExportFolder(context, vaultUri!!, intent)
            ACTION_TAKE_PHOTO -> handleTakePhoto(context, vaultUri!!, intent)
            ACTION_START_RECORDING -> handleStartRecording(context, vaultUri!!, intent)
            ACTION_STOP_RECORDING -> handleStopRecording(context, vaultUri!!)
            else -> handleWipe(context, intent) // ACTION_WIPE_FILE; doesn't need vaultUri, see handleWipe
        }
        sendResult(context, action, outcome)
    }

    private fun sendResult(context: Context, action: String, outcome: Outcome) {
        VeLog.i(TAG) { "$action -> ${outcome.code}: ${outcome.message}" }
        context.sendBroadcast(
            Intent(ACTION_AUTOMATION_RESULT).apply {
                putExtra(EXTRA_ORIGINAL_ACTION, action)
                putExtra(RESULT_CODE, outcome.code)
                putExtra(RESULT_MESSAGE, outcome.message)
                outcome.durationMs?.let { putExtra(EXTRA_DURATION_MS, it) }
            }
        )
    }

    private fun startKeepAlive(context: Context) {
        ContextCompat.startForegroundService(context, Intent(context, VaultKeepAliveService::class.java))
    }

    /**
     * Notifies VaultAutomationUnlockedBridge (and, through it, the dashboard
     * if a Flutter engine is attached) that [volId] is unlocked, reading
     * everything it needs back off the just-committed ContainerSession
     * rather than threading result-specific fields through each of the
     * three call sites below -- unlockContainer, unlockDirectoryVault, and
     * the already-mounted short-circuit all commit a session before this
     * can run, so it's a single source of truth for all three.
     *
     * displayName falls back to UriNameResolver -- the same resolver
     * unlockContainer itself uses -- because ContainerSession.displayName
     * is null whenever automation unlocks a non-split container with no
     * override (there's no Dart-side picker here to already know the name
     * the way the normal unlock flow does).
     *
     * containerFormat reads straight off ContainerSession.containerFormat,
     * which ContainerLifecycleCore now sets at unlock time for every path
     * (block-device via ContainerEngine.format, directory vaults via
     * DirectoryVaultFormat.asContainerFormat) -- no need to re-derive it
     * from AutomationSettings or re-query the native engine here.
     */
    private fun reportAutomationUnlock(context: Context, volId: Int) {
        val session = ContainerSessionRegistry.activeSessions[volId] ?: return
        val displayName = session.displayName ?: runCatching {
            UriNameResolver.resolve(context.contentResolver, Uri.parse(session.uri))
        }.getOrDefault(session.uri)
        VaultAutomationUnlockedBridge.reportUnlocked(
            volId = volId,
            uri = session.uri,
            displayName = displayName,
            containerFormat = session.containerFormat?.wireName ?: "unknown",
            readOnly = session.readOnly,
            files = session.cachedFilesList,
        )
    }

    private fun handleUnlock(context: Context, vaultUri: String, intent: Intent): Outcome {
        if (!AutomationSettings.canUnlockLock(context, vaultUri)) {
            return Outcome("FORBIDDEN", "This vault is not opted in to automation")
        }
        val existingVolId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
        if (existingVolId != null) {
            startKeepAlive(context)
            reportAutomationUnlock(context, existingVolId)
            return Outcome("OK", "Already unlocked")
        }
        val password = intent.getStringExtra(EXTRA_PASSWORD)
            ?: AutomationSettings.getStoredPassword(context, vaultUri)
        if (password.isNullOrEmpty()) {
            return Outcome("INVALID_ARGS", "No password supplied and none stored for this vault")
        }
        val targetVolId = ContainerSessionRegistry.getFreeVolumeId()
            ?: return Outcome("ERROR", "No free volume slots (${ContainerSessionRegistry.MAX_VOLUMES} already mounted)")
        val readOnly = intent.getBooleanExtra(EXTRA_READ_ONLY, false)

        // AutomationSettings.getFormat is set when a vault opts in to
        // automation (null = standard block-device container); that's what
        // picks the unlock path here, rather than inspecting the URI/file
        // itself -- the app already knows each configured vault's format
        // from when it was added, so re-detecting it at unlock time would
        // just be a second, less trustworthy source of truth.
        val directoryFormat = AutomationSettings.getFormat(context, vaultUri)
        if (directoryFormat != null) {
            val result = ContainerLifecycleCore.unlockDirectoryVault(
                context = context,
                format = directoryFormat,
                uriString = vaultUri,
                targetVolId = targetVolId,
                password = password,
                readOnly = readOnly,
            )
            return when (result) {
                is ContainerLifecycleCore.DirectoryVaultOutcome.Success -> {
                    startKeepAlive(context)
                    reportAutomationUnlock(context, result.result.volId)
                    Outcome("OK", "Unlocked")
                }
                is ContainerLifecycleCore.DirectoryVaultOutcome.AuthFailure -> Outcome("AUTH_FAIL", result.message)
                is ContainerLifecycleCore.DirectoryVaultOutcome.InvalidVault -> Outcome("ERROR", result.reason)
                is ContainerLifecycleCore.DirectoryVaultOutcome.Error ->
                    Outcome("ERROR", result.exception.message ?: "Unknown error")
            }
        }

        val result = ContainerLifecycleCore.unlockContainer(
            context = context,
            uriString = vaultUri,
            targetVolId = targetVolId,
            password = password,
            pim = 0,
            readOnly = readOnly,
            fuseHandler = fuseHandler,
        )
        return when (result) {
            is ContainerLifecycleCore.UnlockCoreOutcome.Success -> {
                startKeepAlive(context)
                reportAutomationUnlock(context, result.result.volId)
                Outcome("OK", "Unlocked")
            }
            is ContainerLifecycleCore.UnlockCoreOutcome.AuthFailure -> Outcome("AUTH_FAIL", result.message)
            is ContainerLifecycleCore.UnlockCoreOutcome.Error ->
                Outcome("ERROR", result.exception.message ?: "Unknown error")
        }
    }

    private fun handleLock(context: Context, vaultUri: String): Outcome {
        if (!AutomationSettings.canUnlockLock(context, vaultUri)) {
            return Outcome("FORBIDDEN", "This vault is not opted in to automation")
        }
        val wasMounted = ContainerSessionRegistry.getVolumeIdByUri(vaultUri) != null
        val locked = ContainerLifecycleCore.lockContainer(context, vaultUri)
        if (!ContainerSessionRegistry.hasAnyActiveSessions()) {
            context.stopService(Intent(context, VaultKeepAliveService::class.java))
        }
        return when {
            locked -> Outcome("OK", "Locked")
            !wasMounted -> Outcome("OK", "Already locked")
            else -> Outcome("ERROR", "Lock failed")
        }
    }

    private fun handleImport(context: Context, vaultUri: String, intent: Intent): Outcome {
        if (!AutomationSettings.canImportExport(context, vaultUri)) {
            return Outcome("FORBIDDEN", "This vault is not opted in to automation file import/export")
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
            ?: return Outcome("NOT_MOUNTED", "Vault is not currently unlocked")
        val sourcePath = intent.getStringExtra(EXTRA_SOURCE_PATH)
        val vaultPath = intent.getStringExtra(EXTRA_VAULT_PATH)
        if (sourcePath.isNullOrEmpty() || vaultPath.isNullOrEmpty()) {
            return Outcome("INVALID_ARGS", "source_path and vault_path are required")
        }
        // VaultAutomationFolderOps.importOneFile accepts source_path as either
        // a raw filesystem path or a content:// Uri -- see its own and this
        // class's doc comments for the SAF-permission caveat on the latter.
        if (!VaultAutomationFolderOps.importOneFile(context, volId, sourcePath, vaultPath)) {
            return Outcome("ERROR", "Import failed")
        }
        if (intent.getBooleanExtra(EXTRA_DELETE_SOURCE, false)) {
            val deleted = if (sourcePath.startsWith("content://")) {
                try { DocumentFile.fromSingleUri(context, Uri.parse(sourcePath))?.delete() ?: false }
                catch (e: Exception) { false }
            } else {
                SecureFileWipe.secureDeleteFile(File(sourcePath))
            }
            if (!deleted) {
                return Outcome("OK", "Imported, but deleting/wiping the source afterward failed")
            }
        }
        return Outcome("OK", "Imported")
    }

    private fun handleExport(context: Context, vaultUri: String, intent: Intent): Outcome {
        if (!AutomationSettings.canImportExport(context, vaultUri)) {
            return Outcome("FORBIDDEN", "This vault is not opted in to automation file import/export")
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
            ?: return Outcome("NOT_MOUNTED", "Vault is not currently unlocked")
        val vaultPath = intent.getStringExtra(EXTRA_VAULT_PATH)
        val destPath = intent.getStringExtra(EXTRA_DEST_PATH)
        if (vaultPath.isNullOrEmpty() || destPath.isNullOrEmpty()) {
            return Outcome("INVALID_ARGS", "vault_path and dest_path are required")
        }
        // dest_path is either a raw full file path, or (if it starts with
        // content://) a SAF *tree* Uri to create the file inside -- see
        // VaultAutomationFolderOps.exportOneFile's doc comment for why the
        // two conventions differ here.
        return if (VaultAutomationFolderOps.exportOneFile(context, volId, vaultPath, destPath)) {
            Outcome("OK", "Exported")
        } else {
            Outcome("ERROR", "Export failed")
        }
    }

    private fun handleImportFolder(context: Context, vaultUri: String, intent: Intent): Outcome {
        if (!AutomationSettings.canImportExport(context, vaultUri)) {
            return Outcome("FORBIDDEN", "This vault is not opted in to automation file import/export")
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
            ?: return Outcome("NOT_MOUNTED", "Vault is not currently unlocked")
        val sourcePath = intent.getStringExtra(EXTRA_SOURCE_PATH)
        val vaultDestDir = intent.getStringExtra(EXTRA_VAULT_PATH) ?: ""
        if (sourcePath.isNullOrEmpty()) {
            return Outcome("INVALID_ARGS", "source_path is required")
        }
        val deleteSource = intent.getBooleanExtra(EXTRA_DELETE_SOURCE, false)
        val summary = VaultAutomationFolderOps.importFolder(context, volId, sourcePath, vaultDestDir, deleteSource)
            ?: return Outcome("INVALID_ARGS", "source_path is not a readable folder (check the path/Uri and permissions)")
        return summaryOutcome(summary, "Imported")
    }

    private fun handleExportFolder(context: Context, vaultUri: String, intent: Intent): Outcome {
        if (!AutomationSettings.canImportExport(context, vaultUri)) {
            return Outcome("FORBIDDEN", "This vault is not opted in to automation file import/export")
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
            ?: return Outcome("NOT_MOUNTED", "Vault is not currently unlocked")
        val vaultSourceDir = intent.getStringExtra(EXTRA_VAULT_PATH) ?: ""
        val destPath = intent.getStringExtra(EXTRA_DEST_PATH)
        if (destPath.isNullOrEmpty()) {
            return Outcome("INVALID_ARGS", "dest_path is required")
        }
        val summary = VaultAutomationFolderOps.exportFolder(context, volId, vaultSourceDir, destPath)
            ?: return Outcome("INVALID_ARGS", "dest_path is not a writable folder (check the path/Uri and permissions)")
        return summaryOutcome(summary, "Exported")
    }

    private fun summaryOutcome(summary: VaultAutomationFolderOps.OpSummary, verb: String): Outcome {
        val truncatedNote = if (summary.truncated) " (source directory listing was truncated -- see docs)" else ""
        return when {
            summary.allFailed -> Outcome("ERROR", "$verb 0 files -- all ${summary.filesFailed} failed$truncatedNote")
            summary.anyFailed -> Outcome(
                "PARTIAL",
                "$verb ${summary.filesOk} file(s), ${summary.filesFailed} failed$truncatedNote",
            )
            else -> Outcome("OK", "$verb ${summary.filesOk} file(s)$truncatedNote")
        }
    }

    // ── Camera: photo / video ────────────────────────────────────────────

    private fun handleTakePhoto(context: Context, vaultUri: String, intent: Intent): Outcome {
        if (!AutomationSettings.canCapture(context, vaultUri)) {
            return Outcome("FORBIDDEN", "This vault is not opted in to automation camera capture")
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
            ?: return Outcome("NOT_MOUNTED", "Vault is not currently unlocked")
        val facing = intent.getStringExtra(EXTRA_CAMERA_FACING) ?: "back"
        val cameraId = pickCameraId(context, facing)
            ?: return Outcome("CAMERA_UNAVAILABLE", "No camera matches camera_facing=$facing")
        val vaultPath = intent.getStringExtra(EXTRA_VAULT_PATH)?.takeIf { it.isNotEmpty() }
            ?: generateCaptureName(volId, isPhoto = true)

        val session = VaultHeadlessCameraSession(context)
        if (!session.hasPermissions()) {
            return Outcome(
                "PERMISSION_DENIED",
                "Camera/microphone permission not granted -- grant it once from the app's own camera screen first; automation can't prompt for it",
            )
        }
        val latch = CountDownLatch(1)
        var ok = false
        var error: String? = null
        session.capturePhotoAndClose(cameraId, volId, vaultPath) { resultOk, resultError ->
            ok = resultOk
            error = resultError
            latch.countDown()
        }
        val completed = try { latch.await(PHOTO_TIMEOUT_MS, TimeUnit.MILLISECONDS) } catch (e: InterruptedException) { false }
        if (!completed) {
            session.closeAll()
            return Outcome("ERROR", "Photo capture timed out")
        }
        return if (ok) Outcome("OK", "Photo saved to $vaultPath") else outcomeForCameraError(error)
    }

    private fun handleStartRecording(context: Context, vaultUri: String, intent: Intent): Outcome {
        if (!AutomationSettings.canCapture(context, vaultUri)) {
            return Outcome("FORBIDDEN", "This vault is not opted in to automation camera capture")
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
            ?: return Outcome("NOT_MOUNTED", "Vault is not currently unlocked")
        if (VaultAutomationRecordingService.isRecording) {
            return Outcome("BUSY", "An automation recording is already in progress")
        }
        val facing = intent.getStringExtra(EXTRA_CAMERA_FACING) ?: "back"
        val cameraId = pickCameraId(context, facing)
            ?: return Outcome("CAMERA_UNAVAILABLE", "No camera matches camera_facing=$facing")
        val vaultPath = intent.getStringExtra(EXTRA_VAULT_PATH)?.takeIf { it.isNotEmpty() }
            ?: generateCaptureName(volId, isPhoto = false)
        val quality = when (intent.getStringExtra(EXTRA_VIDEO_QUALITY)?.lowercase(Locale.US)) {
            "hd" -> VaultVideoQuality.HD
            "uhd" -> VaultVideoQuality.UHD
            else -> VaultVideoQuality.FHD
        }
        val recordAudio = intent.getBooleanExtra(EXTRA_RECORD_AUDIO, true)
        val containerName = ContainerSessionRegistry.activeSessions[volId]?.displayName ?: vaultUri

        val latch = VaultAutomationCaptureBridge.arm()
        val serviceIntent = Intent(context, VaultAutomationRecordingService::class.java).apply {
            action = VaultAutomationRecordingService.ACTION_START
            putExtra(VaultAutomationRecordingService.EXTRA_VOL_ID, volId)
            putExtra(VaultAutomationRecordingService.EXTRA_VAULT_PATH, vaultPath)
            putExtra(VaultAutomationRecordingService.EXTRA_CAMERA_ID, cameraId)
            putExtra(VaultAutomationRecordingService.EXTRA_VIDEO_QUALITY, quality.name)
            putExtra(VaultAutomationRecordingService.EXTRA_RECORD_AUDIO, recordAudio)
            putExtra(VaultAutomationRecordingService.EXTRA_CONTAINER_NAME, containerName)
            putExtra("vaultUri", vaultUri)
        }
        ContextCompat.startForegroundService(context, serviceIntent)
        val result = VaultAutomationCaptureBridge.await(latch, START_RECORDING_TIMEOUT_MS)
            ?: return Outcome("ERROR", "Timed out waiting for the camera to start")
        return if (result.ok) Outcome("OK", "Recording started: $vaultPath") else outcomeForCameraError(result.message)
    }

    private fun handleStopRecording(context: Context, vaultUri: String): Outcome {
        if (!AutomationSettings.canCapture(context, vaultUri)) {
            return Outcome("FORBIDDEN", "This vault is not opted in to automation camera capture")
        }
        if (!VaultAutomationRecordingService.isRecording) {
            return Outcome("NOT_RECORDING", "No automation recording is in progress")
        }
        if (VaultAutomationRecordingService.currentVaultUri != vaultUri) {
            return Outcome("NOT_RECORDING", "The in-progress automation recording is for a different vault")
        }
        val latch = VaultAutomationCaptureBridge.arm()
        context.startService(
            Intent(context, VaultAutomationRecordingService::class.java)
                .setAction(VaultAutomationRecordingService.ACTION_STOP)
        )
        val result = VaultAutomationCaptureBridge.await(latch, STOP_RECORDING_TIMEOUT_MS)
            ?: return Outcome("ERROR", "Timed out waiting for the recording to finish saving (it may still complete in the background)")
        return if (result.ok) {
            Outcome("OK", "Recording saved (${result.durationMs}ms)", durationMs = result.durationMs)
        } else {
            outcomeForCameraError(result.message)
        }
    }

    private fun pickCameraId(context: Context, facing: String): String? {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val lenses = listCameraLenses(cameraManager)
        return lenses.firstOrNull { it.facing == facing }?.cameraId ?: lenses.firstOrNull()?.cameraId
    }

    /** Mirrors CameraVaultService.nextAvailableName's naming convention on the
     *  Dart side (IMG_/VID_ + timestamp, deduplicated against the vault root
     *  listing) so an automation capture with no explicit vault_path looks
     *  the same as one taken through the in-app camera. Always lands at the
     *  vault root; pass vault_path explicitly for anywhere else. */
    private fun generateCaptureName(volId: Int, isPhoto: Boolean): String {
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val prefix = if (isPhoto) "IMG_" else "VID_"
        val ext = if (isPhoto) ".jpg" else ".mp4"
        val existingNames = (ContainerFileSystem.listDirectory(volId, "") ?: emptyArray())
            .mapNotNull { VaultAutomationFolderOps.parseDirEntry(it)?.name }
            .toSet()
        var candidate = "$prefix$stamp$ext"
        var counter = 1
        while (candidate in existingNames) {
            candidate = "$prefix${stamp}_$counter$ext"
            counter++
        }
        return candidate
    }

    private fun outcomeForCameraError(error: String?): Outcome = when {
        error == null -> Outcome("ERROR", "Unknown camera error")
        error == "permission_denied" -> Outcome(
            "PERMISSION_DENIED",
            "Camera/microphone permission not granted -- grant it once from the app's own camera screen first",
        )
        error.startsWith("camera_unavailable") || error == "camera disconnected" || error == "session configuration failed" ->
            Outcome("CAMERA_UNAVAILABLE", error)
        else -> Outcome("ERROR", error)
    }

    /**
     * Not vault-gated: this only ever touches a plaintext staging file
     * outside any vault (typically the destination of a prior EXPORT_FILE,
     * once Termux is done processing it), so it doesn't need FULL tier on
     * a specific vault -- it still needed a valid token to get here at all
     * (checked in handleAction before this is reached).
     */
    private fun handleWipe(context: Context, intent: Intent): Outcome {
        val path = intent.getStringExtra(EXTRA_SOURCE_PATH)
            ?: return Outcome("INVALID_ARGS", "source_path is required")
        return if (SecureFileWipe.secureDeleteFile(File(path))) {
            Outcome("OK", "Wiped")
        } else {
            Outcome("ERROR", "Wipe failed")
        }
    }
}