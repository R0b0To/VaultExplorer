package com.aeidolon.vaultexplorer.handlers

import android.content.Intent
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.bridge.LocalIncomingShareBridge
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.VeLog

/**
 * Opens/shares/imports real, already-decrypted files sitting on device
 * storage -- used by the decoy's local storage explorer (browsing plain
 * phone storage, not a mounted vault). Deliberately independent of
 * [SystemPermissionHandlers.handleOpenWithApp] and
 * `ContainerDocumentsProvider`: those exist to stream *decrypted* container
 * bytes out to another app, which is unnecessary machinery (and needless
 * risk surface) for a file that's already plaintext on disk. This exposes
 * the file via the plain androidx [FileProvider] declared in the manifest
 * under the `${applicationId}.localfiles` authority instead.
 *
 * [handleImportSharedUrisToLocal] is the inbound counterpart of
 * [handleShareLocalFile]: same "plain device storage, no vault involved"
 * charter, just copying bytes in from another app instead of out to one.
 */
class LocalFileHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    companion object {
        private const val TAG = "LocalFileHandlers"
    }

    private val authority get() = "${activity.packageName}.localfiles"

    private fun uriFor(path: String): android.net.Uri {
        return FileProvider.getUriForFile(activity, authority, File(path))
    }

    /** First available name in [destDir] starting from [name] -- appends
     *  " (1)", " (2)", etc. before the extension on a collision, same
     *  scheme file managers commonly use. Never overwrites an existing
     *  file silently. */
    private fun uniqueDestFile(destDir: File, name: String): File {
        var candidate = File(destDir, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 1
        while (candidate.exists()) {
            candidate = File(destDir, "$base ($i)$ext")
            i++
        }
        return candidate
    }

    /**
     * Streams whatever [LocalIncomingShareBridge] currently has buffered
     * straight to plain files under [destDirPath] -- the decoy identity's
     * counterpart to [ImportExportHandlers.handlePrepareShareImport]/
     * `handleImportFile`, deliberately much simpler: no container, no
     * crypto, no `pickedFilesByToken` bookkeeping, no batch-write session,
     * because none of that machinery exists for a plain filesystem copy.
     * Just `ContentResolver.openInputStream` -> `FileOutputStream`, one
     * item at a time, off [ioExecutor].
     *
     * Takes (consumes) the pending buffer itself via
     * [LocalIncomingShareBridge.takePendingUris] rather than accepting
     * URIs as call arguments -- same reasoning as
     * [ImportExportHandlers.handlePrepareShareImport] taking them from
     * [com.aeidolon.vaultexplorer.bridge.IncomingShareBridge]: the
     * `content://` grant lives on native's side of the share intent, so
     * there's nothing for Dart to usefully round-trip back.
     *
     * A per-item failure (e.g. the sending app's URI grant already
     * expired) doesn't abort the rest -- returns how many of each.
     */
    fun handleImportSharedUrisToLocal(call: MethodCall, result: MethodChannel.Result) {
        val destDirPath = call.argument<String>("destDirPath")
        if (destDirPath.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "destDirPath required", null)
            return
        }
        val uris = LocalIncomingShareBridge.takePendingUris()
        if (uris.isNullOrEmpty()) {
            result.success(mapOf("savedCount" to 0, "failedCount" to 0))
            return
        }
        ioExecutor.execute {
            val destDir = File(destDirPath)
            var savedCount = 0
            var failedCount = 0
            try {
                destDir.mkdirs()
                for (uri in uris) {
                    try {
                        val doc = DocumentFile.fromSingleUri(activity, uri)
                        val name = doc?.name
                            ?: uri.lastPathSegment?.substringAfterLast('/')
                            ?: "shared_file"
                        val target = uniqueDestFile(destDir, name)
                        val input = activity.contentResolver.openInputStream(uri)
                            ?: throw java.io.IOException("Unable to open input stream for $uri")
                        input.use { src -> target.outputStream().use { dst -> src.copyTo(dst) } }
                        savedCount++
                    } catch (e: Exception) {
                        VeLog.w(TAG) { "Failed to save shared uri $uri to local storage: ${e.message}" }
                        failedCount++
                    }
                }
            } finally {
                val response = mapOf("savedCount" to savedCount, "failedCount" to failedCount)
                activity.runOnUiThread { result.success(response) }
            }
        }
    }

    fun handleGetLocalFileUri(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("filePath")
        if (path == null) {
            result.error("INVALID_ARGS", "filePath required", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("NOT_FOUND", "File does not exist", null)
            return
        }
        try {
            val uri = uriFor(path)
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("GET_LOCAL_FILE_URI_ERROR", e.message, null)
        }
    }

    fun handleOpenLocalFileWithApp(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("filePath")
        if (path == null) {
            result.error("INVALID_ARGS", "filePath required", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("NOT_FOUND", "File does not exist", null)
            return
        }
        try {
            val uri = uriFor(path)
            val mimeType = call.argument<String>("mimeType") ?: MimeTypeHelper.getMimeType(file.name)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(intent, null)
            if (chooser.resolveActivity(activity.packageManager) != null) {
                activity.startActivity(chooser)
                result.success(true)
            } else {
                result.error("NO_APP_FOUND", "No app available to open this file", null)
            }
        } catch (e: Exception) {
            result.error("OPEN_LOCAL_FILE_ERROR", e.message, null)
        }
    }

    fun handleShareLocalFile(call: MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<String>>("filePaths")
        if (paths.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "filePaths required", null)
            return
        }
        try {
            val uris = ArrayList<android.os.Parcelable>()
            for (path in paths) {
                val file = File(path)
                if (file.exists()) uris.add(uriFor(path))
            }
            if (uris.isEmpty()) {
                result.error("NOT_FOUND", "None of the requested files exist", null)
                return
            }
            val intent = if (uris.size == 1) {
                Intent(Intent.ACTION_SEND).apply {
                    putExtra(Intent.EXTRA_STREAM, uris[0])
                    type = MimeTypeHelper.getMimeType(File(paths[0]).name)
                }
            } else {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                    type = "*/*"
                }
            }
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivity(Intent.createChooser(intent, null))
            result.success(true)
        } catch (e: Exception) {
            result.error("SHARE_LOCAL_FILE_ERROR", e.message, null)
        }
    }
}
