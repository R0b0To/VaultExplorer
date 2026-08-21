package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.DirEntryWire
import com.aeidolon.vaultexplorer.engine.ChunkedEngineDelegate
import com.aeidolon.vaultexplorer.engine.ChunkedFileEngine
import com.aeidolon.vaultexplorer.engine.VaultChunkCryptor
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.io.File
import java.security.SecureRandom
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultPathNotFoundException

class GocryptfsSession(
    private val context: Context,
    val vaultRootUri: Uri,
    val nameCryptor: GocryptfsFileNameCryptor,
    val contentCryptor: GocryptfsContentCryptor,
    val tree: GocryptfsVaultTree,
    val readOnly: Boolean,
    private val cipher: GocryptfsCipher,
    private val plaintextNames: Boolean,
) : com.aeidolon.vaultexplorer.container.VaultBackend {

    override val format = com.aeidolon.vaultexplorer.container.ContainerFormat.GOCRYPTFS
    override val skipsPerVolumeLock = true

    private val safOps get() = tree.safOps
    private val chunkCryptor = object : VaultChunkCryptor<GocryptfsFileHeader> {
        override val headerSize: Int get() = GocryptfsContentCryptor.HEADER_LEN
        override val cleartextChunkSize: Int get() = GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE
        override val ciphertextChunkSize: Int get() = contentCryptor.ciphertextChunkSize
        override fun createHeader(): GocryptfsFileHeader = contentCryptor.createHeader()
        override fun encodeHeader(header: GocryptfsFileHeader): ByteArray = contentCryptor.encodeHeader(header)
        override fun decodeHeader(bytes: ByteArray): GocryptfsFileHeader = contentCryptor.decodeHeader(bytes)
        override fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: GocryptfsFileHeader): ByteArray =
            contentCryptor.encryptChunk(cleartext, chunkNumber, header)
        override fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: GocryptfsFileHeader): ByteArray =
            contentCryptor.decryptChunk(ciphertext, chunkNumber, header)
            
        override fun encryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: GocryptfsFileHeader): ByteArray =
            contentCryptor.encryptStream(inputBuffer, startChunkNumber, header)

        // Was missing: without this override, decryptStream() silently fell back to
        // VaultChunkCryptor's default (a Kotlin loop calling decryptChunk() once per
        // 4KB chunk -- single-threaded, and each call re-enters native code to build
        // a brand-new CryptoContext just to decrypt one block). encryptStream above
        // was wired to the fast batched/multi-threaded native path; this one wasn't,
        // which is the actual source of the extract-vs-writeback asymmetry.
        override fun decryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: GocryptfsFileHeader): ByteArray =
            contentCryptor.decryptStream(inputBuffer, startChunkNumber, header)
    }

    private val engineDelegate = object : ChunkedEngineDelegate<GocryptfsFileHeader> {
        override val context: Context get() = this@GocryptfsSession.context
        override val readOnly: Boolean get() = this@GocryptfsSession.readOnly
        override val cryptor: VaultChunkCryptor<GocryptfsFileHeader> get() = chunkCryptor
        override var batchWriteActive: Boolean = false

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
                createNewFileNode(parentPhysical, ciphertextName)
            }
        }

        override fun invalidateCacheAfterWrite(virtualPath: String) {
            tree.invalidate(parentOf(virtualPath))
        }
    }

    private val engine = ChunkedFileEngine(engineDelegate)

    override fun beginBatchWrite() {
        engineDelegate.batchWriteActive = true
    }

    override fun endBatchWrite() {
        engineDelegate.batchWriteActive = false
        tree.invalidateAll()
    }

    override fun invalidateCache(virtualPath: String) {
        if (virtualPath.isEmpty()) {
            tree.invalidateAll()
            engine.invalidateAll()
        } else {
            val normalized = normalize(virtualPath)
            tree.invalidate(normalized)
            engine.invalidateRead(normalized)
        }
    }

    override fun close() {
        engine.close()
    }

    override fun importStream(virtualPath: String, inputStream: java.io.InputStream, volId: Int): Boolean {
        if (readOnly) return false
        val ok = engine.writeBackStream(virtualPath, inputStream, volId)
        if (ok) {
            tree.invalidate(parentOf(virtualPath))
        }
        return ok
    }

    override fun listDirectory(virtualPath: String): Array<String>? {
        return try {
            val normalized = normalize(virtualPath)
            val nodes = tree.list(normalized)
            nodes.map { node ->
                when (node) {
                    is GocryptfsNode.VDir -> {
                        val mtime = node.physicalFolder.lastModified() / 1000L
                        DirEntryWire.encode(node.cleartextName, true, 0L, mtime)
                    }
                    is GocryptfsNode.VFile -> {
                        val ciphertextSize = node.physicalFile.length()
                        val cleartextSize = contentCryptor.cleartextSize(ciphertextSize)
                        val mtime = node.physicalFile.lastModified() / 1000L
                        DirEntryWire.encode(node.cleartextName, false, cleartextSize, mtime)
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
            val existing = tree.resolve(normalized)
            if (existing is GocryptfsNode.VDir) {
                if (tree.hasDirIV) {
                    try {
                        tree.dirivFor(normalized, existing.physicalFolder)
                    } catch (e: VaultIOException) {
                        tree.createDirIv(normalized, existing.physicalFolder)
                    }
                }
                return true
            }
            if (existing != null) return false

            val parentPath = parentOf(normalized)
            val name = nameOf(normalized)
            val parentDirIv = tree.dirivFor(parentPath)
            val parentPhysical = tree.physicalFolderFor(parentPath)
            
            val ciphertextName = nameCryptor.encryptName(name, parentDirIv)
            val newDirFolder = createNodeFolder(parentPhysical, ciphertextName)

            if (tree.hasDirIV) {
                tree.createDirIv(normalized, newDirFolder)
            }
            tree.invalidate(parentPath)
            true
        } catch (e: Exception) {
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

                if (!nameCryptor.isOverLongNameLimit(newCiphertextName)) {
                    renameDocument(physicalNode, newCiphertextName)
                } else {
                    val shortName = nameCryptor.hashLongName(newCiphertextName)
                    renameDocument(physicalNode, shortName)
                    val nameFile = createFileSafe(parentPhysical, "application/octet-stream", "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}")
                        ?: throw VaultIOException("Could not create .name file")
                    writeWhole(nameFile, newCiphertextName.toByteArray(Charsets.UTF_8))
                }
            } else {
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

                if (!nameCryptor.isOverLongNameLimit(newCiphertextName)) {
                    val renamed = renameDocumentAndGet(physicalNode, newCiphertextName)
                    movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)
                } else {
                    val shortName = nameCryptor.hashLongName(newCiphertextName)
                    val renamed = renameDocumentAndGet(physicalNode, shortName)
                    movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)
                    val nameFile = createFileSafe(newParentPhysical, "application/octet-stream", "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}")
                        ?: throw VaultIOException("Could not create .name file")
                    writeWhole(nameFile, newCiphertextName.toByteArray(Charsets.UTF_8))
                }

                if (wasLongName) {
                    childOf(oldParentPhysical, "$oldPhysicalName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}")?.delete()
                }
            }

            tree.invalidate(oldParentPath)
            tree.invalidate(newParentPath)
            if (node is GocryptfsNode.VDir) {
                tree.removeFolder(oldNormalized)
            }
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
                is GocryptfsNode.VDir -> {
                    deleteRecursively(node.physicalFolder)
                    tree.removeFolder(normalized)
                }
                is GocryptfsNode.VFile -> node.physicalFile.delete()
            }

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
        val normalized = normalize(virtualPath)
        val node = tree.resolve(normalized) ?: return false
        val physical = when (node) {
            is GocryptfsNode.VFile -> node.physicalFile
            is GocryptfsNode.VDir -> node.physicalFolder
        }
        val ok = setPhysicalLastModified(physical, epochSeconds)
        if (ok) {
            tree.invalidate(parentOf(normalized))
        }
        return ok
    }

    private fun setPhysicalLastModified(doc: DocumentFile, epochSeconds: Long): Boolean {
        val epochMillis = epochSeconds * 1000L
        val rawFile = com.aeidolon.vaultexplorer.RawFileResolver.getRawFile(context, doc)

        if (rawFile != null) {
            if (rawFile.setLastModified(epochMillis)) {
                return true
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                try {
                    java.nio.file.Files.setLastModifiedTime(
                        rawFile.toPath(),
                        java.nio.file.attribute.FileTime.fromMillis(epochMillis)
                    )
                    return true
                } catch (_: Exception) {}
            }
        }
        return false
    }

    override fun getFileSize(virtualPath: String): Long {
        val normalized = normalize(virtualPath)
        val node = tree.resolve(normalized) ?: return -1L
        val f = node as? GocryptfsNode.VFile ?: return -1L
        val ciphertextLen = f.physicalFile.length()
        return contentCryptor.cleartextSize(ciphertextLen)
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

    override fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? =
        engine.readFileChunk(virtualPath, offset, length)

    override fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean =
        engine.writeFileChunk(virtualPath, offset, data)

    override fun finishWrite(virtualPath: String): Boolean {
        val ok = engine.finishWrite(virtualPath)
        if (ok) {
            val parent = parentOf(virtualPath)
            tree.invalidate(parent)
        }
        return ok
    }

    override fun writeBackFile(virtualPath: String, sourcePath: String, opId: Int): Boolean {
        val ok = engine.writeBackFile(virtualPath, sourcePath, opId)
        if (ok) {
            tree.invalidate(parentOf(virtualPath))
        }
        return ok
    }

    override fun extractFile(virtualPath: String, destinationPath: String, opId: Int): Boolean =
        engine.extractFile(virtualPath, destinationPath, opId)

    override fun getSpaceInfo(): LongArray? =
        com.aeidolon.vaultexplorer.saf.VaultPathUtils.querySafSpaceInfo(context, vaultRootUri)

    override fun getVaultInfo(): Map<String, Any?> = mapOf(
        "formatVersion" to 2,
        "cipher" to when (cipher) {
            GocryptfsCipher.AES_256_GCM -> "AES-256-GCM"
            GocryptfsCipher.XCHACHA20_POLY1305 -> "XChaCha20-Poly1305"
        },
        "plaintextNames" to plaintextNames,
        "readOnly" to readOnly,
    )

    private fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? =
        safOps.createDirectorySafe(parent, name)
    private fun createFileSafe(parent: DocumentFile, mimeType: String, name: String): DocumentFile? =
        safOps.createFileSafe(parent, mimeType, name)
    private fun childOf(folder: DocumentFile, name: String): DocumentFile? = safOps.childOf(folder, name)

    private fun createNodeFolder(parent: DocumentFile, ciphertextName: String): DocumentFile {
        return if (!nameCryptor.isOverLongNameLimit(ciphertextName)) {
            createDirectorySafe(parent, ciphertextName)
                ?: throw VaultIOException("Could not create directory $ciphertextName")
        } else {
            val shortName = nameCryptor.hashLongName(ciphertextName)
            val folder = createDirectorySafe(parent, shortName)
                ?: throw VaultIOException("Could not create directory $shortName")
            val expectedName = "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}"
            var nameFile = createFileSafe(parent, "application/octet-stream", expectedName)
                ?: throw VaultIOException("Could not create .name file")
            if (nameFile.name != expectedName) {
                nameFile = renameDocumentAndGet(nameFile, expectedName)
            }
            writeWhole(nameFile, ciphertextName.toByteArray(Charsets.UTF_8))
            folder
        }
    }

    private fun createNewFileNode(parent: DocumentFile, ciphertextName: String): DocumentFile {
        return if (!nameCryptor.isOverLongNameLimit(ciphertextName)) {
            var file = createFileSafe(parent, "application/octet-stream", ciphertextName)
                ?: throw VaultIOException("Could not create file $ciphertextName")
            if (file.name != ciphertextName) {
                file = renameDocumentAndGet(file, ciphertextName)
            }
            file
        } else {
            val shortName = nameCryptor.hashLongName(ciphertextName)
            var file = createFileSafe(parent, "application/octet-stream", shortName)
                ?: throw VaultIOException("Could not create file $shortName")
            if (file.name != shortName) {
                file = renameDocumentAndGet(file, shortName)
            }
            val expectedName = "$shortName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}"
            var nameFile = createFileSafe(parent, "application/octet-stream", expectedName)
                ?: throw VaultIOException("Could not create .name file")
            if (nameFile.name != expectedName) {
                nameFile = renameDocumentAndGet(nameFile, expectedName)
            }
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

    private fun normalize(path: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.normalize(path)
    private fun parentOf(normalizedPath: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.parentOf(normalizedPath)
    private fun nameOf(normalizedPath: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.nameOf(normalizedPath)
    private fun joinPath(parent: String, name: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.joinPath(parent, name)
}