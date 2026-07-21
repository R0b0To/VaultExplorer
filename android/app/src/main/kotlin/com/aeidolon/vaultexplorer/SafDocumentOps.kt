package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.os.Build
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile

class SafIOException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Shared low-level SAF (DocumentFile / DocumentsContract) plumbing used by
 * both the Cryptomator and Gocryptfs vault backends.
 *
 * Extracted from four near-identical private copies that had accumulated
 * in CryptomatorSession, GocryptfsSession, CryptomatorVaultTree, and
 * GocryptfsVaultTree (see the tech-debt audit). Every method here is
 * format-agnostic — it only ever deals with DocumentFile/Uri, never with
 * ciphertext/cleartext names or vault-specific concepts — so it has no
 * business knowing about Cryptomator or Gocryptfs at all.
 *
 * Callers keep their own thin, same-named wrapper methods (readWhole,
 * writeWhole, etc.) delegating to an instance of this class, so call sites
 * elsewhere in each file don't need to change.
 */
class SafDocumentOps(private val context: Context) {

    /** Fast child lookup: DocumentsContract query instead of DocumentFile.listFiles()'s O(n) per-child stat calls. */
    fun listChildren(folder: DocumentFile): List<DocumentFile> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(folder.uri, DocumentsContract.getDocumentId(folder.uri))
        val results = mutableListOf<DocumentFile>()
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        try {
            context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                while (cursor.moveToNext()) {
                    val docId = cursor.getString(idIdx)
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(folder.uri, docId)
                    DocumentFile.fromSingleUri(context, childUri)?.let { results.add(it) }
                }
            }
        } catch (e: Exception) {
            // Ignored — matches the original callers' best-effort behavior.
        }
        return results
    }

    fun childOf(folder: DocumentFile, name: String): DocumentFile? =
        listChildren(folder).firstOrNull { it.name == name }

    /** Creates a subdirectory via DocumentsContract directly (not DocumentFile.createDirectory()),
     *  since [parent] may be a SingleDocumentFile wrapper produced by [listChildren] (via
     *  fromSingleUri), whose own createDirectory() unconditionally throws
     *  UnsupportedOperationException. DocumentsContract.createDocument() only needs a valid
     *  document-within-tree URI, so it works regardless of which DocumentFile subclass wraps
     *  the parent. */
    fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? = try {
        val uri = DocumentsContract.createDocument(context.contentResolver, parent.uri, DocumentsContract.Document.MIME_TYPE_DIR, name)
        uri?.let { DocumentFile.fromSingleUri(context, it) }
    } catch (e: Exception) {
        null
    }

    /** Same rationale as [createDirectorySafe]. */
    fun createFileSafe(parent: DocumentFile, mimeType: String, name: String): DocumentFile? = try {
        val uri = DocumentsContract.createDocument(context.contentResolver, parent.uri, mimeType, name)
        uri?.let { DocumentFile.fromSingleUri(context, it) }
    } catch (e: Exception) {
        null
    }

    fun readWhole(file: DocumentFile): ByteArray =
        context.contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            ?: throw SafIOException("Could not open ${file.uri} for reading")

    fun writeWhole(file: DocumentFile, bytes: ByteArray) {
        context.contentResolver.openOutputStream(file.uri, "wt")?.use { it.write(bytes) }
            ?: throw SafIOException("Could not open ${file.uri} for writing")
    }

    /** Like DocumentsContract.renameDocument, but returns the (possibly new) DocumentFile handle —
     *  needed when the caller must keep operating on it afterward (e.g. moving it to a different
     *  parent next). */
    fun renameDocumentAndGet(doc: DocumentFile, newName: String): DocumentFile {
        val newUri = DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
        return DocumentFile.fromSingleUri(context, newUri ?: doc.uri)
            ?: throw SafIOException("renameDocument failed for ${doc.uri}")
    }

    fun renameDocument(doc: DocumentFile, newName: String) {
        DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
            ?: throw SafIOException("renameDocument failed for ${doc.uri}")
    }

    /** Physically relocates [doc] (a file, or a small pointer folder like a Cryptomator .c9r/.c9s
     *  node or a gocryptfs long-name pair) from [oldParent] to [newParent]. Prefers the atomic SAF
     *  move operation; falls back to a manual recursive copy+delete for providers that don't
     *  implement FLAG_SUPPORTS_MOVE. */
    fun movePhysicalDocument(doc: DocumentFile, oldParent: DocumentFile, newParent: DocumentFile) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val movedUri = DocumentsContract.moveDocument(
                    context.contentResolver, doc.uri, oldParent.uri, newParent.uri
                )
                if (movedUri != null) return
            } catch (e: Exception) {
                // Provider doesn't support atomic move for this document — fall through.
            }
        }
        copyDocumentRecursive(doc, newParent)
        deleteRecursively(doc)
    }

    fun copyDocumentRecursive(source: DocumentFile, targetParent: DocumentFile): DocumentFile {
        val name = source.name ?: throw SafIOException("Source document has no name")
        return if (source.isDirectory) {
            val newDir = createDirectorySafe(targetParent, name) ?: throw SafIOException("Could not create $name in target")
            for (child in listChildren(source)) copyDocumentRecursive(child, newDir)
            newDir
        } else {
            val newFile = createFileSafe(targetParent, "application/octet-stream", name)
                ?: throw SafIOException("Could not create $name in target")
            context.contentResolver.openInputStream(source.uri)?.use { input ->
                context.contentResolver.openOutputStream(newFile.uri, "wt")?.use { output ->
                    input.copyTo(output)
                } ?: throw SafIOException("Could not open ${newFile.uri} for writing")
            } ?: throw SafIOException("Could not open ${source.uri} for reading")
            newFile
        }
    }

    fun deleteRecursively(folder: DocumentFile) {
        for (child in listChildren(folder)) {
            if (child.isDirectory) deleteRecursively(child)
            child.delete()
        }
        folder.delete()
    }
}
