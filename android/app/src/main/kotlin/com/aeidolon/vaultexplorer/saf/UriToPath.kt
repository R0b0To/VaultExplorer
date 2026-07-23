package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import java.io.File

object UriToPath {
    fun getRawFile(context: Context, uri: Uri): File? {
        val path = getRawPath(context, uri) ?: return null
        val file = File(path)
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

            // Example docId: "primary:Download/Vault" or "1A2B-3C4D:CryptoVault"
            val parts = docId.split(":")
            if (parts.size >= 2) {
                val type = parts[0]
                val relativePath = parts[1]

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