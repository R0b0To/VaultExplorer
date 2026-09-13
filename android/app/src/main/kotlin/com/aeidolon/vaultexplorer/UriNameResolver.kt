package com.aeidolon.vaultexplorer

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import com.aeidolon.vaultexplorer.container.ContainerDocumentsProvider

/**
 * Shared logic for resolving a human-readable display name for a Uri.
 *
 * Resolves display names for both MainActivity (SAF container/tree picker)
 * and ContainerDocumentsProvider (DocumentsProvider roots). Querying
 * OpenableColumns.DISPLAY_NAME for content:// URIs, falling back to the last
 * path segment, or "Container" if unavailable.
 */
object UriNameResolver {
    /**
     * [fallback] is returned when the DISPLAY_NAME query fails/comes back
     * empty *and* the Uri has no usable last path segment either -- the
     * default of "Container" suits this object's original callers
     * (MainActivity's SAF container/tree picker, ContainerDocumentsProvider);
     * callers resolving a name for something else (e.g. LogExportHandlers'
     * saved log file) should pass a fallback that makes sense for their own
     * Uri instead.
     */
    fun resolve(resolver: ContentResolver?, uri: Uri, fallback: String = "Container"): String {
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
        return uri.lastPathSegment?.substringAfterLast('/') ?: fallback
    }
}