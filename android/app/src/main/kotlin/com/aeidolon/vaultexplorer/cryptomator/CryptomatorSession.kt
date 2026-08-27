package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.DirEntryWire
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.VaultBackend
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
) : com.aeidolon.vaultexplorer.container.VaultBackend {
    override val format = com.aeidolon.vaultexplorer.container.ContainerFormat.CRYPTOMATOR
    override val skipsPerVolumeLock = true
    var volId: Int = -1
    private val random = SecureRandom()
    val nameCryptor = CryptomatorFileNameCryptor(masterkey)
    val contentCryptor: CryptomatorContentCryptor = CryptomatorContentCryptor.forCipherCombo(cipherCombo)

    // When the vault's root itself lives inside another app's SAF export
    // (RawFileResolver can't resolve it to a raw path we have POSIX access
    // to -- e.g. the vault folder is exposed by a third-party file
    // manager's own DocumentsProvider), every physical op this session does
    // would otherwise pay a round trip through that other app's provider on
    // every single call, and is exposed to however defensively it handles a
    // second concurrent stream against the same document (observed:
    // MixPlorer's provider tearing down an in-flight read under a competing
    // one -- EPIPE, silent copy failure with no recovery on the other
    // app's side). Mirroring the vault to app-private storage sidesteps
    // this: every op becomes a fast raw-file op, synced back to the real
    // SAF tree explicitly (see MirrorSyncCoordinator's doc comment for the
    // eager-push/lazy-pull policy) instead of implicitly on every access.
    private val mirrorSync: com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator? =
        if (com.aeidolon.vaultexplorer.RawFileResolver.getRawFileFromUri(context, vaultRootUri) == null) {
            val realOps = SafDocumentOps(context)
            com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator(
                context = context,
                sessionTag = java.util.UUID.randomUUID().toString(),
                realOps = realOps,
            ).also { coordinator ->
                val realRoot = DocumentFile.fromTreeUri(context, vaultRootUri)
                    ?: throw VaultIOException("Cannot open vault root: $vaultRootUri")
                coordinator.reset(realRoot)
            }
        } else null

    private val vaultDocOps: com.aeidolon.vaultexplorer.saf.VaultDocumentOps =
        mirrorSync?.let { com.aeidolon.vaultexplorer.saf.MirroredSafDocumentOps(context, it) }
            ?: SafDocumentOps(context)

    val tree = CryptomatorVaultTree(context, vaultRootUri, nameCryptor, shorteningThreshold, vaultDocOps)
    private val safOps get() = tree.safOps
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
            
        override fun encryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: CryptomatorFileHeader): ByteArray {
            val gcm = contentCryptor as? CryptomatorContentCryptor.Gcm
            return gcm?.encryptStream(inputBuffer, startChunkNumber, header)
                ?: super.encryptStream(inputBuffer, startChunkNumber, header)
        }

        // Mirrors encryptStream above -- was missing, so decryption for GCM (format 8)
        // vaults fell all the way back to the per-chunk default (see VaultChunkCryptor's
        // decryptStream doc comment) even though Gcm.decryptStream's fast batched native
        // path already existed and just wasn't being called from here.
        override fun decryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: CryptomatorFileHeader): ByteArray {
            val gcm = contentCryptor as? CryptomatorContentCryptor.Gcm
            return gcm?.decryptStream(inputBuffer, startChunkNumber, header)
                ?: super.decryptStream(inputBuffer, startChunkNumber, header)
        }
    }
    private val engineDelegate = object : ChunkedEngineDelegate<CryptomatorFileHeader> {
        override val context: Context get() = this@CryptomatorSession.context
        override val readOnly: Boolean get() = this@CryptomatorSession.readOnly
        override val cryptor: VaultChunkCryptor<CryptomatorFileHeader> get() = chunkCryptor
        override var batchWriteActive: Boolean = false
        override fun getPhysicalFileForRead(virtualPath: String): DocumentFile? {
            val normalized = normalize(virtualPath)
            val physicalFile = (tree.resolve(normalized) as? VaultNode.VFile)?.physicalFile ?: run {
                VeLog.d("MirrorTrace") { "getPhysicalFileForRead: tree.resolve($normalized) did not yield a VFile" }
                return null
            }
            // For large, not-yet-cached files on a mirrored vault,
            // resolveForRead returns the REAL SAF document so
            // ChunkedFileEngine can stream directly from it (via its
            // existing SAF_PFD / SAF_STREAM fallback paths) while a
            // background pull warms the local mirror cache — instead
            // of blocking here on a synchronous full-file copy that
            // would delay video playback / seeking by the entire
            // download time. Returns null when the mirror already has
            // the content, or for non-mirrored vaults; fall through
            // to ensureContentPulled in that case.
            val directReal = vaultDocOps.resolveForRead(physicalFile) { phase ->
                if (volId >= 0) {
                    com.aeidolon.vaultexplorer.saf.MirrorPullEvents.emit(volId, normalized, phase)
                }
            }
            if (directReal != null) {
                VeLog.d("MirrorTrace") { "getPhysicalFileForRead: path=$normalized streaming direct from real doc ${directReal.uri}" }
                return directReal
            }
            VeLog.d("MirrorTrace") { "getPhysicalFileForRead: path=$normalized mirrorUri=${physicalFile.uri} lengthBefore=${physicalFile.length()}" }
            vaultDocOps.ensureContentPulled(physicalFile)
            VeLog.d("MirrorTrace") { "getPhysicalFileForRead: path=$normalized mirrorUri=${physicalFile.uri} lengthAfterPull=${physicalFile.length()}" }
            return physicalFile
        }
        override fun getOrCreatePhysicalFileForWrite(virtualPath: String): DocumentFile {
            val normalized = normalize(virtualPath)
            val parentPath = parentOf(normalized)
            val name = nameOf(normalized)
            val parentDirId = tree.resolveDirId(parentPath)
            val parentPhysical = tree.physicalFolderForDirId(parentDirId)
            val existing = tree.resolve(normalized) as? VaultNode.VFile
            val result = existing?.physicalFile ?: run {
                val ciphertextName = nameCryptor.encryptFilename(name, parentDirId.toByteArray(Charsets.UTF_8))
                createNewFileNode(parentPhysical, ciphertextName)
            }
            VeLog.d("MirrorTrace") { "getOrCreatePhysicalFileForWrite: path=$normalized existing=${existing != null} mirrorUri=${result.uri} lengthNow=${result.length()}" }
            
            // Do not track temporary scratchpad files for SAF synchronization
            if (!normalized.endsWith(".tmp")) {
                vaultDocOps.markWritePending(result)
                pendingBatchWrites[normalized] = result
            }
            return result
        }
        override fun invalidateCacheAfterWrite(virtualPath: String) {
            val normalized = normalize(virtualPath)
            val physicalFile = pendingBatchWrites.remove(normalized)
            if (physicalFile == null) {
                if (!normalized.endsWith(".tmp")) {
                    VeLog.w("MirrorTrace") { "invalidateCacheAfterWrite: path=$normalized -- no captured write instance, nothing pushed!" }
                }
            } else {
                if (!normalized.endsWith(".tmp")) {
                    pushContentFor(normalized, physicalFile)
                }
            }
            tree.invalidate(parentOf(normalized))
        }
    }
    // Written-to DocumentFile instances captured by every write (see
    // getOrCreatePhysicalFileForWrite), consumed either immediately by
    // invalidateCacheAfterWrite (single write) or later by endBatchWrite
    // (batch write, since ChunkedFileEngine deliberately skips
    // invalidateCacheAfterWrite for the duration of a batch). Keyed by
    // normalized virtual path only to dedupe repeated writes to the same
    // file (last write wins, matching what ends up on disk); the VALUE is
    // what actually gets pushed, never re-resolved from the path.
    private val pendingBatchWrites = java.util.concurrent.ConcurrentHashMap<String, DocumentFile>()
    private fun pushContentFor(normalized: String, physicalFile: DocumentFile) {
        VeLog.d("MirrorTrace") { "pushContentFor: path=$normalized mirrorUri=${physicalFile.uri} mirrorLength=${physicalFile.length()} -- pushing" }
        try {
            vaultDocOps.pushContentWrite(physicalFile)
            VeLog.d("MirrorTrace") { "pushContentFor: path=$normalized push OK" }
        } catch (e: Exception) {
            VeLog.e("MirrorTrace", e) { "pushContentFor: path=$normalized push FAILED -- real SAF file was NOT updated" }
            throw e
        }
    }
   private val engine = ChunkedFileEngine(engineDelegate)
    private var batchDeleteActive = false

    override fun beginBatchDelete() {
        batchDeleteActive = true
    }

    override fun endBatchDelete() {
        batchDeleteActive = false
        tree.invalidateAll()
    }

    override fun beginBatchWrite() {
        engineDelegate.batchWriteActive = true
    }
    override fun endBatchWrite() {
        engineDelegate.batchWriteActive = false
        // Flush every write that was deferred during the batch (see
        // pendingBatchWrites / getOrCreatePhysicalFileForWrite) BEFORE
        // invalidating the tree. Pushes the exact DocumentFile instance
        // captured at write time for each path -- deliberately NOT
        // re-resolved via tree.resolve() here, since that re-resolution
        // was the actual bug: it could return a stale cached DocumentFile
        // for the same path instead of the live object the engine wrote
        // to. See the comment on getOrCreatePhysicalFileForWrite.
        val writes = pendingBatchWrites.toMap()
        pendingBatchWrites.clear()
        val validWrites = writes.filterKeys { !it.endsWith(".tmp") }
        VeLog.d("MirrorTrace") { "endBatchWrite: flushing ${validWrites.size} pending write(s): ${validWrites.keys}" }
        for ((path, physicalFile) in validWrites) {
            pushContentFor(path, physicalFile)
        }
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
        masterkey.destroy()
        mirrorSync?.teardown()
    }
    override fun listDirectory(virtualPath: String): Array<String>? {
        return try {
            val normalized = normalize(virtualPath)
            val nodes = tree.list(normalized)
            nodes.map { node ->
                when (node) {
                    is VaultNode.VDir -> {
                        val mtime = node.physicalFolder.lastModified() / 1000L
                        DirEntryWire.encode(node.cleartextName, true, 0L, mtime)
                    }
                    is VaultNode.VFile -> {
                        val ciphertextSize = node.physicalFile.length()
                        val withoutHeader = ciphertextSize - contentCryptor.headerSize
                        val cleartextSize = if (withoutHeader < 0) 0L else contentCryptor.cleartextSize(withoutHeader)
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
            if (existing is VaultNode.VDir) return true
            if (existing != null) return false
            val parentPath = parentOf(normalized)
            val name = nameOf(normalized)
            val parentDirId = tree.resolveDirId(parentPath)
            val parentPhysical = tree.physicalFolderForDirId(parentDirId)
            val newDirId = UUID.randomUUID().toString()
            val ciphertextName = nameCryptor.encryptFilename(name, parentDirId.toByteArray(Charsets.UTF_8))
            createNodeFolder(parentPhysical, ciphertextName) { nodeFolder ->
                var dirFile = createFileSafe(nodeFolder, "application/octet-stream", "dir.c9r")
                    ?: throw VaultIOException("Could not create dir.c9r")
                if (dirFile.name != "dir.c9r") {
                    dirFile = renameDocumentAndGet(dirFile, "dir.c9r")
                }
                writeWhole(dirFile, newDirId.toByteArray(Charsets.UTF_8))
            }
            tree.createPhysicalFolderForDirId(newDirId)
            tree.invalidate(parentPath)
            true
        } catch (e: Exception) {
            false
        }
    }
    override fun importStream(virtualPath: String, inputStream: java.io.InputStream, volId: Int): Boolean {
        if (readOnly) return false
        val normalized = normalize(virtualPath)
        // engine.writeBackStream() already invalidates (and, outside a
        // batch, pushes) via ChunkedEngineDelegate.invalidateCacheAfterWrite
        // -- see that method and getOrCreatePhysicalFileForWrite above. A
        // second, unconditional tree.invalidate(parentOf(normalized)) used
        // to run here on every call, batch or not. Outside a batch that was
        // a pure duplicate of what writeBackStream just did. During a batch
        // it was actively harmful to import performance: it busts
        // MirroredSafDocumentOps' "already listed" marker for the parent
        // folder, so the very next directory resolve (e.g. the
        // setLastModifiedTime call every raw import makes right after this)
        // forced a fresh *remote* SAF directory listing -- one extra
        // network round trip per imported file, for a cloud-backed vault.
        // The local mirror's own listing cache stays correct incrementally
        // as each file is created (see SafDocumentOps.createFileSafe), so
        // nothing needs a forced re-list mid-batch; endBatchWrite's final
        // tree.invalidateAll() covers full freshness once every file's
        // content has actually been pushed to the real tree.
        return engine.writeBackStream(normalized, inputStream, volId)
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
                val parentPhysical = tree.physicalFolderForDirId(parentDirId)
                val newCiphertextName = nameCryptor.encryptFilename(newName, parentDirId.toByteArray(Charsets.UTF_8))
                val newFullName = newCiphertextName + ".c9r"
                val physicalNode = when (node) {
                    is VaultNode.VDir -> node.physicalFolder
                    is VaultNode.VFile -> node.wrapperFolder ?: node.physicalFile
                }
                val isShortened = physicalNode.name?.endsWith(".c9s") == true

                if (newFullName.length <= shorteningThreshold) {
                    if (isShortened) {
                        if (node is VaultNode.VDir) {
                            childOf(physicalNode, "name.c9s")?.let { deleteRecursively(it) }
                            renameDocument(physicalNode, newFullName)
                        } else {
                            val contentsFile = childOf(physicalNode, "contents.c9r") ?: return false
                            movePhysicalDocument(contentsFile, physicalNode, parentPhysical)
                            safOps.invalidate(parentPhysical)
                            renameDocument(contentsFile, newFullName)
                            deleteRecursively(physicalNode)
                        }
                    } else {
                        renameDocument(physicalNode, newFullName)
                    }
                } else {
                    val hash = java.security.MessageDigest.getInstance("SHA-1").digest(newFullName.toByteArray(Charsets.UTF_8))
                    val newShortName = java.util.Base64.getUrlEncoder().encodeToString(hash) + ".c9s"

                    if (isShortened) {
                        var nameFile = childOf(physicalNode, "name.c9s") 
                            ?: createFileSafe(physicalNode, "application/octet-stream", "name.c9s") 
                            ?: return false
                        if (nameFile.name != "name.c9s") {
                            nameFile = renameDocumentAndGet(nameFile, "name.c9s")
                        }
                        writeWhole(nameFile, newFullName.toByteArray(Charsets.UTF_8))
                        if (physicalNode.name != newShortName) {
                            renameDocument(physicalNode, newShortName)
                        }
                    } else {
                        if (node is VaultNode.VDir) {
                            val folder = renameDocumentAndGet(physicalNode, newShortName)
                            var nameFile = createFileSafe(folder, "application/octet-stream", "name.c9s") ?: return false
                            if (nameFile.name != "name.c9s") {
                                nameFile = renameDocumentAndGet(nameFile, "name.c9s")
                            }
                            writeWhole(nameFile, newFullName.toByteArray(Charsets.UTF_8))
                        } else {
                            val folder = createDirectorySafe(parentPhysical, newShortName) ?: return false
                            var nameFile = createFileSafe(folder, "application/octet-stream", "name.c9s") ?: return false
                            if (nameFile.name != "name.c9s") {
                                nameFile = renameDocumentAndGet(nameFile, "name.c9s")
                            }
                            writeWhole(nameFile, newFullName.toByteArray(Charsets.UTF_8))
                            val movedName = physicalNode.name ?: return false
                            movePhysicalDocument(physicalNode, parentPhysical, folder)
                            safOps.invalidate(folder)
                            val movedFile = childOf(folder, movedName) ?: return false
                            renameDocument(movedFile, "contents.c9r")
                        }
                    }
                }
            } else {
                val oldParentDirId = tree.resolveDirId(oldParentPath)
                val oldParentPhysical = tree.physicalFolderForDirId(oldParentDirId)
                val newParentDirId = tree.resolveDirId(newParentPath)
                val newParentPhysical = tree.physicalFolderForDirId(newParentDirId)
                val newCiphertextName = nameCryptor.encryptFilename(newName, newParentDirId.toByteArray(Charsets.UTF_8))
                val newFullName = newCiphertextName + ".c9r"
                val physicalNode = when (node) {
                    is VaultNode.VDir -> node.physicalFolder
                    is VaultNode.VFile -> node.wrapperFolder ?: node.physicalFile
                }
                val isShortened = physicalNode.name?.endsWith(".c9s") == true

                if (newFullName.length <= shorteningThreshold) {
                    if (isShortened) {
                        if (node is VaultNode.VDir) {
                            childOf(physicalNode, "name.c9s")?.let { deleteRecursively(it) }
                            val renamed = renameDocumentAndGet(physicalNode, newFullName)
                            movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)
                        } else {
                            val contentsFile = childOf(physicalNode, "contents.c9r") ?: return false
                            movePhysicalDocument(contentsFile, physicalNode, newParentPhysical)
                            safOps.invalidate(newParentPhysical)
                            renameDocument(contentsFile, newFullName)
                            deleteRecursively(physicalNode)
                        }
                    } else {
                        val renamed = renameDocumentAndGet(physicalNode, newFullName)
                        movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)
                    }
                } else {
                    val hash = java.security.MessageDigest.getInstance("SHA-1").digest(newFullName.toByteArray(Charsets.UTF_8))
                    val newShortName = java.util.Base64.getUrlEncoder().encodeToString(hash) + ".c9s"

                    if (isShortened) {
                        var nameFile = childOf(physicalNode, "name.c9s") 
                            ?: createFileSafe(physicalNode, "application/octet-stream", "name.c9s") 
                            ?: return false
                        if (nameFile.name != "name.c9s") {
                            nameFile = renameDocumentAndGet(nameFile, "name.c9s")
                        }
                        writeWhole(nameFile, newFullName.toByteArray(Charsets.UTF_8))
                        val renamed = if (physicalNode.name != newShortName) {
                            renameDocumentAndGet(physicalNode, newShortName)
                        } else {
                            physicalNode
                        }
                        movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)
                    } else {
                        if (node is VaultNode.VDir) {
                            val renamed = renameDocumentAndGet(physicalNode, newShortName)
                            var nameFile = childOf(renamed, "name.c9s") ?: createFileSafe(renamed, "application/octet-stream", "name.c9s") ?: return false
                            if (nameFile.name != "name.c9s") {
                                nameFile = renameDocumentAndGet(nameFile, "name.c9s")
                            }
                            writeWhole(nameFile, newFullName.toByteArray(Charsets.UTF_8))
                            movePhysicalDocument(renamed, oldParentPhysical, newParentPhysical)
                        } else {
                            val folder = createDirectorySafe(newParentPhysical, newShortName) ?: return false
                            var nameFile = createFileSafe(folder, "application/octet-stream", "name.c9s") ?: return false
                            if (nameFile.name != "name.c9s") {
                                nameFile = renameDocumentAndGet(nameFile, "name.c9s")
                            }
                            writeWhole(nameFile, newFullName.toByteArray(Charsets.UTF_8))
                            val movedName = physicalNode.name ?: return false
                            movePhysicalDocument(physicalNode, oldParentPhysical, folder)
                            safOps.invalidate(folder)
                            val movedFile = childOf(folder, movedName) ?: return false
                            renameDocument(movedFile, "contents.c9r")
                        }
                    }
                }
            }
            tree.invalidate(oldParentPath)
            tree.invalidate(newParentPath)
            if (node is VaultNode.VDir) tree.invalidate(oldNormalized)
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
                        deleteRecursively(node.physicalFile)
                    }
                }
            }
            // Skip per-file invalidation if we are running in a batch
            if (!batchDeleteActive && !engineDelegate.batchWriteActive) {
                tree.invalidate(parentOf(normalized))
            }
            true
        } catch (e: Exception) {
            false
        }
    }
    override fun setLastModifiedTime(virtualPath: String, epochSeconds: Long): Boolean {
        val normalized = normalize(virtualPath)
        val node = tree.resolve(normalized) ?: return false
        val ok = when (node) {
            is VaultNode.VFile -> {
                val okFile = setPhysicalLastModified(node.physicalFile, epochSeconds)
                if (node.wrapperFolder != null) {
                    setPhysicalLastModified(node.wrapperFolder, epochSeconds)
                }
                okFile
            }
            is VaultNode.VDir -> setPhysicalLastModified(node.physicalFolder, epochSeconds)
        }
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
        val node = tree.resolve(normalize(virtualPath)) ?: return -1L
        val f = node as? VaultNode.VFile ?: return -1L
        // MUST pull here, not just for getPhysicalFileForRead. Traced via
        // MirrorTrace logs: ContainerMediaAccess's ContainerInputStream and
        // ContainerMediaDataSource both call getFileSize() exactly once, at
        // construction, BEFORE the first readFileChunk() -- and both clamp
        // every subsequent read to that cached size. With a not-yet-pulled
        // mirror file this returns 0, so `position >= fileSize` (0 >= 0) is
        // true on the very first read, and the stream reports EOF before a
        // single byte is ever fetched -- readFileChunk (the thing that
        // would otherwise trigger getPhysicalFileForRead's pull) never
        // even runs. Nothing downstream gets a second chance to pull, so
        // this call site has to be the one that does it. Unlike a
        // directory listing (which does NOT go through this method --
        // confirmed by grepping every call site of
        // ContainerFileSystem.getFileSize: it's only ever called per-file,
        // on demand, right before that specific file is opened), this
        // isn't the "pull everything just to show a folder" cost I was
        // worried about earlier -- it's exactly the single-file,
        // about-to-be-read case pulling is meant for.
        vaultDocOps.ensureContentPulled(f.physicalFile)
        val ciphertextSize = f.physicalFile.length()
        VeLog.d("MirrorTrace") { "getFileSize: path=$virtualPath mirrorUri=${f.physicalFile.uri} ciphertextSize=$ciphertextSize" }
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
                    // NOTE: unlike getFileSize just above, deliberately NOT
                    // pulling here. This is the bulk-cost case that concern
                    // was actually about: getFolderSize recurses into every
                    // file under a folder, so forcing a pull here means
                    // computing a folder's size -- e.g. right after unlock,
                    // before anything's been individually opened -- would
                    // silently pull the entire subtree's content through
                    // the real SAF provider. For a not-yet-pulled file this
                    // undercounts (reports the placeholder's current 0
                    // bytes) rather than corrupting anything -- no read or
                    // display of that file's own content depends on this
                    // number -- but it does mean a freshly-unlocked mirrored
                    // vault's reported folder size can read low until files
                    // get opened individually. Left alone rather than fixed
                    // silently, same as the getFileSize note used to say:
                    // your call whether an accurate folder size is worth
                    // eagerly pulling everything under it for.
                    val withoutHeader = node.physicalFile.length() - contentCryptor.headerSize
                    if (withoutHeader < 0) 0L else contentCryptor.cleartextSize(withoutHeader)
                }
                is VaultNode.VDir -> getFolderSize(joinPath(normalized, node.cleartextName))
            }
        }
        return total
    }
    override fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? =
        engine.readFileChunk(normalize(virtualPath), offset, length)
    override fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean =
        engine.writeFileChunk(normalize(virtualPath), offset, data)
    override fun finishWrite(virtualPath: String): Boolean {
        val normalized = normalize(virtualPath)
        val ok = engine.finishWrite(normalized)
        if (ok) {
            tree.invalidate(parentOf(normalized))
        }
        return ok
    }
    override fun writeBackFile(virtualPath: String, sourcePath: String, opId: Int): Boolean {
        val normalized = normalize(virtualPath)
        val ok = engine.writeBackFile(normalized, sourcePath, opId)
        if (ok) {
            tree.invalidate(parentOf(normalized))
        }
        return ok
    }
    override fun extractFile(virtualPath: String, destinationPath: String, opId: Int): Boolean =
        engine.extractFile(normalize(virtualPath), destinationPath, opId)
    override fun getSpaceInfo(): LongArray? =
        com.aeidolon.vaultexplorer.saf.VaultPathUtils.querySafSpaceInfo(context, vaultRootUri)

    override fun getVaultInfo(): Map<String, Any?> = mapOf(
        "vaultFormat" to vaultFormat,
        "cipherCombo" to cipherCombo,
        "shorteningThreshold" to shorteningThreshold,
        "readOnly" to readOnly,
    )
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
        return if (isDir) safOps.createDirectorySafe(folder, name) else safOps.createFileSafe(folder, "application/octet-stream", name)
    }
    private fun createNodeFolder(parent: DocumentFile, ciphertextName: String, populate: (DocumentFile) -> Unit) {
        val fullName = ciphertextName + ".c9r"
        if (fullName.length <= shorteningThreshold) {
            val folder = createDirectorySafe(parent, fullName) ?: throw VaultIOException("Could not create $fullName")
            populate(folder)
        } else {
            val hash = java.security.MessageDigest.getInstance("SHA-1").digest(fullName.toByteArray(Charsets.UTF_8))
            val shortName = java.util.Base64.getUrlEncoder().encodeToString(hash) + ".c9s"
            val folder = createDirectorySafe(parent, shortName) ?: throw VaultIOException("Could not create $shortName")
            var nameFile = createFileSafe(folder, "application/octet-stream", "name.c9s") ?: throw VaultIOException("Could not create name.c9s")
            if (nameFile.name != "name.c9s") {
                nameFile = renameDocumentAndGet(nameFile, "name.c9s")
            }
            writeWhole(nameFile, fullName.toByteArray(Charsets.UTF_8))
            populate(folder)
        }
    }
    private fun createNewFileNode(parent: DocumentFile, ciphertextName: String): DocumentFile {
        val fullName = ciphertextName + ".c9r"
        return if (fullName.length <= shorteningThreshold) {
            var file = createFileSafe(parent, "application/octet-stream", fullName) ?: throw VaultIOException("Could not create $fullName")
            if (file.name != fullName) {
                file = renameDocumentAndGet(file, fullName)
            }
            file
        } else {
            val hash = java.security.MessageDigest.getInstance("SHA-1").digest(fullName.toByteArray(Charsets.UTF_8))
            val shortName = java.util.Base64.getUrlEncoder().encodeToString(hash) + ".c9s"
            val folder = createDirectorySafe(parent, shortName) ?: throw VaultIOException("Could not create $shortName")
            var nameFile = createFileSafe(folder, "application/octet-stream", "name.c9s") ?: throw VaultIOException("Could not create name.c9s")
            if (nameFile.name != "name.c9s") {
                nameFile = renameDocumentAndGet(nameFile, "name.c9s")
            }
            writeWhole(nameFile, fullName.toByteArray(Charsets.UTF_8))
            var contentsFile = createFileSafe(folder, "application/octet-stream", "contents.c9r") ?: throw VaultIOException("Could not create contents.c9r")
            if (contentsFile.name != "contents.c9r") {
                contentsFile = renameDocumentAndGet(contentsFile, "contents.c9r")
            }
            contentsFile
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
    private fun normalize(path: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.normalize(path)
    private fun parentOf(normalizedPath: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.parentOf(normalizedPath)
    private fun nameOf(normalizedPath: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.nameOf(normalizedPath)
    private fun joinPath(parent: String, name: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.joinPath(parent, name)
}