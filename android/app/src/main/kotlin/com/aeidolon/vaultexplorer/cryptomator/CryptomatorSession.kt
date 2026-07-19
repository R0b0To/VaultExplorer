package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * One unlocked Cryptomator vault, keyed by the same `volId` space
 * VeraCrypt/LUKS sessions use (see ContainerSessionRegistry). Holds the
 * decrypted masterkey, vault config, and vault tree, and implements the
 * same Tier-2 file/directory surface ContainerEngine exposes to Dart —
 * `listDirectory`, `readFileChunk`, `writeFileChunk`, etc. — operating on
 * cleartext virtual paths instead of a FatFs-mounted block device.
 *
 * Unlike VeraCryptEngine's native VolumeState slots, this holds no native
 * resources — everything here is plain Kotlin/JVM objects (SAF handles,
 * decrypted key material in memory). [close] zeroes the masterkey.
 */
class CryptomatorSession(
    private val context: Context,
    val vaultRootUri: Uri,
    val masterkey: CryptomatorMasterkey,
    val vaultFormat: Int,
    val cipherCombo: String,
    val shorteningThreshold: Int,
    val readOnly: Boolean,
) {
    private val random = SecureRandom()
    val nameCryptor = CryptomatorFileNameCryptor(masterkey)
    val contentCryptor: CryptomatorContentCryptor = CryptomatorContentCryptor.forCipherCombo(cipherCombo)
    val tree = CryptomatorVaultTree(context, vaultRootUri, nameCryptor, shorteningThreshold)

    /** Open write handles for in-progress sequential writeFileChunk() sequences, keyed by virtual path. */
    private val openWrites = ConcurrentHashMap<String, WriteHandle>()

    fun close() {
        openWrites.values.forEach { it.abort() }
        openWrites.clear()
        masterkey.destroy()
    }

    // ---- directory listing ----------------------------------------------------

    /** Mirrors VeraCryptEngine.listDirectory: returns child names (folders end with '/'), or null if the path doesn't exist. */
fun listDirectory(virtualPath: String): Array<String>? {
    return try {
        val normalized = normalize(virtualPath)
        val nodes = tree.list(normalized)
        nodes.map { node ->
            when (node) {
                is VaultNode.VDir -> {
                    val mtime = node.physicalFolder.lastModified() / 1000L
                    "[DIR] ${node.cleartextName}|0|$mtime"
                }
                is VaultNode.VFile -> {
                    val ciphertextSize = node.physicalFile.length()
                    val withoutHeader = ciphertextSize - contentCryptor.headerSize
                    val cleartextSize = if (withoutHeader < 0) 0L else contentCryptor.cleartextSize(withoutHeader)
                    val mtime = node.physicalFile.lastModified() / 1000L
                    "${node.cleartextName}|$cleartextSize|$mtime"
                }
            }
        }.toTypedArray()
    } catch (e: VaultPathNotFoundException) {
        null
    } catch (e: VaultIOException) {
        null
    }
}

    fun createDirectory(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            val parentPath = parentOf(normalized)
            val name = nameOf(normalized)
            val parentDirId = tree.resolveDirId(parentPath)
            val parentPhysical = tree.physicalFolderForDirId(parentDirId)

            val newDirId = UUID.randomUUID().toString()
            val ciphertextName = nameCryptor.encryptFilename(name, parentDirId.toByteArray(Charsets.UTF_8))
            createNodeFolder(parentPhysical, ciphertextName) { nodeFolder ->
                val dirIdBytes = newDirId.toByteArray(Charsets.UTF_8)
                val dirFile = createFileSafe(nodeFolder, "application/octet-stream", "dir.c9r")
                    ?: throw VaultIOException("Could not create dir.c9r")
                writeWhole(dirFile, dirIdBytes)
            }

            // Ensure the physical two-level (d/xx/yyyy) storage folder for the new directory exists.
            val hash = nameCryptor.hashDirectoryId(newDirId)
            val dataDir = requireNonNull(findOrCreateChild(vaultRoot(), "d", isDir = true))
            val lvl1 = requireNonNull(findOrCreateChild(dataDir, hash.substring(0, 2), isDir = true))
            findOrCreateChild(lvl1, hash.substring(2), isDir = true)

            tree.invalidate(parentPath)
            true
        } catch (e: Exception) {
            android.util.Log.e("CryptomatorSession", "createDirectory failed for $virtualPath", e)
            false
        }
    }

    fun renameFile(oldVirtualPath: String, newVirtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val oldNormalized = normalize(oldVirtualPath)
            val newNormalized = normalize(newVirtualPath)
            val node = tree.resolve(oldNormalized) ?: return false

            val oldParentPath = parentOf(oldNormalized)
            val newParentPath = parentOf(newNormalized)
            val newName = nameOf(newNormalized)

            if (oldParentPath == newParentPath) {
                // Simple rename within the same directory: re-encrypt the name and rename the physical .c9r/.c9s entry.
                val parentDirId = tree.resolveDirId(oldParentPath)
                val newCiphertextName = nameCryptor.encryptFilename(newName, parentDirId.toByteArray(Charsets.UTF_8))
                val physicalNode = when (node) {
                    is VaultNode.VDir -> node.physicalFolder
                    is VaultNode.VFile -> node.wrapperFolder ?: node.physicalFile
                }
                val isShortened = physicalNode.name?.endsWith(".c9s") == true
                if (isShortened) {
                    // Shortened entries keep their (hash-derived) physical folder name; only name.c9r's contents change.
                    val nameFile = childOf(physicalNode, "name.c9r") ?: return false
                    writeWhole(nameFile, (newCiphertextName + ".c9r").toByteArray(Charsets.UTF_8))
                } else {
                    renameDocument(physicalNode, newCiphertextName + ".c9r")
                }
            } else {
                // Cross-directory move: not yet supported by this rename path; caller should use move semantics.
                return false
            }
            tree.invalidate(oldParentPath)
            tree.invalidate(newParentPath)
            true
        } catch (e: Exception) {
            false
        }
    }

    fun deleteFile(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            val node = tree.resolve(normalized) ?: return false
            when (node) {
                is VaultNode.VDir -> {
                    val dirId = tree.readDirId(node.dirIdFile)
                    val physicalContents = tree.physicalFolderForDirId(dirId)
                    deleteRecursively(physicalContents)
                    node.physicalFolder.delete()
                }
                is VaultNode.VFile -> {
                    val container = node.wrapperFolder
                    if (container != null && container.name?.endsWith(".c9s") == true) {
                        deleteRecursively(container)
                    } else {
                        node.physicalFile.delete()
                    }
                }
            }
            tree.invalidate(parentOf(normalized))
            true
        } catch (e: Exception) {
            false
        }
    }

    fun setLastModifiedTime(virtualPath: String, epochSeconds: Long): Boolean {
        // SAF's DocumentFile has no portable "set mtime" — most providers derive
        // mtime from last write. Treat as best-effort no-op success so callers
        // (e.g. copy operations) don't hard-fail; the file's actual mtime will
        // reflect when its ciphertext bytes were last written, which is close
        // enough for a passthrough vault (VeraCrypt/LUKS preserve mtime because
        // they own the filesystem; Cryptomator vaults live on whatever
        // filesystem SAF exposes, which may not support it at all).
        return tree.resolve(normalize(virtualPath)) != null
    }

    fun getFileSize(virtualPath: String): Long {
        val node = tree.resolve(normalize(virtualPath)) ?: return -1L
        val f = node as? VaultNode.VFile ?: return -1L
        val ciphertextSize = f.physicalFile.length()
        val withoutHeader = ciphertextSize - contentCryptor.headerSize
        if (withoutHeader < 0) return 0L
        return contentCryptor.cleartextSize(withoutHeader)
    }

    fun getFolderSize(virtualPath: String): Long {
        val normalized = normalize(virtualPath)
        val nodes = tree.list(normalized)
        var total = 0L
        for (node in nodes) {
            total += when (node) {
                is VaultNode.VFile -> {
                    val withoutHeader = node.physicalFile.length() - contentCryptor.headerSize
                    if (withoutHeader < 0) 0L else contentCryptor.cleartextSize(withoutHeader)
                }
                is VaultNode.VDir -> getFolderSize(joinPath(normalized, node.cleartextName))
            }
        }
        return total
    }

    // ---- file content read/write ----------------------------------------------

    /** Mirrors VeraCryptEngine.readFileChunk: decrypts and returns [length] bytes starting at [offset], or null on error/missing file. */
    fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? {
        return try {
            val node = tree.resolve(normalize(virtualPath)) as? VaultNode.VFile ?: return null
            readRange(node.physicalFile, offset, length)
        } catch (e: Exception) {
            null
        }
    }

    private fun readRange(physicalFile: DocumentFile, offset: Long, length: Int): ByteArray? {
        context.contentResolver.openInputStream(physicalFile.uri)?.use { rawStream ->
            val headerBytes = ByteArray(contentCryptor.headerSize)
            if (readFully(rawStream, headerBytes) < contentCryptor.headerSize) return ByteArray(0)
            val header = contentCryptor.decryptHeader(headerBytes, masterkey)

            val chunkSize = contentCryptor.cleartextChunkSize
            val cipherChunkSize = contentCryptor.ciphertextChunkSize
            val startChunk = offset / chunkSize
            val endOffsetExclusive = offset + length

            // Skip to the first needed chunk.
            var chunkNumber = 0L
            val skipBytes = startChunk * cipherChunkSize
            var remaining = skipBytes
            val skipBuf = ByteArray(64 * 1024)
            while (remaining > 0) {
                val toSkip = minOf(remaining, skipBuf.size.toLong()).toInt()
                val actuallyRead = rawStream.read(skipBuf, 0, toSkip)
                if (actuallyRead <= 0) return ByteArray(0)
                remaining -= actuallyRead
            }
            chunkNumber = startChunk

            val out = java.io.ByteArrayOutputStream(length.coerceAtMost(4 * 1024 * 1024))
            var producedSoFar = startChunk * chunkSize
            val cipherBuf = ByteArray(cipherChunkSize)
            while (producedSoFar < endOffsetExclusive) {
                val n = readFully(rawStream, cipherBuf)
                if (n <= 0) break
                val actualCiphertext = if (n == cipherBuf.size) cipherBuf else cipherBuf.copyOf(n)
                val cleartext = contentCryptor.decryptChunk(actualCiphertext, chunkNumber, header, masterkey)

                val chunkStart = producedSoFar
                val chunkEnd = chunkStart + cleartext.size
                val wantStart = maxOf(offset, chunkStart)
                val wantEnd = minOf(endOffsetExclusive, chunkEnd)
                if (wantStart < wantEnd) {
                    out.write(cleartext, (wantStart - chunkStart).toInt(), (wantEnd - wantStart).toInt())
                }

                producedSoFar = chunkEnd
                chunkNumber += 1
                if (n < cipherBuf.size) break // last chunk was short -> EOF
            }
            return out.toByteArray()
        }
        return null
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

    /**
     * Mirrors VeraCryptEngine.writeFileChunk: appends [data] at [offset] to
     * the (cleartext) file being built. Per the actual call pattern in this
     * app, offsets always arrive in increasing, contiguous order starting at
     * 0 for any given file — so this buffers cleartext until a full
     * ciphertext chunk's worth is ready, encrypts, and streams it out,
     * rather than supporting true random-access patch writes (which chunked
     * AEAD schemes can't do cheaply anyway without decrypt-modify-encrypt of
     * the target chunk).
     */
    fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            val handle = openWrites.getOrPut(normalized) { beginWrite(normalized) }
            if (offset != handle.bytesWrittenSoFar) {
                // Out-of-order/non-contiguous write: unsupported by the buffering
                // scheme above. Abort and fail cleanly rather than silently
                // producing a corrupt file.
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

    /** Finalizes and closes a writeFileChunk() sequence for [virtualPath], flushing any buffered final partial chunk. Callers should invoke this after their last writeFileChunk() call for a given file. */
    fun finishWrite(virtualPath: String): Boolean {
        val normalized = normalize(virtualPath)
        val handle = openWrites.remove(normalized) ?: return true // nothing open; treat as already-finished
        return try {
            handle.commit()
            tree.invalidate(parentOf(normalized))
            true
        } catch (e: Exception) {
            handle.abort()
            false
        }
    }

    /** Mirrors VeraCryptEngine.writeBackFile: whole-file replace from a local plaintext file. */
    fun writeBackFile(virtualPath: String, sourcePath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            openWrites.remove(normalized)?.abort() // discard any stale partial write for this path
            val handle = beginWrite(normalized)
            File(sourcePath).inputStream().use { input ->
                val buf = ByteArray(contentCryptor.cleartextChunkSize)
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
            android.util.Log.e("CryptomatorSession", "writeBackFile failed for $virtualPath", e)
            false
        }
    }

    fun extractFile(virtualPath: String, destinationPath: String): Boolean {
        return try {
            val node = tree.resolve(normalize(virtualPath)) as? VaultNode.VFile ?: return false
            File(destinationPath).outputStream().use { out ->
                context.contentResolver.openInputStream(node.physicalFile.uri)?.use { rawStream ->
                    val headerBytes = ByteArray(contentCryptor.headerSize)
                    if (readFully(rawStream, headerBytes) < contentCryptor.headerSize) return true // empty file
                    val header = contentCryptor.decryptHeader(headerBytes, masterkey)
                    var chunkNumber = 0L
                    val cipherBuf = ByteArray(contentCryptor.ciphertextChunkSize)
                    while (true) {
                        val n = readFully(rawStream, cipherBuf)
                        if (n <= 0) break
                        val actual = if (n == cipherBuf.size) cipherBuf else cipherBuf.copyOf(n)
                        val cleartext = contentCryptor.decryptChunk(actual, chunkNumber, header, masterkey)
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
                    if (cap > 0 && avail >= 0) return longArrayOf(cap, avail)
                }
            }
            null // unknown — let callers treat this as "don't gate on space", not "zero space"
        } catch (e: Exception) {
            null
        }
    }

    // ---- write-handle: buffers cleartext, flushes full ciphertext chunks -----

    /**
     * Streams ciphertext directly to a temp file on internal storage as
     * cleartext chunks fill up, rather than buffering the whole file in
     * memory — bounds memory use to ~2x one cleartext chunk (32 KiB)
     * regardless of the file's total size, which matters for this app given
     * it handles large media files (video playback, big archive members).
     * On commit, the temp file's bytes are streamed into the final SAF
     * document and the temp file is deleted; on abort, the temp file is
     * simply deleted, leaving the vault untouched.
     */
    private inner class WriteHandle(private val virtualPath: String) {
        private var pendingCleartext = java.io.ByteArrayOutputStream()
        var bytesWrittenSoFar = 0L
            private set
        private val header = contentCryptor.createHeader(random)
        private var nextChunkNumber = 0L
        private val tempFile = File.createTempFile("cm_write_", ".tmp", context.cacheDir)
        private val tempOut = java.io.BufferedOutputStream(java.io.FileOutputStream(tempFile))
        private var committed = false

        fun append(data: ByteArray) {
            pendingCleartext.write(data)
            bytesWrittenSoFar += data.size
            flushFullChunks(finalFlush = false)
        }

        private fun flushFullChunks(finalFlush: Boolean) {
            val buffered = pendingCleartext.toByteArray()
            val chunkSize = contentCryptor.cleartextChunkSize
            var offset = 0
            while (buffered.size - offset >= chunkSize) {
                val chunk = buffered.copyOfRange(offset, offset + chunkSize)
                tempOut.write(contentCryptor.encryptChunk(chunk, nextChunkNumber, header, masterkey, random))
                nextChunkNumber += 1
                offset += chunkSize
            }
            val remainder = buffered.copyOfRange(offset, buffered.size)
            pendingCleartext = java.io.ByteArrayOutputStream().apply { write(remainder) }
            if (finalFlush && remainder.isNotEmpty()) {
                tempOut.write(contentCryptor.encryptChunk(remainder, nextChunkNumber, header, masterkey, random))
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
                val parentDirId = tree.resolveDirId(parentPath)
                val parentPhysical = tree.physicalFolderForDirId(parentDirId)

                val existing = tree.resolve(normalized) as? VaultNode.VFile
                val physicalTarget: DocumentFile = if (existing != null) {
                    existing.physicalFile
                } else {
                    val ciphertextName = nameCryptor.encryptFilename(name, parentDirId.toByteArray(Charsets.UTF_8))
                    createNewFileNode(parentPhysical, ciphertextName)
                }

                context.contentResolver.openOutputStream(physicalTarget.uri, "wt")?.use { out ->
                    out.write(contentCryptor.encryptHeader(header, masterkey, random))
                    tempFile.inputStream().use { it.copyTo(out) }
                } ?: throw VaultIOException("Could not open ${physicalTarget.uri} for writing")
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

    /** Safely list children bypassing SingleDocumentFile's restrictions */
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

    /** Safely create a directory bypassing SingleDocumentFile's restrictions */
    private fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? {
        return try {
            val uri = android.provider.DocumentsContract.createDocument(context.contentResolver, parent.uri, android.provider.DocumentsContract.Document.MIME_TYPE_DIR, name)
            uri?.let { DocumentFile.fromSingleUri(context, it) }
        } catch (e: Exception) { null }
    }

    /** Safely create a file bypassing SingleDocumentFile's restrictions */
    private fun createFileSafe(parent: DocumentFile, mimeType: String, name: String): DocumentFile? {
        return try {
            val uri = android.provider.DocumentsContract.createDocument(context.contentResolver, parent.uri, mimeType, name)
            uri?.let { DocumentFile.fromSingleUri(context, it) }
        } catch (e: Exception) { null }
    }

    private fun vaultRoot(): DocumentFile =
        DocumentFile.fromTreeUri(context, vaultRootUri) ?: throw VaultIOException("Cannot open vault root")

    private fun childOf(folder: DocumentFile, name: String): DocumentFile? = listFilesSafe(folder).firstOrNull { it.name == name }

    private fun findOrCreateChild(folder: DocumentFile, name: String, isDir: Boolean): DocumentFile? {
        childOf(folder, name)?.let { return it }
        return if (isDir) createDirectorySafe(folder, name) else createFileSafe(folder, "application/octet-stream", name)
    }

    /** Creates a `<ciphertextName>.c9r` folder under [parent], applying the shortening rule if the name would exceed [shorteningThreshold]. */
    private fun createNodeFolder(parent: DocumentFile, ciphertextName: String, populate: (DocumentFile) -> Unit) {
        val fullName = ciphertextName + ".c9r"
        if (fullName.length <= shorteningThreshold) {
            val folder = createDirectorySafe(parent, fullName) ?: throw VaultIOException("Could not create $fullName")
            populate(folder)
        } else {
            val hash = java.security.MessageDigest.getInstance("SHA-1").digest(fullName.toByteArray(Charsets.UTF_8))
            val shortName = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(hash) + ".c9s"
            val folder = createDirectorySafe(parent, shortName) ?: throw VaultIOException("Could not create $shortName")
            val nameFile = createFileSafe(folder, "application/octet-stream", "name.c9r") ?: throw VaultIOException("Could not create name.c9r")
            writeWhole(nameFile, fullName.toByteArray(Charsets.UTF_8))
            populate(folder)
        }
    }

    /** Creates a new file node, returning the DocumentFile that should receive the ciphertext bytes. */
    private fun createNewFileNode(parent: DocumentFile, ciphertextName: String): DocumentFile {
        val fullName = ciphertextName + ".c9r"
        return if (fullName.length <= shorteningThreshold) {
            createFileSafe(parent, "application/octet-stream", fullName) ?: throw VaultIOException("Could not create $fullName")
        } else {
            val hash = java.security.MessageDigest.getInstance("SHA-1").digest(fullName.toByteArray(Charsets.UTF_8))
            val shortName = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(hash) + ".c9s"
            val folder = createDirectorySafe(parent, shortName) ?: throw VaultIOException("Could not create $shortName")
            val nameFile = createFileSafe(folder, "application/octet-stream", "name.c9r") ?: throw VaultIOException("Could not create name.c9r")
            writeWhole(nameFile, fullName.toByteArray(Charsets.UTF_8))
            createFileSafe(folder, "application/octet-stream", "contents.c9r") ?: throw VaultIOException("Could not create contents.c9r")
        }
    }

    private fun writeWhole(file: DocumentFile, bytes: ByteArray) {
        context.contentResolver.openOutputStream(file.uri, "wt")?.use { it.write(bytes) }
            ?: throw VaultIOException("Could not open ${file.uri} for writing")
    }

    private fun renameDocument(doc: DocumentFile, newName: String) {
        android.provider.DocumentsContract.renameDocument(context.contentResolver, doc.uri, newName)
            ?: throw VaultIOException("renameDocument failed for ${doc.uri}")
    }

    private fun deleteRecursively(folder: DocumentFile) {
        for (child in listFilesSafe(folder)) {
            if (child.isDirectory) deleteRecursively(child)
            child.delete()
        }
        folder.delete()
    }

    private fun requireNonNull(doc: DocumentFile?): DocumentFile = doc ?: throw VaultIOException("Expected SAF document was null")

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

/** Process-wide registry of unlocked Cryptomator sessions, keyed by the same volId space ContainerSessionRegistry uses. */
object CryptomatorSessionRegistry {
    private val sessions = ConcurrentHashMap<Int, CryptomatorSession>()

    fun put(volId: Int, session: CryptomatorSession) {
        sessions[volId] = session
    }

    fun get(volId: Int): CryptomatorSession? = sessions[volId]

    fun remove(volId: Int) {
        sessions.remove(volId)?.close()
    }

    fun isCryptomator(volId: Int): Boolean = sessions.containsKey(volId)
}