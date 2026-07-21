package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.engine.ChunkedEngineDelegate
import com.aeidolon.vaultexplorer.engine.ChunkedFileEngine
import com.aeidolon.vaultexplorer.engine.VaultChunkCryptor
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.io.File
import java.security.SecureRandom
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultPathNotFoundException
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
) : com.aeidolon.vaultexplorer.VaultBackend {
    override val format = com.aeidolon.vaultexplorer.ContainerFormat.GOCRYPTFS
    private val random = SecureRandom()
    private val safOps = SafDocumentOps(context)
    private val shorteningThreshold: Int by lazy {
        try {
            val field = nameCryptor.javaClass.getDeclaredField("longNameMax")
            field.isAccessible = true
            field.get(nameCryptor) as Int
        } catch (e: Exception) {
            176 // Fallback to standard gocryptfs cleartext limit
        }
    }

    private val chunkCryptor = object : VaultChunkCryptor<GocryptfsFileHeader> {
        override val headerSize: Int get() = GocryptfsContentCryptor.HEADER_LEN
        override val cleartextChunkSize: Int get() = GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE
        override val ciphertextChunkSize: Int get() = GocryptfsContentCryptor.CIPHERTEXT_CHUNK_SIZE

        override fun createHeader(): GocryptfsFileHeader = contentCryptor.createHeader()
        override fun encodeHeader(header: GocryptfsFileHeader): ByteArray = contentCryptor.encodeHeader(header)
        override fun decodeHeader(bytes: ByteArray): GocryptfsFileHeader = contentCryptor.decodeHeader(bytes)

        override fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: GocryptfsFileHeader): ByteArray =
            contentCryptor.encryptChunk(cleartext, chunkNumber, header)
        override fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: GocryptfsFileHeader): ByteArray =
            contentCryptor.decryptChunk(ciphertext, chunkNumber, header)
    }

    private val engineDelegate = object : ChunkedEngineDelegate<GocryptfsFileHeader> {
        override val context: Context get() = this@GocryptfsSession.context
        override val readOnly: Boolean get() = this@GocryptfsSession.readOnly
        override val cryptor: VaultChunkCryptor<GocryptfsFileHeader> get() = chunkCryptor

        override fun getPhysicalFileForRead(virtualPath: String): DocumentFile? =
            (tree.resolve(virtualPath) as? GocryptfsNode.VFile)?.physicalFile

        override fun getOrCreatePhysicalFileForWrite(virtualPath: String): DocumentFile {
            val parentPath = parentOf(virtualPath)
            val name = nameOf(virtualPath)
            val parentDirIv = tree.dirivFor(parentPath)
            val parentPhysical = tree.physicalFolderFor(parentPath)

            val existing = tree.resolve(virtualPath) as? GocryptfsNode.VFile
            return existing?.physicalFile ?: run {
                val ciphertextName = nameCryptor.encryptName(name, parentDirIv)
                createNewFileNode(parentPhysical, ciphertextName, name)
            }
        }

        override fun invalidateCacheAfterWrite(virtualPath: String) {
            tree.invalidate(parentOf(virtualPath))
        }
    }

    private val engine = ChunkedFileEngine(engineDelegate)

    fun close() {
        engine.close()
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

    override fun listDirectory(virtualPath: String): Array<String>? {
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
        } catch (e: VaultPathNotFoundException) {
            null
        } catch (e: VaultIOException) {
            null
        }
    }

    override fun createDirectory(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)

            // Idempotent: callers (e.g. ThumbnailCacheService) call this on
            // every write, not just the first. Since the ciphertext name is
            // deterministic, creating it again previously asked SAF for a
            // duplicate display name — Android's local-storage provider
            // doesn't fail that, it silently appends " (2)", " (3)", etc,
            // leaving corrupted, undecryptable duplicate folders behind.
            val existing = tree.resolve(normalized)
            if (existing is GocryptfsNode.VDir) return true
            if (existing != null) return false // a file already occupies this path

            val parentPath = parentOf(normalized)
            val name = nameOf(normalized)
            val parentDirIv = tree.dirivFor(parentPath)
            val parentPhysical = tree.physicalFolderFor(parentPath)

            val ciphertextName = nameCryptor.encryptName(name, parentDirIv)
            createNodeFolder(parentPhysical, ciphertextName, name)

            tree.dirivFor(normalized)
            tree.invalidate(parentPath)
            true
        } catch (e: Exception) {
            android.util.Log.e("GocryptfsSession", "createDirectory failed for $virtualPath", e)
            false
        }
    }

    override fun renameFile(oldVirtualPath: String, newVirtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val oldNormalized = normalize(oldVirtualPath)
            val newNormalized = normalize(newVirtualPath)
            engine.invalidateRead(oldNormalized)
            engine.invalidateRead(newNormalized)
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
                        ?: throw VaultIOException("Could not create .name file")
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
                        ?: throw VaultIOException("Could not create .name file")
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

    override fun deleteFile(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            engine.invalidateRead(normalized)
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

    override fun setLastModifiedTime(virtualPath: String, epochSeconds: Long): Boolean {
        return tree.resolve(normalize(virtualPath)) != null
    }

    override fun getFileSize(virtualPath: String): Long {
        val node = tree.resolve(normalize(virtualPath)) ?: return -1L
        val f = node as? GocryptfsNode.VFile ?: return -1L
        return contentCryptor.cleartextSize(f.physicalFile.length())
    }

    override fun getFolderSize(virtualPath: String): Long {
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

    override fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? =
        engine.readFileChunk(virtualPath, offset, length)

    override fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean =
        engine.writeFileChunk(virtualPath, offset, data)

    override fun finishWrite(virtualPath: String): Boolean =
        engine.finishWrite(virtualPath)

    override fun writeBackFile(virtualPath: String, sourcePath: String): Boolean =
        engine.writeBackFile(virtualPath, sourcePath)

    override fun extractFile(virtualPath: String, destinationPath: String): Boolean =
        engine.extractFile(virtualPath, destinationPath)

    override fun getSpaceInfo(): LongArray? {
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

    // ---- physical SAF helpers ----------------------------------------------
    // (shared implementation lives in SafDocumentOps — see the tech-debt
    // audit; kept as same-named wrappers here so createNodeFolder,
    // createNewFileNode, renameFile, deleteFile, etc. above don't need to
    // change)

    private fun listFilesSafe(folder: DocumentFile): List<DocumentFile> = safOps.listChildren(folder)

    private fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? =
        safOps.createDirectorySafe(parent, name)

    private fun createFileSafe(parent: DocumentFile, mimeType: String, name: String): DocumentFile? =
        safOps.createFileSafe(parent, mimeType, name)

    private fun childOf(folder: DocumentFile, name: String): DocumentFile? = safOps.childOf(folder, name)
    private fun createNodeFolder(parent: DocumentFile, ciphertextName: String, cleartextName: String): DocumentFile {
        return if (cleartextName.length <= shorteningThreshold) {
            createDirectorySafe(parent, ciphertextName) 
                ?: throw VaultIOException("Could not create $ciphertextName")
        } else {
            val hashBytes = java.security.MessageDigest.getInstance("SHA-256").digest(ciphertextName.toByteArray(Charsets.UTF_8))
            val hashStr = android.util.Base64.encodeToString(hashBytes, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
            val shortName = GocryptfsFileNameCryptor.LONGNAME_PREFIX + hashStr
            val folder = createDirectorySafe(parent, shortName) 
                ?: throw VaultIOException("Could not create $shortName")
            val nameFile = createFileSafe(parent, "application/octet-stream", "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}") 
                ?: throw VaultIOException("Could not create .name file")
            writeWhole(nameFile, ciphertextName.toByteArray(Charsets.UTF_8))
            folder
        }
    }

    private fun createNewFileNode(parent: DocumentFile, ciphertextName: String, cleartextName: String): DocumentFile {
        return if (cleartextName.length <= shorteningThreshold) {
            createFileSafe(parent, "application/octet-stream", ciphertextName) 
                ?: throw VaultIOException("Could not create $ciphertextName")
        } else {
            val hashBytes = java.security.MessageDigest.getInstance("SHA-256").digest(ciphertextName.toByteArray(Charsets.UTF_8))
            val hashStr = android.util.Base64.encodeToString(hashBytes, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
            val shortName = GocryptfsFileNameCryptor.LONGNAME_PREFIX + hashStr
            val file = createFileSafe(parent, "application/octet-stream", shortName) 
                ?: throw VaultIOException("Could not create $shortName")
            val nameFile = createFileSafe(parent, "application/octet-stream", "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}") 
                ?: throw VaultIOException("Could not create .name file")
            writeWhole(nameFile, ciphertextName.toByteArray(Charsets.UTF_8))
            file
        }
    }

    private fun writeWhole(file: DocumentFile, bytes: ByteArray) = safOps.writeWhole(file, bytes)

    private fun renameDocumentAndGet(doc: DocumentFile, newName: String): DocumentFile =
        safOps.renameDocumentAndGet(doc, newName)

    private fun movePhysicalDocument(doc: DocumentFile, oldParent: DocumentFile, newParent: DocumentFile) =
        safOps.movePhysicalDocument(doc, oldParent, newParent)

    private fun renameDocument(doc: DocumentFile, newName: String) = safOps.renameDocument(doc, newName)

    private fun deleteRecursively(folder: DocumentFile) = safOps.deleteRecursively(folder)
    
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
