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

/**
 * Common surface for physical document operations against a directory
 * vault's backing storage. Implemented by [SafDocumentOps] (operates
 * directly on the real SAF/raw tree) and by
 * [com.aeidolon.vaultexplorer.saf.MirroredSafDocumentOps] (operates on a
 * local mirror, syncing to the real tree -- see that class and
 * [com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator] for why). Callers
 * such as CryptomatorVaultTree/CryptomatorSession are written against this
 * interface so they work unmodified against either implementation; which
 * one gets constructed is decided once, at unlock time, based on whether
 * the vault's root URI resolves to a raw path (see RawFileResolver).
 */
interface VaultDocumentOps {
    fun invalidate(folder: DocumentFile)
    fun invalidateAll()
    fun invalidateContainingParent(doc: DocumentFile)
    fun listChildren(folder: DocumentFile): List<DocumentFile>
    fun childOf(folder: DocumentFile, name: String): DocumentFile?
    fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile?
    fun createFileSafe(parent: DocumentFile, mimeType: String, name: String): DocumentFile?
    fun readWhole(file: DocumentFile): ByteArray
    fun writeWhole(file: DocumentFile, bytes: ByteArray)
    fun renameDocumentAndGet(doc: DocumentFile, newName: String, parent: DocumentFile? = null): DocumentFile
    fun renameDocument(doc: DocumentFile, newName: String, parent: DocumentFile? = null)
    fun movePhysicalDocument(doc: DocumentFile, oldParent: DocumentFile, newParent: DocumentFile)
    fun copyDocumentRecursive(source: DocumentFile, targetParent: DocumentFile): DocumentFile
    fun deleteRecursively(folder: DocumentFile)

    /**
     * Hook for callers that read a physical file's bytes WITHOUT going
     * through [readWhole] -- namely ChunkedFileEngine, which resolves the
     * physical DocumentFile itself via RawFileResolver and does raw
     * FileInputStream/ParcelFileDescriptor I/O for performance, rather than
     * reading a whole file into memory. For a mirrored vault that raw
     * resolve always succeeds against the LOCAL MIRROR file, so without
     * this hook the engine would silently read whatever's in the mirror
     * (possibly an empty not-yet-pulled placeholder) and the lazy-pull in
     * MirrorSyncCoordinator would never run. Call this before handing a
     * physical file to any such raw-I/O reader. No-op for the plain
     * (non-mirrored) implementation, whose files are already the real
     * ones.
     */
    fun ensureContentPulled(file: DocumentFile) {}

    /**
     * Mirror-only: resolves [file] for a raw-I/O read, returning the
     * [DocumentFile] the caller should actually open for byte-level
     * access. For a mirrored vault with a large, not-yet-cached file
     * this returns the REAL SAF document (so the caller can stream
     * directly from it while a background pull warms the local cache),
     * instead of blocking on [ensureContentPulled]'s synchronous
     * full-file copy. Returns `null` when not applicable (non-mirrored
     * implementation, or the mirror already has the content); callers
     * should fall back to [ensureContentPulled] + the mirror file in
     * that case.
     */
    fun resolveForRead(
        file: DocumentFile,
        onBackgroundPullPhase: ((com.aeidolon.vaultexplorer.saf.MirrorPullEvents.Phase) -> Unit)? = null,
    ): DocumentFile? { return null }

    /**
     * Mirror-only counterpart to [ensureContentPulled], for callers that
     * WRITE a physical file's bytes without going through [writeWhole] --
     * same ChunkedFileEngine raw-I/O paths as above (writeFileChunk,
     * writeBackFile, writeBackStream all write straight to whatever
     * RawFileResolver resolves, i.e. the local mirror file). Call this
     * once a raw-I/O writer has finished writing new content to a physical
     * file, so the result gets eagerly replicated to the real SAF tree
     * the same way writeWhole's callers already get for free. No-op for
     * the plain (non-mirrored) implementation.
     */
    fun pushContentWrite(file: DocumentFile) {}

    /**
     * Mirror-only: call BEFORE handing [file] to a raw-I/O writer (i.e.
     * from getOrCreatePhysicalFileForWrite, for both a brand-new file and
     * an existing one about to be overwritten). Marks the mirror file as
     * having a local write in flight, so a directory re-listing that
     * happens to run before the matching [pushContentWrite] (e.g. from an
     * unrelated setLastModifiedTime call during a batched import) won't
     * mistake the not-yet-pushed mirror content for a stale copy of the
     * (still old/empty) real file and delete it -- see
     * MirrorSyncCoordinator.markPendingLocalWrite for the full story.
     * No-op for the plain (non-mirrored) implementation.
     */
    fun markWritePending(file: DocumentFile) {}
}

class SafDocumentOps(private val context: Context) : VaultDocumentOps {
    private val dirListingCache = ConcurrentHashMap<String, MutableMap<String, DocumentFile>>()

    private fun cacheKey(folder: DocumentFile): String = folder.uri.toString()

    override fun invalidate(folder: DocumentFile) {
        val key = cacheKey(folder)
        dirListingCache.remove(key)
    }

    override fun invalidateAll() {
        dirListingCache.clear()
    }

    override fun invalidateContainingParent(doc: DocumentFile) {
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
                    // Deliberately NOT cachedLength = f.length() here. A
                    // snapshotted length is wrong the moment the file's
                    // bytes change on disk after this listing without a
                    // fresh listing happening -- which is exactly what a
                    // mirrored vault does on purpose: pullListingIfMissing
                    // creates zero-byte placeholder files for every child
                    // up front (see MirrorSyncCoordinator), and their real
                    // content is pulled lazily afterward, onto the SAME
                    // underlying file, through this SAME DocumentFile
                    // handle. A cached 0 here would then permanently report
                    // as 0 (CachedDocumentFile.length() prefers the cached
                    // value over asking the delegate), even once real bytes
                    // land on disk -- CryptomatorSession.getFileSize reads
                    // exactly this field, so a stale 0 there silently
                    // reports (and can make callers treat) every lazily-
                    // pulled file as empty/corrupted after every lock ->
                    // unlock cycle. Leaving cachedLength null makes
                    // .length() delegate live to the real file's current
                    // size instead, which costs nothing for a raw File stat
                    // and is correct regardless of when its content lands
                    // relative to when it was listed.
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

    override fun listChildren(folder: DocumentFile): List<DocumentFile> =
        try {
            listingFor(folder).values.toList()
        } catch (e: Exception) {
            emptyList()
        }

    override fun childOf(folder: DocumentFile, name: String): DocumentFile? {
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
                // No cachedLength here either -- see the matching note in
                // queryChildrenRaw above; same reasoning, same bug shape if
                // childFile is a not-yet-content-pulled mirror placeholder.
                return CachedDocumentFile(
                    delegate = baseFile,
                    cachedName = childFile.name,
                    cachedIsDirectory = childFile.isDirectory,
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

    override fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? = try {
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

    override fun createFileSafe(parent: DocumentFile, mimeType: String, name: String): DocumentFile? = try {
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

    override fun readWhole(file: DocumentFile): ByteArray {
        val rawFile = getRawFile(file)
        if (rawFile != null && rawFile.exists() && rawFile.isFile) {
            return rawFile.readBytes()
        }
        return context.contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            ?: throw SafIOException("Could not open ${file.uri} for reading")
    }

    override fun writeWhole(file: DocumentFile, bytes: ByteArray) {
        val rawFile = getRawFile(file)
        if (rawFile != null) {
            // Stage into a sibling temp file and only replace the
            // original via atomic rename once the FULL write has
            // succeeded, rather than writing directly into `rawFile`.
            // File.writeBytes (and the FileOutputStream(File) constructor
            // it delegates to) truncates the target to 0 bytes the
            // instant it's opened, before any of `bytes` is written -- if
            // rawFile already held real content and this write fails
            // partway (disk full, process killed mid-write, permission
            // revoked), that content is destroyed with nothing valid
            // written in its place. Same class of bug as CVE-2023-21036
            // ("aCropalypse"): truncate-then-write is not atomic with
            // itself. Staging costs one extra rename even for a brand-new,
            // still-empty file, which is negligible; unconditional staging
            // here is simpler and safer than trying to detect "this file
            // has no prior content worth protecting" from inside a
            // function that isn't told which case it's in (contrast
            // MirrorSyncCoordinator.pushFileWrite, which reserves this for
            // only its existing-file branch because it DOES know, via
            // whether it just created the target itself).
            val stagingTmp = File(rawFile.parentFile, rawFile.name + ".writing")
            try {
                stagingTmp.writeBytes(bytes)
                if (!stagingTmp.renameTo(rawFile)) {
                    throw SafIOException("writeWhole: could not finalize write to ${rawFile.absolutePath} (staging rename failed)")
                }
            } finally {
                stagingTmp.delete() // no-op once the rename above has already moved it into place
            }
            return
        }
        // No raw File available (a genuine content://-only provider with
        // no filesystem escape hatch): no rename to stage through, so this
        // still uses the direct truncating write -- same risk as before
        // this fix for that specific provider shape. A real, currently-
        // unaddressed gap for that case, called out explicitly rather than
        // silently carried forward as if this fix covered it too.
        context.contentResolver.openOutputStream(file.uri, "wt")?.use { it.write(bytes) }
            ?: throw SafIOException("Could not open ${file.uri} for writing")
    }

    override fun renameDocumentAndGet(doc: DocumentFile, newName: String, parent: DocumentFile?): DocumentFile {
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

    override fun renameDocument(doc: DocumentFile, newName: String, parent: DocumentFile?) {
    renameDocumentAndGet(doc, newName, parent)
}

    override fun movePhysicalDocument(doc: DocumentFile, oldParent: DocumentFile, newParent: DocumentFile) {
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

    override fun copyDocumentRecursive(source: DocumentFile, targetParent: DocumentFile): DocumentFile {
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

    override fun deleteRecursively(folder: DocumentFile) {
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