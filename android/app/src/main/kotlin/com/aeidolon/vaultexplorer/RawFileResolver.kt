package com.aeidolon.vaultexplorer

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import java.io.File

object RawFileResolver {
    private const val TAG = "RawFileResolver"

    fun getRawFile(context: Context, documentFile: DocumentFile): File? {
        return getRawFileFromUri(context, documentFile.uri)
    }

    fun getRawFileFromUri(context: Context, uri: Uri): File? {
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            val file = File(path)
            val accessible = canAccessRawFile(file)
            Log.d(TAG, "file:// URI path: $path -> accessible: $accessible")
            return if (accessible) file else null
        }
        if (uri.scheme == "content") {
            val auth = uri.authority
            val docId = try {
                android.provider.DocumentsContract.getDocumentId(uri)
            } catch (_: Exception) {
                try {
                    android.provider.DocumentsContract.getTreeDocumentId(uri)
                } catch (_: Exception) {
                    null
                }
            }
            Log.d(TAG, "content:// URI: $uri | auth: $auth | docId: $docId")

            if (auth == "com.android.externalstorage.documents" && docId != null) {
                val split = docId.split(":")
                if (split.size >= 2) {
                    val type = split[0]
                    val relativePath = Uri.decode(split[1])
                    val file = if (type.equals("primary", ignoreCase = true)) {
                        File(Environment.getExternalStorageDirectory(), relativePath)
                    } else {
                        File("/storage/$type", relativePath)
                    }
                    val accessible = canAccessRawFile(file)
                    Log.d(TAG, "Resolved SAF docId '$docId' -> File '${file.absolutePath}' | accessible: $accessible")
                    if (accessible) {
                        return file
                    }
                }
            } else if (auth == "com.android.providers.downloads.documents" && docId != null) {
                if (docId.startsWith("raw:")) {
                    val rawPath = Uri.decode(docId.substring(4))
                    val file = File(rawPath)
                    val accessible = canAccessRawFile(file)
                    Log.d(TAG, "Resolved downloads raw docId -> File '${file.absolutePath}' | accessible: $accessible")
                    if (accessible) return file
                }
            }
        }
        Log.w(TAG, "FAILED to resolve raw file for URI: $uri (Fallback to SAF content://)")
        return null
    }

    private fun canAccessRawFile(file: File): Boolean {
        return try {
            if (file.exists()) {
                file.canRead() && file.canWrite()
            } else {
                val parent = file.parentFile
                parent != null && parent.exists() && parent.canWrite()
            }
        } catch (e: Exception) {
            Log.w(TAG, "canAccessRawFile check failed for ${file.absolutePath}: ${e.message}")
            false
        }
    }
}
