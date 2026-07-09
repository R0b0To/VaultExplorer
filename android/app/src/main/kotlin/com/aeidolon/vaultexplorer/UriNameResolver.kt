package com.aeidolon.vaultexplorer

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns

/**
 * Shared logic for resolving a human-readable display name for a Uri.
 *
 * Resolves display names for both MainActivity (SAF container/tree picker)
 * and VeraCryptDocumentsProvider (DocumentsProvider roots). Querying
 * OpenableColumns.DISPLAY_NAME for content:// URIs, falling back to the last
 * path segment, or "Container" if unavailable.
 */
object UriNameResolver {
    fun resolve(resolver: ContentResolver?, uri: Uri): String {
        if (resolver != null && uri.scheme == "content") {
            try {
                resolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME),
                    null, null, null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx != -1) {
                            cursor.getString(idx)?.let { return it }
                        }
                    }
                }
            } catch (_: Exception) {
                // fall through to path-segment fallback below
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "Container"
    }
}