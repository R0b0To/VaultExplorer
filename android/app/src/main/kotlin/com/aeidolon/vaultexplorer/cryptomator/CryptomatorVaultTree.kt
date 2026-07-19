package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import java.util.concurrent.ConcurrentHashMap

private const val CLOUD_NODE_EXT = ".c9r"
private const val LONG_NODE_EXT = ".c9s"
private const val DIR_FILE_NAME = "dir$CLOUD_NODE_EXT"
private const val LONG_NAME_FILE = "name$CLOUD_NODE_EXT"
private const val LONG_CONTENTS_FILE = "contents$CLOUD_NODE_EXT"
private const val DATA_DIR_NAME = "d"
private const val ROOT_DIR_ID = ""

/** A resolved child of a virtual (cleartext) directory: either a regular file or a subdirectory, with its physical SAF location. */
sealed class VaultNode {
    abstract val cleartextName: String

    /** A regular file. [physicalFile] is the actual ciphertext bytes: either the short `.c9r` file directly, or `contents.c9r` inside a `.c9s` shortened folder. */
    data class VFile(override val cleartextName: String, val physicalFile: DocumentFile, val cleartextSizeHint: Long?) : VaultNode()

    /** A subdirectory. [dirIdFile] holds this directory's own dirId (its "dir.c9r"), used to resolve where its children physically live. [physicalFolder] is its `.c9r`/`.c9s` folder (parent of dirIdFile), useful for rename/delete of the node itself. */
    data class VDir(override val cleartextName: String, val physicalFolder: DocumentFile, val dirIdFile: DocumentFile) : VaultNode()
}

class VaultPathNotFoundException(path: String) : Exception("Path not found in vault: $path")
class VaultIOException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Resolves cleartext virtual paths (e.g. "Documents/report.pdf") against a
 * Cryptomator vault's real on-disk `d/xx/yyyy.../<name>.c9r` structure, using SAF
 * (DocumentFile / DocumentsContract) against the tree Uri the user granted
 * access to.
 *
 * Caches (virtual dir path -> dirId) and (dirId -> physical folder) lookups
 * since every listing/open/write walks the path from the vault root, and
 * both dirId hashing and SAF child-listing round-trips are non-trivial cost.
 * A single top-down walk ([walk]) backs both [resolveDirId] and [resolve] so
 * the path-segment traversal logic only needs to be correct in one place.
 */
class CryptomatorVaultTree(
    private val context: Context,
    private val vaultRootUri: Uri,
    private val nameCryptor: CryptomatorFileNameCryptor,
    private val shorteningThreshold: Int,
) {
    /** virtual dir path ("" for root, else e.g. "Documents/Reports") -> dirId */
    private val dirIdCache = ConcurrentHashMap<String, String>().apply { put("", ROOT_DIR_ID) }

    /** dirId -> physical folder (d/xx/yyyy) backing that directory's contents */
    private val dataDirCache = ConcurrentHashMap<String, DocumentFile>()

    private val vaultRoot: DocumentFile by lazy {
        DocumentFile.fromTreeUri(context, vaultRootUri) ?: throw VaultIOException("Cannot open vault root: $vaultRootUri")
    }

    private val dataDir: DocumentFile by lazy {
        findChild(vaultRoot, DATA_DIR_NAME) ?: throw VaultIOException("Vault is missing its 'd' data directory — not a valid Cryptomator vault.")
    }

    /** Resolves the physical folder for the root directory (dirId = ""). */
    fun rootPhysicalFolder(): DocumentFile = physicalFolderForDirId(ROOT_DIR_ID)

    /** Lists the cleartext children of a virtual directory path ("" = vault root). */
    fun list(virtualDirPath: String): List<VaultNode> {
        val dirId = resolveDirId(virtualDirPath)
        return listByDirId(dirId)
    }

    private fun listByDirId(dirId: String): List<VaultNode> {
        val physicalFolder = physicalFolderForDirId(dirId)
        val children = listChildrenFast(physicalFolder)

        val results = mutableListOf<VaultNode>()
        for (child in children) {
            val name = child.name ?: continue
            try {
                when {
                    name == DIR_FILE_NAME -> continue // this dir's own dirId pointer, not a child
                    name.endsWith(LONG_NODE_EXT) -> {
                        // Shortened name: the real ciphertext name lives in name.c9r inside this folder.
                        if (!child.isDirectory) continue
                        val longName = readSmallFile(child, LONG_NAME_FILE) ?: continue
                        val ciphertextName = stripExtension(String(longName, Charsets.UTF_8), CLOUD_NODE_EXT)
                        val cleartext = nameCryptor.decryptFilename(ciphertextName, dirId.toByteArray(Charsets.UTF_8))
                        val dirPointer = findChild(child, DIR_FILE_NAME)
                        if (dirPointer != null) {
                            results.add(VaultNode.VDir(cleartext, child, dirPointer))
                        } else {
                            val contents = findChild(child, LONG_CONTENTS_FILE)
                            if (contents != null) {
                                results.add(VaultNode.VFile(cleartext, contents, contents.length()))
                            }
                        }
                    }
                    name.endsWith(CLOUD_NODE_EXT) -> {
                        val ciphertextName = name.removeSuffix(CLOUD_NODE_EXT)
                        val cleartext = nameCryptor.decryptFilename(ciphertextName, dirId.toByteArray(Charsets.UTF_8))
                        if (child.isDirectory) {
                            val dirPointer = findChild(child, DIR_FILE_NAME) ?: continue // not yet a valid dir (or a symlink, unsupported)
                            results.add(VaultNode.VDir(cleartext, child, dirPointer))
                        } else {
                            results.add(VaultNode.VFile(cleartext, child, child.length()))
                        }
                    }
                    else -> continue // unrelated/foreign file in the physical dir; ignore
                }
            } catch (e: CryptomatorAuthenticationException) {
                continue // skip undecryptable entries rather than failing the whole listing
            }
        }
        return results
    }

    /** Resolves a full virtual path (e.g. "Documents/report.pdf") to its physical VaultNode, or null if it doesn't exist. */
    fun resolve(virtualPath: String): VaultNode? {
        val segments = normalizedSegments(virtualPath)
        if (segments.isEmpty()) return null // caller should treat root specially; root isn't itself a VaultNode
        return walk(segments).lastNodeOrNull
    }

    /** dirId of the virtual directory at [virtualDirPath] ("" = root). Caches by path. */
    fun resolveDirId(virtualDirPath: String): String {
        val segments = normalizedSegments(virtualDirPath)
        if (segments.isEmpty()) return ROOT_DIR_ID
        val result = walk(segments)
        return result.finalDirId ?: throw VaultPathNotFoundException(virtualDirPath)
    }

    private class WalkResult(val finalDirId: String?, val lastNodeOrNull: VaultNode?)

    /**
     * Walks [segments] top-down from the vault root, resolving each segment
     * against the previous directory's listing, using [dirIdCache] to skip
     * segments whose dirId is already known.
     *
     * Returns finalDirId = the dirId of the directory the full path resolves
     * to (only meaningful if the path is entirely directories), and
     * lastNodeOrNull = the VaultNode the full path resolves to (file or
     * dir), or null if any segment along the way doesn't exist.
     */
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
                lastNode = null // dirId came from cache, not a fresh listing; resolve() re-derives the VaultNode below if it's needed for the final segment
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
                        // tried to descend into a file as if it were a directory
                        return WalkResult(finalDirId = null, lastNodeOrNull = null)
                    }
                }
            }
            builtPath = nextBuiltPath
        }

        // If the last segment's VaultNode wasn't captured (because its dirId
        // came from cache), re-fetch it from its parent's listing so resolve()
        // can still return a proper VaultNode.
        if (lastNode == null) {
            val parentPath = segments.dropLast(1).joinToString("/")
            val parentDirId = if (parentPath.isEmpty()) ROOT_DIR_ID else (dirIdCache[parentPath] ?: return WalkResult(currentDirId, null))
            lastNode = listByDirId(parentDirId).firstOrNull { it.cleartextName == segments.last() }
        }

        return WalkResult(finalDirId = currentDirId, lastNodeOrNull = lastNode)
    }

    /** Physical folder (d/xx/yyyy...) backing a given dirId. */
    fun physicalFolderForDirId(dirId: String): DocumentFile {
        dataDirCache[dirId]?.let { return it }
        val hash = nameCryptor.hashDirectoryId(dirId)
        val lvl1 = findChild(dataDir, hash.substring(0, 2)) ?: throw VaultIOException("Missing lvl1 dir for hash $hash")
        val lvl2 = findChild(lvl1, hash.substring(2)) ?: throw VaultIOException("Missing lvl2 dir for hash $hash")
        dataDirCache[dirId] = lvl2
        return lvl2
    }

    fun readDirId(dirIdFile: DocumentFile): String {
        val bytes = readWholeFile(dirIdFile)
        return String(bytes, Charsets.UTF_8)
    }

    /** Invalidate cached dirId/physical-folder entries under [virtualDirPath] after a rename/move/delete. */
    fun invalidate(virtualDirPath: String) {
        val staleDirIds = mutableListOf<String>()
        dirIdCache.entries.removeIf { (path, dirId) ->
            val stale = path == virtualDirPath || path.startsWith("$virtualDirPath/")
            if (stale) staleDirIds.add(dirId)
            stale
        }
        staleDirIds.forEach { dataDirCache.remove(it) }
    }

    fun invalidateAll() {
        dirIdCache.clear()
        dirIdCache[""] = ROOT_DIR_ID
        dataDirCache.clear()
    }

    private fun normalizedSegments(path: String): List<String> =
        path.trim('/').split('/').filter { it.isNotEmpty() }

    // ---- low-level SAF helpers ------------------------------------------------

    /** Fast child lookup: uses DocumentsContract query instead of DocumentFile.listFiles()'s O(n) per-child stat calls. */
    private fun listChildrenFast(folder: DocumentFile): List<DocumentFile> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(folder.uri, DocumentsContract.getDocumentId(folder.uri))
        val results = mutableListOf<DocumentFile>()
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            while (cursor.moveToNext()) {
                val docId = cursor.getString(idIdx)
                val childUri = DocumentsContract.buildDocumentUriUsingTree(folder.uri, docId)
                DocumentFile.fromSingleUri(context, childUri)?.let { results.add(it) }
            }
        }
        return results
    }

    private fun findChild(folder: DocumentFile, name: String): DocumentFile? {
        return listChildrenFast(folder).firstOrNull { it.name == name }
    }

    private fun readSmallFile(folder: DocumentFile, name: String): ByteArray? {
        val file = findChild(folder, name) ?: return null
        return readWholeFile(file)
    }

    private fun readWholeFile(file: DocumentFile): ByteArray {
        context.contentResolver.openInputStream(file.uri)?.use { stream ->
            return stream.readBytes()
        } ?: throw VaultIOException("Could not open ${file.uri} for reading")
    }

    private fun stripExtension(name: String, ext: String): String = if (name.endsWith(ext)) name.removeSuffix(ext) else name
}