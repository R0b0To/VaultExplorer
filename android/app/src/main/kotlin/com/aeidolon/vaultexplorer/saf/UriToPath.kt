package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import com.aeidolon.vaultexplorer.RawFileResolver
import java.io.File

object UriToPath {
    /**
     * Delegates to [RawFileResolver.getRawFileFromUri], which respects the user's
     * [RawFileResolver.preferRawPath] setting and performs appropriate runtime
     * permission checks per Android API level (All Files Access on API 30+,
     * WRITE_EXTERNAL_STORAGE on API 26-29, READ_EXTERNAL_STORAGE on API <= 25).
     *
     * Returns null if permissions are absent, if the user opted for SAF mode,
     * or if raw path access is technically impossible.
     */
    fun getRawFile(context: Context, uri: Uri): File? {
        return RawFileResolver.getRawFileFromUri(context, uri)
    }

    fun getRawPath(context: Context, uri: Uri): String? {
        if (uri.scheme == "file") return uri.path
        if (DocumentsContract.isTreeUri(uri) || uri.scheme == "content") {
            val docIdRaw = try {
                if (DocumentsContract.isTreeUri(uri)) {
                    DocumentsContract.getTreeDocumentId(uri)
                } else {
                    DocumentsContract.getDocumentId(uri)
                }
            } catch (_: Exception) {
                uri.path
            } ?: return null

            // Decode URL-encoded path components like %2F -> /
            val docId = Uri.decode(docIdRaw) ?: docIdRaw
            val parts = docId.split(":")
            if (parts.size >= 2) {
                val type = parts[0]
                val relativePath = parts.drop(1).joinToString(":")
                val basePath = if ("primary".equalsIgnoreCase(type)) {
                    Environment.getExternalStorageDirectory().absolutePath
                } else {
                    "/storage/$type"
                }
                return if (relativePath.isNotEmpty()) "$basePath/$relativePath" else basePath
            }
        }
        return null
    }

    private fun String.equalsIgnoreCase(other: String): Boolean =
        this.equals(other, ignoreCase = true)
}