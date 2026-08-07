package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract

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
     * Available/total bytes on the SAF root backing [vaultRootUri], as
     * `[capacityBytes, availableBytes]`, or null if the provider doesn't
     * report space (or the query fails). Same
     * DocumentsContract.buildRootsUri query, byte-identical, previously
     * duplicated in all three vault sessions.
     */
    fun querySafSpaceInfo(context: Context, vaultRootUri: Uri): LongArray? {
        return try {
            val rootUri = DocumentsContract.buildRootsUri(vaultRootUri.authority)
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
            null
        } catch (e: Exception) {
            null
        }
    }
}
