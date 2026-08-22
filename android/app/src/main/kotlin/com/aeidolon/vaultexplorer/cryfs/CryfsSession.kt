package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.net.Uri
import com.aeidolon.vaultexplorer.bridge.CopyProgressBridge
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.DirEntryWire
import com.aeidolon.vaultexplorer.container.VaultBackend
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultPathNotFoundException
import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile
import java.security.SecureRandom
import com.aeidolon.vaultexplorer.VeLog

private const val DEFAULT_FILE_MODE = 0x81A4
private const val DEFAULT_DIR_MODE = 0x41ED

class CryfsSession(
    private val context: Context,
    val vaultRootUri: Uri,
    val config: CryfsConfig,
    val dataTree: CryfsDataTree,
    val tree: CryfsVaultTree,
    val readOnly: Boolean,
    private val blockStore: CryfsBlockStore,
) : VaultBackend {
    override val format = ContainerFormat.CRYFS
    override val skipsPerVolumeLock: Boolean = true
    override val managesOwnWriteLocking: Boolean = true
    var volId: Int = -1

    private val pendingWrites = mutableMapOf<String, File>()

    inline fun <T> runRead(block: () -> T): T {
        return if (volId >= 0) ContainerFileSystem.withReadLock(volId, block) else block()
    }

    inline fun <T> runWrite(block: () -> T): T {
        return if (volId >= 0) ContainerFileSystem.withWriteLock(volId, block) else block()
    }

    override fun invalidateCache(virtualPath: String) {
        tree.invalidateCache()
        blockStore.invalidateCache()
    }

    override fun close() {
        synchronized(pendingWrites) {
            pendingWrites.values.forEach { it.delete() }
            pendingWrites.clear()
        }
        try { blockStore.flushIntegrityState() } catch (_: Exception) { /* best-effort */ }
        config.encryptionKey.fill(0)
    }

    override fun listDirectory(virtualPath: String): Array<String>? {
        return runRead {
            try {
                tree.listDirectory(normalize(virtualPath)).map { node ->
                    val entry = node.entry!!
                    val isDir = entry.type == CryfsEntryType.DIR
                    val size = if (isDir) 0L else CryfsFsBlob.payloadSize(dataTree, entry.blobId)
                    DirEntryWire.encode(entry.name, isDir, size, entry.mtimeEpochSec)
                }.toTypedArray()
            } catch (e: Exception) {
                VeLog.e("CryfsSession", e) { "listDirectory failed (pathLen=${virtualPath.length})" }
                null
            }
        }
    }

    override fun createDirectory(virtualPath: String): Boolean {
        if (readOnly) return false
        return runWrite {
            try {
                val normalized = normalize(virtualPath)
                tree.tryResolve(normalized)?.let { return@runWrite it.isDirectory }
                val parentBlobId = tree.resolve(parentOf(normalized)).blobId
                val newDirBlobId = CryfsFsBlob.writeWhole(
                    dataTree, null, CryfsEntryType.DIR, parentBlobId, CryfsDirBlob.serialize(emptyList())
                )
                val now = nowEpochSec()
                tree.addEntry(parentBlobId, CryfsDirBlob.newEntry(CryfsEntryType.DIR, nameOf(normalized), newDirBlobId, DEFAULT_DIR_MODE, now))
                true
            } catch (e: Exception) {
                VeLog.e("CryfsSession", e) { "createDirectory failed (pathLen=${virtualPath.length})" }
                false
            }
        }
    }

    override fun renameFile(oldVirtualPath: String, newVirtualPath: String): Boolean {
        if (readOnly) return false
        return runWrite {
            try {
                val oldNorm = normalize(oldVirtualPath)
                val newNorm = normalize(newVirtualPath)
                val oldNode = tree.resolve(oldNorm)
                val oldParentBlobId = oldNode.parentDirBlobId ?: return@runWrite false
                val newParentBlobId = tree.resolve(parentOf(newNorm)).blobId
                val updatedEntry = oldNode.entry!!.copy(name = nameOf(newNorm))
                if (oldParentBlobId == newParentBlobId) {
                    tree.replaceEntry(oldParentBlobId, oldNode.entry.name, updatedEntry)
                } else {
                    tree.removeEntry(oldParentBlobId, oldNode.entry.name)
                    tree.addEntry(newParentBlobId, updatedEntry)
                    CryfsFsBlob.updateParent(dataTree, updatedEntry.blobId, newParentBlobId)
                }
                true
            } catch (e: Exception) {
                false
            }
        }
    }

    override fun deleteFile(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            val node = runRead { tree.tryResolve(normalized) } ?: return false
            val parentBlobId = node.parentDirBlobId ?: return false

            runWrite {
                tree.removeEntry(parentBlobId, node.entry!!.name)
            }
            synchronized(pendingWrites) {
                pendingWrites.remove(normalized)?.delete()
            }

            if (node.isDirectory) freeDirectoryContentsRecursive(node.blobId)
            dataTree.deleteBlob(node.blobId)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun freeDirectoryContentsRecursive(dirBlobId: CryfsBlockId) {
        val (_, payload) = CryfsFsBlob.readWhole(dataTree, dirBlobId)
        for (entry in CryfsDirBlob.parse(payload)) {
            if (entry.type == CryfsEntryType.DIR) freeDirectoryContentsRecursive(entry.blobId)
            dataTree.deleteBlob(entry.blobId)
        }
    }

    override fun setLastModifiedTime(virtualPath: String, epochSeconds: Long): Boolean {
        return runWrite {
            try {
                val node = tree.resolve(normalize(virtualPath))
                val parentBlobId = node.parentDirBlobId ?: return@runWrite true
                tree.replaceEntry(parentBlobId, node.entry!!.name, node.entry.copy(mtimeEpochSec = epochSeconds))
                true
            } catch (e: Exception) {
                false
            }
        }
    }

    override fun getFileSize(virtualPath: String): Long {
        return runRead {
            try {
                val normalized = normalize(virtualPath)
                val pending = synchronized(pendingWrites) { pendingWrites[normalized] }
                pending?.let { return@runRead it.length() }
                val node = tree.resolve(normalized)
                if (node.isDirectory) -1L else CryfsFsBlob.payloadSize(dataTree, node.blobId)
            } catch (e: Exception) {
                -1L
            }
        }
    }

    override fun getFolderSize(virtualPath: String): Long {
        return try {
            val normalized = normalize(virtualPath)
            var total = 0L
            val children = runRead { tree.listDirectory(normalized) }
            for (node in children) {
                try { Thread.sleep(1) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
                total += if (node.isDirectory) getFolderSize(joinPath(normalized, node.cleartextName))
                else runRead { CryfsFsBlob.payloadSize(dataTree, node.blobId) }
            }
            total
        } catch (e: Exception) {
            0L
        }
    }

    override fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? {
        return runRead {
            try {
                val normalized = normalize(virtualPath)
                val pending = synchronized(pendingWrites) { pendingWrites[normalized] }
                pending?.let { return@runRead readFromLocalFile(it, offset, length) }
                val node = tree.resolve(normalized)
                if (node.isDirectory) return@runRead null
                CryfsFsBlob.readPayload(dataTree, node.blobId, offset, length)
            } catch (e: Exception) {
                null
            }
        }
    }

    override fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean {
        if (readOnly) return false
        return runWrite {
            try {
                val normalized = normalize(virtualPath)
                val tmp = synchronized(pendingWrites) {
                    pendingWrites.getOrPut(normalized) {
                        File.createTempFile("cryfs_write_", ".tmp", context.cacheDir).also { scratch ->
                            val existing = tree.tryResolve(normalized)
                            if (existing != null && !existing.isDirectory) {
                                val fileSize = CryfsFsBlob.payloadSize(dataTree, existing.blobId)
                                scratch.outputStream().use { out ->
                                    var readPos = 0L
                                    val chunkSize = 64 * 1024
                                    while (readPos < fileSize) {
                                        val toRead = minOf(chunkSize.toLong(), fileSize - readPos).toInt()
                                        val chunk = CryfsFsBlob.readPayload(dataTree, existing.blobId, readPos, toRead)
                                        if (chunk.isEmpty()) break
                                        out.write(chunk)
                                        readPos += chunk.size
                                    }
                                }
                            }
                        }
                    }
                }
                RandomAccessFile(tmp, "rw").use { raf ->
                    raf.seek(offset)
                    raf.write(data)
                }
                true
            } catch (e: Exception) {
                false
            }
        }
    }

    override fun finishWrite(virtualPath: String): Boolean {
        if (readOnly) return false
        val normalized = normalize(virtualPath)
        val tmp = synchronized(pendingWrites) { pendingWrites.remove(normalized) } ?: return true
        return try {
            tmp.inputStream().use { stream ->
                commitLocalFileStream(normalized, stream)
            }
            true
        } catch (e: Exception) {
            false
        } finally {
            tmp.delete()
        }
    }

    override fun writeBackFile(virtualPath: String, sourcePath: String, opId: Int): Boolean {
        if (readOnly) return false
        return try {
            val rawStream = File(sourcePath).inputStream()
            val stream: InputStream =
                if (opId > 0) CryfsCopyProgressStream(rawStream, opId) else rawStream
            stream.use {
                commitLocalFileStream(normalize(virtualPath), it)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun extractFile(virtualPath: String, destinationPath: String, opId: Int): Boolean {
        return try {
            val normalized = normalize(virtualPath)
            val node = runRead { tree.resolve(normalized) }
            if (node.isDirectory) return false
            val fileSize = runRead { CryfsFsBlob.payloadSize(dataTree, node.blobId) }
            File(destinationPath).outputStream().use { out ->
                var readPos = 0L
                val chunkSize = 64 * 1024
                while (readPos < fileSize) {
                    val toRead = minOf(chunkSize.toLong(), fileSize - readPos).toInt()
                    val chunk = runRead { CryfsFsBlob.readPayload(dataTree, node.blobId, readPos, toRead) }
                    if (chunk.isEmpty()) break
                    out.write(chunk)
                    readPos += chunk.size
                    // See writeBackFile / CryfsCopyProgressStream for why this is halved.
                    if (opId > 0) CopyProgressBridge.reportProgress(opId, chunk.size.toLong() / 2)
                    try { Thread.sleep(1) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun commitLocalFileStream(normalized: String, inputStream: InputStream) {
        val now = nowEpochSec()
        val existing = runRead { tree.tryResolve(normalized) }
        val parentId = existing?.parentDirBlobId ?: runRead { tree.resolve(parentOf(normalized)).blobId }
        val wrappedStream = object : InputStream() {
            private var headerPos = 0
            private val headerBytes = CryfsFsBlob.wrap(CryfsEntryType.FILE, parentId, ByteArray(0)).copyOfRange(0, CryfsFsBlob.HEADER_SIZE)
            override fun read(): Int {
                if (headerPos < CryfsFsBlob.HEADER_SIZE) {
                    return headerBytes[headerPos++].toInt() and 0xFF
                }
                return inputStream.read()
            }
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (len <= 0) return 0
                if (headerPos < CryfsFsBlob.HEADER_SIZE) {
                    val toCopy = minOf(len, CryfsFsBlob.HEADER_SIZE - headerPos)
                    System.arraycopy(headerBytes, headerPos, b, off, toCopy)
                    headerPos += toCopy
                    if (toCopy == len) return toCopy
                    val n = inputStream.read(b, off + toCopy, len - toCopy)
                    return if (n > 0) toCopy + n else toCopy
                }
                return inputStream.read(b, off, len)
            }
        }
        if (existing != null) {
            if (existing.isDirectory) throw VaultIOException("$normalized is a directory")
            val newBlobId = dataTree.writeWholeBlobStream(existing.blobId, wrappedStream)
            runWrite {
                tree.replaceEntry(existing.parentDirBlobId!!, existing.entry!!.name, existing.entry.copy(blobId = newBlobId, mtimeEpochSec = now))
            }
        } else {
            val parentBlobId = runRead { tree.resolve(parentOf(normalized)).blobId }
            val newBlobId = dataTree.writeWholeBlobStream(null, wrappedStream)
            runWrite {
                tree.addEntry(parentBlobId, CryfsDirBlob.newEntry(CryfsEntryType.FILE, nameOf(normalized), newBlobId, DEFAULT_FILE_MODE, now))
            }
        }
    }

    private fun readFromLocalFile(file: File, offset: Long, length: Int): ByteArray? {
        if (!file.exists()) return null
        RandomAccessFile(file, "r").use { raf ->
            if (offset >= raf.length()) return ByteArray(0)
            raf.seek(offset)
            val toRead = minOf(length.toLong(), raf.length() - offset).toInt()
            val buf = ByteArray(toRead)
            raf.readFully(buf)
            return buf
        }
    }

    override fun importStream(virtualPath: String, inputStream: InputStream, volId: Int): Boolean {
        if (readOnly) return false
        this.volId = volId
        dataTree.volId = volId
        return try {
            commitLocalFileStream(normalize(virtualPath), inputStream)
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun getSpaceInfo(): LongArray? = runRead {
        com.aeidolon.vaultexplorer.saf.VaultPathUtils.querySafSpaceInfo(context, vaultRootUri)
    }

    override fun getVaultInfo(): Map<String, Any?> = mapOf(
        "formatVersion" to config.formatVersion,
        "blockCipherName" to config.blockCipherName,
        "createdWithVersion" to config.createdWithVersion,
        "lastOpenedWithVersion" to config.lastOpenedWithVersion,
        "blockSizeBytes" to config.blocksizeBytes,
        "readOnly" to readOnly,
    )

    private fun normalize(path: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.normalize(path)
    private fun parentOf(normalizedPath: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.parentOf(normalizedPath)
    private fun nameOf(normalizedPath: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.nameOf(normalizedPath)
    private fun joinPath(parent: String, name: String): String = com.aeidolon.vaultexplorer.saf.VaultPathUtils.joinPath(parent, name)
    private fun nowEpochSec(): Long = System.currentTimeMillis() / 1000
}

/**
 * Reports copy progress as [delegate] is read, for CryfsSession.writeBackFile.
 * Mirrors ImportExportHandlers.ProgressInputStream's shape, but wraps the
 * stream instead of instrumenting a batch loop (as ChunkedFileEngine's
 * writeBackFile does) because this path goes through
 * commitLocalFileStream -> CryfsDataTree.writeWholeBlobStream, which reads
 * a plain InputStream with no exposed per-chunk hook.
 *
 * Reports half of each read's byte count -- see the matching comment on
 * ChunkedFileEngine.writeBackFile: a copy is a decrypt pass and an encrypt
 * pass over the same bytes, but Dart's totalBytes budget is one pass, so
 * each side reports half to land on the right total instead of 200%.
 */
private class CryfsCopyProgressStream(
    private val delegate: InputStream,
    private val opId: Int,
) : InputStream() {
    override fun read(): Int {
        val b = delegate.read()
        if (b != -1) CopyProgressBridge.reportProgress(opId, 1L / 2)
        return b
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        val n = delegate.read(b, off, len)
        if (n > 0) CopyProgressBridge.reportProgress(opId, n.toLong() / 2)
        return n
    }

    override fun close() = delegate.close()
    override fun available(): Int = delegate.available()
    override fun skip(n: Long): Long = delegate.skip(n)
    override fun markSupported(): Boolean = delegate.markSupported()
    override fun mark(readlimit: Int) = delegate.mark(readlimit)
    override fun reset() = delegate.reset()
}