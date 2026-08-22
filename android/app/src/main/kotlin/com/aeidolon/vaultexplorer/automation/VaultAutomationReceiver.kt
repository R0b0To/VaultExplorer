package com.aeidolon.vaultexplorer.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.UriNameResolver
import com.aeidolon.vaultexplorer.bridge.VaultAutomationUnlockedBridge
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerLifecycleCore
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.service.VaultKeepAliveService
import java.io.File
import java.util.concurrent.Executors

/**
 * Headless entry point for any automation app to unlock,
 * lock, import into, and export out of a vault without opening the app
 * UI. Every action needs the per-install API token (AutomationSettings)
 * AND the specific vault opted in to the tier that action needs
 * (AutomationSettings.AutomationTier) -- both are checked before any
 * vault state is touched, and a bad/missing token gets no reply at all
 * (see handleAction) so a probing app can't even learn the feature is
 * configured.
 *
 * UNLOCK_VAULT/LOCK_VAULT need only the LIFECYCLE tier. IMPORT_FILE/
 * EXPORT_FILE need FULL, since they read/write arbitrary filesystem
 * paths -- a materially bigger trust decision than lifecycle control
 * alone, hence two separate opt-in switches rather than one.
 *
 * No hidden-volume support and no keyfile support here, by design -- see
 * ContainerLifecycleCore.unlockContainer's doc comment. UNLOCK_VAULT
 * covers all four unlock paths -- standard block-device containers plus
 * Cryptomator/gocryptfs/CryFS -- dispatched on AutomationSettings.getFormat
 * for the given vault (see handleUnlock). USB-attached containers are not
 * covered by any action here yet.
 *
 * IMPORT_FILE/EXPORT_FILE work on plain filesystem paths (this app already holds
 * MANAGE_EXTERNAL_STORAGE), not on incoming content:// Uris from the
 * caller -- resolving an arbitrary third-party content:// Uri on
 * automation's behalf is a bigger surface than a path under shared
 * storage this app can already reach directly.
 *
 * Every action replies on ACTION_AUTOMATION_RESULT with RESULT_CODE /
 * RESULT_MESSAGE so an automation profile listening for that broadcast (an
 * ordinary "Intent Received" event, not a special reply mechanism) can
 * branch a task chain on success/failure instead of assuming success.
 */
class VaultAutomationReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "VaultExplorer_Automation"

        const val ACTION_UNLOCK_VAULT = "com.aeidolon.vaultexplorer.action.UNLOCK_VAULT"
        const val ACTION_LOCK_VAULT = "com.aeidolon.vaultexplorer.action.LOCK_VAULT"
        const val ACTION_IMPORT_FILE = "com.aeidolon.vaultexplorer.action.IMPORT_FILE"
        const val ACTION_EXPORT_FILE = "com.aeidolon.vaultexplorer.action.EXPORT_FILE"
        const val ACTION_WIPE_FILE = "com.aeidolon.vaultexplorer.action.WIPE_FILE"
        const val ACTION_AUTOMATION_RESULT = "com.aeidolon.vaultexplorer.action.AUTOMATION_RESULT"

        const val EXTRA_API_TOKEN = "api_token"
        const val EXTRA_VAULT_URI = "vault_uri"
        const val EXTRA_PASSWORD = "password"            // optional; falls back to the stored automation password
        const val EXTRA_READ_ONLY = "read_only"
        const val EXTRA_SOURCE_PATH = "source_path"       // IMPORT_FILE / WIPE_FILE: real filesystem path
        const val EXTRA_DEST_PATH = "dest_path"           // EXPORT_FILE: real filesystem path to write to
        const val EXTRA_VAULT_PATH = "vault_path"         // path *inside* the vault, IMPORT_FILE / EXPORT_FILE
        const val EXTRA_DELETE_SOURCE = "delete_source"   // IMPORT_FILE: securely wipe source_path after import

        const val EXTRA_ORIGINAL_ACTION = "original_action"
        const val RESULT_CODE = "result_code"       // OK | AUTH_FAIL | NOT_MOUNTED | FORBIDDEN | INVALID_ARGS | ERROR
        const val RESULT_MESSAGE = "result_message"

        // Automation actions must run in the order automation fires them --
        // unlock, then import, then lock is a common chain -- and this
        // receiver has no Activity to hand work off to the way
        // MainActivity's handlers use its ioExecutor, so it gets its own
        // strictly-serial executor rather than a shared/parallel pool.
        private val automationExecutor = Executors.newSingleThreadExecutor()
        private val fuseThread = HandlerThread("automation-split-fuse").apply { start() }
        private val fuseHandler = Handler(fuseThread.looper)
    }

    private data class Outcome(val code: String, val message: String)

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != ACTION_UNLOCK_VAULT && action != ACTION_LOCK_VAULT &&
            action != ACTION_IMPORT_FILE && action != ACTION_EXPORT_FILE && action != ACTION_WIPE_FILE
        ) {
            return
        }
        val appContext = context.applicationContext
        val pending = goAsync()
        automationExecutor.execute {
            try {
                handleAction(appContext, action, intent)
            } catch (e: Exception) {
                Log.e(TAG, "Unhandled automation error for $action", e)
            } finally {
                pending.finish()
            }
        }
    }

    private fun handleAction(context: Context, action: String, intent: Intent) {
        val token = intent.getStringExtra(EXTRA_API_TOKEN)
        if (!AutomationSettings.isTokenValid(context, token)) {
            Log.w(TAG, "Rejected $action: invalid or missing token")
            return // No reply broadcast on a bad token -- don't confirm to an
                   // unauthenticated caller that automation is even configured.
        }
        val vaultUri = intent.getStringExtra(EXTRA_VAULT_URI)
        val outcome = if (vaultUri.isNullOrEmpty()) {
            Outcome("INVALID_ARGS", "vault_uri is required")
        } else when (action) {
            ACTION_UNLOCK_VAULT -> handleUnlock(context, vaultUri, intent)
            ACTION_LOCK_VAULT -> handleLock(context, vaultUri)
            ACTION_IMPORT_FILE -> handleImport(context, vaultUri, intent)
            ACTION_EXPORT_FILE -> handleExport(context, vaultUri, intent)
            else -> handleWipe(context, intent) // ACTION_WIPE_FILE; doesn't need vaultUri, see handleWipe
        }
        sendResult(context, action, outcome)
    }

    private fun sendResult(context: Context, action: String, outcome: Outcome) {
        Log.i(TAG, "$action -> ${outcome.code}: ${outcome.message}")
        context.sendBroadcast(
            Intent(ACTION_AUTOMATION_RESULT).apply {
                putExtra(EXTRA_ORIGINAL_ACTION, action)
                putExtra(RESULT_CODE, outcome.code)
                putExtra(RESULT_MESSAGE, outcome.message)
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
        val sourceFile = File(sourcePath)
        if (!sourceFile.canRead()) {
            return Outcome("INVALID_ARGS", "source_path is not readable (check the path and storage permission)")
        }
        if (!ContainerFileSystem.writeBackFile(volId, vaultPath, sourcePath)) {
            return Outcome("ERROR", "Import failed")
        }
        if (intent.getBooleanExtra(EXTRA_DELETE_SOURCE, false) && !SecureFileWipe.secureDeleteFile(sourceFile)) {
            return Outcome("OK", "Imported, but securely wiping the source file failed")
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
        return if (ContainerFileSystem.extractToFile(volId, vaultPath, destPath)) {
            Outcome("OK", "Exported")
        } else {
            Outcome("ERROR", "Export failed")
        }
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