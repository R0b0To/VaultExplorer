package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.net.Uri
import com.aeidolon.vaultexplorer.ContainerFormat
import com.aeidolon.vaultexplorer.VaultBackend
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultPathNotFoundException
import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile
import java.security.SecureRandom

private const val DEFAULT_FILE_MODE = 0x81A4
private const val DEFAULT_DIR_MODE = 0x41ED

class CryfsSession(
    private val context: Context,
    val vaultRootUri: Uri,
    val config: CryfsConfig,
    val dataTree: CryfsDataTree,
    val tree: CryfsVaultTree,
    val readOnly: Boolean,
) : VaultBackend {
    override val format = ContainerFormat.CRYFS

    private val pendingWrites = mutableMapOf<String, File>()

    fun close() {
        pendingWrites.values.forEach { it.delete() }
        pendingWrites.clear()
        config.encryptionKey.fill(0)
    }

override fun listDirectory(virtualPath: String): Array<String>? {
        return try {
            tree.listDirectory(normalize(virtualPath)).map { node ->
                val entry = node.entry!!
                if (entry.type == CryfsEntryType.DIR) {
                    "[DIR] ${entry.name}|0|${entry.mtimeEpochSec}"
                } else {
                    "${entry.name}|${CryfsFsBlob.payloadSize(dataTree, entry.blobId)}|${entry.mtimeEpochSec}"
                }
            }.toTypedArray()
        } catch (e: Exception) {
            android.util.Log.e("CryfsSession", "listDirectory failed for path: \"$virtualPath\"", e)
            null
        }
    }

    override fun createDirectory(virtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            tree.tryResolve(normalized)?.let { return it.isDirectory }

            val parentBlobId = tree.resolve(parentOf(normalized)).blobId
            val newDirBlobId = CryfsFsBlob.writeWhole(
                dataTree, null, CryfsEntryType.DIR, parentBlobId, CryfsDirBlob.serialize(emptyList())
            )
            val now = nowEpochSec()
            tree.addEntry(parentBlobId, CryfsDirBlob.newEntry(CryfsEntryType.DIR, nameOf(normalized), newDirBlobId, DEFAULT_DIR_MODE, now))
            true
        } catch (e: Exception) {
            android.util.Log.e("CryfsSession", "createDirectory failed for $virtualPath", e)
            false
        }
    }

    override fun renameFile(oldVirtualPath: String, newVirtualPath: String): Boolean {
        if (readOnly) return false
        return try {
            val oldNorm = normalize(oldVirtualPath)
            val newNorm = normalize(newVirtualPath)
            val oldNode = tree.resolve(oldNorm)
            val oldParentBlobId = oldNode.parentDirBlobId ?: return false
            val newParentBlobId = tree.resolve(parentOf(newNorm)).blobId
            val updatedEntry = oldNode.entry!!.copy(name = nameOf(newNorm))

            if (oldParentBlobId == newParentBlobId) {
                tree.replaceEntry(oldParentBlobId, oldNode.entry.name, updatedEntry)
            } else {
                tree.removeEntry(oldParentBlobId, oldNode.entry.name)
                tree.addEntry(newParentBlobId, updatedEntry)
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
            val node = tree.resolve(normalized)
            val parentBlobId = node.parentDirBlobId ?: return false
            if (node.isDirectory) freeDirectoryContentsRecursive(node.blobId)
            dataTree.deleteBlob(node.blobId)
            tree.removeEntry(parentBlobId, node.entry!!.name)
            pendingWrites.remove(normalized)?.delete()
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
        return try {
            val node = tree.resolve(normalize(virtualPath))
            val parentBlobId = node.parentDirBlobId ?: return true
            tree.replaceEntry(parentBlobId, node.entry!!.name, node.entry.copy(mtimeEpochSec = epochSeconds))
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun getFileSize(virtualPath: String): Long {
        return try {
            val normalized = normalize(virtualPath)
            pendingWrites[normalized]?.let { return it.length() }
            val node = tree.resolve(normalized)
            if (node.isDirectory) -1L else CryfsFsBlob.payloadSize(dataTree, node.blobId)
        } catch (e: Exception) {
            -1L
        }
    }

    override fun getFolderSize(virtualPath: String): Long {
        return try {
            val normalized = normalize(virtualPath)
            var total = 0L
            for (node in tree.listDirectory(normalized)) {
                total += if (node.isDirectory) getFolderSize(joinPath(normalized, node.cleartextName))
                else CryfsFsBlob.payloadSize(dataTree, node.entry!!.blobId)
            }
            total
        } catch (e: Exception) {
            0L
        }
    }

    override fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? {
        return try {
            val normalized = normalize(virtualPath)
            pendingWrites[normalized]?.let { return readFromLocalFile(it, offset, length) }
            val node = tree.resolve(normalized)
            if (node.isDirectory) return null
            CryfsFsBlob.readPayload(dataTree, node.blobId, offset, length)
        } catch (e: Exception) {
            null
        }
    }

    override fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean {
        if (readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            val tmp = pendingWrites.getOrPut(normalized) {
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
            RandomAccessFile(tmp, "rw").use { raf ->
                raf.seek(offset)
                raf.write(data)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun finishWrite(virtualPath: String): Boolean {
        if (readOnly) return false
        val normalized = normalize(virtualPath)
        val tmp = pendingWrites.remove(normalized) ?: return true
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

    override fun writeBackFile(virtualPath: String, sourcePath: String): Boolean {
        if (readOnly) return false
        return try {
            File(sourcePath).inputStream().use { stream ->
                commitLocalFileStream(normalize(virtualPath), stream)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun extractFile(virtualPath: String, destinationPath: String): Boolean {
        return try {
            val node = tree.resolve(normalize(virtualPath))
            if (node.isDirectory) return false
            val fileSize = CryfsFsBlob.payloadSize(dataTree, node.blobId)
            File(destinationPath).outputStream().use { out ->
                var readPos = 0L
                val chunkSize = 64 * 1024
                while (readPos < fileSize) {
                    val toRead = minOf(chunkSize.toLong(), fileSize - readPos).toInt()
                    val chunk = CryfsFsBlob.readPayload(dataTree, node.blobId, readPos, toRead)
                    if (chunk.isEmpty()) break
                    out.write(chunk)
                    readPos += chunk.size
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun commitLocalFileStream(normalized: String, inputStream: InputStream) {
        val now = nowEpochSec()
        val existing = tree.tryResolve(normalized)
        
        // Wrap input with 19-byte CryFS fsblob header
        val wrappedStream = object : InputStream() {
            private var headerPos = 0
            private val parentId = existing?.parentDirBlobId ?: tree.resolve(parentOf(normalized)).blobId
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
            tree.replaceEntry(existing.parentDirBlobId!!, existing.entry!!.name, existing.entry.copy(blobId = newBlobId, mtimeEpochSec = now))
        } else {
            val parentBlobId = tree.resolve(parentOf(normalized)).blobId
            val newBlobId = dataTree.writeWholeBlobStream(null, wrappedStream)
            tree.addEntry(parentBlobId, CryfsDirBlob.newEntry(CryfsEntryType.FILE, nameOf(normalized), newBlobId, DEFAULT_FILE_MODE, now))
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

    override fun importStream(virtualPath: String, inputStream: InputStream): Boolean {
        if (readOnly) return false
        return try {
            commitLocalFileStream(normalize(virtualPath), inputStream)
            true
        } catch (e: Exception) {
            false
        }
    }

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
    private fun nowEpochSec(): Long = System.currentTimeMillis() / 1000
}