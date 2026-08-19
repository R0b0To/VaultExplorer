package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.StatFs
import android.provider.DocumentsContract
import java.io.File

/**
 * Virtual-path helpers shared by the directory-based vault sessions
 * (CryptomatorSession, GocryptfsSession, CryfsSession). These were
 * byte-identical, hand-duplicated across all three — pulled out here so a
 * future fix (e.g. path normalization) only needs to land once.
 *
 * Deliberately just string manipulation: each session's actual
 * virtual-path -> physical-DocumentFile resolution (dirId-based for
 * Cryptomator, dirIV-based for gocryptfs, block-store-based for CryFS)
 * differs enough between formats that it isn't a candidate for sharing here
 * — only the path-string arithmetic is truly identical.
 */
object VaultPathUtils {
    fun normalize(path: String): String = path.trim('/')

    fun parentOf(normalizedPath: String): String {
        val idx = normalizedPath.lastIndexOf('/')
        return if (idx < 0) "" else normalizedPath.substring(0, idx)
    }

    fun nameOf(normalizedPath: String): String {
        val idx = normalizedPath.lastIndexOf('/')
        return if (idx < 0) normalizedPath else normalizedPath.substring(idx + 1)
    }

    fun joinPath(parent: String, name: String): String =
        if (parent.isEmpty()) name else "$parent/$name"

    /**
     * Available/total bytes on the storage volume backing [vaultRootUri], as
     * `[capacityBytes, availableBytes]`, or null if the space cannot be resolved.
     *
     * First attempts to resolve the local filesystem mount point (e.g. primary
     * storage or SD card) and query [StatFs]. If that cannot be resolved (e.g.
     * virtual or cloud SAF trees), attempts to query DocumentsContract.buildRootsUri.
     */
    fun querySafSpaceInfo(context: Context, vaultRootUri: Uri): LongArray? {
        // 1. Try resolving local filesystem volume and querying StatFs
        try {
            val localPath = resolveLocalFileForUri(vaultRootUri)
            if (localPath != null && localPath.exists()) {
                val stat = StatFs(localPath.absolutePath)
                val total = stat.totalBytes
                val avail = stat.availableBytes
                if (total > 0L && avail >= 0L) {
                    return longArrayOf(total, avail)
                }
            }
        } catch (_: Exception) {}

        // 2. Fallback: Query SAF roots table if the provider permits it
        try {
            val authority = vaultRootUri.authority
            if (authority != null) {
                val rootUri = DocumentsContract.buildRootsUri(authority)
                context.contentResolver.query(
                    rootUri,
                    arrayOf(DocumentsContract.Root.COLUMN_AVAILABLE_BYTES, DocumentsContract.Root.COLUMN_CAPACITY_BYTES),
                    null, null, null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val availIdx = cursor.getColumnIndex(DocumentsContract.Root.COLUMN_AVAILABLE_BYTES)
                        val capIdx = cursor.getColumnIndex(DocumentsContract.Root.COLUMN_CAPACITY_BYTES)
                        val avail = if (availIdx >= 0) cursor.getLong(availIdx) else -1L
                        val cap = if (capIdx >= 0) cursor.getLong(capIdx) else -1L
                        if (cap > 0L && avail >= 0L) return longArrayOf(cap, avail)
                    }
                }
            }
        } catch (_: Exception) {}

        return null
    }

    private fun resolveLocalFileForUri(uri: Uri): File? {
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            return File(path)
        }
        if (uri.scheme == "content") {
            val docId = try {
                DocumentsContract.getTreeDocumentId(uri)
            } catch (_: Exception) {
                try {
                    DocumentsContract.getDocumentId(uri)
                } catch (_: Exception) {
                    null
                }
            }

            if (docId != null && docId.contains(":")) {
                val split = docId.split(":", limit = 2)
                if (split.size == 2) {
                    val type = split[0]
                    val relativePath = Uri.decode(split[1])
                    val target = if (type.equals("primary", ignoreCase = true)) {
                        File(Environment.getExternalStorageDirectory(), relativePath)
                    } else {
                        File("/storage/$type", relativePath)
                    }
                    if (target.exists()) return target
                    val root = if (type.equals("primary", ignoreCase = true)) {
                        Environment.getExternalStorageDirectory()
                    } else {
                        File("/storage/$type")
                    }
                    if (root.exists()) return root
                }
            }

            if (uri.authority == "com.android.providers.downloads.documents" && docId != null) {
                if (docId.startsWith("raw:")) {
                    val rawPath = Uri.decode(docId.substring(4))
                    val file = File(rawPath)
                    if (file.exists()) return file
                }
            }

            if (uri.authority == "com.android.externalstorage.documents") {
                val extDir = Environment.getExternalStorageDirectory()
                if (extDir.exists()) return extDir
            }
        }
        return null
    }
}
