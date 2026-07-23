package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import java.io.File

object UriToPath {
    fun getRawFile(context: Context, uri: Uri): File? {
        val path = getRawPath(context, uri) ?: return null
        val file = File(path)

        if (!file.exists() && file.parentFile?.exists() != true) {
            return null
        }

        // On Android 11+ (API 30+), Scoped Storage blocks java.io.File access for SAF URIs
        // unless MANAGE_EXTERNAL_STORAGE ("All Files Access") is granted OR the file is in app-private storage.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val isAppPrivate = path.startsWith(context.filesDir.absolutePath) ||
                    context.getExternalFilesDirs(null).any { it != null && path.startsWith(it.absolutePath) }

            if (!isAppPrivate && !Environment.isExternalStorageManager()) {
                // Without All Files Access, java.io.File operations will fail under Scoped Storage.
                // Safely return null to force clean fallback to standard SAF (ContentResolver).
                return null
            }
        }

        // Verify that the path can actually be read via POSIX
        return if (file.canRead()) file else null
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