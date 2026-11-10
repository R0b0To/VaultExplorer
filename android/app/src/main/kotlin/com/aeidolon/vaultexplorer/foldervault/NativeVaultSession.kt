package com.aeidolon.vaultexplorer.foldervault

import android.content.Context
import android.net.Uri
import com.aeidolon.vaultexplorer.DirEntryWire
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.container.VaultBackend
import com.aeidolon.vaultexplorer.saf.VaultPathUtils
import java.util.Base64

/**
 * [VaultBackend] for the three folder-vault formats. Every call goes straight
 * to the native core, which owns all format logic, key material and locking
 * (hence [skipsPerVolumeLock]: the container layer must not add a second
 * lock on top).
 */
open class NativeVaultSession internal constructor(
    protected val context: Context,
    val vaultRootUri: Uri,
    override val format: ContainerFormat,
    handle: Long,
    val readOnly: Boolean,
    /** Shared with the session's storage so mirror-pull progress can name the volume. */
    private val volIdRef: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(-1),
) : VaultBackend {

    override val skipsPerVolumeLock: Boolean = true
    // CryFS used to take the volume lock itself for fine-grained read/write sections.
    override val managesOwnWriteLocking: Boolean = format == ContainerFormat.CRYFS

    var volId: Int
        get() = volIdRef.get()
        set(value) { volIdRef.set(value) }
    @Volatile private var handle: Long = handle
    private val keyMaterialLock = Any()
    private var keyMaterial: KeyMaterial? = null

    private inline fun <T> withHandle(failure: T, block: (Long) -> T): T {
        val h = handle
        return if (h == 0L) failure else block(h)
    }

    override fun listDirectory(virtualPath: String): Array<String>? =
        withHandle(null) { NativeFolderVault.nativeListDirectory(it, virtualPath) }

    override fun listSymlinks(virtualPath: String): Array<String>? =
        withHandle(null) { NativeFolderVault.nativeListSymlinks(it, virtualPath) }

    override fun readSymlink(virtualPath: String): String? =
        withHandle(null) { NativeFolderVault.nativeReadSymlink(it, virtualPath) }

    override fun createSymlink(virtualPath: String, target: String): Boolean =
        withHandle(false) { NativeFolderVault.nativeCreateSymlink(it, virtualPath, target) }

    override fun hiddenEntryCount(virtualPath: String): Int =
        withHandle(-1) { NativeFolderVault.nativeHiddenEntryCount(it, virtualPath) }

    override fun createDirectory(virtualPath: String): Boolean =
        withHandle(false) { NativeFolderVault.nativeCreateDirectory(it, virtualPath) }

    override fun renameFile(oldVirtualPath: String, newVirtualPath: String): Boolean =
        withHandle(false) { NativeFolderVault.nativeRenameFile(it, oldVirtualPath, newVirtualPath) }

    override fun setLastModifiedTime(virtualPath: String, epochSeconds: Long): Boolean =
        withHandle(false) { NativeFolderVault.nativeSetLastModified(it, virtualPath, epochSeconds) }

    override fun deleteFile(virtualPath: String): Boolean =
        withHandle(false) { NativeFolderVault.nativeDeleteFile(it, virtualPath) }

    override fun getFileSize(virtualPath: String): Long =
        withHandle(-1L) { NativeFolderVault.nativeGetFileSize(it, virtualPath) }

    override fun getFolderSize(virtualPath: String): Long =
        withHandle(0L) { NativeFolderVault.nativeGetFolderSize(it, virtualPath) }

    override fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? =
        withHandle(null) { NativeFolderVault.nativeReadFileChunk(it, virtualPath, offset, length) }

    override fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean =
        withHandle(false) { NativeFolderVault.nativeWriteFileChunk(it, virtualPath, offset, data) }

    override fun finishWrite(virtualPath: String): Boolean =
        withHandle(false) { NativeFolderVault.nativeFinishWrite(it, virtualPath) }

    override fun writeBackFile(virtualPath: String, sourcePath: String, opId: Int, singlePass: Boolean): Boolean =
        withHandle(false) { NativeFolderVault.nativeWriteBackFile(it, virtualPath, sourcePath, opId, singlePass) }

    override fun importStream(virtualPath: String, inputStream: java.io.InputStream, volId: Int): Boolean =
        withHandle(false) { NativeFolderVault.nativeImportStream(it, virtualPath, inputStream) }

    override fun extractFile(virtualPath: String, destinationPath: String, opId: Int, singlePass: Boolean): Boolean =
        withHandle(false) { NativeFolderVault.nativeExtractFile(it, virtualPath, destinationPath, opId, singlePass) }

    override fun beginBatchWrite() { withHandle(Unit) { NativeFolderVault.nativeBeginBatchWrite(it) } }
    override fun endBatchWrite() { withHandle(Unit) { NativeFolderVault.nativeEndBatchWrite(it) } }
    override fun beginBatchDelete() { withHandle(Unit) { NativeFolderVault.nativeBeginBatchDelete(it) } }
    override fun endBatchDelete() { withHandle(Unit) { NativeFolderVault.nativeEndBatchDelete(it) } }

    override fun invalidateCache(virtualPath: String) {
        withHandle(Unit) { NativeFolderVault.nativeInvalidateCache(it, virtualPath) }
    }

    override fun getSpaceInfo(): LongArray? = VaultPathUtils.querySafSpaceInfo(context, vaultRootUri)

    override fun getVaultInfo(): Map<String, Any?> {
        val triples = withHandle(null) { NativeFolderVault.nativeInfo(it) } ?: return mapOf("readOnly" to readOnly)
        val out = LinkedHashMap<String, Any?>()
        var i = 0
        while (i + 2 < triples.size) {
            val key = triples[i]
            val value = triples[i + 2]
            out[key] = when (triples[i + 1]) {
                "i" -> value.toLongOrNull()?.let { if (it in Int.MIN_VALUE..Int.MAX_VALUE) it.toInt() else it } ?: value
                "b" -> value == "true"
                else -> value
            }
            i += 3
        }
        return out
    }

    /**
     * Snapshot of the key material this session holds, for the Check & Repair
     * tooling, which still runs on the Kotlin primitives. Cached; the copy
     * lives on the JVM heap exactly as the old Kotlin sessions' keys did.
     */
    internal fun keyMaterial(): KeyMaterial = synchronized(keyMaterialLock) {
        keyMaterial ?: run {
            val h = handle
            val lines = if (h == 0L) null else NativeFolderVault.nativeExportKeys(h)
            KeyMaterial.parse(lines ?: throw IllegalStateException("vault session is closed")).also { keyMaterial = it }
        }
    }

    override fun close() {
        val h = handle
        handle = 0L
        synchronized(keyMaterialLock) {
            keyMaterial?.wipe()
            keyMaterial = null
        }
        if (h != 0L) NativeFolderVault.nativeClose(h)
    }
}

/** Parsed output of nativeExportKeys. */
internal class KeyMaterial private constructor(
    private val binary: Map<String, ByteArray>,
    private val text: Map<String, String>,
) {
    fun bytes(name: String): ByteArray = binary[name]?.copyOf() ?: throw IllegalStateException("missing key field $name")
    fun string(name: String): String = text[name] ?: throw IllegalStateException("missing field $name")
    fun stringOrNull(name: String): String? = text[name]
    fun wipe() { binary.values.forEach { it.fill(0) } }

    companion object {
        fun parse(lines: Array<String>): KeyMaterial {
            val bin = HashMap<String, ByteArray>()
            val txt = HashMap<String, String>()
            for (l in lines) {
                if (l.length < 4) continue
                val kind = l[0]
                val sep = l.indexOf(':', 2)
                if (l[1] != ':' || sep < 0) continue
                val name = l.substring(2, sep)
                val value = l.substring(sep + 1)
                if (kind == 'f') bin[name] = Base64.getDecoder().decode(value) else if (kind == 's') txt[name] = value
            }
            return KeyMaterial(bin, txt)
        }
    }
}
