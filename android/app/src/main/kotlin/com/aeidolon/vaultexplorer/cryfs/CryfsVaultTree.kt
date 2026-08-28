package com.aeidolon.vaultexplorer.cryfs

import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultPathNotFoundException
import com.aeidolon.vaultexplorer.engine.VaultTreeNode
import java.util.concurrent.ConcurrentHashMap

data class CryfsResolvedNode(
    override val cleartextName: String,
    val entry: CryfsDirEntry?,
    val blobId: CryfsBlockId,
    val parentDirBlobId: CryfsBlockId?,
) : VaultTreeNode {
    val isDirectory: Boolean get() = entry == null || entry.type == CryfsEntryType.DIR
}

class CryfsVaultTree(
    private val dataTree: CryfsDataTree,
    private val rootBlobId: CryfsBlockId,
) {
    companion object {
        private const val TAG = "CryfsVaultTree"
    }

    private val dirEntriesCache = ConcurrentHashMap<String, List<CryfsDirEntry>>()

    private fun splitPath(path: String): List<String> = path.trim('/').split('/').filter { it.isNotEmpty() }

    private fun readDirEntries(dirBlobId: CryfsBlockId): List<CryfsDirEntry> {
        dirEntriesCache[dirBlobId.hex]?.let { return it }
        val (header, payload) = try {
            CryfsFsBlob.readWhole(dataTree, dirBlobId)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "readDirEntries failed to read blob ${dirBlobId.hex}" }
            throw VaultIOException("Failed to read directory blob ${dirBlobId.hex}", e)
        }
        if (header.type != CryfsEntryType.DIR) {
            val errorMsg = "Block ${dirBlobId.hex} is not a directory blob (type: ${header.type})"
            VeLog.e(TAG) { errorMsg }
            throw VaultIOException(errorMsg)
        }
        val entries = try {
            CryfsDirBlob.parse(payload)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "readDirEntries failed to parse directory payload in ${dirBlobId.hex}" }
            throw e
        }
        dirEntriesCache[dirBlobId.hex] = entries
        return entries
    }

    fun resolve(path: String): CryfsResolvedNode {
        val segments = splitPath(path)
        if (segments.isEmpty()) return CryfsResolvedNode("", null, rootBlobId, null)

        var currentBlobId = rootBlobId
        var currentEntry: CryfsDirEntry? = null
        var parentDirBlobId: CryfsBlockId? = null

        for ((i, seg) in segments.withIndex()) {
            if (i > 0 && currentEntry?.type != CryfsEntryType.DIR) {
                val errorMsg = "${segments.subList(0, i).joinToString("/")} is not a directory"
                VeLog.e(TAG) { "resolve failed: $errorMsg (full path: $path)" }
                throw VaultIOException(errorMsg)
            }
            val match = readDirEntries(currentBlobId).firstOrNull { it.name == seg }
                ?: run {
                    VeLog.e(TAG) { "resolve failed: Path component '$seg' not found in parent blob ${currentBlobId.hex} (full path: $path)" }
                    throw VaultPathNotFoundException(path)
                }
            parentDirBlobId = currentBlobId
            currentEntry = match
            currentBlobId = match.blobId
        }
        return CryfsResolvedNode(segments.last(), currentEntry, currentBlobId, parentDirBlobId)
    }

    fun tryResolve(path: String): CryfsResolvedNode? = try {
        resolve(path)
    } catch (e: VaultPathNotFoundException) {
        null
    } catch (e: Exception) {
        VeLog.e(TAG, e) { "tryResolve error for path: '$path'" }
        null
    }

    fun listDirectory(path: String): List<CryfsResolvedNode> {
        val node = if (path.isEmpty() || path == "/") CryfsResolvedNode("", null, rootBlobId, null) else resolve(path)
        if (!node.isDirectory) {
            val errorMsg = "$path is not a directory"
            VeLog.e(TAG) { "listDirectory failed: $errorMsg" }
            throw VaultIOException(errorMsg)
        }
        return readDirEntries(node.blobId).map { CryfsResolvedNode(it.name, it, it.blobId, node.blobId) }
    }

    fun addEntry(parentDirBlobId: CryfsBlockId, entry: CryfsDirEntry) {
        val entries = readDirEntries(parentDirBlobId)
        if (entries.any { it.name == entry.name }) {
            val errorMsg = "\"${entry.name}\" already exists in parent blob ${parentDirBlobId.hex}"
            VeLog.e(TAG) { errorMsg }
            throw VaultIOException(errorMsg)
        }
        val (header, _) = CryfsFsBlob.readWhole(dataTree, parentDirBlobId)
        dirEntriesCache.remove(parentDirBlobId.hex)
        CryfsFsBlob.writeWhole(dataTree, parentDirBlobId, CryfsEntryType.DIR, header.parent, CryfsDirBlob.serialize(entries + entry))
    }

    fun removeEntry(parentDirBlobId: CryfsBlockId, name: String) {
        val entries = readDirEntries(parentDirBlobId)
        val remaining = entries.filterNot { it.name == name }
        if (remaining.size == entries.size) {
            VeLog.e(TAG) { "removeEntry failed: '$name' not found in parent blob ${parentDirBlobId.hex}" }
            throw VaultPathNotFoundException(name)
        }
        val (header, _) = CryfsFsBlob.readWhole(dataTree, parentDirBlobId)
        dirEntriesCache.remove(parentDirBlobId.hex)
        CryfsFsBlob.writeWhole(dataTree, parentDirBlobId, CryfsEntryType.DIR, header.parent, CryfsDirBlob.serialize(remaining))
    }

    fun replaceEntry(parentDirBlobId: CryfsBlockId, oldName: String, newEntry: CryfsDirEntry) {
        val entries = readDirEntries(parentDirBlobId)
        var found = false
        val updated = entries.map {
            if (it.name == oldName) { found = true; newEntry } else it
        }
        if (!found) {
            VeLog.e(TAG) { "replaceEntry failed: '$oldName' not found in parent blob ${parentDirBlobId.hex}" }
            throw VaultPathNotFoundException(oldName)
        }
        val (header, _) = CryfsFsBlob.readWhole(dataTree, parentDirBlobId)
        dirEntriesCache.remove(parentDirBlobId.hex)
        CryfsFsBlob.writeWhole(dataTree, parentDirBlobId, CryfsEntryType.DIR, header.parent, CryfsDirBlob.serialize(updated))
    }

    fun invalidateCache() {
        dirEntriesCache.clear()
    }
}