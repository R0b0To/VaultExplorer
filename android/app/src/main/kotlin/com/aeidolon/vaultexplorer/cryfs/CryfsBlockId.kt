package com.aeidolon.vaultexplorer.cryfs

import java.security.SecureRandom

/**
 * A CryFS block ID: 16 random bytes, printed/stored as 32 lowercase hex
 * chars. Every block (directory blob, file blob, tree-inner-node, or plain
 * leaf) is addressed by one of these — CryFS has no notion of a physical
 * path mirroring the virtual tree the way gocryptfs/Cryptomator do; the
 * *virtual* directory structure lives entirely inside directory blobs'
 * contents (see [CryfsDirBlob]), while physical storage is one flat,
 * sharded pool of block files (see [CryfsBlockStore]).
 */
data class CryfsBlockId(val bytes: ByteArray) {
    init {
        require(bytes.size == SIZE_BYTES) { "CryfsBlockId must be $SIZE_BYTES bytes, got ${bytes.size}" }
    }

    val hex: String by lazy { bytes.joinToString("") { "%02x".format(it) } }

    /** First 3 hex chars = shard directory name, remaining 29 = the block's filename. */
    val shardDir: String get() = hex.substring(0, 3)
    val fileName: String get() = hex.substring(3)

    override fun equals(other: Any?): Boolean = other is CryfsBlockId && bytes.contentEquals(other.bytes)
    override fun hashCode(): Int = bytes.contentHashCode()
    override fun toString(): String = hex

    companion object {
        const val SIZE_BYTES = 16

        fun random(random: SecureRandom): CryfsBlockId =
            CryfsBlockId(ByteArray(SIZE_BYTES).also { random.nextBytes(it) })

        fun fromHex(hex: String): CryfsBlockId {
            val cleaned = hex.trim()
            require(cleaned.length == SIZE_BYTES * 2) { "CryfsBlockId hex must be ${SIZE_BYTES * 2} chars, got ${cleaned.length}" }
            val out = ByteArray(SIZE_BYTES)
            for (i in out.indices) {
                out[i] = ((Character.digit(cleaned[i * 2], 16) shl 4) + Character.digit(cleaned[i * 2 + 1], 16)).toByte()
            }
            return CryfsBlockId(out)
        }

        /** Case-insensitive: real cryfs and this app might not agree on hex casing on disk. */
        fun fromShardAndFileName(shardDir: String, fileName: String): CryfsBlockId? {
            if (shardDir.length != 3 || fileName.length != 29) return null
            return try {
                fromHex(shardDir + fileName)
            } catch (e: Exception) {
                null
            }
        }
    }
}
