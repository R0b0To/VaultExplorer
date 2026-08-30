package com.aeidolon.vaultexplorer.handlers

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.MimeTypeHelper

/**
 * Opens/shares real, already-decrypted files sitting on device storage --
 * used by the decoy's local storage explorer (browsing plain phone
 * storage, not a mounted vault). Deliberately independent of
 * [SystemPermissionHandlers.handleOpenWithApp] and
 * `ContainerDocumentsProvider`: those exist to stream *decrypted* container
 * bytes out to another app, which is unnecessary machinery (and needless
 * risk surface) for a file that's already plaintext on disk. This exposes
 * the file via the plain androidx [FileProvider] declared in the manifest
 * under the `${applicationId}.localfiles` authority instead.
 */
class LocalFileHandlers(private val activity: MainActivity) {

    private val authority get() = "${activity.packageName}.localfiles"

    private fun uriFor(path: String): android.net.Uri {
        return FileProvider.getUriForFile(activity, authority, File(path))
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
