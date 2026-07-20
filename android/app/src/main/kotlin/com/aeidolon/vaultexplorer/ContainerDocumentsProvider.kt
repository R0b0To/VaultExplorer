package com.aeidolon.vaultexplorer

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Point
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import android.system.ErrnoException
import android.system.OsConstants
import java.io.File
import java.io.FileNotFoundException

class ContainerDocumentsProvider : DocumentsProvider() {

    companion object {
        private const val AUTHORITY = "com.aeidolon.vaultexplorer.documents"
    }

    private val defaultRootProjection = arrayOf(
        DocumentsContract.Root.COLUMN_ROOT_ID,
        DocumentsContract.Root.COLUMN_MIME_TYPES,
        DocumentsContract.Root.COLUMN_FLAGS,
        DocumentsContract.Root.COLUMN_ICON,
        DocumentsContract.Root.COLUMN_TITLE,
        DocumentsContract.Root.COLUMN_SUMMARY,
        DocumentsContract.Root.COLUMN_DOCUMENT_ID,
        DocumentsContract.Root.COLUMN_AVAILABLE_BYTES,
        DocumentsContract.Root.COLUMN_CAPACITY_BYTES
    )

    private val defaultDocumentProjection = arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        DocumentsContract.Document.COLUMN_FLAGS,
        DocumentsContract.Document.COLUMN_SIZE
    )

    override fun onCreate(): Boolean {
        return true
    }

    // ── Roots ──────────────────────────────────────────────────────────────

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val resolvedProjection = projection ?: defaultRootProjection
        val cursor = MatrixCursor(resolvedProjection)
        cursor.setNotificationUri(context?.contentResolver, DocumentsContract.buildRootsUri(AUTHORITY))
        
        for ((volId, session) in ContainerSessionRegistry.activeSessions.filter { it.value.documentProvider }) {
            var flags = DocumentsContract.Root.FLAG_LOCAL_ONLY or
                    DocumentsContract.Root.FLAG_SUPPORTS_EJECT
            if (!session.readOnly) {
                flags = flags or DocumentsContract.Root.FLAG_SUPPORTS_CREATE          
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                flags = flags or DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD
            }

            val rootTitle = session.displayName
                ?: UriNameResolver.resolve(context?.contentResolver, Uri.parse(session.uri))
            val (totalBytes, freeBytes) = ContainerFileSystem.getSpacePair(volId)
            val rootSummary = if (totalBytes > 0)
                "Volume — ${android.text.format.Formatter.formatFileSize(context, freeBytes)} free"
            else "Volume"

            val row = cursor.newRow()
            for (col in resolvedProjection) {
                when (col) {
                    DocumentsContract.Root.COLUMN_ROOT_ID -> row.add(volId.toString())
                    DocumentsContract.Root.COLUMN_MIME_TYPES -> row.add("*/*")
                    DocumentsContract.Root.COLUMN_DOCUMENT_ID -> row.add(DocumentId(volId, "dir", "").toString())
                    DocumentsContract.Root.COLUMN_TITLE -> row.add(rootTitle)
                    DocumentsContract.Root.COLUMN_SUMMARY -> row.add(rootSummary)
                    DocumentsContract.Root.COLUMN_FLAGS -> row.add(flags)
                    DocumentsContract.Root.COLUMN_ICON -> row.add(android.R.drawable.ic_lock_idle_charging)
                    DocumentsContract.Root.COLUMN_AVAILABLE_BYTES -> row.add(freeBytes)
                    DocumentsContract.Root.COLUMN_CAPACITY_BYTES -> row.add(totalBytes)
                    else -> row.add(null)
                }
            }
        }
        return cursor
    }

    override fun isChildDocument(parentDocumentId: String?, documentId: String?): Boolean {
        if (parentDocumentId == null || documentId == null) return false
        val parent = try { DocumentId.parse(parentDocumentId, "parent") }
                     catch (e: Exception) { return false }
        val child  = try { DocumentId.parse(documentId, "child") }
                     catch (e: Exception) { return false }
        
        if (parent.volId != child.volId) return false
        if (parent.fatPath.isEmpty()) return true
        if (parent.fatPath == child.fatPath) return true 
        
        return child.fatPath.startsWith("${parent.fatPath}/")
    }

    override fun ejectRoot(rootId: String?) {
        val volId = rootId?.toIntOrNull()
            ?.takeIf { it in 0 until ContainerSessionRegistry.MAX_VOLUMES }
            ?: return
        val session = ContainerSessionRegistry.activeSessions[volId]
        ContainerEngine.lock(volId)
        if (session?.isUsbSource == true) UsbBlockBridge.unregister(volId)
        ContainerSessionRegistry.removeSession(volId)
        context?.contentResolver?.notifyChange(
            DocumentsContract.buildRootsUri(AUTHORITY), null
        )
    }

    private fun addDocumentRow(
        cursor: MatrixCursor,
        projection: Array<out String>,
        docId: String,
        displayName: String,
        mimeType: String,
        size: Long,
        isDir: Boolean,
        isRoot: Boolean,
        readOnly: Boolean,
    ) {
        var flags = 0
        if (!isRoot && !readOnly) {
            flags = flags or DocumentsContract.Document.FLAG_SUPPORTS_DELETE
            flags = flags or DocumentsContract.Document.FLAG_SUPPORTS_RENAME
        }
        if (isDir) {
            if (!readOnly) flags = flags or DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE
        } else {
            if (!readOnly) flags = flags or DocumentsContract.Document.FLAG_SUPPORTS_WRITE
            if (mimeType.startsWith("image/"))
                flags = flags or DocumentsContract.Document.FLAG_SUPPORTS_THUMBNAIL
        }

        val row = cursor.newRow()
        for (col in projection) {
            when (col) {
                DocumentsContract.Document.COLUMN_DOCUMENT_ID -> row.add(docId)
                DocumentsContract.Document.COLUMN_MIME_TYPE -> row.add(mimeType)
                DocumentsContract.Document.COLUMN_DISPLAY_NAME -> row.add(displayName)
                DocumentsContract.Document.COLUMN_LAST_MODIFIED -> row.add(System.currentTimeMillis()) 
                DocumentsContract.Document.COLUMN_FLAGS -> row.add(flags)
                DocumentsContract.Document.COLUMN_SIZE -> if (isDir) row.add(null) else row.add(size) 
                "_id" -> row.add(docId.hashCode()) 
                else -> row.add(null)
            }
        }
    }

    override fun queryDocument(documentId: String?, projection: Array<out String>?): Cursor {
        val resolvedProjection = projection ?: defaultDocumentProjection
        val cursor = MatrixCursor(resolvedProjection)
        
        if (documentId == null) return cursor
        cursor.setNotificationUri(context?.contentResolver, DocumentsContract.buildDocumentUri(AUTHORITY, documentId))
        
        val doc = try { DocumentId.parse(documentId, "document") } catch (e: Exception) { 
            throw FileNotFoundException("Invalid ID")
        }
        val volId   = doc.volId
        val fatPath = doc.fatPath

        ContainerFileSystem.requireSession(volId)
        val readOnly = ContainerSessionRegistry.activeSessions[volId]?.readOnly == true

        var actualIsDir = doc.isDir
        var actualSize = 0L

        if (fatPath.isNotEmpty()) {
            val parentPath = if (fatPath.contains("/")) fatPath.substringBeforeLast("/") else ""
            val fileName = fatPath.substringAfterLast("/")
            
            val siblings = ContainerFileSystem.listDirectory(volId, parentPath) 
                ?: throw FileNotFoundException("Parent directory missing")
                
            var found = false
            for (fileStr in siblings) {
                if (fileStr.startsWith("System:")) continue
                val isDirStr = fileStr.startsWith("[DIR] ")
                val cleanName = if (isDirStr) fileStr.substringAfter("[DIR] ").substringBefore("|") else fileStr.substringBefore("|")
                
                if (cleanName == fileName) {
                    found = true
                    actualIsDir = isDirStr
                    actualSize = if (isDirStr) 0L else fileStr.split("|").getOrNull(1)?.toLongOrNull() ?: 0L
                    break
                }
            }
            
            if (!found) {
                throw FileNotFoundException("Document $fatPath not found")
            }
        } else {
            actualIsDir = true
        }

        val displayName = if (fatPath.isEmpty()) "Root $volId" else fatPath.substringAfterLast("/")
        val mimeType = if (actualIsDir) DocumentsContract.Document.MIME_TYPE_DIR 
                       else (MimeTypeHelper.getMimeType(displayName) ?: "application/octet-stream")

        addDocumentRow(
            cursor, resolvedProjection, doc.toString(), displayName,
            mimeType, actualSize, actualIsDir, fatPath.isEmpty(), readOnly
        )
        return cursor
    }

    override fun queryChildDocuments(
        parentDocumentId: String?,
        projection: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val resolvedProjection = projection ?: defaultDocumentProjection
        val cursor = MatrixCursor(resolvedProjection)
        
        if (parentDocumentId == null) return cursor
        cursor.setNotificationUri(context?.contentResolver, DocumentsContract.buildChildDocumentsUri(AUTHORITY, parentDocumentId))
        
        val parent = try { DocumentId.parse(parentDocumentId, "parent") } catch (e: Exception) { 
            return cursor 
        }
        val volId         = parent.volId
        val parentFatPath = parent.fatPath
        ContainerFileSystem.requireSession(volId)
        val readOnly = ContainerSessionRegistry.activeSessions[volId]?.readOnly == true

        try {
            val files = ContainerFileSystem.listDirectory(volId, parentFatPath)
            
            files?.forEach { file ->
                if (file.startsWith("System:")) return@forEach
                val isDir     = file.startsWith("[DIR] ")
                val cleanName = if (isDir) file.substringAfter("[DIR] ").substringBefore("|") else file.substringBefore("|")
                val size      = if (isDir) 0L else file.split("|").getOrNull(1)?.toLongOrNull() ?: 0L
                val childFatPath = if (parentFatPath.isEmpty()) cleanName else "$parentFatPath/$cleanName"
                val childType    = if (isDir) "dir" else "file"
                
                val childMime = if (isDir) DocumentsContract.Document.MIME_TYPE_DIR 
                                else (MimeTypeHelper.getMimeType(cleanName) ?: "application/octet-stream")

                addDocumentRow(
                    cursor, resolvedProjection, DocumentId(volId, childType, childFatPath).toString(),
                    cleanName, childMime, size, isDir, false, readOnly
                )
            }
        } catch (e: FileNotFoundException) {
            throw e
        } catch (e: Exception) {
            // Ignored
        }
        return cursor
    }

    @Throws(FileNotFoundException::class)
    override fun createDocument(parentDocumentId: String?, mimeType: String?, displayName: String?): String {
        val parent = DocumentId.parse(parentDocumentId, "parent")
        val volId  = parent.volId
        val parentFatPath = parent.fatPath
        ContainerFileSystem.requireSession(volId)
        if (ContainerSessionRegistry.activeSessions[volId]?.readOnly == true) {   
            throw FileNotFoundException("Container is mounted read-only")
        }
        
        val fileName  = displayName?.replace("/", "_") ?: throw FileNotFoundException("No file name provided")
        val cleanPath = if (parentFatPath.isEmpty()) fileName else "$parentFatPath/$fileName"
        val isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR

        val success = try {
            if (isDirectory) {
                ContainerFileSystem.createDirectory(volId, cleanPath)
            } else {
                val tempFile = File(context?.cacheDir, "vc_new_${volId}_${cleanPath.hashCode()}_$fileName")
                try {
                    if (tempFile.exists()) tempFile.delete()
                    tempFile.createNewFile()
                    ContainerFileSystem.writeBackFile(volId, cleanPath, tempFile.absolutePath)
                } finally {
                    tempFile.delete()
                }
            }
        } catch (e: Exception) {
            throw FileNotFoundException("File operations failed natively: ${e.message}")
        }

        if (!success) throw FileNotFoundException("Creation failed for $cleanPath")

        context?.contentResolver?.notifyChange(DocumentsContract.buildChildDocumentsUri(AUTHORITY, parentDocumentId), null)
        context?.contentResolver?.notifyChange(DocumentsContract.buildDocumentUri(AUTHORITY, parentDocumentId), null)
        
        val childType = if (isDirectory) "dir" else "file"
        return DocumentId(volId, childType, cleanPath).toString()
    }

    private fun deleteRecursive(volId: Int, path: String, isDir: Boolean): Boolean {
        if (isDir) {
            try {
                val children = ContainerFileSystem.listDirectory(volId, path)
                children?.forEach { child ->
                    if (child.startsWith("System:")) return@forEach
                    val childIsDir = child.startsWith("[DIR] ")
                    val cleanName = if (childIsDir) child.substringAfter("[DIR] ").substringBefore("|") else child.substringBefore("|")
                    val childPath = if (path.isEmpty()) cleanName else "$path/$cleanName"
                    
                    deleteRecursive(volId, childPath, childIsDir)
                }
            } catch (e: Exception) {
                // Ignore directory listing failures and try to delete whatever we can
            }
        }
        return ContainerFileSystem.deleteFile(volId, path)
    }

    @Throws(FileNotFoundException::class)
    override fun deleteDocument(documentId: String?) {
        val doc     = DocumentId.parse(documentId, "document")
        val volId   = doc.volId
        val fatPath = doc.fatPath
        ContainerFileSystem.requireSession(volId)

        if (ContainerSessionRegistry.activeSessions[volId]?.readOnly == true) {                                        
            throw FileNotFoundException("Container is mounted read-only")
        }

        val success = deleteRecursive(volId, fatPath, doc.isDir)
        if (!success) throw FileNotFoundException("Delete failed for $fatPath")

        val parentPath = if (fatPath.contains("/")) fatPath.substringBeforeLast("/") else ""
        val parentDocId = DocumentId(volId, "dir", parentPath).toString()
        
        context?.contentResolver?.notifyChange(DocumentsContract.buildChildDocumentsUri(AUTHORITY, parentDocId), null)
        context?.contentResolver?.notifyChange(DocumentsContract.buildDocumentUri(AUTHORITY, parentDocId), null)
    }

    @Throws(FileNotFoundException::class)
    override fun renameDocument(documentId: String?, displayName: String?): String {
        val doc = DocumentId.parse(documentId, "document")
        val volId = doc.volId
        ContainerFileSystem.requireSession(volId)

        if (ContainerSessionRegistry.activeSessions[volId]?.readOnly == true) {                                        
            throw FileNotFoundException("Container is mounted read-only")
        }

        val newName = displayName?.replace("/", "_") ?: throw FileNotFoundException("No name provided")

        val oldFatPath = doc.fatPath
        val parentPath = if (oldFatPath.contains("/")) oldFatPath.substringBeforeLast("/") else ""
        val newFatPath = if (parentPath.isEmpty()) newName else "$parentPath/$newName"

        val success = ContainerFileSystem.renameFile(doc.volId, oldFatPath, newFatPath)
        if (!success) throw FileNotFoundException("Rename failed for $oldFatPath to $newFatPath")

        val parentDocId = DocumentId(doc.volId, "dir", parentPath).toString()
        context?.contentResolver?.notifyChange(DocumentsContract.buildChildDocumentsUri(AUTHORITY, parentDocId), null)
        
        val childType = if (doc.isDir) "dir" else "file"
        val newDocId = DocumentId(doc.volId, childType, newFatPath).toString()
        
        context?.contentResolver?.notifyChange(DocumentsContract.buildDocumentUri(AUTHORITY, documentId), null)
        context?.contentResolver?.notifyChange(DocumentsContract.buildDocumentUri(AUTHORITY, newDocId), null)
        
        return newDocId
    }

    @Throws(FileNotFoundException::class)
    override fun openDocument(
        documentId: String?,
        mode: String?,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        val doc     = DocumentId.parse(documentId, "document")
        val volId   = doc.volId
        val session = ContainerFileSystem.requireSession(volId)
        val fatPath = doc.fatPath

        val isWrite = mode?.contains("w") == true || mode?.contains("r+") == true
        if (isWrite && session.readOnly) {                                        
            throw FileNotFoundException("Container is mounted read-only")
        }

        val storageManager = context?.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            ?: throw FileNotFoundException("Could not obtain StorageManager")

        val handlerThread = HandlerThread(
            "vc_proxy_${volId}_${System.nanoTime()}"
        ).apply { start() }
        val handler = Handler(handlerThread.looper)

        val callback = VeraCryptProxyCallback(volId, session, fatPath, isWrite, handlerThread)

        return try {
            val parcelMode = ParcelFileDescriptor.parseMode(mode ?: "r")
            storageManager.openProxyFileDescriptor(parcelMode, callback, handler)
        } catch (e: Exception) {
            handlerThread.quitSafely()
            throw FileNotFoundException("Failed to open proxy file descriptor: ${e.message}")
        }
    }

    @Throws(FileNotFoundException::class)
    override fun openDocumentThumbnail(
        documentId: String?,
        sizeHint: Point?,
        signal: CancellationSignal?
    ): AssetFileDescriptor {
        val doc     = DocumentId.parse(documentId, "document")
        val volId   = doc.volId
        val fatPath = doc.fatPath
        if (fatPath.isEmpty()) throw FileNotFoundException(
            "Cannot generate thumbnail for volume root"
        )
        ContainerFileSystem.requireSession(volId)

        val pipe     = ParcelFileDescriptor.createPipe()
        val readEnd  = pipe[0]
        val writeEnd = pipe[1]

        Thread {
            val tempFile = File(context?.cacheDir, "thumb_${System.nanoTime()}")
            try {
                val ok = ContainerFileSystem.extractToFile(volId, fatPath, tempFile.absolutePath)

                if (ok && tempFile.exists()) {
                    val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(tempFile.absolutePath, opts)
                    val reqW = sizeHint?.x ?: 256
                    val reqH = sizeHint?.y ?: 256
                    opts.inSampleSize       = calculateInSampleSize(opts, reqW, reqH)
                    opts.inJustDecodeBounds = false
                    val bmp = BitmapFactory.decodeFile(tempFile.absolutePath, opts)
                    if (bmp != null) {
                        ParcelFileDescriptor.AutoCloseOutputStream(writeEnd).use { out ->
                            bmp.compress(Bitmap.CompressFormat.JPEG, 85, out)
                        }
                        bmp.recycle()
                        return@Thread
                    }
                }
            } catch (e: Exception) {
                // Ignored
            } finally {
                if (tempFile.exists()) tempFile.delete()
                runCatching { writeEnd.close() }
            }
        }.start()

        return AssetFileDescriptor(readEnd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
    }

    // ── Proxy callback (Zero-Copy Fast Stream Bridge) ──────────────────────

    inner class VeraCryptProxyCallback(
        private val volId: Int,
        private val session: ContainerSession,
        private val fatPath: String,
        private val isWrite: Boolean,
        private val handlerThread: HandlerThread
    ) : ProxyFileDescriptorCallback() {

        private var hasChanges = false
        private var fileSizeCached: Long = -1L
        private var streamPtr: Long = 0L

        // 1 MB Read-Ahead Cache
        private val isCacheEnabled = !isWrite
        private val readCacheCapacity = 1024 * 1024 
        private val readCache = if (isCacheEnabled) ByteArray(readCacheCapacity) else null
        private var readCacheOffset: Long = -1L
        private var readCacheLength: Int = 0

        // 2 MB Write-Behind Cache
        private val writeCacheCapacity = 2 * 1024 * 1024 
        private val writeCache = if (isWrite) ByteArray(writeCacheCapacity) else null
        private var writeCacheOffset: Long = -1L
        private var writeCacheLength: Int = 0

        init {
            try {
                ContainerFileSystem.withLock(volId) {
                    fileSizeCached = ContainerFileSystem.getFileSize(volId, fatPath)
                    if (fileSizeCached < 0) fileSizeCached = 0L
                    if (!isWrite) {
                        streamPtr = ContainerFileSystem.openStream(volId, fatPath)
                    }
                }
            } catch (e: Exception) {
                handlerThread.quitSafely()
                throw FileNotFoundException("VeraCrypt init failed for $fatPath: ${e.message}")
            }
        }

        private fun flushWriteCache() {
            if (writeCache != null && writeCacheLength > 0) {
                val chunk = if (writeCacheLength == writeCacheCapacity) writeCache else writeCache.copyOf(writeCacheLength)
                ContainerFileSystem.withLock(volId) {
                    ContainerFileSystem.writeFileChunk(volId, fatPath, writeCacheOffset, chunk)
                }
                
                val endOffset = writeCacheOffset + writeCacheLength
                if (endOffset > fileSizeCached) fileSizeCached = endOffset
                
                writeCacheLength = 0
                writeCacheOffset = -1L
            }
        }

        override fun onGetSize(): Long {
            val pendingSize = if (writeCacheOffset >= 0) writeCacheOffset + writeCacheLength else 0L
            return maxOf(fileSizeCached, pendingSize)
        }

        override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
            if (offset >= fileSizeCached || streamPtr == 0L) return 0
            val readSize = minOf(size.toLong(), fileSizeCached - offset).toInt()
            if (readSize <= 0) return 0

            if (readCache != null) {
                if (offset >= readCacheOffset && offset + readSize <= readCacheOffset + readCacheLength) {
                    val relativeOffset = (offset - readCacheOffset).toInt()
                    System.arraycopy(readCache, relativeOffset, data, 0, readSize)
                    return readSize
                }

                if (readSize <= readCacheCapacity) {
                    val fetchSize = minOf(readCacheCapacity.toLong(), fileSizeCached - offset).toInt()
                    val actualRead = ContainerFileSystem.withLock(volId) {
                        ContainerFileSystem.readStream(volId, streamPtr, offset, readCache, fetchSize)
                    }
                    if (actualRead < 0) throw ErrnoException("onRead", OsConstants.EIO)
                    
                    readCacheOffset = offset
                    readCacheLength = actualRead

                    val copySize = minOf(readSize, readCacheLength)
                    if (copySize > 0) {
                        System.arraycopy(readCache, 0, data, 0, copySize)
                    }
                    return copySize
                }
            }

            val actualRead = ContainerFileSystem.withLock(volId) {
                ContainerFileSystem.readStream(volId, streamPtr, offset, data, readSize)
            }
            if (actualRead < 0) throw ErrnoException("onRead", OsConstants.EIO)
            return actualRead
        }

        override fun onWrite(offset: Long, size: Int, data: ByteArray): Int {
            if (!isWrite || writeCache == null) throw ErrnoException("onWrite", OsConstants.EBADF)
            
            if (writeCacheLength > 0 && (offset != writeCacheOffset + writeCacheLength || writeCacheLength + size > writeCacheCapacity)) {
                flushWriteCache()
            }

            if (size >= writeCacheCapacity) {
                val chunkData = if (data.size == size) data else data.copyOf(size)
                val success = ContainerFileSystem.withLock(volId) {
                    ContainerFileSystem.writeFileChunk(volId, fatPath, offset, chunkData)
                }
                if (!success) throw ErrnoException("onWrite", OsConstants.EIO)
                
                val endOffset = offset + size
                if (endOffset > fileSizeCached) fileSizeCached = endOffset
            } else {
                if (writeCacheLength == 0) writeCacheOffset = offset
                System.arraycopy(data, 0, writeCache, writeCacheLength, size)
                writeCacheLength += size
            }
            
            hasChanges = true
            return size
        }

        override fun onFsync() {
            flushWriteCache()
        }

override fun onRelease() {
    flushWriteCache()
    if (isWrite) {
        ContainerFileSystem.withLock(volId) {
            ContainerEngine.finishWrite(fatPath, volId)
        }
    }
    ContainerFileSystem.withLock(volId) {
        if (streamPtr != 0L) { ContainerFileSystem.closeStream(volId, streamPtr); streamPtr = 0L }
    }
    if (isWrite && hasChanges) {
                val parentPath = if (fatPath.contains("/")) fatPath.substringBeforeLast("/") else ""
                val parentDocId = DocumentId(volId, "dir", parentPath).toString()
                
                context?.contentResolver?.notifyChange(DocumentsContract.buildChildDocumentsUri(AUTHORITY, parentDocId), null)
                context?.contentResolver?.notifyChange(DocumentsContract.buildDocumentUri(AUTHORITY, parentDocId), null)
                
                val fileDocId = DocumentId(volId, "file", fatPath).toString()
                context?.contentResolver?.notifyChange(DocumentsContract.buildDocumentUri(AUTHORITY, fileDocId), null)
            }
            handlerThread.quitSafely()
        }
    }

    private fun calculateInSampleSize(
        options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int
    ): Int {
        val height = options.outHeight
        val width  = options.outWidth
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth  = width / 2
            while (halfHeight / inSampleSize >= reqHeight &&
                   halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }
}