package com.aeidolon.vaultexplorer

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
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
                    documentUriFor(uri),
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

    /**
     * A bare tree URI (`content://<authority>/tree/<treeDocId>`, what
     * ACTION_OPEN_DOCUMENT_TREE hands back for a picked folder) is not itself
     * a document URI, so querying it for DISPLAY_NAME is rejected by the
     * provider (ExternalStorageProvider throws "Unsupported Uri"). That used
     * to drop straight through to the last-path-segment fallback, which for
     * a folder on internal storage decodes to the raw document id -- e.g. a
     * folder called "test" came back labelled "primary:test". Resolve the
     * tree's root document instead, which is what carries the real name.
     * Anything that is not a bare tree URI is returned unchanged.
     */
    private fun documentUriFor(uri: Uri): Uri {
        return try {
            if (DocumentsContract.isTreeUri(uri) && uri.pathSegments.size == 2) {
                DocumentsContract.buildDocumentUriUsingTree(
                    uri, DocumentsContract.getTreeDocumentId(uri),
                )
            } else {
                uri
            }
        } catch (_: Exception) {
            uri
        }
    }
}
