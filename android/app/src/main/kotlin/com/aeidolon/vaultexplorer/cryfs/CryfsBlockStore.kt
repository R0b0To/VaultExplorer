package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.util.LruCache
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.RawFileResolver
import com.aeidolon.vaultexplorer.crypto.LittleEndian
import com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator
import com.aeidolon.vaultexplorer.saf.MirroredSafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafIOException
import com.aeidolon.vaultexplorer.saf.VaultDocumentOps
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import com.aeidolon.vaultexplorer.VeLog

/** A block failed to authenticate against this device's durably recorded
 *  history: [writerClientId] claimed [attemptedVersion] for [blockId], but
 *  this device has already seen that exact (client, block) pair at
 *  [knownVersion], which is higher. This is this app's equivalent of
 *  CryFS's error 24/25 -- a rollback/tampering signal, not ordinary
 *  corruption. See [CryfsBlockStore.lastIntegrityViolation]. */
data class CryfsIntegrityViolation(
    val blockId: CryfsBlockId,
    val writerClientId: Long,
    val attemptedVersion: Long,
    val knownVersion: Long,
)

class CryfsBlockStore(
    private val context: Context,
    // The vault's REAL root -- always the real SAF/raw tree, even when
    // mirroring is active (see mirrorSync below). Block files live
    // directly under here as sharded (2-hex-char) subdirectories; there's
    // no separate "blocks" subfolder for CryFS the way gocryptfs/
    // Cryptomator have a data dir.
    private val blocksRoot: DocumentFile,
    private val cipherId: Int,
    private val blockKey: ByteArray,
    private val integrityState: CryfsLocalIntegrityState,
    // Non-null to mirror this vault's physical block storage to app-private
    // storage instead of talking to blocksRoot's real SAF tree directly on
    // every block read/write/delete -- same rationale as
    // CryptomatorSession/GocryptfsVault (see MirrorSyncCoordinator's doc
    // comment), just applied per-block rather than through the generic
    // VaultDocumentOps CRUD surface those use: block files have a
    // deterministic shard/name path from a CryfsBlockId, so there's no need
    // to discover them via a directory listing first (see realBlockDoc).
    // Opt-in and defaulted off: FolderVaultChecker's one-shot, no-close
    // structural scan constructs a CryfsBlockStore too, and that call site
    // has no teardown() lifecycle to release a mirror directory through, so
    // it must never enable one.
    private val mirrorSync: MirrorSyncCoordinator? = null,
) : CryfsBlockStorage {
    private val mirroredOps: MirroredSafDocumentOps? = mirrorSync?.let { MirroredSafDocumentOps(context, it) }
    private val saf: VaultDocumentOps = mirroredOps ?: SafDocumentOps(context)
    // When mirroring, physical I/O happens against the local mirror root
    // instead of blocksRoot's real tree -- a plain java.io.File-backed
    // DocumentFile, always raw-accessible (it's under this app's own
    // filesDir). Falls back to a raw resolve of blocksRoot itself
    // otherwise, same as before mirroring existed.
    private val effectiveBlocksRoot: DocumentFile = mirroredOps?.root ?: blocksRoot
    private val rawRootFolder: File? = RawFileResolver.getRawFile(context, effectiveBlocksRoot)
    override val isRaw: Boolean get() = rawRootFolder != null
    private val decryptedCache = object : LruCache<String, ByteArray>(1024) {
        override fun sizeOf(key: String, value: ByteArray): Int = 1
    }
    private val shardDirCache = ConcurrentHashMap<String, DocumentFile>()

    fun invalidateCache() {
        decryptedCache.evictAll()
        shardDirCache.clear()
        saf.invalidateAll()
    }

    /** Tears down this store's local mirror, if mirroring is active --
     *  see [CryfsSession.close]. No-op otherwise. */
    fun teardownMirror() {
        mirrorSync?.teardown()
    }

    /** Set by [load] whenever it rejects a block for looking like a
     *  rollback (see [CryfsIntegrityViolation]), so callers that get a
     *  `null` back can tell "genuinely missing/corrupt block" apart from
     *  "this device has durable proof a newer version of this block
     *  existed" and surface a clearer message than upstream cryfs's own
     *  fairly opaque error 24/25 -- cleared at the start of every [load]
     *  call, so it always reflects only the most recent one. */
    @Volatile
    var lastIntegrityViolation: CryfsIntegrityViolation? = null
        private set

    private fun blockFile(id: CryfsBlockId, createDirs: Boolean = false): File? {
        val root = rawRootFolder ?: return null
        val shardDir = File(root, id.shardDir)
        if (createDirs && !shardDir.exists()) {
            shardDir.mkdirs()
        }
        return File(shardDir, id.fileName)
    }

    private fun getShardDirSaf(shardDirName: String): DocumentFile? {
        return shardDirCache.getOrPut(shardDirName) {
            saf.childOf(effectiveBlocksRoot, shardDirName) ?: return null
        }
    }

    /**
     * Mirror-only: resolves the REAL SAF DocumentFile a given block
     * corresponds to, against blocksRoot (never the mirror). Block files
     * have a deterministic shard/name path derived from [id], so -- unlike
     * MirroredSafDocumentOps's generic childOf/listChildren, which needs a
     * prior [MirrorSyncCoordinator.pullListingIfMissing] to have discovered
     * a document before it can be looked up -- this can always compute it
     * directly, no listing required. Returns null if the block genuinely
     * doesn't exist on the real tree yet (not an error: covers both a
     * brand-new block about to be written and a real lookup miss).
     */
    private fun realBlockDoc(id: CryfsBlockId): DocumentFile? {
        val sync = mirrorSync ?: return null
        val shardDir = sync.realOps.childOf(blocksRoot, id.shardDir) ?: return null
        return sync.realOps.childOf(shardDir, id.fileName)
    }

    /** Mirror-only: pulls block [id]'s bytes from the real SAF tree into
     *  the local mirror if they aren't already there. Call before any read
     *  of [blockFile]. No-op when not mirroring, or when the block simply
     *  doesn't exist on the real tree either (see [realBlockDoc]). */
    private fun ensureBlockPulled(id: CryfsBlockId) {
        val sync = mirrorSync ?: return
        val real = realBlockDoc(id) ?: return
        if (sync.hasContent(real)) return
        val mirrorFile = blockFile(id) ?: return
        sync.registerExisting(real, mirrorFile)
        try {
            sync.pullFileIfMissing(real)
        } catch (e: SafIOException) {
            VeLog.w("CryfsBlockStore", e) { "ensureBlockPulled: failed to pull block ${id.hex}" }
        }
    }

    /** Mirror-only: pushes a just-written local mirror block file back to
     *  the real SAF tree, creating its shard dir and/or the block file
     *  there if this is the first time this block has been pushed. Call
     *  after every local write of [blockFile]. */
    private fun pushBlockWrite(id: CryfsBlockId, mirrorFile: File) {
        val sync = mirrorSync ?: return
        val existingReal = realBlockDoc(id)
        if (existingReal != null) {
            sync.pushFileWrite(mirrorFile, realParent = null, existingRealDoc = existingReal, displayName = id.fileName, mimeType = "application/octet-stream")
            return
        }
        val realShardDir = sync.realOps.childOf(blocksRoot, id.shardDir)
            ?: sync.pushCreateDirectory(blocksRoot, id.shardDir)
        sync.pushFileWrite(mirrorFile, realParent = realShardDir, existingRealDoc = null, displayName = id.fileName, mimeType = "application/octet-stream")
    }

    fun exists(id: CryfsBlockId): Boolean {
        if (synchronized(decryptedCache) { decryptedCache.get(id.hex) } != null) return true
        val directFile = blockFile(id)
        if (directFile != null) {
            if (directFile.exists()) return true
            // Mirrored vault: a block that's on the real tree but not yet
            // pulled into the local mirror would otherwise wrongly report
            // as missing here.
            if (mirrorSync != null) return realBlockDoc(id) != null
            return false
        }
        val dir = getShardDirSaf(id.shardDir) ?: return false
        return saf.childOf(dir, id.fileName) != null
    }

    override fun load(id: CryfsBlockId): ByteArray? {
        lastIntegrityViolation = null
        synchronized(decryptedCache) { decryptedCache.get(id.hex) }?.let { return it.copyOf() }
        if (mirrorSync != null) ensureBlockPulled(id)
        val raw = if (rawRootFolder != null) {
            val file = blockFile(id) ?: return null
            if (!file.exists()) return null
            try { file.readBytes() } catch (_: Exception) { return null }
        } else {
            val dir = getShardDirSaf(id.shardDir) ?: return null
            val file = saf.childOf(dir, id.fileName) ?: return null
            try { saf.readWhole(file) } catch (_: Exception) { return null }
        }
        if (raw.size < ON_DISK_HEADER.size + ENCRYPTED_LAYER_HEADER.size) return null
        for (i in ON_DISK_HEADER.indices) if (raw[i] != ON_DISK_HEADER[i]) return null
        val encLayerOff = ON_DISK_HEADER.size
        for (i in ENCRYPTED_LAYER_HEADER.indices) if (raw[encLayerOff + i] != ENCRYPTED_LAYER_HEADER[i]) return null
        val cipherInput = raw.copyOfRange(encLayerOff + ENCRYPTED_LAYER_HEADER.size, raw.size)
        val plaintext = CryfsBlockCipher.decrypt(cipherId, blockKey, cipherInput) ?: return null
        if (plaintext.size < INTEGRITY_HEADER_SIZE) return null
        val formatVersion = LittleEndian.readU16(plaintext, 0)
        if (formatVersion != FORMAT_VERSION_HEADER) return null
        val storedBlockId = plaintext.copyOfRange(2, 18)
        if (!storedBlockId.contentEquals(id.bytes)) return null
        val writerClientId = LittleEndian.readU32(plaintext, 18)
        val version = LittleEndian.readU64(plaintext, 22)
        val conflictingKnownVersion = integrityState.checkAndRecordRead(writerClientId, id, version)
        if (conflictingKnownVersion != null) {
            lastIntegrityViolation = CryfsIntegrityViolation(
                blockId = id,
                writerClientId = writerClientId,
                attemptedVersion = version,
                knownVersion = conflictingKnownVersion,
            )
            VeLog.e("CryfsBlockStore") {
                "Rejecting block ${id.hex}: client $writerClientId claims version $version, which is " +
                    "lower than a version this device has already durably recorded for that client+block " +
                    "-- looks like a rollback (CryFS error 24/25 equivalent), not ordinary corruption."
            }
            return null
        }
        val payload = plaintext.copyOfRange(INTEGRITY_HEADER_SIZE, plaintext.size)
        synchronized(decryptedCache) { decryptedCache.put(id.hex, payload.copyOf()) }
        return payload
    }

    override fun store(id: CryfsBlockId, payload: ByteArray, isNewBlock: Boolean) {
        // Always this client's OWN last-used version for this exact block, plus
        // one -- never derived from whatever version currently happens to be on
        // disk (that block may have been last written by a completely different
        // client, with its own unrelated counter). See CryfsLocalIntegrityState's
        // KDoc for why that distinction is exactly what makes vaults interchangeable
        // with DroidFS/other cryfs clients instead of eventually tripping their
        // error 24/25. isNewBlock is not needed here: a genuinely fresh block ID
        // has no recorded history either way, so this still comes out to 1.
        val version = integrityState.nextVersionForOwnWrite(id)
        val plaintext = ByteArray(INTEGRITY_HEADER_SIZE + payload.size)
        LittleEndian.writeU16(plaintext, 0, FORMAT_VERSION_HEADER)
        System.arraycopy(id.bytes, 0, plaintext, 2, 16)
        LittleEndian.writeU32(plaintext, 18, integrityState.myClientId)
        LittleEndian.writeU64(plaintext, 22, version)
        System.arraycopy(payload, 0, plaintext, INTEGRITY_HEADER_SIZE, payload.size)
        val cipherOutput = CryfsBlockCipher.encrypt(cipherId, blockKey, plaintext)
        val onDisk = ByteArray(ON_DISK_HEADER.size + ENCRYPTED_LAYER_HEADER.size + cipherOutput.size)
        System.arraycopy(ON_DISK_HEADER, 0, onDisk, 0, ON_DISK_HEADER.size)
        System.arraycopy(ENCRYPTED_LAYER_HEADER, 0, onDisk, ON_DISK_HEADER.size, ENCRYPTED_LAYER_HEADER.size)
        System.arraycopy(cipherOutput, 0, onDisk, ON_DISK_HEADER.size + ENCRYPTED_LAYER_HEADER.size, cipherOutput.size)
        if (rawRootFolder != null) {
            val targetFile = blockFile(id, createDirs = true)
                ?: throw IllegalStateException("Could not resolve path for ${id.hex}")
            java.io.FileOutputStream(targetFile).use { fos ->
                fos.write(onDisk)
            }
            if (mirrorSync != null) pushBlockWrite(id, targetFile)
        } else {
            val dir = getShardDirSaf(id.shardDir)
                ?: saf.createDirectorySafe(effectiveBlocksRoot, id.shardDir)?.also { shardDirCache[id.shardDir] = it }
                ?: throw IllegalStateException("Could not access shard dir ${id.shardDir}")
            val file = if (isNewBlock) {
                saf.createFileSafe(dir, "application/octet-stream", id.fileName)
            } else {
                saf.childOf(dir, id.fileName) ?: saf.createFileSafe(dir, "application/octet-stream", id.fileName)
            } ?: throw IllegalStateException("Could not create file ${id.fileName}")
            saf.writeWhole(file, onDisk)
        }
        synchronized(decryptedCache) { decryptedCache.put(id.hex, payload) }
    }

    override fun remove(id: CryfsBlockId): Boolean {
        synchronized(decryptedCache) { decryptedCache.remove(id.hex) }
        if (rawRootFolder != null) {
            val file = blockFile(id) ?: return false
            val removed = if (file.exists()) file.delete() else false
            // Mirrored vault: a local-mirror-only delete would silently
            // diverge from the real SAF tree, same class of bug as the
            // SAF-path branch below -- just reached from the raw fast path
            // once mirroring makes it the active one for this store.
            if (removed && mirrorSync != null) {
                realBlockDoc(id)?.let { real -> runCatching { mirrorSync?.pushDelete(real) } }
            }
            return removed
        }
        val dir = getShardDirSaf(id.shardDir) ?: return false
        val file = saf.childOf(dir, id.fileName) ?: return false
        // Routed through saf.deleteRecursively, not a raw .delete() -- a raw
        // delete on a MirroredSafDocumentOps-backed DocumentFile would only
        // remove it from the local mirror and never reach the real SAF
        // tree. See VaultDocumentOps/MirrorSyncCoordinator.
        saf.deleteRecursively(file)
        return true
    }

    fun clearCache() {
        synchronized(decryptedCache) { decryptedCache.evictAll() }
        shardDirCache.clear()
    }

    /** Durably flushes any pending integrity-state updates. Call at session
     *  boundaries (see [CryfsSession.close]) -- block writes are already
     *  fsync'd as they happen (see [CryfsLocalIntegrityState]), but this
     *  also compacts the on-disk log so it doesn't linger larger than it
     *  needs to be between runs. */
    fun flushIntegrityState() = integrityState.flush()

    companion object {
        const val FORMAT_VERSION_HEADER = 1
        const val INTEGRITY_HEADER_SIZE = 2 + 16 + 4 + 8
        private val ON_DISK_HEADER = byteArrayOf(
            'c'.code.toByte(), 'r'.code.toByte(), 'y'.code.toByte(), 'f'.code.toByte(), 's'.code.toByte(),
            ';'.code.toByte(), 'b'.code.toByte(), 'l'.code.toByte(), 'o'.code.toByte(), 'c'.code.toByte(),
            'k'.code.toByte(), ';'.code.toByte(), '0'.code.toByte(), 0,
        )
        private val ENCRYPTED_LAYER_HEADER = byteArrayOf(1, 0)

        /**
         * The plaintext prefix every valid block file starts with (magic +
         * encrypted-layer version), before the password-dependent
         * ciphertext. Exposed so FolderVaultChecker.kt's no-password
         * structural CryFS scan can flag obviously-wrong files (zero-byte
         * blocks from a failed sync, a foreign file dropped into a shard
         * dir, etc.) without needing the vault's key.
         */
        val MAGIC_PREFIX: ByteArray = ON_DISK_HEADER + ENCRYPTED_LAYER_HEADER

        fun calculateVirtualBlockSize(physicalBlockSize: Int, cipherName: String): Int {
            val cipherOverhead = when (cipherName) {
                "xchacha20-poly1305" -> 40
                "aes-256-gcm", "aes-128-gcm" -> 32
                "aes-256-cfb", "aes-128-cfb" -> 16
                else -> 40
            }
            val totalOverhead = ON_DISK_HEADER.size + ENCRYPTED_LAYER_HEADER.size + cipherOverhead + INTEGRITY_HEADER_SIZE
            return physicalBlockSize - totalOverhead
        }
    }
}