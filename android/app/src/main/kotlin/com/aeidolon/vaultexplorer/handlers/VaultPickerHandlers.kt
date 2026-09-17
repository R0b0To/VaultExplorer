package com.aeidolon.vaultexplorer.handlers

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.UriToPath
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.PendingActivityResult
import com.aeidolon.vaultexplorer.SafSplitResolver
import com.aeidolon.vaultexplorer.UriNameResolver
import com.aeidolon.vaultexplorer.VeLog

/**
 * SAF pickers for every vault type: the classic single-file
 * ACTION_OPEN_DOCUMENT picker for VeraCrypt/LUKS/BitLocker containers, the
 * ACTION_OPEN_DOCUMENT_TREE folder picker for the three directory-backed
 * vault formats (Cryptomator, gocryptfs, CryFS), and the multi-select
 * keyfile picker. Each pick launcher must be registered on the Activity
 * before it leaves the CREATED state, so this class has to be constructed
 * as an eager (non-lazy) MainActivity property — see the launcher
 * properties below, and [NativeOpSupport]'s doc comment for the related
 * "don't touch Context in a constructor" trap this class avoids by only
 * ever reading activity.contentResolver inside a launcher callback (never
 * at construction time).
 */
class VaultPickerHandlers(
    private val activity: MainActivity,
    private val pendingResult: PendingActivityResult,
    private val ioExecutor: ExecutorService,
) {
    private fun detectVaultFormatInFolder(uri: Uri): String? {
        if (com.aeidolon.vaultexplorer.cryfs.CryfsVault.looksLikeVault(activity, uri)) return "cryfs"
        if (com.aeidolon.vaultexplorer.cryptomator.CryptomatorVault.looksLikeVault(activity, uri)) return "cryptomator"
        if (com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault.looksLikeVault(activity, uri)) return "gocryptfs"
        return null
    }

    // Holds the container pick's Flutter result while a follow-up
    // ACTION_OPEN_DOCUMENT_TREE prompt is on screen -- see
    // pickContainerLauncher below. Deliberately bypasses [pendingResult]
    // for this second hop (rather than stash/take again) since this is an
    // internal implementation detail of finishing one pick, not a new
    // Flutter-visible picker operation.
    private data class SplitContainerPickCompletion(
        val res: MethodChannel.Result,
        val uri: Uri,
        val name: String,
    )
    private var pendingSplitContainerCompletion: SplitContainerPickCompletion? = null

    private val pickContainerLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val name = UriNameResolver.resolve(activity.contentResolver, uri)

                // A single ACTION_OPEN_DOCUMENT pick only grants access to
                // this one document -- never its siblings. That's fine for
                // a plain container, but a split part (".001"/".part1"/...)
                // needs SafSplitResolver to enumerate its siblings later,
                // which requires tree-level access to the parent folder.
                // Local files get that for free via UriToPath.getRawFile
                // (raw filesystem access, no SAF ACL involved); genuine
                // cloud documents don't, so prompt for the folder once --
                // SafFolderGrants persists it so this never happens twice
                // for the same folder.
                val looksLikeSplitPart = SafSplitResolver.isSplitFileName(name)
                val isRawLocalFile = UriToPath.getRawFile(activity, uri) != null
                val alreadyCovered = com.aeidolon.vaultexplorer.saf.SafFolderGrants.hasCoveringTreeGrant(activity, uri)

                if (looksLikeSplitPart && !isRawLocalFile && !alreadyCovered) {
                    pendingSplitContainerCompletion = SplitContainerPickCompletion(res, uri, name)
                    activity.runOnUiThread {
                        val treeIntent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            // Best-effort hint to open at the file's own
                            // location; providers are free to ignore this.
                            try { putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri) } catch (_: Exception) {}
                        }
                        pickParentFolderForSplitLauncher.launch(treeIntent)
                    }
                } else {
                    activity.runOnUiThread {
                        res.success(mapOf(
                            "uri" to uri.toString(),
                            "displayName" to name
                        ))
                    }
                }
            }
        } else {
            res.success(null)
        }
    }

    // Follow-up folder picker triggered from pickContainerLauncher above
    // when the picked file looks like a cloud-hosted split part. Grants
    // (and persists) tree-level access to its parent folder so
    // SafSplitResolver can actually enumerate ".002", ".003", etc. later,
    // then completes the *original* container pick's Flutter result --
    // this picker is invisible to the Dart side, which only ever sees one
    // pickContainer call complete.
    private val pickParentFolderForSplitLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val completion = pendingSplitContainerCompletion
        pendingSplitContainerCompletion = null
        if (completion == null) return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val treeUri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        treeUri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                    com.aeidolon.vaultexplorer.saf.SafFolderGrants.recordTreeForFile(activity, completion.uri, treeUri)
                } catch (_: SecurityException) {}
                activity.runOnUiThread {
                    completion.res.success(mapOf(
                        "uri" to completion.uri.toString(),
                        "displayName" to completion.name
                    ))
                }
            }
        } else {
            // User declined folder access. Don't block the pick over it --
            // fall through with just the single file, same as before this
            // patch. SafSplitResolver will simply fail to find siblings
            // and the container mounts (or fails) as a single file, same
            // as today's behavior, rather than the picker itself failing.
            completion.res.success(mapOf(
                "uri" to completion.uri.toString(),
                "displayName" to completion.name
            ))
        }
    }

    private val pickCryptomatorVaultLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val format = detectVaultFormatInFolder(uri)
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf(
                        "uri" to uri.toString(),
                        "displayName" to name,
                        "looksLikeVault" to (format != null),
                        "format" to format,
                    ))
                }
            }
        } else {
            res.success(null)
        }
    }

    private val pickGocryptfsVaultLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val format = detectVaultFormatInFolder(uri)
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf(
                        "uri" to uri.toString(),
                        "displayName" to name,
                        "looksLikeVault" to (format != null),
                        "format" to format,
                    ))
                }
            }
        } else {
            res.success(null)
        }
    }

    private val pickCryfsVaultLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val format = detectVaultFormatInFolder(uri)
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf(
                        "uri" to uri.toString(),
                        "displayName" to name,
                        "looksLikeVault" to (format != null),
                        "format" to format,
                    ))
                }
            }
        } else {
            res.success(null)
        }
    }

    // Check & Repair tool's folder-vault picker (see
    // foldercheck/FolderVaultChecker.kt and RepairHandlers.handleCheckFolderVault).
    // Same body as pickCryptomatorVaultLauncher/pickGocryptfsVaultLauncher/
    // pickCryfsVaultLauncher above -- kept as its own launcher rather than
    // reused so the repair tool's entry point stays independent of the
    // per-format "add a vault" flows (e.g. free to gain repair-specific
    // intent hints later without touching those).
    private val pickFolderVaultForRepairLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val format = detectVaultFormatInFolder(uri)
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf(
                        "uri" to uri.toString(),
                        "displayName" to name,
                        "looksLikeVault" to (format != null),
                        "format" to format,
                    ))
                }
            }
        } else {
            res.success(null)
        }
    }

    // Used by the decoy Archive Explorer screen to let the user open a zip
    // that isn't sitting in the public Downloads folder. Unlike the other
    // launchers here, this doesn't take a persistable URI permission -- the
    // decoy screen only ever operates through plain dart:io, so all it
    // needs back is a real filesystem path (resolved via [UriToPath]) that
    // it can hand to [ArchiveContext.open] the same way it already does
    // for files it finds itself. If the picked document can't be resolved
    // to a raw path (e.g. it lives on a provider with no on-disk backing,
    // or "All files access" hasn't been granted), `path` comes back null
    // and the Dart side shows a friendly error instead of trying to open
    // a content:// URI the archive decoder doesn't understand.
    private val pickArchiveFileLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                val path = UriToPath.getRawPath(activity, uri)
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf("path" to path, "displayName" to name))
                }
            }
        } else {
            res.success(null)
        }
    }

    private val pickExtractFolderLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            val takeFlags = (data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
            try {
                activity.contentResolver.takePersistableUriPermission(uri, takeFlags)
            } catch (e: Exception) {
                try {
                    activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: Exception) {}
            }
            ioExecutor.execute {
                var path = UriToPath.getRawPath(activity, uri)
                if (path.isNullOrEmpty()) {
                    path = resolveTreeUriToPath(activity, uri)
                }

                var name = DocumentFile.fromTreeUri(activity, uri)?.name
                if (name.isNullOrEmpty() || name.contains("acc=") || name.contains("encoded=")) {
                    try {
                        val docId = DocumentsContract.getTreeDocumentId(uri)
                        val docUri = DocumentsContract.buildDocumentUriUsingTree(uri, docId)
                        activity.contentResolver.query(docUri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
                            if (c.moveToFirst()) {
                                name = c.getString(0)
                            }
                        }
                    } catch (_: Exception) {}
                }

                if (name.isNullOrEmpty() || name!!.contains("acc=") || name == "primary" || name!!.matches(Regex("^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$"))) {
                    name = when (uri.authority) {
                        "com.google.android.apps.docs.storage" -> "Google Drive"
                        "org.nextcloud.documents" -> "Nextcloud"
                        "com.microsoft.skydrive.content.StorageAccessProvider" -> "OneDrive"
                        "com.dropbox.android.provider.SDK" -> "Dropbox"
                        else -> UriNameResolver.resolve(activity.contentResolver, uri)
                    }
                }

                if (name!!.contains("acc=") || name!!.isEmpty()) {
                    name = if (uri.authority == "com.google.android.apps.docs.storage") "Google Drive" else "Cloud Storage"
                }

                VeLog.i("VaultPickerHandlers") { "pickExtractFolder: uri=$uri, resolvedPath=$path, displayName=$name" }

                activity.runOnUiThread {
                    res.success(mapOf("path" to path, "displayName" to name, "treeUri" to uri.toString()))
                }
            }
        } else {
            res.success(null)
        }
    }

    private fun resolveTreeUriToPath(context: android.content.Context, uri: Uri): String? {
        try {
            val docId = if (DocumentsContract.isTreeUri(uri)) {
                DocumentsContract.getTreeDocumentId(uri)
            } else {
                DocumentsContract.getDocumentId(uri)
            } ?: return null

            val split = docId.split(":")
            if (split.isEmpty()) return null
            val type = split[0]
            val relativePath = if (split.size > 1) split[1].trimStart('/') else ""

            if ("primary".equals(type, ignoreCase = true)) {
                val base = android.os.Environment.getExternalStorageDirectory().absolutePath
                return if (relativePath.isNotEmpty()) "$base/$relativePath" else base
            }

            // Removable SD Card / USB volume UUID matching
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val sm = context.getSystemService(android.content.Context.STORAGE_SERVICE) as android.os.storage.StorageManager
                for (vol in sm.storageVolumes) {
                    val uuid = vol.uuid
                    if (uuid != null && uuid.equals(type, ignoreCase = true)) {
                        val dir = vol.directory
                        if (dir != null) {
                            return if (relativePath.isNotEmpty()) "${dir.absolutePath}/$relativePath" else dir.absolutePath
                        }
                    }
                }
            }

            // Standard Linux mount fallback: /storage/XXXX-XXXX
            val candidate = java.io.File("/storage/$type", relativePath)
            if (candidate.exists()) return candidate.absolutePath
            val rootCandidate = java.io.File("/storage/$type")
            if (rootCandidate.exists()) {
                return if (relativePath.isNotEmpty()) "${rootCandidate.absolutePath}/$relativePath" else rootCandidate.absolutePath
            }
        } catch (_: Exception) {}
        return null
    }

    private val pickKeyfilesLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode != Activity.RESULT_OK || data == null) {
            res.success(null)
            return@registerForActivityResult
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }

        val picked = uris.mapNotNull { uri ->
            try {
                activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: SecurityException) {}
            try {
                mapOf(
                    "uri" to uri.toString(),
                    "displayName" to UriNameResolver.resolve(activity.contentResolver, uri)
                )
            } catch (_: Exception) { null }
        }
        res.success(picked)
    }

    // Multi-select source-file picker for the encrypt/decrypt file tool's
    // batch mode. Same shape as pickKeyfilesLauncher (clipData fan-out,
    // best-effort persistable-permission grant, uri/displayName map per
    // item) but kept as its own launcher/handler pair -- see
    // pickCryptoFiles's doc comment in vault_explorer_api_container_lifecycle.dart.
    private val pickCryptoFilesLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode != Activity.RESULT_OK || data == null) {
            res.success(null)
            return@registerForActivityResult
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }
        val picked = uris.mapNotNull { uri ->
            try {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: SecurityException) {
                try {
                    activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: SecurityException) {}
            }
            try {
                mapOf(
                    "uri" to uri.toString(),
                    "displayName" to UriNameResolver.resolve(activity.contentResolver, uri)
                )
            } catch (_: Exception) { null }
        }
        res.success(picked)
    }

    fun handlePickContainer(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        pickContainerLauncher.launch(intent)
    }

    fun handlePickCryptomatorVault(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        pickCryptomatorVaultLauncher.launch(intent)
    }

    fun handlePickGocryptfsVault(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        pickGocryptfsVaultLauncher.launch(intent)
    }

    fun handlePickCryfsVault(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        pickCryfsVaultLauncher.launch(intent)
    }

    fun handlePickFolderVaultForRepair(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        pickFolderVaultForRepairLauncher.launch(intent)
    }

    fun handlePickArchiveFile(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/x-zip-compressed"))
        }
        pickArchiveFileLauncher.launch(intent)
    }

    fun handlePickExtractFolder(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        pickExtractFolderLauncher.launch(intent)
    }

    fun handlePickKeyfiles(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        pickKeyfilesLauncher.launch(intent)
    }

    fun handlePickCryptoFiles(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        pickCryptoFilesLauncher.launch(intent)
    }
}