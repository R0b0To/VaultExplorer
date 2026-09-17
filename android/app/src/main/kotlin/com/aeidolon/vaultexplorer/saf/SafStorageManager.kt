package com.aeidolon.vaultexplorer.saf

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Point
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import androidx.exifinterface.media.ExifInterface
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.VeLog
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.ConcurrentHashMap

data class SafEntry(
    val name: String,
    val isDir: Boolean,
    val size: Long,
    val lastModified: Long,
    val docId: String,
    val mimeType: String,
)

/**
 * High-performance SAF (Storage Access Framework) engine modeled after MaterialFiles'
 * DocumentResolver and DocumentFileSystemProvider.
 *
 * Provides:
 * - Thread-safe document ID resolution with O(1) path caching
 * - Fast single-pass cursor directory listings
 * - ExternalStorageProvider direct document-ID optimizations and Android/data / Android/obb hacks
 * - Seekable FileChannel random-access chunk reads and writes
 * - Recursive directory deletion
 * - Efficient thumbnail generation for both images and videos
 * - Direct intent-based external app opening and sharing
 * - Auto-discovery of mounted storage volumes (Internal, SD Card, USB OTG)
 */
class SafStorageManager(private val context: Context) {

    companion object {
        private const val TAG = "SafStorageManager"
        private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
        private const val DOCUMENT_ID_PRIMARY = "primary"
        private const val DOCUMENT_ID_PRIMARY_ANDROID = "primary:Android"
        private const val DOCUMENT_ID_PRIMARY_ANDROID_DATA = "primary:Android/data"
        private const val DOCUMENT_ID_PRIMARY_ANDROID_OBB = "primary:Android/obb"

        private val PROJECTION_CHILDREN = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS,
        )

        private val PROJECTION_DOCUMENT = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
    }

    // Cache: "$treeUri|$cleanPath" -> documentId
    private val pathDocumentIdCache = ConcurrentHashMap<String, String>()

    // Cache: "$treeUri|$cleanPath" -> List<SafEntry>
    private val dirListingCache = ConcurrentHashMap<String, List<SafEntry>>()

    private fun normalizePath(path: String): String =
        path.trim().trim('/').replace('\\', '/')

    private fun cacheKey(treeUri: Uri, cleanPath: String): String =
        "${treeUri}|$cleanPath"

    fun invalidateCache(treeUri: Uri, relativePath: String? = null) {
        if (relativePath == null) {
            val prefix = "${treeUri}|"
            pathDocumentIdCache.keys.removeIf { it.startsWith(prefix) }
            dirListingCache.keys.removeIf { it.startsWith(prefix) }
        } else {
            val clean = normalizePath(relativePath)
            pathDocumentIdCache.remove(cacheKey(treeUri, clean))
            dirListingCache.remove(cacheKey(treeUri, clean))
            val parentPath = if (clean.contains('/')) clean.substringBeforeLast('/') else ""
            dirListingCache.remove(cacheKey(treeUri, parentPath))
        }
    }

    /**
     * Resolves the Document ID for a relative path under a treeUri.
     */
    fun resolveDocumentId(treeUri: Uri, relativePath: String): String? {
        val clean = normalizePath(relativePath)
        if (clean.isEmpty()) {
            return try {
                if (DocumentsContract.isTreeUri(treeUri)) {
                    DocumentsContract.getTreeDocumentId(treeUri)
                } else {
                    DocumentsContract.getDocumentId(treeUri)
                }
            } catch (e: Exception) {
                VeLog.w(TAG) { "Failed to get tree document ID for $treeUri: ${e.message}" }
                null
            }
        }

        val key = cacheKey(treeUri, clean)
        pathDocumentIdCache[key]?.let { return it }

        // Optimization for ExternalStorageProvider: IDs are of form "rootId:subpath"
        if (treeUri.authority == EXTERNAL_STORAGE_AUTHORITY) {
            val rootDocId = try {
                DocumentsContract.getTreeDocumentId(treeUri)
            } catch (_: Exception) { null }
            if (rootDocId != null) {
                val rootPrefix = if (rootDocId.endsWith(":")) rootDocId else "$rootDocId:"
                val candidateDocId = "$rootPrefix$clean"
                val candidateUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, candidateDocId)
                if (documentExists(candidateUri)) {
                    pathDocumentIdCache[key] = candidateDocId
                    return candidateDocId
                }
            }
        }

        // Segment-by-segment lookup with caching
        val segments = clean.split('/')
        var currentPath = ""
        var currentDocId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (_: Exception) {
            return null
        }

        for (segment in segments) {
            if (segment.isEmpty()) continue
            val nextPath = if (currentPath.isEmpty()) segment else "$currentPath/$segment"
            val cachedNext = pathDocumentIdCache[cacheKey(treeUri, nextPath)]
            if (cachedNext != null) {
                currentPath = nextPath
                currentDocId = cachedNext
                continue
            }

            // Query children of current directory
            val children = queryChildrenInternal(treeUri, currentDocId, currentPath)
            val matched = children.firstOrNull { it.name.equals(segment, ignoreCase = true) }
            if (matched == null) {
                return null
            }
            currentPath = nextPath
            currentDocId = matched.docId
            pathDocumentIdCache[cacheKey(treeUri, currentPath)] = currentDocId
        }

        pathDocumentIdCache[key] = currentDocId
        return currentDocId
    }

    fun getDocumentUri(treeUri: Uri, relativePath: String): Uri? {
        val docId = resolveDocumentId(treeUri, relativePath) ?: return null
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
    }

    /**
     * Converts a concatenated tree-path string (e.g. "content://.../tree/rootId/subfolder/file.ext")
     * into a valid Android SAF Document URI containing "/document/<docId>".
     */
    fun resolveDocumentUriFromTreePath(pathOrUri: String): Uri? {
        if (!pathOrUri.startsWith("content://")) return null
        val parsed = Uri.parse(pathOrUri)

        // 1. If already a valid document URI (has /document/), return as-is
        if (DocumentsContract.isDocumentUri(context, parsed)) {
            return parsed
        }

        // 2. Separate base tree URI from the appended relative sub-path
        val path = parsed.encodedPath ?: return null
        val treeMarker = "/tree/"
        val treeIdx = path.indexOf(treeMarker)
        if (treeIdx == -1) return parsed

        val afterTree = path.substring(treeIdx + treeMarker.length)
        val slashIdx = afterTree.indexOf('/')

        if (slashIdx == -1) {
            // Root treeUri itself
            return parsed
        }

        val treeDocIdEncoded = afterTree.substring(0, slashIdx)
        val relPathEncoded = afterTree.substring(slashIdx + 1)
        val relPath = Uri.decode(relPathEncoded)

        val baseTreeUri = Uri.Builder()
            .scheme(parsed.scheme)
            .encodedAuthority(parsed.encodedAuthority)
            .appendPath("tree")
            .appendEncodedPath(treeDocIdEncoded)
            .build()

        return getDocumentUri(baseTreeUri, relPath)
    }

    private fun documentExists(uri: Uri): Boolean {
        return try {
            context.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use {
                it.moveToFirst()
            } ?: false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Lists directory contents in a single cursor pass with full metadata.
     */
    fun listDirectory(treeUri: Uri, relativePath: String): List<SafEntry> {
        val clean = normalizePath(relativePath)
        val docId = resolveDocumentId(treeUri, clean) ?: return emptyList()
        return queryChildrenInternal(treeUri, docId, clean)
    }

    private fun queryChildrenInternal(treeUri: Uri, parentDocId: String, currentPath: String): List<SafEntry> {
        val cached = dirListingCache[cacheKey(treeUri, currentPath)]
        if (cached != null && cached.isNotEmpty()) {
            return cached
        }

      val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        val entries = mutableListOf<SafEntry>()

        // Use null projection first (MaterialFiles / DocumentsUI standard for cloud providers like Google Drive)
        var cursor = try {
            context.contentResolver.query(childrenUri, null, null, null, null)
        } catch (_: Exception) {
            try {
                context.contentResolver.query(childrenUri, PROJECTION_CHILDREN, null, null, null)
            } catch (e: Exception) {
                VeLog.w(TAG) { "queryChildren failed for $childrenUri: ${e.message}" }
                null
            }
        } ?: return emptyList()

        // Cloud provider handling: wait for EXTRA_LOADING to complete network fetch (e.g. Google Drive)
        var isLoading = cursor.extras?.getBoolean(DocumentsContract.EXTRA_LOADING, false) == true
        if (cursor.count == 0 && isLoading) {
            val latch = java.util.concurrent.CountDownLatch(1)
            val observer = object : android.database.ContentObserver(android.os.Handler(android.os.Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) {
                    latch.countDown()
                }
            }
            try {
                cursor.registerContentObserver(observer)
                latch.await(4000, java.util.concurrent.TimeUnit.MILLISECONDS)
            } catch (_: Exception) {
            } finally {
                runCatching { cursor.unregisterContentObserver(observer) }
            }
            cursor.close()
            cursor = try {
                context.contentResolver.query(childrenUri, null, null, null, null)
            } catch (_: Exception) {
                null
            } ?: return emptyList()
        }

        cursor.use { c ->
            val idIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)

            while (c.moveToNext()) {
                val childId = if (idIdx >= 0) c.getString(idIdx) else null ?: continue
                val name = if (nameIdx >= 0) c.getString(nameIdx) else null ?: continue
                val mime = if (mimeIdx >= 0) c.getString(mimeIdx) else null ?: ""
                val size = if (sizeIdx >= 0 && !c.isNull(sizeIdx)) c.getLong(sizeIdx) else 0L
                val mod = if (modIdx >= 0 && !c.isNull(modIdx)) c.getLong(modIdx) else 0L
                val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR

                val childPath = if (currentPath.isEmpty()) name else "$currentPath/$name"
                pathDocumentIdCache[cacheKey(treeUri, childPath)] = childId

                entries.add(
                    SafEntry(
                        name = name,
                        isDir = isDir,
                        size = if (isDir) 0L else size,
                        lastModified = mod / 1000L,
                        docId = childId,
                        mimeType = mime,
                    )
                )
            }
        }

        // MaterialFiles Hack: On Android 11+, ExternalStorageProvider omits Android/data and Android/obb
        // from the Android directory. Inject them if they exist and are missing.
        if (treeUri.authority == EXTERNAL_STORAGE_AUTHORITY &&
            (parentDocId == DOCUMENT_ID_PRIMARY_ANDROID || parentDocId.endsWith(":Android"))
        ) {
            injectAndroidSpecialFolders(treeUri, parentDocId, currentPath, entries)
        }

        if (entries.isNotEmpty()) {
            dirListingCache[cacheKey(treeUri, currentPath)] = entries
        }
        return entries
    }

    private fun injectAndroidSpecialFolders(
        treeUri: Uri,
        parentDocId: String,
        currentPath: String,
        entries: MutableList<SafEntry>
    ) {
        val rootPrefix = parentDocId.substringBefore(":")
        val hasData = entries.any { it.name.equals("data", ignoreCase = true) }
        val hasObb = entries.any { it.name.equals("obb", ignoreCase = true) }

        if (!hasData) {
            val dataDocId = "$rootPrefix:Android/data"
            val dataUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, dataDocId)
            if (documentExists(dataUri)) {
                val childPath = if (currentPath.isEmpty()) "data" else "$currentPath/data"
                pathDocumentIdCache[cacheKey(treeUri, childPath)] = dataDocId
                entries.add(SafEntry("data", true, 0L, 0L, dataDocId, DocumentsContract.Document.MIME_TYPE_DIR))
            }
        }
        if (!hasObb) {
            val obbDocId = "$rootPrefix:Android/obb"
            val obbUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, obbDocId)
            if (documentExists(obbUri)) {
                val childPath = if (currentPath.isEmpty()) "obb" else "$currentPath/obb"
                pathDocumentIdCache[cacheKey(treeUri, childPath)] = obbDocId
                entries.add(SafEntry("obb", true, 0L, 0L, obbDocId, DocumentsContract.Document.MIME_TYPE_DIR))
            }
        }
    }

    fun getFileSize(treeUri: Uri, relativePath: String): Long {
        val docUri = getDocumentUri(treeUri, relativePath) ?: return -1L
        return try {
            context.contentResolver.query(docUri, arrayOf(DocumentsContract.Document.COLUMN_SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                    if (idx >= 0 && !c.isNull(idx)) c.getLong(idx) else 0L
                } else -1L
            } ?: -1L
        } catch (_: Exception) {
            -1L
        }
    }

    /**
     * Reads a chunk using seekable FileChannel random access where possible.
     */
    fun readFileChunk(treeUri: Uri, relativePath: String, offset: Long, length: Int): ByteArray? {
        val docUri = getDocumentUri(treeUri, relativePath) ?: return null
        return try {
            val pfd = context.contentResolver.openFileDescriptor(docUri, "r")
            if (pfd != null) {
                pfd.use { descriptor ->
                    FileInputStream(descriptor.fileDescriptor).use { fis ->
                        val channel = fis.channel
                        channel.position(offset)
                        val bytes = ByteArray(length)
                        val buffer = ByteBuffer.wrap(bytes)
                        var totalRead = 0
                        while (totalRead < length) {
                            val r = channel.read(buffer)
                            if (r <= 0) break
                            totalRead += r
                        }
                        if (totalRead == length) bytes else bytes.copyOf(totalRead)
                    }
                }
            } else {
                context.contentResolver.openInputStream(docUri)?.use { input ->
                    if (offset > 0) {
                        var skipped = 0L
                        while (skipped < offset) {
                            val s = input.skip(offset - skipped)
                            if (s <= 0) break
                            skipped += s
                        }
                    }
                    val buf = ByteArray(length)
                    var totalRead = 0
                    while (totalRead < length) {
                        val r = input.read(buf, totalRead, length - totalRead)
                        if (r == -1) break
                        totalRead += r
                    }
                    if (totalRead == length) buf else buf.copyOf(totalRead)
                }
            }
        } catch (t: Throwable) {
            VeLog.w(TAG) { "readFileChunk error for $relativePath (offset=$offset, len=$length): ${t.message}" }
            if (t is OutOfMemoryError) {
                System.gc()
            }
            null
        }
    }

    /**
     * Writes a chunk using seekable FileChannel random access.
     */
    fun writeFileChunk(treeUri: Uri, relativePath: String, offset: Long, data: ByteArray): Boolean {
        var docUri = getDocumentUri(treeUri, relativePath)
        if (docUri == null) {
            // File does not exist yet; create it first
            if (!createFile(treeUri, relativePath)) {
                return false
            }
            docUri = getDocumentUri(treeUri, relativePath) ?: return false
        }

        return try {
            val mode = if (offset == 0L && data.isEmpty()) "wt" else "rw"
            val pfd = context.contentResolver.openFileDescriptor(docUri, mode)
                ?: context.contentResolver.openFileDescriptor(docUri, "wa")
                ?: return false

            pfd.use { descriptor ->
                FileOutputStream(descriptor.fileDescriptor).use { fos ->
                    val channel = fos.channel
                    channel.position(offset)
                    channel.write(ByteBuffer.wrap(data))
                    channel.force(true)
                }
            }
            invalidateCache(treeUri, relativePath)
            true
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "writeFileChunk failed for $relativePath at offset $offset" }
            false
        }
    }

    fun createFile(treeUri: Uri, relativePath: String, mimeType: String? = null): Boolean {
        val clean = normalizePath(relativePath)
        val parentPath = if (clean.contains('/')) clean.substringBeforeLast('/') else ""
        val fileName = if (clean.contains('/')) clean.substringAfterLast('/') else clean
        val parentUri = getDocumentUri(treeUri, parentPath) ?: return false
        val mime = mimeType ?: MimeTypeHelper.getMimeType(fileName)

        return try {
            val created = DocumentsContract.createDocument(context.contentResolver, parentUri, mime, fileName)
            if (created != null) {
                invalidateCache(treeUri, parentPath)
                val docId = DocumentsContract.getDocumentId(created)
                pathDocumentIdCache[cacheKey(treeUri, clean)] = docId
                true
            } else {
                false
            }
        } catch (e: Exception) {
            VeLog.w(TAG) { "createFile failed for $relativePath: ${e.message}" }
            false
        }
    }

    fun createDirectory(treeUri: Uri, parentPath: String, dirName: String): Boolean {
        val cleanParent = normalizePath(parentPath)
        val parentUri = getDocumentUri(treeUri, cleanParent) ?: return false

        return try {
            val created = DocumentsContract.createDocument(
                context.contentResolver,
                parentUri,
                DocumentsContract.Document.MIME_TYPE_DIR,
                dirName
            )
            if (created != null) {
                invalidateCache(treeUri, cleanParent)
                val newDirPath = if (cleanParent.isEmpty()) dirName else "$cleanParent/$dirName"
                val docId = DocumentsContract.getDocumentId(created)
                pathDocumentIdCache[cacheKey(treeUri, newDirPath)] = docId
                true
            } else {
                false
            }
        } catch (e: Exception) {
            VeLog.w(TAG) { "createDirectory failed for $dirName in $parentPath: ${e.message}" }
            false
        }
    }

    fun renameFile(treeUri: Uri, relativePath: String, newName: String): Boolean {
        val clean = normalizePath(relativePath)
        val docUri = getDocumentUri(treeUri, clean) ?: return false

        return try {
            val renamedUri = DocumentsContract.renameDocument(context.contentResolver, docUri, newName)
            if (renamedUri != null) {
                invalidateCache(treeUri, clean)
                val parentPath = if (clean.contains('/')) clean.substringBeforeLast('/') else ""
                val newPath = if (parentPath.isEmpty()) newName else "$parentPath/$newName"
                val newDocId = DocumentsContract.getDocumentId(renamedUri)
                pathDocumentIdCache[cacheKey(treeUri, newPath)] = newDocId
                true
            } else {
                false
            }
        } catch (e: Exception) {
            VeLog.w(TAG) { "renameFile failed for $relativePath: ${e.message}" }
            false
        }
    }

    fun deleteRecursively(treeUri: Uri, relativePath: String): Boolean {
        val clean = normalizePath(relativePath)
        val docId = resolveDocumentId(treeUri, clean) ?: return false
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)

        // Check if directory
        val isDir = try {
            context.contentResolver.query(docUri, arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    idx >= 0 && c.getString(idx) == DocumentsContract.Document.MIME_TYPE_DIR
                } else false
            } ?: false
        } catch (_: Exception) { false }

        if (isDir) {
            val children = listDirectory(treeUri, clean)
            for (child in children) {
                val childPath = if (clean.isEmpty()) child.name else "$clean/${child.name}"
                deleteRecursively(treeUri, childPath)
            }
        }

        return try {
            val deleted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val parentPath = if (clean.contains('/')) clean.substringBeforeLast('/') else ""
                val parentUri = getDocumentUri(treeUri, parentPath)
                if (parentUri != null) {
                    try {
                        DocumentsContract.removeDocument(context.contentResolver, docUri, parentUri)
                    } catch (_: UnsupportedOperationException) {
                        DocumentsContract.deleteDocument(context.contentResolver, docUri)
                    }
                } else {
                    DocumentsContract.deleteDocument(context.contentResolver, docUri)
                }
            } else {
                DocumentsContract.deleteDocument(context.contentResolver, docUri)
            }
            invalidateCache(treeUri, clean)
            deleted
        } catch (e: Exception) {
            VeLog.w(TAG) { "deleteRecursively failed for $relativePath: ${e.message}" }
            false
        }
    }

    fun getSpaceInfo(treeUri: Uri): List<Long>? {
        return try {
            VaultPathUtils.querySafSpaceInfo(context, treeUri)?.toList()
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Extracts an image or video thumbnail directly from SAF storage.
     */
    fun getThumbnail(
        treeUri: Uri,
        relativePath: String,
        targetSize: Int,
        quality: Int,
        isVideo: Boolean
    ): Map<String, Any>? {
        val docUri = getDocumentUri(treeUri, relativePath) ?: return null

        if (isVideo) {
            return try {
                context.contentResolver.openFileDescriptor(docUri, "r")?.use { pfd ->
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(pfd.fileDescriptor)
                        val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        val durationMs = durationStr?.toLongOrNull() ?: 0L
                        val frame = tryExtractVideoFrame(retriever, durationMs, targetSize) ?: return null
                        val scaled = scaledToFit(frame, targetSize)
                        val stream = ByteArrayOutputStream()
                        scaled.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), stream)
                        val bytes = stream.toByteArray()
                        val w = frame.width
                        val h = frame.height
                        if (scaled != frame) scaled.recycle()
                        frame.recycle()
                        mapOf("bytes" to bytes, "width" to w, "height" to h)
                    } finally {
                        retriever.release()
                    }
                }
            } catch (e: Exception) {
                VeLog.w(TAG) { "getVideoThumbnail failed for $relativePath: ${e.message}" }
                null
            }
        }

        // Image thumbnail
        // 1. Try DocumentsContract.getDocumentThumbnail
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val point = Point(targetSize, targetSize)
                val thumb = DocumentsContract.getDocumentThumbnail(context.contentResolver, docUri, point, null)
                if (thumb != null) {
                    val scaled = scaledToFit(thumb, targetSize)
                    val stream = ByteArrayOutputStream()
                    scaled.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), stream)
                    val bytes = stream.toByteArray()
                    val w = thumb.width
                    val h = thumb.height
                    if (scaled != thumb) scaled.recycle()
                    thumb.recycle()
                    return mapOf("bytes" to bytes, "width" to w, "height" to h)
                }
            } catch (_: Exception) {}
        }

        // 2. Decode from stream with EXIF correction
        return try {
            val exifOrientation = context.contentResolver.openInputStream(docUri)?.use { stream ->
                runCatching {
                    ExifInterface(stream).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL
                    )
                }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
            } ?: ExifInterface.ORIENTATION_NORMAL

            val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(docUri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, boundsOptions)
            }
            val srcW = boundsOptions.outWidth
            val srcH = boundsOptions.outHeight
            if (srcW <= 0 || srcH <= 0) return null

            val decodeOptions = BitmapFactory.Options().apply {
                inSampleSize = calculateInSampleSize(srcW, srcH, targetSize)
                inPreferredConfig = Bitmap.Config.RGB_565
            }

            val decoded = context.contentResolver.openInputStream(docUri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, decodeOptions)
            } ?: return null

            val oriented = applyExifOrientation(decoded, exifOrientationMatrix(exifOrientation))
            val scaled = scaledToFit(oriented, targetSize)
            val stream = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), stream)
            val bytes = stream.toByteArray()
            if (scaled != oriented) scaled.recycle()
            oriented.recycle()

            mapOf("bytes" to bytes, "width" to srcW, "height" to srcH)
        } catch (e: Exception) {
            VeLog.w(TAG) { "getImageThumbnail failed for $relativePath: ${e.message}" }
            null
        }
    }

    private fun tryExtractVideoFrame(retriever: MediaMetadataRetriever, durationMs: Long, targetSize: Int): Bitmap? {
        val frame0 = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            runCatching {
                retriever.getScaledFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, targetSize, targetSize)
            }.getOrNull() ?: retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        } else {
            retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        }
        if (frame0 != null) return frame0

        if (durationMs > 0L) {
            val candidateUs = (durationMs * 1000L * 0.1).toLong()
            return retriever.getFrameAtTime(candidateUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        }
        return null
    }

    private fun calculateInSampleSize(width: Int, height: Int, targetSize: Int): Int {
        var inSampleSize = 1
        val maxDim = maxOf(width, height)
        if (maxDim > targetSize) {
            val halfMax = maxDim / 2
            while ((halfMax / inSampleSize) >= targetSize) {
                inSampleSize *= 2
            }
        }
        return inSampleSize.coerceAtLeast(1)
    }

    private fun scaledToFit(src: Bitmap, targetSize: Int): Bitmap {
        val w = src.width
        val h = src.height
        if (w <= 0 || h <= 0) return src
        val maxDim = maxOf(w, h)
        if (maxDim <= targetSize) return src
        val scale = targetSize.toFloat() / maxDim
        val dstW = (w * scale).toInt().coerceAtLeast(1)
        val dstH = (h * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, dstW, dstH, true)
    }

    private fun exifOrientationMatrix(orientation: Int): Matrix {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
        }
        return matrix
    }

    private fun applyExifOrientation(src: Bitmap, matrix: Matrix): Bitmap {
        if (matrix.isIdentity) return src
        val rotated = Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
        if (rotated != src) src.recycle()
        return rotated
    }

    fun openWithApp(
        treeUri: Uri,
        relativePath: String,
        mimeTypeOverride: String?,
        packageName: String?
    ): Boolean {
        val docUri = getDocumentUri(treeUri, relativePath) ?: return false
        val fileName = relativePath.substringAfterLast('/')
        val mime = mimeTypeOverride ?: MimeTypeHelper.getMimeType(fileName)

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(docUri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            if (!packageName.isNullOrEmpty()) {
                setPackage(packageName)
            }
        }

        return try {
            if (!packageName.isNullOrEmpty()) {
                try {
                    context.startActivity(intent)
                    return true
                } catch (_: Exception) {
                    intent.setPackage(null)
                }
            }
            val chooser = Intent.createChooser(intent, "Open with…").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(chooser)
            true
        } catch (e: Exception) {
            VeLog.w(TAG) { "openWithApp failed for $relativePath: ${e.message}" }
            false
        }
    }

    fun shareFiles(treeUri: Uri, relativePaths: List<String>): Boolean {
        if (relativePaths.isEmpty()) return false
        val uris = ArrayList<Uri>()
        for (rel in relativePaths) {
            val docUri = getDocumentUri(treeUri, rel)
            if (docUri != null) uris.add(docUri)
        }
        if (uris.isEmpty()) return false

        val intent = if (uris.size == 1) {
            val fileName = relativePaths[0].substringAfterLast('/')
            Intent(Intent.ACTION_SEND).apply {
                putExtra(Intent.EXTRA_STREAM, uris[0])
                type = MimeTypeHelper.getMimeType(fileName)
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                type = "*/*"
            }
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        return try {
            val chooser = Intent.createChooser(intent, null).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(chooser)
            true
        } catch (e: Exception) {
            VeLog.w(TAG) { "shareFiles failed: ${e.message}" }
            false
        }
    }

    /**
     * Fast native copy between SAF documents or between SAF and local storage.
     */
    fun copyFile(
        srcTreeUri: Uri?,
        srcPath: String,
        destTreeUri: Uri?,
        destPath: String
    ): Boolean {
        if (srcTreeUri != null && destTreeUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            srcTreeUri.authority == destTreeUri.authority
        ) {
            val srcDocUri = getDocumentUri(srcTreeUri, srcPath)
            val destParentPath = if (destPath.contains('/')) destPath.substringBeforeLast('/') else ""
            val destParentUri = getDocumentUri(destTreeUri, destParentPath)
            if (srcDocUri != null && destParentUri != null) {
                try {
                    val copied = DocumentsContract.copyDocument(context.contentResolver, srcDocUri, destParentUri)
                    if (copied != null) {
                        val destName = destPath.substringAfterLast('/')
                        val copiedName = getFileNameFromUri(copied)
                        if (copiedName != null && copiedName != destName) {
                            DocumentsContract.renameDocument(context.contentResolver, copied, destName)
                        }
                        invalidateCache(destTreeUri, destPath)
                        return true
                    }
                } catch (_: UnsupportedOperationException) {}
            }
        }

        // Streaming copy fallback
        val inStream = (if (srcTreeUri != null) {
            val docUri = getDocumentUri(srcTreeUri, srcPath) ?: return false
            context.contentResolver.openInputStream(docUri)
        } else {
            val file = File(srcPath)
            if (file.exists()) FileInputStream(file) else null
        }) ?: return false

        val outStream = (if (destTreeUri != null) {
            createFile(destTreeUri, destPath)
            val docUri = getDocumentUri(destTreeUri, destPath) ?: run {
                inStream.close()
                return false
            }
            context.contentResolver.openOutputStream(docUri, "wt")
        } else {
            val destFile = File(destPath)
            destFile.parentFile?.mkdirs()
            FileOutputStream(destFile)
        }) ?: run {
            inStream.close()
            return false
        }

        return try {
            inStream.use { input ->
                outStream.use { output ->
                    val buffer = ByteArray(1024 * 1024) // 1 MB buffer
                    var read: Int
                    while (input.read(buffer).also { read = it } != -1) {
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            }
            if (destTreeUri != null) invalidateCache(destTreeUri, destPath)
            true
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "copyFile streaming failed: ${e.message}" }
            false
        }
    }

    private fun getFileNameFromUri(uri: Uri): String? {
        return try {
            context.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    if (idx >= 0) c.getString(idx) else null
                } else null
            }
        } catch (_: Exception) { null }
    }

    /**
     * Auto-discovers all mounted storage volumes (Primary, SD Cards, USB OTG).
     */
    fun getStorageVolumes(): List<Map<String, Any?>> {
        val sm = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
        val volumes = mutableListOf<Map<String, Any?>>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            for (vol in sm.storageVolumes) {
                val isPrimary = vol.isPrimary
                val isRemovable = vol.isRemovable
                val state = vol.state
                val desc = vol.getDescription(context)
                val uuid = vol.uuid
                val dir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) vol.directory else null
                val path = dir?.absolutePath
                    ?: (if (isPrimary) Environment.getExternalStorageDirectory().absolutePath else (if (uuid != null) "/storage/$uuid" else null))
                val canRead = path != null && File(path).canRead()

                volumes.add(mapOf(
                    "id" to (uuid ?: if (isPrimary) "primary" else "volume_${System.currentTimeMillis()}"),
                    "description" to desc,
                    "isPrimary" to isPrimary,
                    "isRemovable" to isRemovable,
                    "state" to state,
                    "path" to (path ?: ""),
                    "hasDirectAccess" to canRead,
                ))
            }
        } else {
            // Pre-Nougat fallback
            val primaryDir = Environment.getExternalStorageDirectory()
            volumes.add(mapOf(
                "id" to "primary",
                "description" to "Internal Storage",
                "isPrimary" to true,
                "isRemovable" to false,
                "state" to Environment.getExternalStorageState(),
                "path" to primaryDir.absolutePath,
                "hasDirectAccess" to primaryDir.canRead(),
            ))
        }

        return volumes
    }
}
