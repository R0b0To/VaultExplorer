package com.aeidolon.vaultexplorer

import android.content.Context
import android.net.Uri
import android.os.Environment
import androidx.documentfile.provider.DocumentFile
import java.io.File

object RawFileResolver {

    fun getRawFile(context: Context, documentFile: DocumentFile): File? {
        return getRawFileFromUri(context, documentFile.uri)
    }

    fun getRawFileFromUri(context: Context, uri: Uri): File? {
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            val file = File(path)
            return if (canAccessRawFile(file)) file else null
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

            // Relaxed check: any authority that yields a volume:path ID format.
            if (docId != null && docId.contains(":")) {
                val split = docId.split(":", limit = 2)
                if (split.size == 2) {
                    val type = split[0]
                    val relativePath = Uri.decode(split[1])
                    val file = if (type.equals("primary", ignoreCase = true)) {
                        File(Environment.getExternalStorageDirectory(), relativePath)
                    } else {
                        File("/storage/$type", relativePath)
                    }

                    if (canAccessRawFile(file)) {
                        return file
                    }
                }
            }

            if (auth == "com.android.providers.downloads.documents" && docId != null) {
                if (docId.startsWith("raw:")) {
                    val rawPath = Uri.decode(docId.substring(4))
                    val file = File(rawPath)
                    if (canAccessRawFile(file)) return file
                }
            }
        }

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
            false
        }
    }
}