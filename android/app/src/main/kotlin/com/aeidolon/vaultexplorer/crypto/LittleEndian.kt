package com.aeidolon.vaultexplorer.crypto

/**
 * Little-endian integer <-> byte helpers for CryFS's on-disk binary formats.
 *
 * Previously hand-rolled separately in CryfsConfig.kt, CryfsBlockStore.kt,
 * CryfsDataTree.kt, and CryfsFsBlob.kt, and already drifted apart: writeU32LE
 * took an Int in one file and a Long in another (same name, same package),
 * and no single file had a complete read/write set for every width. See the
 * tech-debt audit for the full history -- this is the consolidated version.
 *
 * U32 reads/writes always use Long, never Int: a block/file size that grows
 * past Int.MAX_VALUE can't silently truncate through this API the way the
 * old CryfsDataTree.kt copy could. Callers that need an Int (e.g. to size an
 * ArrayList or index a small, format-bounded count) convert explicitly with
 * `.toInt()` at the call site, so the truncation -- if it ever happens -- is
 * visible in a diff instead of hiding inside a helper.
 */
object LittleEndian {

    // ---- offset-based: read/write into an existing buffer ----

    fun readU16(src: ByteArray, off: Int): Int =
        (src[off].toInt() and 0xFF) or ((src[off + 1].toInt() and 0xFF) shl 8)

    fun writeU16(dst: ByteArray, off: Int, v: Int) {
        dst[off] = (v and 0xFF).toByte()
        dst[off + 1] = ((v ushr 8) and 0xFF).toByte()
    }

    fun readU32(src: ByteArray, off: Int): Long {
        var result = 0L
        for (i in 0 until 4) result = result or ((src[off + i].toLong() and 0xFF) shl (8 * i))
        return result
    }

    fun writeU32(dst: ByteArray, off: Int, v: Long) {
        for (i in 0 until 4) dst[off + i] = ((v ushr (8 * i)) and 0xFF).toByte()
    }

    fun readU64(src: ByteArray, off: Int): Long {
        var result = 0L
        for (i in 0 until 8) result = result or ((src[off + i].toLong() and 0xFF) shl (8 * i))
        return result
    }

    fun writeU64(dst: ByteArray, off: Int, v: Long) {
        for (i in 0 until 8) dst[off + i] = ((v ushr (8 * i)) and 0xFF).toByte()
    }

    // ---- allocate-and-return: for building up variable-length records via
    // concatenation (CryfsConfig's usage pattern -- e.g. `writeU64Bytes(n) +
    // writeU32Bytes(r) + salt`) ----

    fun u32Bytes(v: Long): ByteArray = ByteArray(4).also { writeU32(it, 0, v) }

    fun u64Bytes(v: Long): ByteArray = ByteArray(8).also { writeU64(it, 0, v) }

    // ---- hex codec: CryFS's on-disk config format hex-encodes several
    // fields. JSON/Base64 elsewhere in this app has a JDK builtin
    // (java.util.Base64); hex does not until Java 17's HexFormat, which is
    // why this exists at all -- it doesn't need to exist twice. ----

    fun bytesToHex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }

    fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "Odd-length hex string" }
        return ByteArray(hex.length / 2) { i ->
            ((Character.digit(hex[i * 2], 16) shl 4) + Character.digit(hex[i * 2 + 1], 16)).toByte()
        }
    }
}
