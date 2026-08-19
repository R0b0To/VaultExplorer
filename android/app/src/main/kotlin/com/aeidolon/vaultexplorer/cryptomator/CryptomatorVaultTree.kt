package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.util.concurrent.ConcurrentHashMap
import com.aeidolon.vaultexplorer.engine.VaultTreeNode
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultPathNotFoundException

private const val CLOUD_NODE_EXT = ".c9r"
private const val LONG_NODE_EXT = ".c9s"
private const val DIR_FILE_NAME = "dir$CLOUD_NODE_EXT"
private const val LONG_NAME_FILE = "name$LONG_NODE_EXT"
private const val LONG_CONTENTS_FILE = "contents$CLOUD_NODE_EXT"
private const val DATA_DIR_NAME = "d"
private const val ROOT_DIR_ID = ""

/** A resolved child of a virtual (cleartext) directory: either a regular file or a subdirectory, with its physical SAF location. */
sealed class VaultNode : VaultTreeNode {

    /** A regular file. [physicalFile] is the actual ciphertext bytes: either the short `.c9r` file directly, or `contents.c9r` inside a `.c9s` shortened folder. [wrapperFolder] is the `.c9s` directory if shortened, null otherwise. */
    data class VFile(
        override val cleartextName: String, 
        val physicalFile: DocumentFile, 
        val cleartextSizeHint: Long?,
        val wrapperFolder: DocumentFile? = null
    ) : VaultNode()

    /** A subdirectory. [dirIdFile] holds this directory's own dirId (its "dir.c9r"), used to resolve where its children physically live. [physicalFolder] is its `.c9r`/`.c9s` folder (parent of dirIdFile), useful for rename/delete of the node itself. */
    data class VDir(override val cleartextName: String, val physicalFolder: DocumentFile, val dirIdFile: DocumentFile) : VaultNode()
}

/**
 * Resolves cleartext virtual paths against a Cryptomator vault's on-disk structure.
 */
class CryptomatorVaultTree(
    private val context: Context,
    private val vaultRootUri: Uri,
    private val nameCryptor: CryptomatorFileNameCryptor,
    private val shorteningThreshold: Int,
) {
    private val dirIdCache = ConcurrentHashMap<String, String>().apply { put("", ROOT_DIR_ID) }
    private val dataDirCache = ConcurrentHashMap<String, DocumentFile>()
    private val safOps = SafDocumentOps(context)

    private val vaultRoot: DocumentFile by lazy {
        DocumentFile.fromTreeUri(context, vaultRootUri) ?: throw VaultIOException("Cannot open vault root: $vaultRootUri")
    }

    private val dataDir: DocumentFile by lazy {
        findChild(vaultRoot, DATA_DIR_NAME) ?: throw VaultIOException("Vault is missing its 'd' data directory — not a valid Cryptomator vault.")
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
                        val longName = readSmallFile(child, LONG_NAME_FILE) ?: continue
                        val rawLongName = String(longName, Charsets.UTF_8).trim().trimEnd('\u0000', '\r', '\n', ' ')
                        val ciphertextName = stripExtension(rawLongName, CLOUD_NODE_EXT).trim()
                        val cleartext = nameCryptor.decryptFilename(ciphertextName, dirId.toByteArray(Charsets.UTF_8))
                        val dirPointer = findChild(child, DIR_FILE_NAME)
                        if (dirPointer != null) {
                            results.add(VaultNode.VDir(cleartext, child, dirPointer))
                        } else {
                            val contents = findChild(child, LONG_CONTENTS_FILE)
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
        return result.finalDirId ?: throw VaultPathNotFoundException(virtualDirPath)
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
        val lvl1 = findChild(dataDir, hash.substring(0, 2)) ?: throw VaultIOException("Missing lvl1 dir for hash $hash")
        val lvl2 = findChild(lvl1, hash.substring(2)) ?: throw VaultIOException("Missing lvl2 dir for hash $hash")
        dataDirCache[dirId] = lvl2
        return lvl2
    }

    fun readDirId(dirIdFile: DocumentFile): String {
        val bytes = safOps.readWhole(dirIdFile)
        return String(bytes, Charsets.UTF_8)
    }

    fun invalidate(virtualDirPath: String) {
        val normalized = virtualDirPath.trim('/')
        val dirId = if (normalized.isEmpty()) ROOT_DIR_ID else dirIdCache[normalized]
        if (dirId != null) {
            dataDirCache[dirId]?.let { safOps.invalidate(it) }
        }
        val staleDirIds = mutableListOf<String>()
        dirIdCache.entries.removeIf { (path, dirId) ->
            val stale = path == normalized || path.startsWith("$normalized/")
            if (stale) staleDirIds.add(dirId)
            stale
        }
        dirIdCache[""] = ROOT_DIR_ID
        staleDirIds.forEach { dataDirCache.remove(it) }
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
        return safOps.readWhole(file)
    }

    private fun stripExtension(name: String, ext: String): String = if (name.endsWith(ext)) name.removeSuffix(ext) else name
}