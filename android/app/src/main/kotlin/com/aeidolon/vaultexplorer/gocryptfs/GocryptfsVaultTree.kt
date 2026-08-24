package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.MirroredSafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.VaultDocumentOps
import java.util.concurrent.ConcurrentHashMap

import com.aeidolon.vaultexplorer.engine.VaultTreeNode
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultPathNotFoundException

sealed class GocryptfsNode : VaultTreeNode {
    data class VFile(override val cleartextName: String, val physicalFile: DocumentFile) : GocryptfsNode()
    data class VDir(override val cleartextName: String, val physicalFolder: DocumentFile) : GocryptfsNode()
}

/**
 * Resolves cleartext paths against the physical SAF tree.
 */
class GocryptfsVaultTree(
    private val context: Context,
    private val vaultRootUri: Uri,
    private val nameCryptor: GocryptfsFileNameCryptor,
    val hasDirIV: Boolean = true,
    // Same rationale as CryptomatorVaultTree.safOps: typed against the
    // interface (rather than the concrete SafDocumentOps) so a
    // MirroredSafDocumentOps -- constructed by GocryptfsVault when
    // vaultRootUri is itself SAF-backed by another app's provider -- can be
    // passed in unmodified. See MirrorSyncCoordinator's doc comment for why.
    val safOps: VaultDocumentOps = SafDocumentOps(context),
) {
    private val folderCache = ConcurrentHashMap<String, DocumentFile>()
    private val dirivCache = ConcurrentHashMap<String, ByteArray>()

    companion object {
        private val ZERO_DIRIV = ByteArray(16)
    }

    private val vaultRoot: DocumentFile by lazy {
        (safOps as? MirroredSafDocumentOps)?.root
            ?: DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: throw VaultIOException("Cannot open vault root")
    }

    init {
        folderCache[""] = vaultRoot
    }

    fun rootPhysicalFolder(): DocumentFile = vaultRoot

    fun list(virtualDirPath: String): List<GocryptfsNode> {
        val physical = physicalFolderFor(virtualDirPath)
        val diriv = dirivFor(virtualDirPath, physical)
        val children = safOps.listChildren(physical)

        val byName = children.associateBy { it.name }
        val results = mutableListOf<GocryptfsNode>()

        for (child in children) {
            val name = child.name ?: continue
            when {
                name == GocryptfsFileNameCryptor.DIRIV_FILENAME -> continue
                name.endsWith(GocryptfsFileNameCryptor.LONGNAME_SUFFIX) -> continue
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
        val parentPath = segments.dropLast(1).joinToString("/")
        val targetName = segments.last()

        val parentFolder = try {
            physicalFolderFor(parentPath)
        } catch (e: Exception) {
            return null
        }

        val diriv = try {
            dirivFor(parentPath, parentFolder)
        } catch (e: Exception) {
            return null
        }

        // Fast path: direct lookup by computed ciphertext name (O(1))
        val cipherName = nameCryptor.encryptName(targetName, diriv)
        val physicalName = if (!nameCryptor.isOverLongNameLimit(cipherName)) {
            cipherName
        } else {
            nameCryptor.hashLongName(cipherName)
        }

        val direct = safOps.childOf(parentFolder, physicalName)
        if (direct != null) {
            return nodeFor(direct, targetName)
        }

        return null
    }

    fun physicalFolderFor(virtualDirPath: String): DocumentFile {
        if (virtualDirPath.isEmpty()) return vaultRoot
        folderCache[virtualDirPath]?.let { return it }
        val segments = normalizedSegments(virtualDirPath)
        var current = vaultRoot
        var built = ""
        for (segment in segments) {
            val nextBuilt = if (built.isEmpty()) segment else "$built/$segment"
            folderCache[nextBuilt]?.let {
                current = it
                built = nextBuilt
            } ?: run {
                val diriv = dirivFor(built, current)
                val cipherName = nameCryptor.encryptName(segment, diriv)
                val physicalName = if (!nameCryptor.isOverLongNameLimit(cipherName)) {
                    cipherName
                } else {
                    nameCryptor.hashLongName(cipherName)
                }

                val match = safOps.childOf(current, physicalName)
                    ?: safOps.listChildren(current).firstOrNull { child ->
                        val name = child.name ?: return@firstOrNull false
                        resolvedNameMatches(name, current, diriv, segment)
                    } ?: throw VaultPathNotFoundException(virtualDirPath)

                current = match
                built = nextBuilt
                folderCache[built] = current
            }
        }
        return current
    }

    fun dirivFor(virtualDirPath: String, physicalFolder: DocumentFile = physicalFolderFor(virtualDirPath)): ByteArray {
        if (!hasDirIV) return ZERO_DIRIV
        dirivCache[virtualDirPath]?.let { return it }
        val existing = findChild(physicalFolder, GocryptfsFileNameCryptor.DIRIV_FILENAME)
            ?: throw VaultIOException("Missing gocryptfs.diriv in ${physicalFolder.name ?: virtualDirPath}")
        val bytes = readWhole(existing)
        require(bytes.size == 16) { "corrupt gocryptfs.diriv (expected 16 bytes, got ${bytes.size})" }
        dirivCache[virtualDirPath] = bytes
        return bytes
    }

    fun createDirIv(virtualDirPath: String, physicalFolder: DocumentFile): ByteArray {
        if (!hasDirIV) return ZERO_DIRIV
        val fresh = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }
        val f = safOps.createFileSafe(physicalFolder, "application/octet-stream", GocryptfsFileNameCryptor.DIRIV_FILENAME)
            ?: throw VaultIOException("Could not create gocryptfs.diriv")
        writeWhole(f, fresh)
        dirivCache[virtualDirPath] = fresh
        return fresh
    }

    fun removeFolder(virtualDirPath: String) {
        if (virtualDirPath.isEmpty()) {
            dirivCache.clear()
            folderCache.clear()
            folderCache[""] = vaultRoot
            safOps.invalidate(vaultRoot)
        } else {
            val staleDirs = folderCache.keys.filter { it == virtualDirPath || it.startsWith("$virtualDirPath/") }
            staleDirs.forEach { 
                folderCache[it]?.let { doc -> safOps.invalidate(doc) }
                folderCache.remove(it)
            }
            val staleIvs = dirivCache.keys.filter { it == virtualDirPath || it.startsWith("$virtualDirPath/") }
            staleIvs.forEach { dirivCache.remove(it) }
        }
    }

    fun invalidate(virtualDirPath: String) {
        val normalized = virtualDirPath.trim('/')
        val physical = folderCache[normalized]
        if (physical != null) {
            safOps.invalidate(physical)
        }
    }

    fun invalidateAll() {
        safOps.invalidateAll()
        folderCache.clear()
        folderCache[""] = vaultRoot
        dirivCache.clear()
    }

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

    private fun findChild(folder: DocumentFile, name: String): DocumentFile? = safOps.childOf(folder, name)

    private fun readWhole(file: DocumentFile): ByteArray = safOps.readWhole(file)

    private fun writeWhole(file: DocumentFile, bytes: ByteArray) = safOps.writeWhole(file, bytes)

    private fun normalizedSegments(path: String) = path.trim('/').split('/').filter { it.isNotEmpty() }
}