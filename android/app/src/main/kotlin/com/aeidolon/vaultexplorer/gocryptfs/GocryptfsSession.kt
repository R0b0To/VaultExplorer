package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap

/**
 * One unlocked Gocryptfs vault, keyed by the same `volId` space
 * VeraCrypt/LUKS sessions use (see ContainerSessionRegistry). Holds the
 * decrypted masterkey, vault config, and vault tree, and implements the
 * same Tier-2 file/directory surface ContainerEngine exposes to Dart —
 * `listDirectory`, `readFileChunk`, `writeFileChunk`, etc. — operating on
 * cleartext virtual paths instead of a FatFs-mounted block device.
 */
class GocryptfsSession(
    private val context: Context,
    val vaultRootUri: Uri,
    val nameCryptor: GocryptfsFileNameCryptor,
    val contentCryptor: GocryptfsContentCryptor,
    val tree: GocryptfsVaultTree,
    val readOnly: Boolean,
) {
    private val random = SecureRandom()
    private val shorteningThreshold: Int by lazy {
        try {
            val field = nameCryptor.javaClass.getDeclaredField("longNameMax")
            field.isAccessible = true
            field.get(nameCryptor) as Int
        } catch (e: Exception) {
            176 // Fallback to standard gocryptfs cleartext limit
        }
    }

    /** Open write handles for in-progress sequential writeFileChunk() sequences, keyed by virtual path. */
    private val openWrites = ConcurrentHashMap<String, WriteHandle>()

    private inner class ReadHandle(
        val pfd: android.os.ParcelFileDescriptor?,
        val stream: java.io.InputStream,
        val header: Any,
        var currentPos: Long
    ) {
        var cachedChunkIndex: Long = -1L
        var cachedChunkCleartext: ByteArray? = null

        fun close() {
            try { stream.close() } catch (_: Exception) {}
            try { pfd?.close() } catch (_: Exception) {}
        }
        @Suppress("UNCHECKED_CAST")
        fun <T> typedHeader(): T = header as T
    }

    private val openReads = object : android.util.LruCache<String, ReadHandle>(8) {
        override fun entryRemoved(evicted: Boolean, key: String, oldValue: ReadHandle, newValue: ReadHandle?) {
            oldValue.close()
        }
    }

    fun close() {
        openWrites.values.forEach { it.abort() }
        openWrites.clear()
        openReads.evictAll()
    }

  
    private fun physicalFolderForDirPath(dirPath: String): DocumentFile? =
    if (dirPath.isEmpty()) tree.rootPhysicalFolder()
    else (tree.resolve(dirPath) as? GocryptfsNode.VDir)?.physicalFolder

    /** Physical SAF folder for [path] ("" = vault root). `tree.resolve(path)` can't handle
     *  the root case -- there's no parent entry whose name it could decrypt -- so every call
     *  site that needs "the folder I'm about to create/rename/delete something inside" must
     *  go through this instead of casting `tree.resolve(path)` directly. */
    private fun physicalFolderFor(path: String): DocumentFile? {
        if (path.isEmpty()) return DocumentFile.fromTreeUri(context, vaultRootUri)
        return (tree.resolve(path) as? GocryptfsNode.VDir)?.physicalFolder
    }

    // ---- directory listing ----------------------------------------------------

    fun listDirectory(virtualPath: String): Array<String>? {
        return try {
            val normalized = normalize(virtualPath)
            val nodes = tree.list(normalized)
            nodes.map { node ->
                when (node) {
                    is GocryptfsNode.VDir -> {
                        val mtime = node.physicalFolder.lastModified() / 1000L
                        "[DIR] ${node.cleartextName}|0|$mtime"
                    }
                    is GocryptfsNode.VFile -> {
    val ciphertextSize = node.physicalFile.length()
    val cleartextSize = contentCryptor.cleartextSize(ciphertextSize)
    val mtime = node.physicalFile.lastModified() / 1000L
    "${node.cleartextName}|$cleartextSize|$mtime"
}
                }
            }.toTypedArray()
        } catch (e: GocryptfsPathNotFoundException) {
            null
        } catch (e: GocryptfsIOException) {
            null
        }
    }

    fun createDirectory(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            val parentPath = parentOf(normalized)
            val name = nameOf(normalized)
            val parentDirIv = tree.dirivFor(parentPath)
            val parentPhysical = tree.physicalFolderFor(parentPath)

            val ciphertextName = nameCryptor.encryptName(name, parentDirIv)
            createNodeFolder(parentPhysical, ciphertextName, name)

            // Additionally writes a fresh gocryptfs.diriv for the new directory
            tree.dirivFor(normalized)

            tree.invalidate(parentPath)
            true
        } catch (e: Exception) {
            android.util.Log.e("GocryptfsSession", "createDirectory failed for $virtualPath", e)
            false
        }
    }

    fun renameFile(oldVirtualPath: String, newVirtualPath: String): Boolean {
    if (readOnly) return false
    return try {
        val oldNormalized = normalize(oldVirtualPath)
        val newNormalized = normalize(newVirtualPath)
        openReads.remove(oldNormalized)
        openReads.remove(newNormalized)
        val node = tree.resolve(oldNormalized) ?: return false

        val oldParentPath = parentOf(oldNormalized)
        val newParentPath = parentOf(newNormalized)
        val newName = nameOf(newNormalized)

        if (oldParentPath == newParentPath) {
            // Simple rename within the same directory
            val parentDirIv = tree.dirivFor(oldParentPath)
            val newCiphertextName = nameCryptor.encryptName(newName, parentDirIv)
            val physicalNode = when (node) {
                is GocryptfsNode.VDir -> node.physicalFolder
                is GocryptfsNode.VFile -> node.physicalFile
            }

            val oldPhysicalName = physicalNode.name ?: ""
            val parentPhysical = tree.physicalFolderFor(oldParentPath)

            if (oldPhysicalName.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX) && !oldPhysicalName.endsWith(GocryptfsFileNameCryptor.LONGNAME_SUFFIX)) {
                childOf(parentPhysical, "$oldPhysicalName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}")?.delete()
            }

            if (newCiphertextName.length <= shorteningThreshold) {
                renameDocument(physicalNode, newCiphertextName)
            } else {
                val hashBytes = java.security.MessageDigest.getInstance("SHA-256").digest(newCiphertextName.toByteArray(Charsets.UTF_8))
                val hashStr = android.util.Base64.encodeToString(hashBytes, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
                val shortName = GocryptfsFileNameCryptor.LONGNAME_PREFIX + hashStr
                renameDocument(physicalNode, shortName)
                val nameFile = createFileSafe(parentPhysical, "application/octet-stream", "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}")
                    ?: throw GocryptfsIOException("Could not create .name file")
                writeWhole(nameFile, newCiphertextName.toByteArray(Charsets.UTF_8))
            }
        } else {
            // Cross-directory move. A gocryptfs entry's ciphertext name is
            // encrypted with its PARENT's diriv, so it must be re-derived for
            // the destination — but the moved node's own contents (a file's
            // bytes, or a directory's own diriv and children) are untouched.
            // Only this small pointer entry relocates.
            val oldParentPhysical = tree.physicalFolderFor(oldParentPath)
            val newParentPhysical = tree.physicalFolderFor(newParentPath)
            val newParentDirIv = tree.dirivFor(newParentPath, newParentPhysical)

            val newCiphertextName = nameCryptor.encryptName(newName, newParentDirIv)
            val physicalNode = when (node) {
                is GocryptfsNode.VDir -> node.physicalFolder
                is GocryptfsNode.VFile -> node.physicalFile
            }
            val oldPhysicalName = physicalNode.name ?: ""
            val wasLongName = oldPhysicalName.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX) &&
                !oldPhysicalName.endsWith(GocryptfsFileNameCryptor.LONGNAME_SUFFIX)

            if (newCiphertextName.length <= shorteningThreshold) {
                val renamed = renameDocumentAndGet(physicalNode, newCiphertextName)
                movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)
            } else {
                val hashBytes = java.security.MessageDigest.getInstance("SHA-256").digest(newCiphertextName.toByteArray(Charsets.UTF_8))
                val hashStr = android.util.Base64.encodeToString(hashBytes, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
                val shortName = GocryptfsFileNameCryptor.LONGNAME_PREFIX + hashStr

                val renamed = renameDocumentAndGet(physicalNode, shortName)
                movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)

                val nameFile = createFileSafe(newParentPhysical, "application/octet-stream", "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}")
                    ?: throw GocryptfsIOException("Could not create .name file")
                writeWhole(nameFile, newCiphertextName.toByteArray(Charsets.UTF_8))
            }

            if (wasLongName) {
                // The old sidecar is a sibling in the OLD parent, not nested
                // inside the moved node, so it doesn't move automatically.
                childOf(oldParentPhysical, "$oldPhysicalName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}")?.delete()
            }
        }
        tree.invalidate(oldParentPath)
        tree.invalidate(newParentPath)
        if (node is GocryptfsNode.VDir) tree.invalidate(oldNormalized)
        true
    } catch (e: Exception) {
        false
    }
}

    fun deleteFile(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            openReads.remove(normalized)
            val node = tree.resolve(normalized) ?: return false
            val parentPhysical = runCatching { tree.physicalFolderFor(parentOf(normalized)) }.getOrNull()

            val physicalName = when (node) {
                is GocryptfsNode.VDir -> node.physicalFolder.name
                is GocryptfsNode.VFile -> node.physicalFile.name
            } ?: ""

            when (node) {
                is GocryptfsNode.VDir -> deleteRecursively(node.physicalFolder)
                is GocryptfsNode.VFile -> node.physicalFile.delete()
            }

            // Gocryptfs keeps the .name file right alongside the content file
            if (physicalName.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX)) {
                parentPhysical?.let { childOf(it, "$physicalName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}")?.delete() }
            }

            tree.invalidate(parentOf(normalized))
            true
        } catch (e: Exception) {
            false
        }
    }

    fun setLastModifiedTime(virtualPath: String, epochSeconds: Long): Boolean {
        return tree.resolve(normalize(virtualPath)) != null
    }

fun getFileSize(virtualPath: String): Long {
    val node = tree.resolve(normalize(virtualPath)) ?: return -1L
    val f = node as? GocryptfsNode.VFile ?: return -1L
    return contentCryptor.cleartextSize(f.physicalFile.length())
}

fun getFolderSize(virtualPath: String): Long {
    val normalized = normalize(virtualPath)
    val nodes = tree.list(normalized)
    var total = 0L
    for (node in nodes) {
        total += when (node) {
            is GocryptfsNode.VFile -> contentCryptor.cleartextSize(node.physicalFile.length())
            is GocryptfsNode.VDir -> getFolderSize(joinPath(normalized, node.cleartextName))
        }
    }
    return total
}

    // ---- file content read/write ----------------------------------------------

    /** Decrypts and returns [length] bytes starting at [offset], or null on error/missing file. */
fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? {
    val normalized = normalize(virtualPath)
    return try {
        val physicalFileProvider = {
            (tree.resolve(normalized) as? GocryptfsNode.VFile)?.physicalFile
                ?: throw GocryptfsPathNotFoundException(normalized)
        }
        readRange(physicalFileProvider, offset, length, normalized)
    } catch (e: Exception) {
        openReads.remove(normalized)
        null
    }
}

    private fun readRange(resolvePhysicalFile: () -> DocumentFile, offset: Long, length: Int, normalizedPath: String): ByteArray? {
    val chunkSize = GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE
    val cipherChunkSize = GocryptfsContentCryptor.CIPHERTEXT_CHUNK_SIZE
    val headerSize = GocryptfsContentCryptor.HEADER_LEN

    var handle = openReads.get(normalizedPath)

    if (handle == null) {
        val physicalFile = resolvePhysicalFile()
        var pfd: android.os.ParcelFileDescriptor? = null
        var stream: java.io.InputStream? = null
        try {
            pfd = context.contentResolver.openFileDescriptor(physicalFile.uri, "r")
            if (pfd != null) {
                stream = java.io.FileInputStream(pfd.fileDescriptor)
            }
        } catch (e: Exception) { }

        if (stream == null) {
            stream = context.contentResolver.openInputStream(physicalFile.uri)
        }
        if (stream == null) return null

        val headerBytes = ByteArray(headerSize)
        if (readFully(stream, headerBytes) < headerSize) {
            try { stream.close() } catch (_: Exception) {}
            try { pfd?.close() } catch (_: Exception) {}
            return ByteArray(0)
        }
        val header = contentCryptor.decodeHeader(headerBytes)
        handle = ReadHandle(pfd, stream, header, headerSize.toLong())
        openReads.put(normalizedPath, handle)
    }

        val startChunk = offset / chunkSize
        val endOffsetExclusive = offset + length
        var chunkNumber = startChunk
        var producedSoFar = startChunk * chunkSize
        val out = java.io.ByteArrayOutputStream(length.coerceAtMost(4 * 1024 * 1024))
        
        while (producedSoFar < endOffsetExclusive) {
            val cleartext: ByteArray
            if (handle!!.cachedChunkIndex == chunkNumber && handle!!.cachedChunkCleartext != null) {
                cleartext = handle!!.cachedChunkCleartext!!
            } else {
                val desiredPos = headerSize.toLong() + chunkNumber * cipherChunkSize
                
                if (handle!!.currentPos != desiredPos) {
                    var positioned = false
                    if (handle!!.pfd != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                        try {
                            android.system.Os.lseek(handle!!.pfd!!.fileDescriptor, desiredPos, android.system.OsConstants.SEEK_SET)
                            handle!!.currentPos = desiredPos
                            positioned = true
                        } catch (e: Exception) {}
                    }
                    if (!positioned && handle!!.stream is java.io.FileInputStream) {
                        try {
                            handle!!.stream.channel.position(desiredPos)
                            handle!!.currentPos = desiredPos
                            positioned = true
                        } catch (e: Exception) {}
                    }
                    if (!positioned) {
                    if (handle!!.currentPos > desiredPos) {
                        openReads.remove(normalizedPath)
                        return readRange(resolvePhysicalFile, offset, length, normalizedPath)  // was: physicalFile
                    } else {
                            var remaining = desiredPos - handle!!.currentPos
                            val skipBuf = ByteArray(64 * 1024)
                            while (remaining > 0L) {
                                val toSkip = minOf(remaining, skipBuf.size.toLong()).toInt()
                                val actuallyRead = handle!!.stream.read(skipBuf, 0, toSkip)
                                if (actuallyRead <= 0) break
                                remaining -= actuallyRead
                                handle!!.currentPos += actuallyRead
                            }
                        }
                    }
                }

                val cipherBuf = ByteArray(cipherChunkSize)
                val n = readFully(handle!!.stream, cipherBuf)
                if (n <= 0) break
                handle!!.currentPos += n
                val actualCiphertext = if (n == cipherBuf.size) cipherBuf else cipherBuf.copyOf(n)
                
                cleartext = contentCryptor.decryptChunk(actualCiphertext, chunkNumber, handle!!.typedHeader())
                handle!!.cachedChunkIndex = chunkNumber
                handle!!.cachedChunkCleartext = cleartext
            }

            val chunkStart = producedSoFar
            val chunkEnd = chunkStart + cleartext.size
            val wantStart = maxOf(offset, chunkStart)
            val wantEnd = minOf(endOffsetExclusive, chunkEnd)
            if (wantStart < wantEnd) {
                out.write(cleartext, (wantStart - chunkStart).toInt(), (wantEnd - wantStart).toInt())
            }

            producedSoFar = chunkEnd
            chunkNumber += 1
            if (cleartext.size < chunkSize) break // Short chunk means EOF
        }
        return out.toByteArray()
    }

    private fun readFully(stream: java.io.InputStream, buf: ByteArray): Int {
        var total = 0
        while (total < buf.size) {
            val n = stream.read(buf, total, buf.size - total)
            if (n < 0) break
            total += n
        }
        return total
    }

    fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            openReads.remove(normalized)
            val handle = openWrites.getOrPut(normalized) { beginWrite(normalized) }
            if (offset != handle.bytesWrittenSoFar) {
                handle.abort()
                openWrites.remove(normalized)
                return false
            }
            handle.append(data)
            true
        } catch (e: Exception) {
            openWrites.remove(virtualPath)?.abort()
            false
        }
    }

    fun finishWrite(virtualPath: String): Boolean {
        val normalized = normalize(virtualPath)
        openReads.remove(normalized)
        val handle = openWrites.remove(normalized) ?: return true
        return try {
            handle.commit()
            tree.invalidate(parentOf(normalized))
            true
        } catch (e: Exception) {
            handle.abort()
            false
        }
    }

    fun writeBackFile(virtualPath: String, sourcePath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            openReads.remove(normalized)
            openWrites.remove(normalized)?.abort()
            val handle = beginWrite(normalized)
            File(sourcePath).inputStream().use { input ->
                val buf = ByteArray(GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    handle.append(if (n == buf.size) buf else buf.copyOf(n))
                }
            }
            handle.commit()
            tree.invalidate(parentOf(normalized))
            true
       } catch (e: Exception) {
            android.util.Log.e("GocryptfsSession", "writeBackFile failed for $virtualPath", e)
            false
        }
    }

    fun extractFile(virtualPath: String, destinationPath: String): Boolean {
        return try {
            val node = tree.resolve(normalize(virtualPath)) as? GocryptfsNode.VFile ?: return false
            File(destinationPath).outputStream().use { out ->
                context.contentResolver.openInputStream(node.physicalFile.uri)?.use { rawStream ->
                    val headerBytes = ByteArray(GocryptfsContentCryptor.HEADER_LEN)
                    if (readFully(rawStream, headerBytes) < GocryptfsContentCryptor.HEADER_LEN) return true
                    val header = contentCryptor.decodeHeader(headerBytes)
                    var chunkNumber = 0L
                    val cipherBuf = ByteArray(GocryptfsContentCryptor.CIPHERTEXT_CHUNK_SIZE)
                    while (true) {
                        val n = readFully(rawStream, cipherBuf)
                        if (n <= 0) break
                        val actual = if (n == cipherBuf.size) cipherBuf else cipherBuf.copyOf(n)
                        val cleartext = contentCryptor.decryptChunk(actual, chunkNumber, header)
                        out.write(cleartext)
                        chunkNumber += 1
                        if (n < cipherBuf.size) break
                    }
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    fun getSpaceInfo(): LongArray? {
        return try {
            val rootUri = android.provider.DocumentsContract.buildRootsUri(vaultRootUri.authority)
            context.contentResolver.query(
                rootUri,
                arrayOf(android.provider.DocumentsContract.Root.COLUMN_AVAILABLE_BYTES, android.provider.DocumentsContract.Root.COLUMN_CAPACITY_BYTES),
                null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val availIdx = cursor.getColumnIndex(android.provider.DocumentsContract.Root.COLUMN_AVAILABLE_BYTES)
                    val capIdx = cursor.getColumnIndex(android.provider.DocumentsContract.Root.COLUMN_CAPACITY_BYTES)
                    val avail = if (availIdx >= 0) cursor.getLong(availIdx) else -1L
                    val cap = if (capIdx >= 0) cursor.getLong(capIdx) else -1L
                    if (cap > 0L && avail >= 0L) return longArrayOf(cap, avail)
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    // ---- write-handle: buffers cleartext, flushes full ciphertext chunks -----

    private inner class WriteHandle(private val virtualPath: String) {
        private var pendingCleartext = java.io.ByteArrayOutputStream()
        var bytesWrittenSoFar = 0L
            private set
        private val header = contentCryptor.createHeader()
        private var nextChunkNumber = 0L
        private val tempFile = File.createTempFile("go_write_", ".tmp", context.cacheDir)
        private val tempOut = java.io.BufferedOutputStream(java.io.FileOutputStream(tempFile))
        private var committed = false

        fun append(data: ByteArray) {
            pendingCleartext.write(data)
            bytesWrittenSoFar += data.size
            flushFullChunks(finalFlush = false)
        }

        private fun flushFullChunks(finalFlush: Boolean) {
            val buffered = pendingCleartext.toByteArray()
            var offset = 0
            while (buffered.size - offset >= GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE) {
                val chunk = buffered.copyOfRange(offset, offset + GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE)
                tempOut.write(contentCryptor.encryptChunk(chunk, nextChunkNumber, header))
                nextChunkNumber += 1
                offset += GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE
            }
            val remainder = buffered.copyOfRange(offset, buffered.size)
            pendingCleartext = java.io.ByteArrayOutputStream().apply { write(remainder) }
            if (finalFlush && remainder.isNotEmpty()) {
                tempOut.write(contentCryptor.encryptChunk(remainder, nextChunkNumber, header))
                nextChunkNumber += 1
                pendingCleartext = java.io.ByteArrayOutputStream()
            }
        }

        fun commit() {
            try {
                flushFullChunks(finalFlush = true)
                tempOut.flush()
                tempOut.close()

                val normalized = normalize(virtualPath)
                val parentPath = parentOf(normalized)
                val name = nameOf(normalized)
                val parentDirIv = tree.dirivFor(parentPath)
                val parentPhysical = tree.physicalFolderFor(parentPath) 

                val existing = tree.resolve(normalized) as? GocryptfsNode.VFile
                val physicalTarget: DocumentFile = if (existing != null) {
                    existing.physicalFile
                } else {
                    val ciphertextName = nameCryptor.encryptName(name, parentDirIv)
                    createNewFileNode(parentPhysical, ciphertextName, name)
                }

                context.contentResolver.openOutputStream(physicalTarget.uri, "wt")?.use { out ->
                    out.write(contentCryptor.encodeHeader(header))
                    tempFile.inputStream().use { it.copyTo(out) }
                } ?: throw GocryptfsIOException("Could not open ${physicalTarget.uri} for writing")
                committed = true
            } finally {
                tempFile.delete()
            }
        }

        fun abort() {
            try {
                if (!committed) tempOut.close()
            } catch (_: Exception) {
                // best-effort close
            }
            tempFile.delete()
        }
    }

    private fun beginWrite(virtualPath: String): WriteHandle = WriteHandle(virtualPath)

    // ---- physical SAF helpers ----------------------------------------------

    private fun listFilesSafe(folder: DocumentFile): List<DocumentFile> {
        val childrenUri = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(folder.uri, android.provider.DocumentsContract.getDocumentId(folder.uri))
        val results = mutableListOf<DocumentFile>()
        val projection = arrayOf(android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        try {
            context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                while (cursor.moveToNext()) {
                    val docId = cursor.getString(idIdx)
                    val childUri = android.provider.DocumentsContract.buildDocumentUriUsingTree(folder.uri, docId)
                    DocumentFile.fromSingleUri(context, childUri)?.let { results.add(it) }
                }
            }
        } catch (e: Exception) {
            // Ignored
        }
        return results
    }

    private fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? {
        return try {
            val uri = android.provider.DocumentsContract.createDocument(context.contentResolver, parent.uri, android.provider.DocumentsContract.Document.MIME_TYPE_DIR, name)
            uri?.let { DocumentFile.fromSingleUri(context, it) }
        } catch (e: Exception) { null }
    }

    private fun createFileSafe(parent: DocumentFile, mimeType: String, name: String): DocumentFile? {
        return try {
            val uri = android.provider.DocumentsContract.createDocument(context.contentResolver, parent.uri, mimeType, name)
            uri?.let { DocumentFile.fromSingleUri(context, it) }
        } catch (e: Exception) { null }
    }

    private fun childOf(folder: DocumentFile, name: String): DocumentFile? = listFilesSafe(folder).firstOrNull { it.name == name }

    private fun createNodeFolder(parent: DocumentFile, ciphertextName: String, cleartextName: String): DocumentFile {
        return if (cleartextName.length <= shorteningThreshold) {
            createDirectorySafe(parent, ciphertextName) 
                ?: throw GocryptfsIOException("Could not create $ciphertextName")
        } else {
            val hashBytes = java.security.MessageDigest.getInstance("SHA-256").digest(ciphertextName.toByteArray(Charsets.UTF_8))
            val hashStr = android.util.Base64.encodeToString(hashBytes, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
            val shortName = GocryptfsFileNameCryptor.LONGNAME_PREFIX + hashStr
            val folder = createDirectorySafe(parent, shortName) 
                ?: throw GocryptfsIOException("Could not create $shortName")
            val nameFile = createFileSafe(parent, "application/octet-stream", "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}") 
                ?: throw GocryptfsIOException("Could not create .name file")
            writeWhole(nameFile, ciphertextName.toByteArray(Charsets.UTF_8))
            folder
        }
    }

    private fun createNewFileNode(parent: DocumentFile, ciphertextName: String, cleartextName: String): DocumentFile {
        return if (cleartextName.length <= shorteningThreshold) {
            createFileSafe(parent, "application/octet-stream", ciphertextName) 
                ?: throw GocryptfsIOException("Could not create $ciphertextName")
        } else {
            val hashBytes = java.security.MessageDigest.getInstance("SHA-256").digest(ciphertextName.toByteArray(Charsets.UTF_8))
            val hashStr = android.util.Base64.encodeToString(hashBytes, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
            val shortName = GocryptfsFileNameCryptor.LONGNAME_PREFIX + hashStr
            val file = createFileSafe(parent, "application/octet-stream", shortName) 
                ?: throw GocryptfsIOException("Could not create $shortName")
            val nameFile = createFileSafe(parent, "application/octet-stream", "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}") 
                ?: throw GocryptfsIOException("Could not create .name file")
            writeWhole(nameFile, ciphertextName.toByteArray(Charsets.UTF_8))
            file
        }
    }

    private fun writeWhole(file: DocumentFile, bytes: ByteArray) {
        context.contentResolver.openOutputStream(file.uri, "wt")?.use { it.write(bytes) }
            ?: throw GocryptfsIOException("Could not open ${file.uri} for writing")
    }

    private fun renameDocumentAndGet(doc: DocumentFile, newName: String): DocumentFile {
    val newUri = android.provider.DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
    return DocumentFile.fromSingleUri(context, newUri ?: doc.uri)
        ?: throw GocryptfsIOException("renameDocument failed for ${doc.uri}")
}

private fun movePhysicalDocument(doc: DocumentFile, oldParent: DocumentFile, newParent: DocumentFile) {
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
        try {
            val movedUri = android.provider.DocumentsContract.moveDocument(
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

private fun copyDocumentRecursive(source: DocumentFile, targetParent: DocumentFile): DocumentFile {
    val name = source.name ?: throw GocryptfsIOException("Source document has no name")
    return if (source.isDirectory) {
        val newDir = createDirectorySafe(targetParent, name) ?: throw GocryptfsIOException("Could not create $name in target")
        for (child in listFilesSafe(source)) copyDocumentRecursive(child, newDir)
        newDir
    } else {
        val newFile = createFileSafe(targetParent, "application/octet-stream", name)
            ?: throw GocryptfsIOException("Could not create $name in target")
        context.contentResolver.openInputStream(source.uri)?.use { input ->
            context.contentResolver.openOutputStream(newFile.uri, "wt")?.use { output ->
                input.copyTo(output)
            } ?: throw GocryptfsIOException("Could not open ${newFile.uri} for writing")
        } ?: throw GocryptfsIOException("Could not open ${source.uri} for reading")
        newFile
    }
}

    private fun renameDocument(doc: DocumentFile, newName: String) {
        android.provider.DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
            ?: throw GocryptfsIOException("renameDocument failed for ${doc.uri}")
    }

    private fun deleteRecursively(folder: DocumentFile) {
        for (child in listFilesSafe(folder)) {
            if (child.isDirectory) deleteRecursively(child)
            child.delete()
        }
        folder.delete()
    }

    // ---- path helpers ----------------------------------------------------

    private fun normalize(path: String): String = path.trim('/')
    private fun parentOf(normalizedPath: String): String {
        val idx = normalizedPath.lastIndexOf('/')
        return if (idx < 0) "" else normalizedPath.substring(0, idx)
    }
    private fun nameOf(normalizedPath: String): String {
        val idx = normalizedPath.lastIndexOf('/')
        return if (idx < 0) normalizedPath else normalizedPath.substring(idx + 1)
    }
    private fun joinPath(parent: String, name: String): String = if (parent.isEmpty()) name else "$parent/$name"
}
