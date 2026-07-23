package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.os.Build
import android.provider.DocumentsContract
import androidx.documentfile.provider.CachedDocumentFile
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.util.concurrent.ConcurrentHashMap

class SafIOException(message: String, cause: Throwable? = null) : Exception(message, cause)

class SafDocumentOps(private val context: Context) {
    private val dirListingCache = ConcurrentHashMap<String, MutableMap<String, DocumentFile>>()

    private fun cacheKey(folder: DocumentFile): String = folder.uri.toString()

    fun invalidate(folder: DocumentFile) {
        dirListingCache.remove(cacheKey(folder))
    }

    fun invalidateAll() {
        dirListingCache.clear()
    }

    private fun getRawFile(doc: DocumentFile): File? {
        return UriToPath.getRawFile(context, doc.uri)
    }

    private fun queryChildrenRaw(folder: DocumentFile): MutableMap<String, DocumentFile> {
        // --- DIRECT FILE SPEEDUP FOR CRYPTOMATOR, GOCRYPTFS & CRYFS ---
        val rawDir = getRawFile(folder)
        if (rawDir != null && rawDir.exists() && rawDir.isDirectory) {
            val results = LinkedHashMap<String, DocumentFile>()
            val files = rawDir.listFiles() ?: emptyArray()
            for (f in files) {
                val baseFile = DocumentFile.fromFile(f)
                val cachedFile = CachedDocumentFile(
                    delegate = baseFile,
                    cachedName = f.name,
                    cachedIsDirectory = f.isDirectory,
                    cachedLength = if (f.isDirectory) 0L else f.length(),
                    cachedLastModified = f.lastModified(),
                )
                results[f.name.lowercase()] = cachedFile
            }
            return results
        }

        // --- SAF FALLBACK ---
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            folder.uri,
            DocumentsContract.getDocumentId(folder.uri)
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val results = LinkedHashMap<String, DocumentFile>()
        try {
            context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val sizeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                val modIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                while (cursor.moveToNext()) {
                    val docId = if (idIdx >= 0) cursor.getString(idIdx) else null ?: continue
                    val docName = if (nameIdx >= 0) cursor.getString(nameIdx) else null ?: continue
                    val mimeType = if (mimeIdx >= 0) cursor.getString(mimeIdx) else null
                    val size = if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) cursor.getLong(sizeIdx) else 0L
                    val lastModified = if (modIdx >= 0 && !cursor.isNull(modIdx)) cursor.getLong(modIdx) else 0L
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(folder.uri, docId)
                    val baseFile = DocumentFile.fromSingleUri(context, childUri) ?: continue
                    val isDir = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                    val cachedFile = CachedDocumentFile(
                        delegate = baseFile,
                        cachedName = docName,
                        cachedIsDirectory = isDir,
                        cachedLength = size,
                        cachedLastModified = lastModified,
                    )
                    results[docName.lowercase()] = cachedFile
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("SafDocumentOps", "queryChildrenRaw failed for ${folder.uri}", e)
        }
        return results
    }

    private fun listingFor(folder: DocumentFile): MutableMap<String, DocumentFile> =
        dirListingCache.getOrPut(cacheKey(folder)) { queryChildrenRaw(folder) }

    fun listChildren(folder: DocumentFile): List<DocumentFile> =
        listingFor(folder).values.toList()

    fun childOf(folder: DocumentFile, name: String): DocumentFile? =
        listingFor(folder)[name.lowercase()]

    fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? = try {
        val rawParent = getRawFile(parent)
        if (rawParent != null && rawParent.exists()) {
            val newDir = File(rawParent, name)
            if (newDir.exists() || newDir.mkdirs()) {
                invalidate(parent)
                val baseFile = DocumentFile.fromFile(newDir)
                CachedDocumentFile(baseFile, name, cachedIsDirectory = true)
            } else null
        } else {
            val uri = DocumentsContract.createDocument(
                context.contentResolver,
                parent.uri,
                DocumentsContract.Document.MIME_TYPE_DIR,
                name
            )
            val created = uri?.let { DocumentFile.fromSingleUri(context, it) }
            invalidate(parent)
            created?.let { CachedDocumentFile(it, name, cachedIsDirectory = true) }
        }
    } catch (e: Exception) {
        null
    }

    fun createFileSafe(parent: DocumentFile, mimeType: String, name: String): DocumentFile? = try {
        val rawParent = getRawFile(parent)
        if (rawParent != null && rawParent.exists()) {
            val newFile = File(rawParent, name)
            if (!newFile.exists()) {
                newFile.createNewFile()
            }
            invalidate(parent)
            val baseFile = DocumentFile.fromFile(newFile)
            CachedDocumentFile(baseFile, name, cachedIsDirectory = false)
        } else {
            val uri = DocumentsContract.createDocument(context.contentResolver, parent.uri, mimeType, name)
            val created = uri?.let { DocumentFile.fromSingleUri(context, it) }
            invalidate(parent)
            created?.let { CachedDocumentFile(it, name, cachedIsDirectory = false) }
        }
    } catch (e: Exception) {
        null
    }

    fun readWhole(file: DocumentFile): ByteArray {
        val rawFile = getRawFile(file)
        if (rawFile != null && rawFile.exists() && rawFile.isFile) {
            return rawFile.readBytes()
        }
        return context.contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            ?: throw SafIOException("Could not open ${file.uri} for reading")
    }

    fun writeWhole(file: DocumentFile, bytes: ByteArray) {
        val rawFile = getRawFile(file)
        if (rawFile != null) {
            rawFile.writeBytes(bytes)
            return
        }
        context.contentResolver.openOutputStream(file.uri, "wt")?.use { it.write(bytes) }
            ?: throw SafIOException("Could not open ${file.uri} for writing")
    }

    fun renameDocumentAndGet(doc: DocumentFile, newName: String): DocumentFile {
        val rawFile = getRawFile(doc)
        if (rawFile != null && rawFile.exists()) {
            val target = File(rawFile.parentFile, newName)
            if (rawFile.renameTo(target)) {
                val baseFile = DocumentFile.fromFile(target)
                return CachedDocumentFile(baseFile, newName)
            }
        }
        val newUri = DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
        val created = DocumentFile.fromSingleUri(context, newUri ?: doc.uri)
            ?: throw SafIOException("renameDocument failed for ${doc.uri}")
        return CachedDocumentFile(created, newName)
    }

    fun renameDocument(doc: DocumentFile, newName: String) {
        val rawFile = getRawFile(doc)
        if (rawFile != null && rawFile.exists()) {
            val target = File(rawFile.parentFile, newName)
            if (rawFile.renameTo(target)) return
        }
        DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
            ?: throw SafIOException("renameDocument failed for ${doc.uri}")
    }

    fun movePhysicalDocument(doc: DocumentFile, oldParent: DocumentFile, newParent: DocumentFile) {
        val rawDoc = getRawFile(doc)
        val rawNewParent = getRawFile(newParent)
        if (rawDoc != null && rawNewParent != null && rawDoc.exists() && rawNewParent.exists()) {
            val target = File(rawNewParent, rawDoc.name)
            if (rawDoc.renameTo(target)) {
                invalidate(oldParent)
                invalidate(newParent)
                return
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val movedUri = DocumentsContract.moveDocument(
                    context.contentResolver, doc.uri, oldParent.uri, newParent.uri
                )
                if (movedUri != null) {
                    invalidate(oldParent)
                    invalidate(newParent)
                    return
                }
            } catch (_: Exception) {}
        }
        copyDocumentRecursive(doc, newParent)
        deleteRecursively(doc)
        invalidate(oldParent)
        invalidate(newParent)
    }

    fun copyDocumentRecursive(source: DocumentFile, targetParent: DocumentFile): DocumentFile {
        val name = source.name ?: throw SafIOException("Source document has no name")
        val rawSource = getRawFile(source)
        val rawTargetParent = getRawFile(targetParent)

        if (rawSource != null && rawTargetParent != null && rawSource.exists() && rawTargetParent.exists()) {
            val target = File(rawTargetParent, name)
            if (rawSource.isDirectory) {
                rawSource.copyRecursively(target, overwrite = true)
            } else {
                rawSource.copyTo(target, overwrite = true)
            }
            val baseFile = DocumentFile.fromFile(target)
            return CachedDocumentFile(baseFile, name, cachedIsDirectory = rawSource.isDirectory)
        }

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
        val rawFile = getRawFile(folder)
        if (rawFile != null && rawFile.exists()) {
            rawFile.deleteRecursively()
            invalidate(folder)
            return
        }

        for (child in listChildren(folder)) {
            if (child.isDirectory) deleteRecursively(child)
            child.delete()
        }
        folder.delete()
        invalidate(folder)
    }
}