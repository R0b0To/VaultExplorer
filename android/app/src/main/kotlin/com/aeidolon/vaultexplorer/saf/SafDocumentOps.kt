package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.documentfile.provider.CachedDocumentFile
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import com.aeidolon.vaultexplorer.VeLog

class SafIOException(message: String, cause: Throwable? = null) : Exception(message, cause)

class SafDocumentOps(private val context: Context) {
    private val dirListingCache = ConcurrentHashMap<String, MutableMap<String, DocumentFile>>()

    private fun cacheKey(folder: DocumentFile): String = folder.uri.toString()

    fun invalidate(folder: DocumentFile) {
        val key = cacheKey(folder)
        dirListingCache.remove(key)
    }

    fun invalidateAll() {
        dirListingCache.clear()
    }

    fun invalidateContainingParent(doc: DocumentFile) {
        val docUriStr = doc.uri.toString()
        for ((folderKey, childrenMap) in dirListingCache) {
            val matched = childrenMap.entries.any { it.value.uri.toString() == docUriStr }
            if (matched) {
                dirListingCache.remove(folderKey)
            }
        }
    }

    private fun getRawFile(doc: DocumentFile): File? {
        return com.aeidolon.vaultexplorer.RawFileResolver.getRawFile(context, doc)
    }

    private fun queryChildrenRaw(folder: DocumentFile): MutableMap<String, DocumentFile> {
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
                results[f.name] = cachedFile
            }
            return results
        }

        val docId = try {
            DocumentsContract.getDocumentId(folder.uri)
        } catch (e: Exception) {
            DocumentsContract.getTreeDocumentId(folder.uri)
        }
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            folder.uri,
            docId
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val results = LinkedHashMap<String, DocumentFile>()
        var cursor = try {
            context.contentResolver.query(childrenUri, projection, null, null, null)
        } catch (e: Exception) {
            VeLog.e("SafDocumentOps", e) { "queryChildrenRaw failed for ${folder.uri}" }
            throw SafIOException("Failed to query children of ${folder.uri}", e)
        } ?: throw SafIOException("ContentResolver query returned null for ${folder.uri}")

        var isLoading = cursor.extras?.getBoolean(DocumentsContract.EXTRA_LOADING, false) == true
        var retries = 0
        while (cursor.count == 0 && isLoading && retries < 3) {
            cursor.close()
            try { Thread.sleep(150) } catch (_: InterruptedException) { break }
            retries++
            cursor = try {
                context.contentResolver.query(childrenUri, projection, null, null, null) ?: break
            } catch (_: Exception) {
                break
            }
            isLoading = cursor.extras?.getBoolean(DocumentsContract.EXTRA_LOADING, false) == true
        }

        cursor.use { c ->
            val idIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (c.moveToNext()) {
                val childDocId = if (idIdx >= 0) c.getString(idIdx) else null ?: continue
                val docName = if (nameIdx >= 0) c.getString(nameIdx) else null ?: continue
                val mimeType = if (mimeIdx >= 0) c.getString(mimeIdx) else null
                val size = if (sizeIdx >= 0 && !c.isNull(sizeIdx)) c.getLong(sizeIdx) else 0L
                val lastModified = if (modIdx >= 0 && !c.isNull(modIdx)) c.getLong(modIdx) else 0L
                val childUri = DocumentsContract.buildDocumentUriUsingTree(folder.uri, childDocId)
                val baseFile = DocumentFile.fromSingleUri(context, childUri) ?: continue
                val isDir = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                val cachedFile = CachedDocumentFile(
                    delegate = baseFile,
                    cachedName = docName,
                    cachedIsDirectory = isDir,
                    cachedLength = size,
                    cachedLastModified = lastModified,
                )
                results[docName] = cachedFile
            }
        }
        return results
    }

    private fun listingFor(folder: DocumentFile): MutableMap<String, DocumentFile> {
        val key = cacheKey(folder)
        val existing = dirListingCache[key]
        if (existing != null && existing.isNotEmpty()) return existing
        val result = queryChildrenRaw(folder)
        if (result.isNotEmpty()) {
            dirListingCache[key] = result
        }
        return result
    }

    fun listChildren(folder: DocumentFile): List<DocumentFile> =
        try {
            listingFor(folder).values.toList()
        } catch (e: Exception) {
            emptyList()
        }

    fun childOf(folder: DocumentFile, name: String): DocumentFile? {
        // 1. Check in-memory listing cache (O(1) instant lookup)
        val cached = dirListingCache[cacheKey(folder)]
        if (cached != null) {
            return cached[name] ?: cached.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
        }

        // 2. Direct raw file check (O(1) direct filesystem stat if permitted)
        val rawDir = getRawFile(folder)
        if (rawDir != null && rawDir.exists() && rawDir.isDirectory) {
            val childFile = File(rawDir, name)
            if (childFile.exists()) {
                val baseFile = DocumentFile.fromFile(childFile)
                return CachedDocumentFile(
                    delegate = baseFile,
                    cachedName = childFile.name,
                    cachedIsDirectory = childFile.isDirectory,
                    cachedLength = if (childFile.isDirectory) 0L else childFile.length(),
                    cachedLastModified = childFile.lastModified(),
                )
            }
            return null
        }

        // 3. SAF Fallback: Query and populate dirListingCache ONCE, then return child from memory
        val listing = try {
            listingFor(folder)
        } catch (e: Exception) {
            return null
        }
        return listing[name] ?: listing.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
    }

    fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? = try {
        val rawParent = getRawFile(parent)
        if (rawParent != null && rawParent.exists()) {
            val newDir = File(rawParent, name)
            if (newDir.exists() || newDir.mkdirs()) {
                val baseFile = DocumentFile.fromFile(newDir)
                val cached = CachedDocumentFile(baseFile, name, cachedIsDirectory = true)
                dirListingCache[cacheKey(parent)]?.put(name, cached)
                cached
            } else null
        } else {
            val uri = DocumentsContract.createDocument(
                context.contentResolver,
                parent.uri,
                DocumentsContract.Document.MIME_TYPE_DIR,
                name
            )
            val effectiveUri = if (uri != null && !DocumentsContract.isTreeUri(uri) && DocumentsContract.isTreeUri(parent.uri)) {
                val docId = try { DocumentsContract.getDocumentId(uri) } catch (_: Exception) { null }
                if (docId != null) DocumentsContract.buildDocumentUriUsingTree(parent.uri, docId) else uri
            } else {
                uri
            }
            val created = effectiveUri?.let { DocumentFile.fromSingleUri(context, it) }
            if (created != null) {
                val cached = CachedDocumentFile(created, name, cachedIsDirectory = true)
                dirListingCache[cacheKey(parent)]?.put(name, cached)
                val actualName = created.name
                if (actualName != null && actualName != name) {
                    dirListingCache[cacheKey(parent)]?.put(actualName, cached)
                }
                cached
            } else null
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
            val baseFile = DocumentFile.fromFile(newFile)
            val cached = CachedDocumentFile(baseFile, name, cachedIsDirectory = false)
            dirListingCache[cacheKey(parent)]?.put(name, cached)
            cached
        } else {
            val uri = DocumentsContract.createDocument(context.contentResolver, parent.uri, mimeType, name)
            val effectiveUri = if (uri != null && !DocumentsContract.isTreeUri(uri) && DocumentsContract.isTreeUri(parent.uri)) {
                val docId = try { DocumentsContract.getDocumentId(uri) } catch (_: Exception) { null }
                if (docId != null) DocumentsContract.buildDocumentUriUsingTree(parent.uri, docId) else uri
            } else {
                uri
            }
            val created = effectiveUri?.let { DocumentFile.fromSingleUri(context, it) }
            if (created != null) {
                val cached = CachedDocumentFile(created, name, cachedIsDirectory = false)
                dirListingCache[cacheKey(parent)]?.put(name, cached)
                val actualName = created.name
                if (actualName != null && actualName != name) {
                    dirListingCache[cacheKey(parent)]?.put(actualName, cached)
                }
                cached
            } else null
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

    fun renameDocumentAndGet(doc: DocumentFile, newName: String, parent: DocumentFile? = null): DocumentFile {
        val rawFile = getRawFile(doc)
        if (rawFile != null && rawFile.exists()) {
            val parentFile = rawFile.parentFile
            val target = File(parentFile, newName)
            if (rawFile.renameTo(target)) {
                if (parentFile != null) {
                    invalidate(DocumentFile.fromFile(parentFile))
                }
                if (parent != null) {
                    invalidate(parent)
                }
                val baseFile = DocumentFile.fromFile(target)
                return CachedDocumentFile(baseFile, newName, cachedIsDirectory = target.isDirectory)
            }
        }
        val newUri = DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
            ?: throw SafIOException("renameDocument failed for ${doc.uri}")
        val effectiveUri = if (!DocumentsContract.isTreeUri(newUri) && DocumentsContract.isTreeUri(doc.uri)) {
            val docId = try { DocumentsContract.getDocumentId(newUri) } catch (_: Exception) { null }
            if (docId != null) DocumentsContract.buildDocumentUriUsingTree(doc.uri, docId) else newUri
        } else {
            newUri
        }
        val created = DocumentFile.fromSingleUri(context, effectiveUri)
            ?: throw SafIOException("renameDocument failed for ${doc.uri}")
        invalidate(doc)
        if (parent != null) {
            invalidate(parent)
        }
        invalidateContainingParent(doc)
        return CachedDocumentFile(created, newName, cachedIsDirectory = doc.isDirectory)
    }

    fun renameDocument(doc: DocumentFile, newName: String, parent: DocumentFile? = null) {
        renameDocumentAndGet(doc, newName, parent)
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
                    invalidateContainingParent(doc)
                    return
                }
            } catch (_: Exception) {}
        }
        copyDocumentRecursive(doc, newParent)
        deleteRecursively(doc)
        invalidate(oldParent)
        invalidate(newParent)
        invalidateContainingParent(doc)
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
            rawFile.parentFile?.let { invalidate(DocumentFile.fromFile(it)) }
            return
        }
        for (child in listChildren(folder)) {
            if (child.isDirectory) deleteRecursively(child)
            child.delete()
        }
        folder.delete()
        invalidate(folder)
        invalidateContainingParent(folder)
    }
}