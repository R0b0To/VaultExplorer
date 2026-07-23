package com.aeidolon.vaultexplorer.cryfs

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
    private val dirEntriesCache = ConcurrentHashMap<String, List<CryfsDirEntry>>()

    private fun splitPath(path: String): List<String> = path.trim('/').split('/').filter { it.isNotEmpty() }

    private fun readDirEntries(dirBlobId: CryfsBlockId): List<CryfsDirEntry> {
        dirEntriesCache[dirBlobId.hex]?.let { return it }
        val (header, payload) = CryfsFsBlob.readWhole(dataTree, dirBlobId)
        if (header.type != CryfsEntryType.DIR) {
            throw VaultIOException("Block $dirBlobId is not a directory blob")
        }
        val entries = CryfsDirBlob.parse(payload)
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
                throw VaultIOException("${segments.subList(0, i).joinToString("/")} is not a directory")
            }
            val match = readDirEntries(currentBlobId).firstOrNull { it.name == seg }
                ?: throw VaultPathNotFoundException(path)
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
    }

    fun listDirectory(path: String): List<CryfsResolvedNode> {
        val node = if (path.isEmpty() || path == "/") CryfsResolvedNode("", null, rootBlobId, null) else resolve(path)
        if (!node.isDirectory) throw VaultIOException("$path is not a directory")
        return readDirEntries(node.blobId).map { CryfsResolvedNode(it.name, it, it.blobId, node.blobId) }
    }

    fun addEntry(parentDirBlobId: CryfsBlockId, entry: CryfsDirEntry) {
        val entries = readDirEntries(parentDirBlobId)
        if (entries.any { it.name == entry.name }) {
            throw VaultIOException("\"${entry.name}\" already exists")
        }
        val (header, _) = CryfsFsBlob.readWhole(dataTree, parentDirBlobId)
        dirEntriesCache.remove(parentDirBlobId.hex)
        CryfsFsBlob.writeWhole(dataTree, parentDirBlobId, CryfsEntryType.DIR, header.parent, CryfsDirBlob.serialize(entries + entry))
    }

    fun removeEntry(parentDirBlobId: CryfsBlockId, name: String) {
        val entries = readDirEntries(parentDirBlobId)
        val remaining = entries.filterNot { it.name == name }
        if (remaining.size == entries.size) throw VaultPathNotFoundException(name)
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
        if (!found) throw VaultPathNotFoundException(oldName)
        val (header, _) = CryfsFsBlob.readWhole(dataTree, parentDirBlobId)
        dirEntriesCache.remove(parentDirBlobId.hex)
        CryfsFsBlob.writeWhole(dataTree, parentDirBlobId, CryfsEntryType.DIR, header.parent, CryfsDirBlob.serialize(updated))
    }

    fun invalidateCache() {
        dirEntriesCache.clear()
    }
}