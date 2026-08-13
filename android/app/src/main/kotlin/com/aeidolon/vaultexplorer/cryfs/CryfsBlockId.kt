package com.aeidolon.vaultexplorer.cryfs

import java.security.SecureRandom

/**
 * A CryFS block ID: 16 random bytes, printed/stored as 32 lowercase hex
 * chars. Every block (directory blob, file blob, tree-inner-node, or plain
 * leaf) is addressed by one of these.
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

        // Thread-local buffer to eliminate SecureRandom synchronization lock contention
        private val threadLocalBuffer = ThreadLocal.withInitial { ByteArray(1024) }
        private val threadLocalPos = ThreadLocal.withInitial { 1024 }

        /** Batched RNG: Locks SecureRandom only once every 64 block IDs */
        fun randomFast(random: SecureRandom): CryfsBlockId {
            var pos = threadLocalPos.get()
            val buf = threadLocalBuffer.get()
            if (pos + SIZE_BYTES > buf.size) {
                random.nextBytes(buf)
                pos = 0
            }
            val idBytes = buf.copyOfRange(pos, pos + SIZE_BYTES)
            threadLocalPos.set(pos + SIZE_BYTES)
            return CryfsBlockId(idBytes)
        }

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