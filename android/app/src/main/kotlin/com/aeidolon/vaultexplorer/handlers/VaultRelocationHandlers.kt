package com.aeidolon.vaultexplorer.handlers

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.PendingActivityResult
import com.aeidolon.vaultexplorer.RawFileResolver
import com.aeidolon.vaultexplorer.UriNameResolver
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.automation.AutomationSettings
import com.aeidolon.vaultexplorer.bridge.SplitJoinProgressBridge
import com.aeidolon.vaultexplorer.cancellation.SplitJoinCancellation
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.foldervault.VaultOpenPreferences
import com.aeidolon.vaultexplorer.internalvault.CopyManifest
import com.aeidolon.vaultexplorer.internalvault.FileFingerprint
import com.aeidolon.vaultexplorer.internalvault.InternalVaultStorage
import com.aeidolon.vaultexplorer.internalvault.LocalNode
import com.aeidolon.vaultexplorer.internalvault.LocalWritableDir
import com.aeidolon.vaultexplorer.internalvault.RelocationCancelledException
import com.aeidolon.vaultexplorer.internalvault.RelocationVerifyException
import com.aeidolon.vaultexplorer.internalvault.SafFileNode
import com.aeidolon.vaultexplorer.internalvault.SafTreeNode
import com.aeidolon.vaultexplorer.internalvault.SafWritableDir
import com.aeidolon.vaultexplorer.internalvault.SyncOnCloseOutputStream
import com.aeidolon.vaultexplorer.internalvault.TreeCopier
import com.aeidolon.vaultexplorer.internalvault.VaultNode
import com.aeidolon.vaultexplorer.internalvault.WritableDir
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService

/**
 * Moving a vault between its current location (a picked file or folder, via
 * the Storage Access Framework or a raw path) and app storage, the app's
 * private `<filesDir>/vaults` folder, in either direction.
 *
 * A move is split into steps the Dart side drives, so the original is never
 * touched until the copy has been proven good and the app has switched over
 * to it:
 *
 *  1. [handleRelocateToAppStorage] / [handleRelocateFromAppStorage] copy the
 *     vault, read the copy back and compare SHA-256 per file (see
 *     [TreeCopier]). The original is untouched. On any failure the partial
 *     copy is removed here and nothing changes.
 *  2. Dart switches the vault's record, credentials and settings to the new
 *     location.
 *  3. [handleFinalizeRelocation] deletes the original (if asked) and clears the
 *     old location's native per-vault state.
 *
 * [handleDiscardRelocationCopy] undoes step 1 if step 2 fails. Both delete
 * operations only act on copies this process created and verified, so a
 * confused or hostile caller cannot use them to delete arbitrary user files.
 *
 * Progress and cancellation reuse the Split/Join channel
 * ([SplitJoinProgressBridge], [SplitJoinCancellation]); the Dart caller uses
 * an opId range of its own so the two never collide.
 */
class VaultRelocationHandlers(
    private val activity: MainActivity,
    private val pendingResult: PendingActivityResult,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    companion object {
        private const val TAG = "VaultRelocation"

        /** Free space that must remain after copying into app storage (the volume is shared with the OS). */
        const val SPACE_MARGIN_BYTES = 32L * 1024 * 1024

        /** `.001` / `.part1` style names: a piece of a split container, which cannot be moved on its own. */
        private val SPLIT_PART = Regex("""^(.*)\.(\d+|part\d+)$""", RegexOption.IGNORE_CASE)

        /** Files whose presence marks a folder as the root of a Cryptomator, gocryptfs or CryFS vault. */
        private val FOLDER_VAULT_SENTINELS = setOf(
            "vault.cryptomator", "masterkey.cryptomator", "gocryptfs.conf", "cryfs.config",
        )

        fun looksLikeSplitPart(name: String?): Boolean = name != null && SPLIT_PART.matches(name)

        fun isUnsupportedScheme(uri: String): Boolean = uri.startsWith("usb:") || uri.startsWith("composite:")
    }

    /** A request that cannot be carried out; [code] is what the Dart side branches on. */
    private class Refused(val code: String, message: String) : IOException(message)

    private class InsufficientSpace(val needed: Long, val available: Long) : IOException("Not enough free space")

    /** URIs of copies this process made and verified: the only things the delete operations will touch. */
    private val verifiedCopies = ConcurrentHashMap.newKeySet<String>()

    // ── Replies ────────────────────────────────────────────────────────────────

    private fun reply(res: MethodChannel.Result, value: Any?) = activity.runOnUiThread { res.success(value) }

    /** Maps a failure from a copy to the channel error the Dart side understands. */
    private fun replyFailure(res: MethodChannel.Result, e: Exception) = activity.runOnUiThread {
        when (e) {
            is RelocationCancelledException -> res.error("CANCELLED", "Cancelled", null)
            is RelocationVerifyException -> res.error("VERIFY_FAILED", e.message, null)
            is InsufficientSpace -> res.error(
                "INSUFFICIENT_SPACE", e.message,
                mapOf("neededBytes" to e.needed, "availableBytes" to e.available),
            )
            is Refused -> res.error(e.code, e.message, null)
            is IOException -> res.error("IO_ERROR", e.message ?: e.toString(), null)
            else -> nativeOps.dispatchNativeError(e, res)
        }
    }

    // ── App storage info ───────────────────────────────────────────────────────

    /**
     * Describes app storage: free space and the vaults in it. Also sweeps what
     * a crash can leave behind, when nothing is being created or copied.
     * `includeSizes` adds each vault's size (slow for a large folder vault, so
     * it is opt-in; the vault list alone is enough to find unregistered vaults).
     */
    fun handleGetAppStorageInfo(call: MethodCall, result: MethodChannel.Result) {
        val includeSizes = call.argument<Boolean>("includeSizes") ?: false
        ioExecutor.execute {
            try {
                val swept = InternalVaultStorage.sweepLeftoversIfIdle(activity)
                val store = InternalVaultStorage.store(activity)
                store.ensureRoot()
                val vaults = store.list().map { entry ->
                    mapOf(
                        "uri" to InternalVaultStorage.uriString(entry.file),
                        "name" to entry.file.name,
                        "isDirectory" to entry.isDirectory,
                        "sizeBytes" to (if (includeSizes) entry.sizeBytes else -1L),
                    )
                }
                reply(
                    result,
                    mapOf(
                        "rootUri" to InternalVaultStorage.uriString(store.root),
                        "availableBytes" to store.availableBytes(),
                        "vaults" to vaults,
                        "sweptLeftovers" to swept,
                    ),
                )
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("APP_STORAGE_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }

    // ── Preconditions ──────────────────────────────────────────────────────────

    private fun requireLocked(uri: String) {
        if (ContainerSessionRegistry.getVolumeIdByUri(uri) != null) {
            throw Refused("VAULT_UNLOCKED", "Lock the vault before moving it.")
        }
    }

    /** The vault to copy *into* app storage, as a readable node. */
    private fun sourceNode(uri: Uri, isFolder: Boolean): VaultNode {
        val raw = RawFileResolver.getRawFileFromUri(activity, uri)
        if (isFolder) {
            if (raw != null && raw.isDirectory && raw.canRead()) return LocalNode(raw)
            val doc = DocumentFile.fromTreeUri(activity, uri)
                ?: throw Refused("SOURCE_MISSING", "The vault folder can no longer be accessed.")
            return SafTreeNode(activity, SafDocumentOps(activity), doc)
        }
        if (raw != null && raw.isFile && raw.canRead()) return LocalNode(raw)
        return SafFileNode(activity, uri, UriNameResolver.resolve(activity.contentResolver, uri))
    }

    private fun requireSupportedSource(node: VaultNode, isFolder: Boolean) {
        if (isFolder) {
            if (node.children().none { it.name in FOLDER_VAULT_SENTINELS }) {
                throw Refused("NOT_A_VAULT_FOLDER", "This folder does not contain a vault's configuration file.")
            }
        } else if (looksLikeSplitPart(node.name)) {
            throw Refused("SPLIT_UNSUPPORTED", "Split containers cannot be moved. Join the parts first.")
        }
    }

    // ── Progress ───────────────────────────────────────────────────────────────

    private class ProgressReporter(private val opId: Int, private val total: Long) {
        private var done = 0L
        private var lastReportAt = 0L

        fun add(bytes: Long) {
            done += bytes
            val now = SystemClock.elapsedRealtime()
            if (now - lastReportAt >= 100) {
                lastReportAt = now
                SplitJoinProgressBridge.reportProgress(opId, minOf(done, total), total)
            }
        }

        fun finish() = SplitJoinProgressBridge.reportProgress(opId, total, total)
    }

    // ── Into app storage ───────────────────────────────────────────────────────

    /**
     * Copies the vault at `sourceUri` into app storage and verifies the copy.
     * Replies `{uri, bytes, files}` for the new vault; the original is untouched.
     */
    fun handleRelocateToAppStorage(call: MethodCall, result: MethodChannel.Result) {
        val sourceUri = call.argument<String>("sourceUri")
        val isFolder = call.argument<Boolean>("isFolderVault") ?: false
        val displayName = call.argument<String>("displayName") ?: ""
        val opId = call.argument<Number>("opId")?.toInt() ?: 0
        if (sourceUri.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "sourceUri is required", null)
            return
        }
        ioExecutor.execute {
            val store = InternalVaultStorage.store(activity)
            var staging: File? = null
            var reserved: File? = null
            var published = false
            try {
                val payload = InternalVaultStorage.runOperation {
                    if (isUnsupportedScheme(sourceUri)) {
                        throw Refused("UNSUPPORTED_SOURCE", "This kind of vault cannot be moved to app storage.")
                    }
                    if (InternalVaultStorage.isAppStorageUri(activity, sourceUri)) {
                        throw Refused("ALREADY_IN_APP_STORAGE", "This vault is already in app storage.")
                    }
                    requireLocked(sourceUri)
                    val source = sourceNode(Uri.parse(sourceUri), isFolder)
                    requireSupportedSource(source, isFolder)

                    val (bytes, files) = TreeCopier().measure(source)
                    val free = store.availableBytes()
                    if (free < bytes + SPACE_MARGIN_BYTES) throw InsufficientSpace(bytes + SPACE_MARGIN_BYTES, free)

                    val name = displayName.ifBlank { source.name }
                    val claimed = (if (isFolder) store.reserveFolderVaultDir(name) else store.reserveContainerFile(name))
                        .also { reserved = it }
                    val stage = store.newStagingPath().also { staging = it }

                    val progress = ProgressReporter(opId, 2 * bytes)
                    val copier = TreeCopier(
                        isCancelled = { SplitJoinCancellation.isCancelled(opId) },
                        onBytes = progress::add,
                    )
                    if (isFolder) {
                        if (!stage.mkdir()) throw IOException("Could not create a folder in app storage")
                        val sink = LocalWritableDir(stage)
                        val manifest = copier.copyTree(source, sink)
                        copier.verifyTree(sink, manifest)
                    } else {
                        val fingerprint = SyncOnCloseOutputStream(FileOutputStream(stage)).use { out ->
                            copier.copyFile(source, out)
                        }
                        copier.verifyFile(LocalNode(stage), fingerprint, source.name)
                    }
                    store.publish(stage, claimed)
                    published = true
                    progress.finish()

                    val newUri = InternalVaultStorage.uriString(claimed)
                    carryOpenPreferences(sourceUri, newUri)
                    verifiedCopies.add(newUri)
                    mapOf("uri" to newUri, "bytes" to bytes, "files" to files)
                }
                reply(result, payload)
            } catch (e: Exception) {
                if (!published) {
                    staging?.let { store.deleteTree(it) }
                    reserved?.let { store.deleteTree(it) }
                }
                if (e !is RelocationCancelledException && e !is Refused) {
                    VeLog.w(TAG, e) { "relocateToAppStorage failed" }
                }
                replyFailure(result, e)
            } finally {
                SplitJoinCancellation.clear(opId)
            }
        }
    }

    // ── Out of app storage ─────────────────────────────────────────────────────

    private class FromAppStorageRequest(
        val source: File,
        val isFolder: Boolean,
        val displayName: String,
        val opId: Int,
    )

    private var pendingFromAppStorage: FromAppStorageRequest? = null

    /**
     * Asks the user where to put the vault, copies it there from app storage
     * and verifies the copy. Replies `{success: true, uri, bytes, files}`, or
     * `{success: false}` if the user dismissed the picker. The original is
     * untouched.
     *
     * A container is saved with the system "create document" picker; a folder
     * vault needs an empty folder chosen with the folder picker.
     */
    fun handleRelocateFromAppStorage(call: MethodCall, result: MethodChannel.Result) {
        val sourceUri = call.argument<String>("sourceUri")
        val isFolder = call.argument<Boolean>("isFolderVault") ?: false
        val displayName = call.argument<String>("displayName") ?: ""
        val opId = call.argument<Number>("opId")?.toInt() ?: 0
        if (sourceUri.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "sourceUri is required", null)
            return
        }
        val source = InternalVaultStorage.localFile(activity, sourceUri)
        if (source == null || !source.exists()) {
            result.error("NOT_IN_APP_STORAGE", "This vault is not in app storage.", null)
            return
        }
        if (source.isDirectory != isFolder) {
            result.error("INVALID_ARGS", "isFolderVault does not match what is stored at this location", null)
            return
        }
        if (ContainerSessionRegistry.getVolumeIdByUri(sourceUri) != null) {
            result.error("VAULT_UNLOCKED", "Lock the vault before moving it.", null)
            return
        }
        if (!isFolder && looksLikeSplitPart(source.name)) {
            result.error("SPLIT_UNSUPPORTED", "Split containers cannot be moved. Join the parts first.", null)
            return
        }

        val name = displayName.ifBlank { source.name }
        pendingFromAppStorage = FromAppStorageRequest(source, isFolder, name, opId)
        pendingResult.stash(result)
        val intent = if (isFolder) {
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        } else {
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, name)
            }
        }
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        try {
            pickDestinationLauncher.launch(intent)
        } catch (e: Exception) {
            pendingFromAppStorage = null
            pendingResult.take()?.error("NO_PICKER", "No file picker is available on this device.", null)
        }
    }

    private val pickDestinationLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val request = pendingFromAppStorage
        pendingFromAppStorage = null
        val dest = activityResult.data?.data
        if (activityResult.resultCode == Activity.RESULT_OK && dest != null && request != null) {
            ioExecutor.execute { copyOutOfAppStorage(request, dest, res) }
        } else {
            res.success(mapOf("success" to false, "uri" to null))
        }
    }

    private fun persistPermission(uri: Uri) {
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Some providers only offer a read grant; the copy below fails clearly if it cannot write.
        }
    }

    private fun copyOutOfAppStorage(request: FromAppStorageRequest, dest: Uri, res: MethodChannel.Result) {
        val opId = request.opId
        var destroyOnFailure: (() -> Unit)? = null
        try {
            val payload = InternalVaultStorage.runOperation {
                persistPermission(dest)
                val source = LocalNode(request.source)
                val (bytes, files) = TreeCopier().measure(source)
                val progress = ProgressReporter(opId, 2 * bytes)
                val copier = TreeCopier(
                    isCancelled = { SplitJoinCancellation.isCancelled(opId) },
                    onBytes = progress::add,
                )
                if (request.isFolder) {
                    copyFolderOut(source, dest, copier) { destroyOnFailure = it }
                } else {
                    copyContainerOut(request, source, dest, copier) { destroyOnFailure = it }
                }
                progress.finish()
                carryOpenPreferences(request.source.let { InternalVaultStorage.uriString(it) }, dest.toString())
                verifiedCopies.add(dest.toString())
                mapOf("success" to true, "uri" to dest.toString(), "bytes" to bytes, "files" to files)
            }
            reply(res, payload)
        } catch (e: Exception) {
            try { destroyOnFailure?.invoke() } catch (_: Exception) {}
            if (e !is RelocationCancelledException && e !is Refused) {
                VeLog.w(TAG, e) { "relocateFromAppStorage failed" }
            }
            replyFailure(res, e)
        } finally {
            SplitJoinCancellation.clear(opId)
        }
    }

    private fun copyContainerOut(
        request: FromAppStorageRequest,
        source: VaultNode,
        dest: Uri,
        copier: TreeCopier,
        onCreated: (() -> Unit) -> Unit,
    ) {
        // The picker has already created an empty document; remove it if the copy does not complete.
        onCreated { DocumentFile.fromSingleUri(activity, dest)?.delete() }
        val raw = RawFileResolver.getRawFileFromUri(activity, dest)?.takeIf { it.isFile && it.canWrite() }
        val out = if (raw != null) {
            SyncOnCloseOutputStream(FileOutputStream(raw))
        } else {
            activity.contentResolver.openOutputStream(dest, "wt")
                ?: throw IOException("Could not open the chosen location for writing")
        }
        val fingerprint: FileFingerprint = out.use { copier.copyFile(source, it) }
        val written: VaultNode = if (raw != null) LocalNode(raw) else SafFileNode(activity, dest, request.source.name)
        copier.verifyFile(written, fingerprint, request.source.name)
    }

    private fun copyFolderOut(
        source: VaultNode,
        dest: Uri,
        copier: TreeCopier,
        onCreated: (() -> Unit) -> Unit,
    ) {
        val raw = RawFileResolver.getRawFileFromUri(activity, dest)?.takeIf { it.isDirectory && it.canWrite() }
        val ops = SafDocumentOps(activity)
        val doc: DocumentFile? = if (raw == null) {
            DocumentFile.fromTreeUri(activity, dest) ?: throw IOException("Cannot access the chosen folder")
        } else {
            null
        }
        // Mixing a vault into a folder that already has other files would make it impossible to tell them
        // apart later, and a rollback could not safely tell which entries were ours.
        val isEmpty = if (raw != null) raw.list().isNullOrEmpty() else ops.listChildren(doc!!).isEmpty()
        if (!isEmpty) throw Refused("DESTINATION_NOT_EMPTY", "Choose an empty folder.")

        // From here every entry in the destination is ours, so a failure may remove them all
        // (the folder itself is the user's and stays).
        onCreated {
            if (raw != null) {
                raw.listFiles()?.forEach { it.deleteRecursively() }
            } else {
                val fresh = SafDocumentOps(activity)
                fresh.listChildren(doc!!).forEach { child ->
                    try { fresh.deleteRecursively(child) } catch (_: Exception) {}
                }
            }
        }
        val sink: WritableDir = if (raw != null) LocalWritableDir(raw) else SafWritableDir(activity, ops, doc!!)
        val manifest: CopyManifest = copier.copyTree(source, sink)
        // Re-read through a fresh listing: the writer's cache would only echo back what it created.
        val readBack: VaultNode = if (raw != null) LocalNode(raw) else SafTreeNode(activity, SafDocumentOps(activity), doc!!)
        copier.verifyTree(readBack, manifest)
    }

    // ── Finalize / discard / delete ────────────────────────────────────────────

    /**
     * Step 3 of a move. Clears the old location's native automation grant and stored
     * credentials and, when `deleteSource`, deletes the original. Replies
     * `{sourceDeleted, automationReset, reason?}`.
     *
     * Automation access is reset rather than carried over: it is an explicit grant (with a stored
     * password) that the user made for one location, and silently re-issuing it elsewhere is
     * not something a move should do.
     */
    fun handleFinalizeRelocation(call: MethodCall, result: MethodChannel.Result) {
        val oldUri = call.argument<String>("oldUri")
        val newUri = call.argument<String>("newUri")
        val isFolder = call.argument<Boolean>("isFolderVault") ?: false
        val deleteSource = call.argument<Boolean>("deleteSource") ?: false
        if (oldUri.isNullOrEmpty() || newUri.isNullOrEmpty() || oldUri == newUri) {
            result.error("INVALID_ARGS", "oldUri and newUri are required and must differ", null)
            return
        }
        ioExecutor.execute {
            var automationReset = false
            try {
                automationReset = AutomationSettings.getTier(activity, oldUri) != AutomationSettings.AutomationTier.NONE
                clearNativeVaultState(oldUri)
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "finalizeRelocation: per-vault state cleanup failed" }
            }

            var deleted = false
            var reason: String? = null
            if (deleteSource) {
                if (!verifiedCopies.contains(newUri)) {
                    // Only ever delete after a copy this process verified; e.g. not after a restart.
                    reason = "NOT_VERIFIED"
                } else {
                    deleted = try {
                        deleteVault(oldUri, isFolder)
                    } catch (e: Exception) {
                        VeLog.w(TAG, e) { "finalizeRelocation: deleting the original failed" }
                        false
                    }
                    if (!deleted) reason = "DELETE_FAILED"
                }
            }
            verifiedCopies.remove(newUri)
            reply(result, mapOf("sourceDeleted" to deleted, "automationReset" to automationReset, "reason" to reason))
        }
    }

    /** Undoes a copy whose switch-over failed. Only a copy made and verified by this process is removed. */
    fun handleDiscardRelocationCopy(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val isFolder = call.argument<Boolean>("isFolderVault") ?: false
        if (uri.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "uri is required", null)
            return
        }
        ioExecutor.execute {
            val ok = if (!verifiedCopies.remove(uri)) {
                false
            } else try {
                VaultOpenPreferences.clearVault(activity, uri)
                discardCopy(uri, isFolder)
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "discardRelocationCopy failed" }
                false
            }
            reply(result, ok)
        }
    }

    /**
     * Permanently deletes a vault from app storage (the "remove" action for such a vault: with no
     * file manager to find it in, forgetting it would strand the data). Refuses while it is unlocked.
     */
    fun handleDeleteAppStorageVault(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        if (uri.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "uri is required", null)
            return
        }
        val file = InternalVaultStorage.localFile(activity, uri)
        if (file == null) {
            result.error("NOT_IN_APP_STORAGE", "This vault is not in app storage.", null)
            return
        }
        if (ContainerSessionRegistry.getVolumeIdByUri(uri) != null) {
            result.error("VAULT_UNLOCKED", "Lock the vault before deleting it.", null)
            return
        }
        ioExecutor.execute {
            try {
                val deleted = InternalVaultStorage.runOperation { InternalVaultStorage.store(activity).deleteTree(file) }
                if (deleted) {
                    clearNativeVaultState(uri)
                    VaultOpenPreferences.clearVault(activity, uri)
                }
                reply(result, deleted)
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }

    /**
     * Copies the non-secret per-vault open preference (the Cryptomator key-file backup switch) to the new
     * location as soon as the copy is verified. It has to happen here rather than at finalize, because the
     * Dart side forgets the old location's preferences when it switches the record, which is before finalize.
     */
    private fun carryOpenPreferences(fromUri: String, toUri: String) {
        try {
            VaultOpenPreferences.setBackupKeyFiles(
                activity, toUri, VaultOpenPreferences.getBackupKeyFiles(activity, fromUri),
            )
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "could not carry the open preferences to the new location" }
        }
    }

    private fun clearNativeVaultState(uri: String) {
        AutomationSettings.setTier(activity, uri, AutomationSettings.AutomationTier.NONE)
        AutomationSettings.setStoredPassword(activity, uri, null)
        AutomationSettings.setStoredKeyfiles(activity, uri, null)
        AutomationSettings.setStoredPim(activity, uri, null)
    }

    /** Deletes a whole vault at [uriString] wherever it lives. Returns whether nothing was left behind. */
    private fun deleteVault(uriString: String, isFolder: Boolean): Boolean {
        val uri = Uri.parse(uriString)
        InternalVaultStorage.localFile(activity, uri)?.let { return InternalVaultStorage.store(activity).deleteTree(it) }
        val raw = RawFileResolver.getRawFileFromUri(activity, uri)
        if (raw != null && raw.exists() && raw.canWrite()) {
            return if (isFolder) raw.deleteRecursively() else raw.delete()
        }
        return if (isFolder) {
            val doc = DocumentFile.fromTreeUri(activity, uri) ?: return false
            SafDocumentOps(activity).deleteRecursively(doc)
            true
        } else {
            DocumentFile.fromSingleUri(activity, uri)?.delete() == true
        }
    }

    /** Removes a copy this process made. A picked destination folder is kept; only its contents go. */
    private fun discardCopy(uriString: String, isFolder: Boolean): Boolean {
        val uri = Uri.parse(uriString)
        InternalVaultStorage.localFile(activity, uri)?.let { return InternalVaultStorage.store(activity).deleteTree(it) }
        if (!isFolder) return DocumentFile.fromSingleUri(activity, uri)?.delete() == true
        val raw = RawFileResolver.getRawFileFromUri(activity, uri)
        if (raw != null && raw.isDirectory && raw.canWrite()) {
            raw.listFiles()?.forEach { it.deleteRecursively() }
            return raw.list().isNullOrEmpty()
        }
        val doc = DocumentFile.fromTreeUri(activity, uri) ?: return false
        val ops = SafDocumentOps(activity)
        ops.listChildren(doc).forEach { ops.deleteRecursively(it) }
        return true
    }
}
