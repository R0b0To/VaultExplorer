package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultPathNotFoundException
import com.aeidolon.vaultexplorer.engine.VaultTreeNode
import com.aeidolon.vaultexplorer.saf.MirroredSafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.VaultDocumentOps
import java.util.concurrent.ConcurrentHashMap

private const val CLOUD_NODE_EXT = ".c9r"
private const val LONG_NODE_EXT = ".c9s"
private const val DIR_FILE_NAME = "dir$CLOUD_NODE_EXT"
private const val LONG_NAME_FILE = "name$LONG_NODE_EXT"
private const val LONG_CONTENTS_FILE = "contents$CLOUD_NODE_EXT"
private const val DATA_DIR_NAME = "d"
private const val ROOT_DIR_ID = ""

sealed class VaultNode : VaultTreeNode {
    data class VFile(
        override val cleartextName: String,
        val physicalFile: DocumentFile,
        val cleartextSizeHint: Long?,
        val wrapperFolder: DocumentFile? = null
    ) : VaultNode()

    data class VDir(override val cleartextName: String, val physicalFolder: DocumentFile, val dirIdFile: DocumentFile) : VaultNode()
}

class CryptomatorVaultTree(
    private val context: Context,
    private val vaultRootUri: Uri,
    private val nameCryptor: CryptomatorFileNameCryptor,
    private val shorteningThreshold: Int,
    val safOps: VaultDocumentOps = SafDocumentOps(context),
) {
    companion object {
        private const val TAG = "CryptomatorVaultTree"
    }

    private val dirIdCache = ConcurrentHashMap<String, String>().apply { put("", ROOT_DIR_ID) }
    private val dataDirCache = ConcurrentHashMap<String, DocumentFile>()

    private val vaultRoot: DocumentFile by lazy {
        (safOps as? MirroredSafDocumentOps)?.root
            ?: DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: run {
                val errorMsg = "Cannot open vault root: $vaultRootUri"
                VeLog.e(TAG) { errorMsg }
                throw VaultIOException(errorMsg)
            }
    }

    val dataDir: DocumentFile by lazy {
        findChild(vaultRoot, DATA_DIR_NAME) ?: run {
            val errorMsg = "Vault is missing its '$DATA_DIR_NAME' data directory in ${vaultRoot.uri}"
            VeLog.e(TAG) { errorMsg }
            throw VaultIOException(errorMsg)
        }
    }

    fun rootPhysicalFolder(): DocumentFile = physicalFolderForDirId(ROOT_DIR_ID)

    fun list(virtualDirPath: String): List<VaultNode> {
        val dirId = resolveDirId(virtualDirPath)
        return listByDirId(dirId)
    }

    private fun listByDirId(dirId: String): List<VaultNode> {
        val physicalFolder = physicalFolderForDirId(dirId)
        val children = safOps.listChildren(physicalFolder)
        val results = mutableListOf<VaultNode>()
        for (child in children) {
            val name = child.name ?: continue
            try {
                when {
                    name == DIR_FILE_NAME -> continue
                    name.endsWith(LONG_NODE_EXT) -> {
                        if (!child.isDirectory) continue
                        var longName = readSmallFile(child, LONG_NAME_FILE)
                        if (longName == null) {
                            safOps.invalidate(child)
                            longName = readSmallFile(child, LONG_NAME_FILE) ?: continue
                        }
                        val rawLongName = String(longName, Charsets.UTF_8).trim().trimEnd('\u0000', '\r', '\n', ' ')
                        val ciphertextName = stripExtension(rawLongName, CLOUD_NODE_EXT).trim()
                        val cleartext = nameCryptor.decryptFilename(ciphertextName, dirId.toByteArray(Charsets.UTF_8))
                        val dirPointer = findChild(child, DIR_FILE_NAME)
                        if (dirPointer != null) {
                            results.add(VaultNode.VDir(cleartext, child, dirPointer))
                        } else {
                            val contents = findChild(child, LONG_CONTENTS_FILE)
                                ?: run {
                                    safOps.invalidate(child)
                                    findChild(child, LONG_CONTENTS_FILE)
                                }
                            if (contents != null) {
                                results.add(VaultNode.VFile(cleartext, contents, contents.length(), wrapperFolder = child))
                            }
                        }
                    }
                    name.endsWith(CLOUD_NODE_EXT) -> {
                        val ciphertextName = name.removeSuffix(CLOUD_NODE_EXT)
                        val cleartext = nameCryptor.decryptFilename(ciphertextName, dirId.toByteArray(Charsets.UTF_8))
                        if (child.isDirectory) {
                            val dirPointer = findChild(child, DIR_FILE_NAME) ?: continue
                            results.add(VaultNode.VDir(cleartext, child, dirPointer))
                        } else {
                            results.add(VaultNode.VFile(cleartext, child, child.length(), wrapperFolder = null))
                        }
                    }
                    else -> continue
                }
            } catch (e: CryptomatorAuthenticationException) {
                VeLog.w(TAG) { "listByDirId: Skipping unauthenticated child '$name' in dirId '$dirId': ${e.message}" }
                continue
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "listByDirId: Error resolving child '$name' in dirId '$dirId'" }
                continue
            }
        }
        return results
    }

    fun resolve(virtualPath: String): VaultNode? {
        val segments = normalizedSegments(virtualPath)
        if (segments.isEmpty()) return null
        return walk(segments).lastNodeOrNull
    }

    fun resolveDirId(virtualDirPath: String): String {
        val segments = normalizedSegments(virtualDirPath)
        if (segments.isEmpty()) return ROOT_DIR_ID
        val result = walk(segments)
        return result.finalDirId ?: run {
            VeLog.e(TAG) { "resolveDirId failed for path: '$virtualDirPath'" }
            throw VaultPathNotFoundException(virtualDirPath)
        }
    }

    private class WalkResult(val finalDirId: String?, val lastNodeOrNull: VaultNode?)

    private fun walk(segments: List<String>): WalkResult {
        var currentDirId = ROOT_DIR_ID
        var builtPath = ""
        var lastNode: VaultNode? = null
        for ((index, segment) in segments.withIndex()) {
            val nextBuiltPath = if (builtPath.isEmpty()) segment else "$builtPath/$segment"
            val cachedDirId = dirIdCache[nextBuiltPath]
            if (cachedDirId != null) {
                currentDirId = cachedDirId
                builtPath = nextBuiltPath
                lastNode = null
                continue
            }
            val children = listByDirId(currentDirId)
            val match = children.firstOrNull { it.cleartextName == segment }
                ?: return WalkResult(finalDirId = null, lastNodeOrNull = null)
            lastNode = match
            when (match) {
                is VaultNode.VDir -> {
                    currentDirId = readDirId(match.dirIdFile)
                    dirIdCache[nextBuiltPath] = currentDirId
                }
                is VaultNode.VFile -> {
                    if (index != segments.lastIndex) {
                        return WalkResult(finalDirId = null, lastNodeOrNull = null)
                    }
                }
            }
            builtPath = nextBuiltPath
        }
        if (lastNode == null) {
            val parentPath = segments.dropLast(1).joinToString("/")
            val parentDirId = if (parentPath.isEmpty()) ROOT_DIR_ID else (dirIdCache[parentPath] ?: return WalkResult(currentDirId, null))
            lastNode = listByDirId(parentDirId).firstOrNull { it.cleartextName == segments.last() }
        }
        return WalkResult(finalDirId = currentDirId, lastNodeOrNull = lastNode)
    }

    fun physicalFolderForDirId(dirId: String): DocumentFile {
        dataDirCache[dirId]?.let { return it }
        val hash = nameCryptor.hashDirectoryId(dirId)
        val lvl1Name = hash.substring(0, 2)
        val lvl2Name = hash.substring(2)
        val lvl1 = findChild(dataDir, lvl1Name) ?: run {
            val errorMsg = "Missing lvl1 directory '$lvl1Name' for dirId '$dirId' (hash: $hash)"
            VeLog.e(TAG) { errorMsg }
            throw VaultIOException(errorMsg)
        }
        val lvl2 = findChild(lvl1, lvl2Name) ?: run {
            val errorMsg = "Missing lvl2 directory '$lvl2Name' in '$lvl1Name' for dirId '$dirId' (hash: $hash)"
            VeLog.e(TAG) { errorMsg }
            throw VaultIOException(errorMsg)
        }
        dataDirCache[dirId] = lvl2
        return lvl2
    }

    fun createPhysicalFolderForDirId(dirId: String): DocumentFile {
        dataDirCache[dirId]?.let { return it }
        val hash = nameCryptor.hashDirectoryId(dirId)
        val lvl1Name = hash.substring(0, 2)
        val lvl2Name = hash.substring(2)
        val lvl1 = findOrCreateChild(dataDir, lvl1Name, isDir = true)
            ?: run {
                val errorMsg = "Could not create lvl1 dir '$lvl1Name' for dirId '$dirId' (hash: $hash)"
                VeLog.e(TAG) { errorMsg }
                throw VaultIOException(errorMsg)
            }
        val lvl2 = findOrCreateChild(lvl1, lvl2Name, isDir = true)
            ?: run {
                val errorMsg = "Could not create lvl2 dir '$lvl2Name' for dirId '$dirId' (hash: $hash)"
                VeLog.e(TAG) { errorMsg }
                throw VaultIOException(errorMsg)
            }
        dataDirCache[dirId] = lvl2
        return lvl2
    }

    fun findOrCreateChild(folder: DocumentFile, name: String, isDir: Boolean): DocumentFile? {
        findChild(folder, name)?.let { return it }
        return if (isDir) safOps.createDirectorySafe(folder, name) else safOps.createFileSafe(folder, "application/octet-stream", name)
    }

    fun readDirId(dirIdFile: DocumentFile): String {
        return try {
            val bytes = safOps.readWhole(dirIdFile)
            String(bytes, Charsets.UTF_8).trim()
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "Failed to read dirId from ${dirIdFile.uri}" }
            throw VaultIOException("Failed to read dirId from ${dirIdFile.name}", e)
        }
    }

    fun invalidate(virtualDirPath: String) {
        val normalized = virtualDirPath.trim('/')
        if (normalized.isEmpty()) {
            invalidateAll()
            return
        }
        val dirId = dirIdCache[normalized] ?: runCatching { resolveDirId(normalized) }.getOrNull()
        if (dirId != null) {
            val physical = dataDirCache[dirId] ?: runCatching { physicalFolderForDirId(dirId) }.getOrNull()
            if (physical != null) {
                safOps.invalidate(physical)
            }
        }
        val staleDirIds = mutableListOf<String>()
        dirIdCache.entries.removeIf { (path, id) ->
            val stale = path == normalized || path.startsWith("$normalized/")
            if (stale) staleDirIds.add(id)
            stale
        }
        dirIdCache[""] = ROOT_DIR_ID
        staleDirIds.forEach { id ->
            dataDirCache[id]?.let { doc -> safOps.invalidate(doc) }
            dataDirCache.remove(id)
        }
        val parent = if (normalized.contains('/')) normalized.substringBeforeLast('/') else ""
        val parentDirId = if (parent.isEmpty()) ROOT_DIR_ID else dirIdCache[parent]
        if (parentDirId != null) {
            dataDirCache[parentDirId]?.let { safOps.invalidate(it) }
        }
    }

    fun invalidateAll() {
        safOps.invalidateAll()
        dirIdCache.clear()
        dirIdCache[""] = ROOT_DIR_ID
        dataDirCache.clear()
    }

    private fun normalizedSegments(path: String): List<String> =
        path.trim('/').split('/').filter { it.isNotEmpty() }

    private fun findChild(folder: DocumentFile, name: String): DocumentFile? = safOps.childOf(folder, name)

    private fun readSmallFile(folder: DocumentFile, name: String): ByteArray? {
        val file = findChild(folder, name) ?: return null
        return try {
            val bytes = safOps.readWhole(file)
            if (bytes.isEmpty()) null else bytes
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "Failed to read file '$name' in '${folder.name}' (URI: ${file.uri})" }
            null
        }
    }

    private fun stripExtension(name: String, ext: String): String = if (name.endsWith(ext)) name.removeSuffix(ext) else name
}