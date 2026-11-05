package com.aeidolon.vaultexplorer.foldervault

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.DirEntryWire
import com.aeidolon.vaultexplorer.RawFileResolver
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.saf.MirrorPullEvents
import com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator
import com.aeidolon.vaultexplorer.saf.VaultDocumentOps
import com.aeidolon.vaultexplorer.saf.VaultPathUtils
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Where a vault's *physical* (encrypted) files live, as seen by the native
 * core. Paths are relative to the vault root, '/'-separated, "" = the root.
 *
 * The native side calls these by name through JNI (cpp/jni/foldervault_bridge.cpp,
 * class JniStorage) -- keep names and signatures in sync with it. Directory
 * entries travel in the [DirEntryWire] format ("D|size|mtimeSecs|name").
 *
 * When the vault folder is reachable through a verified raw path the core
 * does all I/O itself and none of this is used; this interface exists for the
 * Storage-Access-Framework / local-mirror case.
 */
interface FolderVaultStorage {
    fun list(dir: String): Array<String>?
    fun stat(path: String): String?
    fun mkdir(path: String): Boolean
    fun createFile(path: String): Boolean
    fun rename(from: String, to: String): Boolean
    fun remove(path: String): Boolean
    fun setMtime(path: String, epochSec: Long): Boolean
    fun readWhole(path: String): ByteArray?
    fun writeWhole(path: String, data: ByteArray): Boolean
    fun writeWholeAtomic(path: String, data: ByteArray): Boolean
    fun writeBlock(path: String, data: ByteArray): Boolean
    fun ensureContentReady(path: String)

    /** Returns a *detached* file descriptor (the native side closes it), or -1. */
    fun openRead(path: String, hint: String): Int
    fun openWrite(path: String, truncate: Boolean): Int
    fun markWritePending(path: String)
    fun publishWrite(path: String, defer: Boolean): Boolean
    fun invalidate(dir: String)
    fun invalidateAll()
    fun spaceInfo(): LongArray?
    fun close()
}

/** Builds the storage a session runs on once the password has been verified. */
interface FolderVaultSessionProvider {
    fun buildSessionStorage(): FolderVaultStorage?
}

private const val TAG = "FolderVaultStorage"

private fun norm(p: String) = p.trim('/')
private fun parentOfPath(p: String): String = p.substringBeforeLast('/', "")
private fun nameOfPath(p: String): String = p.substringAfterLast('/')
private fun joinPath(a: String, b: String) = if (a.isEmpty()) b else "$a/$b"

private fun openRawRead(file: File): Int = try {
    ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).detachFd()
} catch (_: Exception) { -1 }

private fun openRawWrite(file: File, truncate: Boolean): Int = try {
    var mode = ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_CREATE
    if (truncate) mode = mode or ParcelFileDescriptor.MODE_TRUNCATE
    ParcelFileDescriptor.open(file, mode).detachFd()
} catch (_: Exception) { -1 }

/**
 * [FolderVaultStorage] over SAF documents, optionally through the local mirror
 * ([com.aeidolon.vaultexplorer.saf.MirroredSafDocumentOps]) -- i.e. exactly the
 * document operations the Kotlin gocryptfs / Cryptomator sessions used to issue,
 * but addressed by path so the native core can drive them.
 */
class SafFolderVaultStorage(
    private val context: Context,
    private val root: DocumentFile,
    private val ops: VaultDocumentOps,
    private val mirrorSync: MirrorSyncCoordinator?,
    private val rootUri: Uri?,
    private val volIdProvider: () -> Int = { -1 },
) : FolderVaultStorage {

    private val nodes = ConcurrentHashMap<String, DocumentFile>()
    /** The exact document instance a pending write targets; pushing re-resolves nothing. */
    private val pendingWriteDocs = ConcurrentHashMap<String, DocumentFile>()

    private fun resolve(path: String): DocumentFile? {
        val n = norm(path)
        if (n.isEmpty()) return root
        nodes[n]?.let { return it }
        var cur = root
        var built = ""
        for (seg in n.split('/')) {
            built = joinPath(built, seg)
            val cached = nodes[built]
            cur = cached ?: (ops.childOf(cur, seg) ?: return null).also { nodes[built] = it }
        }
        return cur
    }

    private fun forgetSubtree(n: String) {
        if (n.isEmpty()) { nodes.clear(); return }
        val prefix = "$n/"
        nodes.keys.removeIf { it == n || it.startsWith(prefix) }
    }

    private fun entry(doc: DocumentFile, name: String): String =
        DirEntryWire.encode(name, doc.isDirectory, if (doc.isDirectory) 0L else doc.length(), doc.lastModified() / 1000)

    override fun list(dir: String): Array<String>? = try {
        val d = resolve(dir)
        if (d == null || !d.isDirectory) null
        else {
            val n = norm(dir)
            ops.listChildren(d).mapNotNull { c ->
                val name = c.name ?: return@mapNotNull null
                nodes[joinPath(n, name)] = c
                entry(c, name)
            }.toTypedArray()
        }
    } catch (e: Exception) {
        VeLog.d(TAG) { "list($dir) failed: ${e.message}" }
        null
    }

    override fun stat(path: String): String? = try {
        resolve(path)?.let { entry(it, nameOfPath(norm(path)).ifEmpty { it.name ?: "" }) }
    } catch (e: Exception) { null }

    override fun mkdir(path: String): Boolean = try {
        val n = norm(path)
        val existing = resolve(n)
        if (existing != null) existing.isDirectory
        else {
            val parent = resolve(parentOfPath(n))
            val name = nameOfPath(n)
            val created = if (parent == null) null else ops.createDirectorySafe(parent, name)
            if (created == null) false
            else {
                nodes[n] = if (created.name != name) ops.renameDocumentAndGet(created, name, parent) else created
                true
            }
        }
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "mkdir($path) failed" }
        false
    }

    override fun createFile(path: String): Boolean = try {
        val n = norm(path)
        val existing = resolve(n)
        if (existing != null) !existing.isDirectory
        else {
            val parent = resolve(parentOfPath(n))
            val name = nameOfPath(n)
            val created = if (parent == null) null else ops.createFileSafe(parent, "application/octet-stream", name)
            if (created == null) false
            else {
                nodes[n] = if (created.name != name) ops.renameDocumentAndGet(created, name, parent) else created
                true
            }
        }
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "createFile($path) failed" }
        false
    }

    override fun rename(from: String, to: String): Boolean = try {
        val f = norm(from)
        val t = norm(to)
        val node = resolve(f)
        val oldParent = resolve(parentOfPath(f))
        val newParent = resolve(parentOfPath(t))
        if (node == null || oldParent == null || newParent == null) false
        else {
            val newName = nameOfPath(t)
            // POSIX rename-over for files: SAF providers would otherwise fail or invent "name (1)".
            resolve(t)?.let { existing ->
                if (existing.isDirectory) return false
                ops.deleteRecursively(existing)
                forgetSubtree(t)
            }
            val renamed = if (node.name == newName) node else ops.renameDocumentAndGet(node, newName, oldParent)
            val sameParent = parentOfPath(f) == parentOfPath(t)
            if (!sameParent) ops.movePhysicalDocument(renamed, oldParent, newParent)
            forgetSubtree(f)
            remapPending(f, t, if (sameParent) renamed else null)
            ops.invalidate(oldParent)
            if (!sameParent) ops.invalidate(newParent)
            true
        }
    } catch (e: Exception) {
        VeLog.d(TAG) { "rename($from -> $to) failed: ${e.message}" }
        false
    }

    private fun remapPending(from: String, to: String, renamed: DocumentFile?) {
        val prefix = "$from/"
        for (key in pendingWriteDocs.keys.toList()) {
            if (key == from) {
                pendingWriteDocs.remove(key)
                if (renamed != null) pendingWriteDocs[to] = renamed
            } else if (key.startsWith(prefix)) {
                pendingWriteDocs.remove(key)   // the document moved: publishWrite will resolve it by path
            }
        }
    }

    override fun remove(path: String): Boolean = try {
        val n = norm(path)
        val node = resolve(n)
        if (node != null) {
            ops.deleteRecursively(node)
            forgetSubtree(n)
            pendingWriteDocs.keys.removeIf { it == n || it.startsWith("$n/") }
            resolve(parentOfPath(n))?.let { ops.invalidate(it) }
        }
        true
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "remove($path) failed" }
        false
    }

    override fun setMtime(path: String, epochSec: Long): Boolean = try {
        val node = resolve(path)
        node != null && (RawFileResolver.getRawFile(context, node)?.setLastModified(epochSec * 1000) ?: false)
    } catch (e: Exception) { false }

    override fun readWhole(path: String): ByteArray? = try {
        resolve(path)?.let { ops.readWhole(it) }
    } catch (e: Exception) { null }

    override fun writeWhole(path: String, data: ByteArray): Boolean = try {
        val n = norm(path)
        var node = resolve(n)
        if (node == null) { createFile(n); node = resolve(n) }
        if (node == null) false else { ops.writeWhole(node, data); true }
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "writeWhole($path) failed" }
        false
    }

    // SAF has no atomic replace; the mirror/provider path already serialises writes.
    override fun writeWholeAtomic(path: String, data: ByteArray): Boolean = writeWhole(path, data)
    override fun writeBlock(path: String, data: ByteArray): Boolean = writeWhole(path, data)

    override fun ensureContentReady(path: String) {
        try { resolve(path)?.let { ops.ensureContentPulled(it) } } catch (_: Exception) {}
    }

    override fun openRead(path: String, hint: String): Int = try {
        val node = resolve(path)
        if (node == null) -1
        else {
            val direct = ops.resolveForRead(node) { phase ->
                val v = volIdProvider()
                if (v >= 0 && hint.isNotEmpty()) MirrorPullEvents.emit(v, hint, phase)
            }
            val target = direct ?: node.also { ops.ensureContentPulled(it) }
            var fd = RawFileResolver.getRawFile(context, target)?.let { openRawRead(it) } ?: -1
            if (fd < 0) {
                fd = try { context.contentResolver.openFileDescriptor(target.uri, "r")?.detachFd() ?: -1 } catch (_: Exception) { -1 }
            }
            fd
        }
    } catch (e: Exception) {
        VeLog.d(TAG) { "openRead($path) failed: ${e.message}" }
        -1
    }

    override fun openWrite(path: String, truncate: Boolean): Int = try {
        val n = norm(path)
        val node = pendingWriteDocs[n] ?: resolve(n)
        if (node == null) -1
        else {
            var fd = RawFileResolver.getRawFile(context, node)?.let { openRawWrite(it, truncate) } ?: -1
            if (fd < 0) {
                fd = try { context.contentResolver.openFileDescriptor(node.uri, if (truncate) "wt" else "w")?.detachFd() ?: -1 } catch (_: Exception) { -1 }
            }
            fd
        }
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "openWrite($path) failed" }
        -1
    }

    override fun markWritePending(path: String) {
        try {
            val n = norm(path)
            resolve(n)?.let { pendingWriteDocs[n] = it; ops.markWritePending(it) }
        } catch (_: Exception) {}
    }

    override fun publishWrite(path: String, defer: Boolean): Boolean = try {
        val n = norm(path)
        val node = pendingWriteDocs.remove(n) ?: resolve(n)
        if (node == null) false
        else {
            if (defer) ops.deferContentWrite(node) else ops.pushContentWrite(node)
            true
        }
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "publishWrite($path) failed" }
        false
    }

    override fun invalidate(dir: String) {
        try {
            val n = norm(dir)
            resolve(n)?.let { ops.invalidate(it) }
            forgetSubtree(n)
        } catch (_: Exception) {}
    }

    override fun invalidateAll() {
        try { ops.invalidateAll() } catch (_: Exception) {}
        nodes.clear()
    }

    override fun spaceInfo(): LongArray? = rootUri?.let { VaultPathUtils.querySafSpaceInfo(context, it) }

    override fun close() {
        pendingWriteDocs.clear()
        nodes.clear()
        try { mirrorSync?.teardown() } catch (e: Exception) { VeLog.w(TAG, e) { "mirror teardown failed" } }
    }
}

/**
 * CryFS in mirror mode. Block files are addressed by an id, so (as the old
 * CryfsBlockStore did) they are located on the REAL tree by deterministic
 * lookup instead of listing 4096 shard directories: local I/O happens in the
 * mirror directory, and each block is pulled / pushed individually.
 */
class CryfsMirrorFolderVaultStorage(
    private val context: Context,
    private val realRoot: DocumentFile,
    private val sync: MirrorSyncCoordinator,
    private val mirrorRoot: File,
    private val rootUri: Uri?,
) : FolderVaultStorage {

    private fun local(path: String): File = File(mirrorRoot, norm(path))

    private fun realBlockDoc(path: String): DocumentFile? {
        val n = norm(path)
        val shard = parentOfPath(n)
        if (shard.isEmpty() || shard.contains('/')) return null
        val dir = sync.realOps.childOf(realRoot, shard) ?: return null
        return sync.realOps.childOf(dir, nameOfPath(n))
    }

    private fun isBlockPath(path: String): Boolean {
        val n = norm(path)
        val parent = parentOfPath(n)
        return parent.isNotEmpty() && !parent.contains('/')
    }

    private fun ensureBlockPulled(path: String) {
        if (!isBlockPath(path)) return
        val real = realBlockDoc(path) ?: return
        if (sync.hasContent(real)) return
        sync.registerExisting(real, local(path))
        try { sync.pullFileIfMissing(real) }
        catch (e: Exception) { VeLog.w(TAG, e) { "ensureBlockPulled: failed to pull $path" } }
    }

    private fun pushBlockWrite(path: String, file: File) {
        val n = norm(path)
        val existing = realBlockDoc(n)
        if (existing != null) {
            sync.pushFileWrite(file, realParent = null, existingRealDoc = existing, displayName = nameOfPath(n), mimeType = "application/octet-stream")
            return
        }
        val shard = parentOfPath(n)
        val realShard = sync.realOps.childOf(realRoot, shard) ?: sync.pushCreateDirectory(realRoot, shard)
        sync.pushFileWrite(file, realParent = realShard, existingRealDoc = null, displayName = nameOfPath(n), mimeType = "application/octet-stream")
    }

    override fun list(dir: String): Array<String>? {
        val d = local(dir)
        val files = d.listFiles() ?: return if (d.isDirectory) emptyArray() else null
        return files.map { DirEntryWire.encode(it.name, it.isDirectory, it.length(), it.lastModified() / 1000) }.toTypedArray()
    }

    override fun stat(path: String): String? {
        val f = local(path)
        if (f.exists()) return DirEntryWire.encode(f.name, f.isDirectory, f.length(), f.lastModified() / 1000)
        if (isBlockPath(path)) {
            val real = try { realBlockDoc(path) } catch (_: Exception) { null }
            if (real != null) return DirEntryWire.encode(nameOfPath(norm(path)), false, real.length(), real.lastModified() / 1000)
        }
        return null
    }

    override fun mkdir(path: String): Boolean = local(path).let { it.isDirectory || it.mkdirs() }
    override fun createFile(path: String): Boolean = try { local(path).let { it.parentFile?.mkdirs(); it.exists() || it.createNewFile() } } catch (_: Exception) { false }
    override fun rename(from: String, to: String): Boolean = false          // CryFS never renames physical blocks
    override fun setMtime(path: String, epochSec: Long): Boolean = false

    override fun remove(path: String): Boolean = try {
        val file = local(path)
        val removed = if (file.exists()) file.deleteRecursively() else false
        if (removed && isBlockPath(path)) {
            realBlockDoc(path)?.let { real -> runCatching { sync.pushDelete(real) } }
        }
        removed || !file.exists()
    } catch (_: Exception) { false }

    override fun readWhole(path: String): ByteArray? = try {
        ensureBlockPulled(path)
        local(path).let { if (it.isFile) it.readBytes() else null }
    } catch (_: Exception) { null }

    override fun writeBlock(path: String, data: ByteArray): Boolean = try {
        val file = local(path)
        file.parentFile?.mkdirs()
        java.io.FileOutputStream(file).use { it.write(data) }
        if (isBlockPath(path)) pushBlockWrite(path, file)
        true
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "writeBlock($path) failed" }
        false
    }

    override fun writeWhole(path: String, data: ByteArray): Boolean = writeBlock(path, data)
    override fun writeWholeAtomic(path: String, data: ByteArray): Boolean = writeBlock(path, data)
    override fun ensureContentReady(path: String) = ensureBlockPulled(path)
    override fun openRead(path: String, hint: String): Int { ensureBlockPulled(path); return openRawRead(local(path)) }
    override fun openWrite(path: String, truncate: Boolean): Int = openRawWrite(local(path), truncate)
    override fun markWritePending(path: String) {}
    override fun publishWrite(path: String, defer: Boolean): Boolean = true
    override fun invalidate(dir: String) {}
    override fun invalidateAll() {}
    override fun spaceInfo(): LongArray? = rootUri?.let { VaultPathUtils.querySafSpaceInfo(context, it) }
    override fun close() { try { sync.teardown() } catch (e: Exception) { VeLog.w(TAG, e) { "mirror teardown failed" } } }
}
