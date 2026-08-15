package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.util.LruCache
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.RawFileResolver
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.io.File
import java.util.concurrent.ConcurrentHashMap

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
    context: Context,
    private val blocksRoot: DocumentFile,
    private val cipherId: Int,
    private val blockKey: ByteArray,
    private val integrityState: CryfsLocalIntegrityState,
) : CryfsBlockStorage {
    private val saf = SafDocumentOps(context)
    private val rawRootFolder: File? = RawFileResolver.getRawFile(context, blocksRoot)
    override val isRaw: Boolean get() = rawRootFolder != null
    private val decryptedCache = object : LruCache<String, ByteArray>(1024) {
        override fun sizeOf(key: String, value: ByteArray): Int = 1
    }
    private val shardDirCache = ConcurrentHashMap<String, DocumentFile>()

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
            saf.childOf(blocksRoot, shardDirName) ?: return null
        }
    }

    fun exists(id: CryfsBlockId): Boolean {
        if (synchronized(decryptedCache) { decryptedCache.get(id.hex) } != null) return true
        val directFile = blockFile(id)
        if (directFile != null) {
            return directFile.exists()
        }
        val dir = getShardDirSaf(id.shardDir) ?: return false
        return saf.childOf(dir, id.fileName) != null
    }

    override fun load(id: CryfsBlockId): ByteArray? {
        lastIntegrityViolation = null
        synchronized(decryptedCache) { decryptedCache.get(id.hex) }?.let { return it.copyOf() }
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
        val formatVersion = readU16LE(plaintext, 0)
        if (formatVersion != FORMAT_VERSION_HEADER) return null
        val storedBlockId = plaintext.copyOfRange(2, 18)
        if (!storedBlockId.contentEquals(id.bytes)) return null
        val writerClientId = readU32LE(plaintext, 18)
        val version = readU64LE(plaintext, 22)
        val conflictingKnownVersion = integrityState.checkAndRecordRead(writerClientId, id, version)
        if (conflictingKnownVersion != null) {
            lastIntegrityViolation = CryfsIntegrityViolation(
                blockId = id,
                writerClientId = writerClientId,
                attemptedVersion = version,
                knownVersion = conflictingKnownVersion,
            )
            android.util.Log.e(
                "CryfsBlockStore",
                "Rejecting block ${id.hex}: client $writerClientId claims version $version, which is " +
                    "lower than a version this device has already durably recorded for that client+block " +
                    "-- looks like a rollback (CryFS error 24/25 equivalent), not ordinary corruption.",
            )
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
        writeU16LE(plaintext, 0, FORMAT_VERSION_HEADER)
        System.arraycopy(id.bytes, 0, plaintext, 2, 16)
        writeU32LE(plaintext, 18, integrityState.myClientId)
        writeU64LE(plaintext, 22, version)
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
        } else {
            val dir = getShardDirSaf(id.shardDir)
                ?: saf.createDirectorySafe(blocksRoot, id.shardDir)?.also { shardDirCache[id.shardDir] = it }
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
            return if (file.exists()) file.delete() else false
        }
        val dir = getShardDirSaf(id.shardDir) ?: return false
        val file = saf.childOf(dir, id.fileName) ?: return false
        return file.delete()
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

        private fun writeU16LE(dst: ByteArray, off: Int, v: Int) {
            dst[off] = (v and 0xFF).toByte()
            dst[off + 1] = ((v ushr 8) and 0xFF).toByte()
        }

        private fun writeU32LE(dst: ByteArray, off: Int, v: Long) {
            for (i in 0 until 4) dst[off + i] = ((v ushr (8 * i)) and 0xFF).toByte()
        }

        private fun writeU64LE(dst: ByteArray, off: Int, v: Long) {
            for (i in 0 until 8) dst[off + i] = ((v ushr (8 * i)) and 0xFF).toByte()
        }

        private fun readU16LE(src: ByteArray, off: Int): Int =
            (src[off].toInt() and 0xFF) or ((src[off + 1].toInt() and 0xFF) shl 8)

        private fun readU32LE(src: ByteArray, off: Int): Long {
            var v = 0L
            for (i in 0 until 4) v = v or ((src[off + i].toLong() and 0xFF) shl (8 * i))
            return v
        }

        private fun readU64LE(src: ByteArray, off: Int): Long {
            var v = 0L
            for (i in 0 until 8) v = v or ((src[off + i].toLong() and 0xFF) shl (8 * i))
            return v
        }
    }
}