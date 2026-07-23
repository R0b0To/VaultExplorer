package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.util.LruCache
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.UriToPath
import java.io.File
import java.util.concurrent.ConcurrentHashMap

class CryfsBlockStore(
    context: Context,
    private val blocksRoot: DocumentFile,
    private val cipherId: Int,
    private val blockKey: ByteArray,
    private val clientId: Long,
) {
    private val saf = SafDocumentOps(context)
    private val rawRootFolder: File? = UriToPath.getRawFile(context, blocksRoot.uri)

    private val decryptedCache = object : LruCache<String, ByteArray>(1024) {
        override fun sizeOf(key: String, value: ByteArray): Int = 1
    }
    private val versionCache = ConcurrentHashMap<String, Long>()

    private fun blockFile(id: CryfsBlockId, createDirs: Boolean = false): File? {
        val root = rawRootFolder ?: return null
        val shardDir = File(root, id.shardDir)
        if (createDirs && !shardDir.exists()) {
            shardDir.mkdirs()
        }
        return File(shardDir, id.fileName)
    }

    fun exists(id: CryfsBlockId): Boolean {
        if (decryptedCache.get(id.hex) != null) return true
        val directFile = blockFile(id)
        if (directFile != null) {
            return directFile.exists()
        }
        // Fallback to SAF if raw path is not accessible
        val dir = saf.childOf(blocksRoot, id.shardDir) ?: return false
        return saf.childOf(dir, id.fileName) != null
    }

    fun load(id: CryfsBlockId): ByteArray? {
        decryptedCache.get(id.hex)?.let { return it.copyOf() }

        val raw = if (rawRootFolder != null) {
            val file = blockFile(id) ?: return null
            if (!file.exists()) return null
            try { file.readBytes() } catch (_: Exception) { return null }
        } else {
            val dir = saf.childOf(blocksRoot, id.shardDir) ?: return null
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

        val version = readU64LE(plaintext, 22)
        versionCache[id.hex] = version

        val payload = plaintext.copyOfRange(INTEGRITY_HEADER_SIZE, plaintext.size)
        decryptedCache.put(id.hex, payload.copyOf())
        return payload
    }

    fun store(id: CryfsBlockId, payload: ByteArray, isNewBlock: Boolean = false) {
        val version = if (isNewBlock) {
            1L
        } else {
            if (!versionCache.containsKey(id.hex)) {
                load(id)
            }
            (versionCache[id.hex] ?: 0L) + 1
        }
        versionCache[id.hex] = version

        val plaintext = ByteArray(INTEGRITY_HEADER_SIZE + payload.size)
        writeU16LE(plaintext, 0, FORMAT_VERSION_HEADER)
        System.arraycopy(id.bytes, 0, plaintext, 2, 16)
        writeU32LE(plaintext, 18, clientId)
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
            targetFile.writeBytes(onDisk)
        } else {
            val dir = saf.createDirectorySafe(blocksRoot, id.shardDir)
                ?: throw IllegalStateException("Could not access shard dir ${id.shardDir}")
            val file = saf.createFileSafe(dir, "application/octet-stream", id.fileName)
                ?: throw IllegalStateException("Could not create file ${id.fileName}")
            saf.writeWhole(file, onDisk)
        }

        decryptedCache.put(id.hex, payload.copyOf())
    }

    fun remove(id: CryfsBlockId): Boolean {
        decryptedCache.remove(id.hex)
        versionCache.remove(id.hex)

        if (rawRootFolder != null) {
            val file = blockFile(id) ?: return false
            return if (file.exists()) file.delete() else false
        }

        val dir = saf.childOf(blocksRoot, id.shardDir) ?: return false
        val file = saf.childOf(dir, id.fileName) ?: return false
        return file.delete()
    }

    fun clearCache() {
        decryptedCache.evictAll()
        versionCache.clear()
    }

    companion object {
        const val FORMAT_VERSION_HEADER = 1
        const val INTEGRITY_HEADER_SIZE = 2 + 16 + 4 + 8
        private val ON_DISK_HEADER = byteArrayOf(
            'c'.code.toByte(), 'r'.code.toByte(), 'y'.code.toByte(), 'f'.code.toByte(), 's'.code.toByte(),
            ';'.code.toByte(), 'b'.code.toByte(), 'l'.code.toByte(), 'o'.code.toByte(), 'c'.code.toByte(),
            'k'.code.toByte(), ';'.code.toByte(), '0'.code.toByte(), 0,
        )
        private val ENCRYPTED_LAYER_HEADER = byteArrayOf(1, 0)

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
        private fun readU64LE(src: ByteArray, off: Int): Long {
            var v = 0L
            for (i in 0 until 8) v = v or ((src[off + i].toLong() and 0xFF) shl (8 * i))
            return v
        }
    }
}