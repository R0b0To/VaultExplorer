package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract

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
    /** True if a persisted tree grant already covers [documentUri]'s folder. */
    fun hasCoveringTreeGrant(context: Context, documentUri: Uri): Boolean =
        findCoveringTreeUri(context, documentUri) != null

    /** The persisted tree Uri covering [documentUri]'s folder, if any. */
    fun findCoveringTreeUri(context: Context, documentUri: Uri): Uri? {
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
            // Doc IDs are opaque per-provider strings, but every provider
            // we need this for treats them as a path-shaped namespace, so
            // a covering tree's doc ID is always a path-prefix of the
            // file's doc ID. Providers that don't follow this shape just
            // fall through here and the caller re-prompts, which is safe.
            docId == treeDocId || docId.startsWith("$treeDocId/")
        }?.uri
    }
}
