package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.os.Build
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile

class SafIOException(message: String, cause: Throwable? = null) : Exception(message, cause)

class SafDocumentOps(private val context: Context) {

    fun listChildren(folder: DocumentFile): List<DocumentFile> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(folder.uri, DocumentsContract.getDocumentId(folder.uri))
        val results = mutableListOf<DocumentFile>()
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
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
            // Ignored
        }
        return results
    }

    /** Fast case-insensitive child matching in a single ContentResolver query. */
    fun childOf(folder: DocumentFile, name: String): DocumentFile? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(folder.uri, DocumentsContract.getDocumentId(folder.uri))
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        try {
            context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    val docName = if (nameIdx >= 0) cursor.getString(nameIdx) else null
                    if (docName?.equals(name, ignoreCase = true) == true) {
                        val docId = cursor.getString(idIdx)
                        val childUri = DocumentsContract.buildDocumentUriUsingTree(folder.uri, docId)
                        return DocumentFile.fromSingleUri(context, childUri)
                    }
                }
            }
        } catch (e: Exception) {
            // Fallback
        }
        return null
    }

    fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? = try {
        val uri = DocumentsContract.createDocument(context.contentResolver, parent.uri, DocumentsContract.Document.MIME_TYPE_DIR, name)
        uri?.let { DocumentFile.fromSingleUri(context, it) }
    } catch (e: Exception) {
        null
    }

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

    fun renameDocumentAndGet(doc: DocumentFile, newName: String): DocumentFile {
        val newUri = DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
        return DocumentFile.fromSingleUri(context, newUri ?: doc.uri)
            ?: throw SafIOException("renameDocument failed for ${doc.uri}")
    }

    fun renameDocument(doc: DocumentFile, newName: String) {
        DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
            ?: throw SafIOException("renameDocument failed for ${doc.uri}")
    }

    fun movePhysicalDocument(doc: DocumentFile, oldParent: DocumentFile, newParent: DocumentFile) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val movedUri = DocumentsContract.moveDocument(
                    context.contentResolver, doc.uri, oldParent.uri, newParent.uri
                )
                if (movedUri != null) return
            } catch (e: Exception) {
                // Fallback
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