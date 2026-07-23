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

        // 1. App-private internal/external storage paths are ALWAYS accessible directly
        val isAppPrivateStorage = path.startsWith(context.filesDir.absolutePath) ||
                path.startsWith(context.cacheDir.absolutePath) ||
                context.getExternalFilesDirs(null).any { it != null && path.startsWith(it.absolutePath) }

        if (isAppPrivateStorage) {
            return if (file.exists() || file.parentFile?.exists() == true) file else null
        }

        // 2. Shared external storage (/storage/emulated/0/...) REQUIRES All Files Access on Android 11+
        val hasDirectAccess = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            file.canRead() || file.parentFile?.canRead() == true
        }

        if (!hasDirectAccess) {
            return null // Force fallback to SAF (ContentResolver / DocumentFile)
        }

        return if (file.exists() || file.parentFile?.exists() == true) file else null
    }

    fun getRawPath(context: Context, uri: Uri): String? {
        if (uri.scheme == "file") return uri.path

        if (DocumentsContract.isTreeUri(uri) || uri.scheme == "content") {
            val docId = try {
                if (DocumentsContract.isTreeUri(uri)) {
                    DocumentsContract.getTreeDocumentId(uri)
                } else {
                    DocumentsContract.getDocumentId(uri)
                }
            } catch (_: Exception) {
                uri.path
            } ?: return null

            val parts = docId.split(":")
            if (parts.size >= 2) {
                val type = parts[0]
                val relativePath = parts[1]

                val basePath = if ("primary".equals(type, ignoreCase = true)) {
                    Environment.getExternalStorageDirectory().absolutePath
                } else {
                    "/storage/$type"
                }
                return if (relativePath.isNotEmpty()) "$basePath/$relativePath" else basePath
            }
        }
        return null
    }
}