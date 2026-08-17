package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import com.aeidolon.vaultexplorer.handlers.VaultPickerHandlers

/**
 * Split-container sibling lookup (see [SafSplitResolver] in
 * LocalSplitFuseCallback.kt) needs tree-level SAF access to a cloud
 * document's parent folder -- but the container picker itself only ever
 * grants single-document access via ACTION_OPEN_DOCUMENT. This checks
 * whether we already hold a *separate*, persisted tree-level grant
 * (obtained via the ACTION_OPEN_DOCUMENT_TREE follow-up prompt in
 * VaultPickerHandlers.pickContainerLauncher the first time a cloud split
 * part is picked) that covers a given document's folder, so repeat
 * unlocks of the same container never need to prompt again.
 */
object SafFolderGrants {
    private const val PREFS_NAME = "saf_split_folder_grants"

    /**
     * Explicit file-Uri -> tree-Uri record, set by
     * [recordTreeForFile] right after the follow-up
     * ACTION_OPEN_DOCUMENT_TREE prompt succeeds. The picker asks the user
     * to choose that *specific file's own containing folder*, so once
     * recorded, this mapping is authoritative -- no doc-ID inference
     * needed at all. This is required for providers like Google Drive
     * whose doc IDs are fully opaque (no path-like relationship between
     * a file and its parent's doc ID), where the doc-ID-prefix heuristic
     * in [findCoveringTreeUriByDocIdPrefix] can never match even though
     * the grant genuinely covers the right folder.
     */
    fun recordTreeForFile(context: Context, fileUri: Uri, treeUri: Uri) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(fileUri.toString(), treeUri.toString())
            .apply()
    }

    /** The explicitly recorded tree Uri for [documentUri], if one was ever set via [recordTreeForFile]. */
    fun findRecordedTreeUri(context: Context, documentUri: Uri): Uri? {
        val stored = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(documentUri.toString(), null) ?: return null
        val treeUri = Uri.parse(stored)
        // The recorded grant may since have been revoked (permission
        // list changes independently of our own SharedPreferences
        // record) -- confirm it's still actually held before trusting it.
        val stillHeld = context.contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        }
        return if (stillHeld) treeUri else null
    }

    /** True if we can resolve [documentUri]'s folder, either via an explicit record or the doc-ID heuristic. */
    fun hasCoveringTreeGrant(context: Context, documentUri: Uri): Boolean =
        findCoveringTreeUri(context, documentUri) != null

    /**
     * The persisted tree Uri covering [documentUri]'s folder, if any --
     * checks the authoritative explicit record first (see
     * [recordTreeForFile]), then falls back to the best-effort doc-ID
     * prefix heuristic for providers that happen to use path-shaped doc
     * IDs (e.g. Round-Sync/rclone-style mounts) even without ever having
     * explicitly recorded a grant for this exact file.
     */
    fun findCoveringTreeUri(context: Context, documentUri: Uri): Uri? =
        findRecordedTreeUri(context, documentUri)
            ?: findCoveringTreeUriByDocIdPrefix(context, documentUri)

    fun findCoveringTreeUriByDocIdPrefix(context: Context, documentUri: Uri): Uri? {
        val docId = try {
            DocumentsContract.getDocumentId(documentUri)
        } catch (_: Exception) {
            return null
        }
        return context.contentResolver.persistedUriPermissions.firstOrNull { perm ->
            if (!perm.isReadPermission) return@firstOrNull false
            val treeUri = perm.uri
            if (treeUri.authority != documentUri.authority) return@firstOrNull false
            if (!DocumentsContract.isTreeUri(treeUri)) return@firstOrNull false
            val treeDocId = try {
                DocumentsContract.getTreeDocumentId(treeUri)
            } catch (_: Exception) {
                return@firstOrNull false
            }
            // Doc IDs are opaque per-provider strings, but some providers
            // (path-backed mounts like Round-Sync/rclone) treat them as a
            // path-shaped namespace, so a covering tree's doc ID is a
            // path-prefix of the file's doc ID there. Providers that don't
            // follow this shape (Drive, pCloud, ...) just fall through
            // here -- they rely on the explicit record above instead.
            docId == treeDocId || docId.startsWith("$treeDocId/")
        }?.uri
    }
}

