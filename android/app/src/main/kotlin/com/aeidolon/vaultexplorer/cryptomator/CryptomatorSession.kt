package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.VaultBackend
import com.aeidolon.vaultexplorer.engine.ChunkedEngineDelegate
import com.aeidolon.vaultexplorer.engine.ChunkedFileEngine
import com.aeidolon.vaultexplorer.engine.VaultChunkCryptor
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultPathNotFoundException
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.io.File
import java.security.SecureRandom
import java.util.UUID

class CryptomatorSession(
    private val context: Context,
    val vaultRootUri: Uri,
    val masterkey: CryptomatorMasterkey,
    val vaultFormat: Int,
    val cipherCombo: String,
    val shorteningThreshold: Int,
    val readOnly: Boolean,
) : com.aeidolon.vaultexplorer.VaultBackend {
    override val format = com.aeidolon.vaultexplorer.ContainerFormat.CRYPTOMATOR
    private val random = SecureRandom()
    private val safOps = SafDocumentOps(context)
    val nameCryptor = CryptomatorFileNameCryptor(masterkey)
    val contentCryptor: CryptomatorContentCryptor = CryptomatorContentCryptor.forCipherCombo(cipherCombo)
    val tree = CryptomatorVaultTree(context, vaultRootUri, nameCryptor, shorteningThreshold)
    private val chunkCryptor: VaultChunkCryptor<CryptomatorFileHeader> = object : VaultChunkCryptor<CryptomatorFileHeader> {
        override val headerSize: Int get() = contentCryptor.headerSize
        override val cleartextChunkSize: Int get() = contentCryptor.cleartextChunkSize
        override val ciphertextChunkSize: Int get() = contentCryptor.ciphertextChunkSize
        override fun createHeader(): CryptomatorFileHeader = contentCryptor.createHeader(random)
        override fun encodeHeader(header: CryptomatorFileHeader): ByteArray =
            contentCryptor.encryptHeader(header, masterkey, random)
        override fun decodeHeader(bytes: ByteArray): CryptomatorFileHeader =
            contentCryptor.decryptHeader(bytes, masterkey)
        override fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: CryptomatorFileHeader): ByteArray =
            contentCryptor.encryptChunk(cleartext, chunkNumber, header, masterkey, random)
        override fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: CryptomatorFileHeader): ByteArray =
            contentCryptor.decryptChunk(ciphertext, chunkNumber, header, masterkey)
    }
    private val engineDelegate = object : ChunkedEngineDelegate<CryptomatorFileHeader> {
        override val context: Context get() = this@CryptomatorSession.context
        override val readOnly: Boolean get() = this@CryptomatorSession.readOnly
        override val cryptor: VaultChunkCryptor<CryptomatorFileHeader> get() = chunkCryptor
        override fun getPhysicalFileForRead(virtualPath: String): DocumentFile? =
            (tree.resolve(virtualPath) as? VaultNode.VFile)?.physicalFile
        override fun getOrCreatePhysicalFileForWrite(virtualPath: String): DocumentFile {
            val parentPath = parentOf(virtualPath)
            val name = nameOf(virtualPath)
            val parentDirId = tree.resolveDirId(parentPath)
            val parentPhysical = tree.physicalFolderForDirId(parentDirId)
            val existing = tree.resolve(virtualPath) as? VaultNode.VFile
            return existing?.physicalFile ?: run {
                val ciphertextName = nameCryptor.encryptFilename(name, parentDirId.toByteArray(Charsets.UTF_8))
                createNewFileNode(parentPhysical, ciphertextName)
            }
        }
        override fun invalidateCacheAfterWrite(virtualPath: String) {
            tree.invalidate(parentOf(virtualPath))
            safOps.invalidateAll()
        }
    }
    private val engine = ChunkedFileEngine(engineDelegate)
    fun close() {
        engine.close()
        masterkey.destroy()
    }
    override fun listDirectory(virtualPath: String): Array<String>? {
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
    override fun createDirectory(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            val existing = tree.resolve(normalized)
            if (existing is VaultNode.VDir) return true
            if (existing != null) return false
            val parentPath = parentOf(normalized)
            val name = nameOf(normalized)
            val parentDirId = tree.resolveDirId(parentPath)
            val parentPhysical = tree.physicalFolderForDirId(parentDirId)
            val newDirId = UUID.randomUUID().toString()
            val ciphertextName = nameCryptor.encryptFilename(name, parentDirId.toByteArray(Charsets.UTF_8))
            createNodeFolder(parentPhysical, ciphertextName) { nodeFolder ->
                val dirFile = createFileSafe(nodeFolder, "application/octet-stream", "dir.c9r")
                    ?: throw VaultIOException("Could not create dir.c9r")
                writeWhole(dirFile, newDirId.toByteArray(Charsets.UTF_8))
            }
            val hash = nameCryptor.hashDirectoryId(newDirId)
            val dataDir = requireNonNull(findOrCreateChild(vaultRoot(), "d", isDir = true))
            val lvl1 = requireNonNull(findOrCreateChild(dataDir, hash.substring(0, 2), isDir = true))
            findOrCreateChild(lvl1, hash.substring(2), isDir = true)
            tree.invalidate(parentPath)
            safOps.invalidateAll()
            true
        } catch (e: Exception) {
            android.util.Log.e("CryptomatorSession", "createDirectory failed for $virtualPath", e)
            false
        }
    }
    override fun importStream(virtualPath: String, inputStream: java.io.InputStream): Boolean {
        if (readOnly) return false
        val ok = engine.writeBackStream(virtualPath, inputStream)
        if (ok) {
            tree.invalidate(parentOf(virtualPath))
            safOps.invalidateAll()
        }
        return ok
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
                val parentDirId = tree.resolveDirId(oldParentPath)
                val newCiphertextName = nameCryptor.encryptFilename(newName, parentDirId.toByteArray(Charsets.UTF_8))
                val physicalNode = when (node) {
                    is VaultNode.VDir -> node.physicalFolder
                    is VaultNode.VFile -> node.wrapperFolder ?: node.physicalFile
                }
                val isShortened = physicalNode.name?.endsWith(".c9s") == true
                if (isShortened) {
                    val nameFile = childOf(physicalNode, "name.c9r") ?: return false
                    writeWhole(nameFile, (newCiphertextName + ".c9r").toByteArray(Charsets.UTF_8))
                } else {
                    val fullName = newCiphertextName + ".c9r"
                    if (fullName.length <= shorteningThreshold) {
                        renameDocument(physicalNode, fullName)
                    } else {
                        val parentPhysical = tree.physicalFolderForDirId(parentDirId)
                        val hash = java.security.MessageDigest.getInstance("SHA-1").digest(fullName.toByteArray(Charsets.UTF_8))
                        val shortName = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(hash) + ".c9s"
                        if (node is VaultNode.VDir) {
                            val folder = renameDocumentAndGet(physicalNode, shortName)
                            val nameFile = createFileSafe(folder, "application/octet-stream", "name.c9r") ?: return false
                            writeWhole(nameFile, fullName.toByteArray(Charsets.UTF_8))
                        } else {
                            val folder = createDirectorySafe(parentPhysical, shortName) ?: return false
                            val nameFile = createFileSafe(folder, "application/octet-stream", "name.c9r") ?: return false
                            writeWhole(nameFile, fullName.toByteArray(Charsets.UTF_8))
                            movePhysicalDocument(physicalNode, parentPhysical, folder)
                            renameDocument(physicalNode, "contents.c9r")
                        }
                    }
                }
            } else {
                val oldParentDirId = tree.resolveDirId(oldParentPath)
                val oldParentPhysical = tree.physicalFolderForDirId(oldParentDirId)
                val newParentDirId = tree.resolveDirId(newParentPath)
                val newParentPhysical = tree.physicalFolderForDirId(newParentDirId)
                val newCiphertextName = nameCryptor.encryptFilename(newName, newParentDirId.toByteArray(Charsets.UTF_8))
                val physicalNode = when (node) {
                    is VaultNode.VDir -> node.physicalFolder
                    is VaultNode.VFile -> node.wrapperFolder ?: node.physicalFile
                }
                val isShortened = physicalNode.name?.endsWith(".c9s") == true
                if (isShortened) {
                    val nameFile = childOf(physicalNode, "name.c9r") ?: return false
                    writeWhole(nameFile, (newCiphertextName + ".c9r").toByteArray(Charsets.UTF_8))
                    movePhysicalDocument(physicalNode, oldParentPhysical, newParentPhysical)
                } else {
                    val fullName = newCiphertextName + ".c9r"
                    if (fullName.length <= shorteningThreshold) {
                        val renamed = renameDocumentAndGet(physicalNode, fullName)
                        movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)
                    } else {
                        val hash = java.security.MessageDigest.getInstance("SHA-1").digest(fullName.toByteArray(Charsets.UTF_8))
                        val shortName = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(hash) + ".c9s"
                        if (node is VaultNode.VDir) {
                            val renamed = renameDocumentAndGet(physicalNode, shortName)
                            val nameFile = childOf(renamed, "name.c9r") ?: createFileSafe(renamed, "application/octet-stream", "name.c9r") ?: return false
                            writeWhole(nameFile, fullName.toByteArray(Charsets.UTF_8))
                            movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)
                        } else {
                            val folder = createDirectorySafe(newParentPhysical, shortName) ?: return false
                            val nameFile = createFileSafe(folder, "application/octet-stream", "name.c9r") ?: return false
                            writeWhole(nameFile, fullName.toByteArray(Charsets.UTF_8))
                            movePhysicalDocument(physicalNode, oldParentPhysical, folder)
                            renameDocument(physicalNode, "contents.c9r")
                        }
                    }
                }
            }
            tree.invalidate(oldParentPath)
            tree.invalidate(newParentPath)
            if (node is VaultNode.VDir) tree.invalidate(oldNormalized)
            safOps.invalidateAll()
            true
        } catch (e: Exception) {
            android.util.Log.e("CryptomatorSession", "renameFile failed for $oldVirtualPath -> $newVirtualPath", e)
            false
        }
    }
    override fun deleteFile(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            engine.invalidateRead(normalized)
            val node = tree.resolve(normalized) ?: return false
            when (node) {
                is VaultNode.VDir -> {
                    val dirId = tree.readDirId(node.dirIdFile)
                    val physicalContents = tree.physicalFolderForDirId(dirId)
                    deleteRecursively(physicalContents)
                    deleteRecursively(node.physicalFolder)
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
            safOps.invalidateAll()
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
        val f = node as? VaultNode.VFile ?: return -1L
        val ciphertextSize = f.physicalFile.length()
        val withoutHeader = ciphertextSize - contentCryptor.headerSize
        if (withoutHeader < 0) return 0L
        return contentCryptor.cleartextSize(withoutHeader)
    }
    override fun getFolderSize(virtualPath: String): Long {
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
    override fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? =
        engine.readFileChunk(virtualPath, offset, length)
    override fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean =
        engine.writeFileChunk(virtualPath, offset, data)
    override fun finishWrite(virtualPath: String): Boolean {
        val ok = engine.finishWrite(virtualPath)
        if (ok) {
            tree.invalidate(parentOf(virtualPath))
            safOps.invalidateAll()
        }
        return ok
    }
    override fun writeBackFile(virtualPath: String, sourcePath: String): Boolean {
        val ok = engine.writeBackFile(virtualPath, sourcePath)
        if (ok) {
            tree.invalidate(parentOf(virtualPath))
            safOps.invalidateAll()
        }
        return ok
    }
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
                    if (cap > 0 && avail >= 0) return longArrayOf(cap, avail)
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }
    private fun listFilesSafe(folder: DocumentFile): List<DocumentFile> = safOps.listChildren(folder)
    private fun createDirectorySafe(parent: DocumentFile, name: String): DocumentFile? =
        safOps.createDirectorySafe(parent, name)
    private fun createFileSafe(parent: DocumentFile, mimeType: String, name: String): DocumentFile? =
        safOps.createFileSafe(parent, mimeType, name)
    private fun vaultRoot(): DocumentFile =
        DocumentFile.fromTreeUri(context, vaultRootUri) ?: throw VaultIOException("Cannot open vault root")
    private fun childOf(folder: DocumentFile, name: String): DocumentFile? = safOps.childOf(folder, name)
    private fun findOrCreateChild(folder: DocumentFile, name: String, isDir: Boolean): DocumentFile? {
        childOf(folder, name)?.let { return it }
        return if (isDir) createDirectorySafe(folder, name) else createFileSafe(folder, "application/octet-stream", name)
    }
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
    private fun writeWhole(file: DocumentFile, bytes: ByteArray) = safOps.writeWhole(file, bytes)
    private fun renameDocumentAndGet(doc: DocumentFile, newName: String): DocumentFile =
        safOps.renameDocumentAndGet(doc, newName)
    private fun movePhysicalDocument(doc: DocumentFile, oldParent: DocumentFile, newParent: DocumentFile) =
        safOps.movePhysicalDocument(doc, oldParent, newParent)
    private fun renameDocument(doc: DocumentFile, newName: String) = safOps.renameDocument(doc, newName)
    private fun deleteRecursively(folder: DocumentFile) = safOps.deleteRecursively(folder)
    private fun requireNonNull(doc: DocumentFile?): DocumentFile = doc ?: throw VaultIOException("Expected SAF document was null")
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