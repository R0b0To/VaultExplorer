package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile

sealed class GocryptfsNode {
    abstract val cleartextName: String
    data class VFile(override val cleartextName: String, val physicalFile: DocumentFile) : GocryptfsNode()
    data class VDir(override val cleartextName: String, val physicalFolder: DocumentFile) : GocryptfsNode()
}

class GocryptfsPathNotFoundException(path: String) : Exception("Path not found in vault: $path")
class GocryptfsIOException(message: String) : Exception(message)

/**
 * Resolves cleartext paths against the physical SAF tree. Much simpler than
 * CryptomatorVaultTree: there's no separate "d/xx/yyyy" storage tree to
 * consult — a gocryptfs directory's ciphertext children live directly inside
 * its own physical SAF folder, so "physical folder for cleartext path P" is
 * just "walk P's segments, decrypting each with its parent's diriv."
 *
 * Caches (virtual dir path -> physical DocumentFile) and (virtual dir path ->
 * diriv bytes), invalidated the same way CryptomatorVaultTree invalidates its
 * dirId cache on mutation.
 */
class GocryptfsVaultTree(
    private val context: Context,
    private val vaultRootUri: Uri,
    private val nameCryptor: GocryptfsFileNameCryptor,
) {
    private val folderCache = HashMap<String, DocumentFile>()
    private val dirivCache = HashMap<String, ByteArray>()

    private val vaultRoot: DocumentFile by lazy {
        DocumentFile.fromTreeUri(context, vaultRootUri) ?: throw GocryptfsIOException("Cannot open vault root")
    }

    init {
        folderCache[""] = vaultRoot
    }

    fun rootPhysicalFolder(): DocumentFile = vaultRoot

    fun list(virtualDirPath: String): List<GocryptfsNode> {
        val physical = physicalFolderFor(virtualDirPath)
        val diriv = dirivFor(virtualDirPath, physical)
        val children = listChildrenFast(physical)

        // Long-name files (`gocryptfs.longname.<hash>`) need their sibling
        // `.name` file resolved before we know their cleartext name — index
        // by hash-name first.
        val byName = children.associateBy { it.name }
        val results = mutableListOf<GocryptfsNode>()

        for (child in children) {
            val name = child.name ?: continue
            when {
                name == GocryptfsFileNameCryptor.DIRIV_FILENAME -> continue
                name.endsWith(GocryptfsFileNameCryptor.LONGNAME_SUFFIX) -> continue // consumed below
                name.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX) -> {
                    val nameFile = byName[name + GocryptfsFileNameCryptor.LONGNAME_SUFFIX] ?: continue
                    val cipherName = readWhole(nameFile).toString(Charsets.UTF_8)
                    val cleartext = try { nameCryptor.decryptName(cipherName, diriv) } catch (e: Exception) { continue }
                    results.add(nodeFor(child, cleartext))
                }
                else -> {
                    val cleartext = try { nameCryptor.decryptName(name, diriv) } catch (e: Exception) { continue }
                    results.add(nodeFor(child, cleartext))
                }
            }
        }
        return results
    }

    fun resolve(virtualPath: String): GocryptfsNode? {
        val segments = normalizedSegments(virtualPath)
        if (segments.isEmpty()) return null
        var currentDirPath = ""
        var node: GocryptfsNode? = null
        for (segment in segments) {
            node = list(currentDirPath).firstOrNull { it.cleartextName == segment } ?: return null
            currentDirPath = if (currentDirPath.isEmpty()) segment else "$currentDirPath/$segment"
        }
        return node
    }

    fun physicalFolderFor(virtualDirPath: String): DocumentFile {
        folderCache[virtualDirPath]?.let { return it }
        val segments = normalizedSegments(virtualDirPath)
        var current = vaultRoot
        var built = ""
        for (segment in segments) {
            val nextBuilt = if (built.isEmpty()) segment else "$built/$segment"
            folderCache[nextBuilt]?.let { current = it; built = nextBuilt; return@let }
                ?: run {
                    val diriv = dirivFor(built, current)
                    val match = listChildrenFast(current).firstOrNull { child ->
                        val name = child.name ?: return@firstOrNull false
                        resolvedNameMatches(name, current, diriv, segment)
                    } ?: throw GocryptfsPathNotFoundException(virtualDirPath)
                    current = match
                    built = nextBuilt
                    folderCache[built] = current
                }
        }
        return current
    }

    /** Creates (or returns, if it already exists) the per-directory tweak file. */
    fun dirivFor(virtualDirPath: String, physicalFolder: DocumentFile = physicalFolderFor(virtualDirPath)): ByteArray {
        dirivCache[virtualDirPath]?.let { return it }
        val existing = findChild(physicalFolder, GocryptfsFileNameCryptor.DIRIV_FILENAME)
        val bytes = if (existing != null) {
            readWhole(existing)
        } else {
            val fresh = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }
            val f = physicalFolder.createFile("application/octet-stream", GocryptfsFileNameCryptor.DIRIV_FILENAME)
                ?: throw GocryptfsIOException("Could not create gocryptfs.diriv")
            writeWhole(f, fresh)
            fresh
        }
        require(bytes.size == 16) { "corrupt gocryptfs.diriv (expected 16 bytes, got ${bytes.size})" }
        dirivCache[virtualDirPath] = bytes
        return bytes
    }

    fun invalidate(virtualDirPath: String) {
        val stale = folderCache.keys.filter { it == virtualDirPath || it.startsWith("$virtualDirPath/") }
        stale.forEach { folderCache.remove(it); dirivCache.remove(it) }
    }

    // ---- helpers (identical approach to CryptomatorVaultTree's SAF plumbing) ----

    private fun nodeFor(physical: DocumentFile, cleartextName: String): GocryptfsNode =
        if (physical.isDirectory) GocryptfsNode.VDir(cleartextName, physical)
        else GocryptfsNode.VFile(cleartextName, physical)

    private fun resolvedNameMatches(physicalName: String, parent: DocumentFile, diriv: ByteArray, want: String): Boolean {
        if (physicalName.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX) &&
            !physicalName.endsWith(GocryptfsFileNameCryptor.LONGNAME_SUFFIX)) {
            val nameFile = findChild(parent, "$physicalName${GocryptfsFileNameCryptor.LONGNAME_SUFFIX}") ?: return false
            val cipherName = readWhole(nameFile).toString(Charsets.UTF_8)
            return runCatching { nameCryptor.decryptName(cipherName, diriv) == want }.getOrDefault(false)
        }
        if (physicalName == GocryptfsFileNameCryptor.DIRIV_FILENAME || physicalName.endsWith(GocryptfsFileNameCryptor.LONGNAME_SUFFIX)) return false
        return runCatching { nameCryptor.decryptName(physicalName, diriv) == want }.getOrDefault(false)
    }

    private fun listChildrenFast(folder: DocumentFile): List<DocumentFile> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(folder.uri, DocumentsContract.getDocumentId(folder.uri))
        val results = mutableListOf<DocumentFile>()
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
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

    private fun findChild(folder: DocumentFile, name: String): DocumentFile? =
        listChildrenFast(folder).firstOrNull { it.name == name }

    private fun readWhole(file: DocumentFile): ByteArray =
        context.contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            ?: throw GocryptfsIOException("Could not open ${file.uri}")

    private fun writeWhole(file: DocumentFile, bytes: ByteArray) {
        context.contentResolver.openOutputStream(file.uri, "wt")?.use { it.write(bytes) }
            ?: throw GocryptfsIOException("Could not open ${file.uri} for writing")
    }

    private fun normalizedSegments(path: String) = path.trim('/').split('/').filter { it.isNotEmpty() }
}