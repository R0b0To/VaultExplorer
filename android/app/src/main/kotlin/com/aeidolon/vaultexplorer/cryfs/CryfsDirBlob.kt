package com.aeidolon.vaultexplorer.cryfs

enum class CryfsEntryType(val wireValue: Int) {
    DIR(0), FILE(1), SYMLINK(2);

    companion object {
        fun fromWire(v: Int): CryfsEntryType = values().firstOrNull { it.wireValue == v }
            ?: throw CryfsConfigException("Unknown directory entry type $v")
    }
}

data class CryfsDirEntry(
    val type: CryfsEntryType,
    val name: String,
    val blobId: CryfsBlockId,
    val mode: Int,
    val uid: Int,
    val gid: Int,
    val atimeEpochSec: Long,
    val mtimeEpochSec: Long,
    val ctimeEpochSec: Long,
)

object CryfsDirBlob {
    private val blockIdComparator = Comparator<CryfsDirEntry> { a, b ->
        var cmp = 0
        for (i in 0 until CryfsBlockId.SIZE_BYTES) {
            val byteA = a.blobId.bytes[i].toInt() and 0xFF
            val byteB = b.blobId.bytes[i].toInt() and 0xFF
            if (byteA != byteB) {
                cmp = byteA.compareTo(byteB)
                break
            }
        }
        cmp
    }

    fun parse(bytes: ByteArray): List<CryfsDirEntry> {
        val out = ArrayList<CryfsDirEntry>()
        var pos = 0
        while (pos < bytes.size) {
            if (pos + FIXED_FIELDS_SIZE > bytes.size) {
                throw CryfsConfigException("Truncated directory entry")
            }
            val type = CryfsEntryType.fromWire(bytes[pos].toInt() and 0xFF); pos += 1
            val mode = readU32(bytes, pos); pos += 4
            val uid = readU32(bytes, pos); pos += 4
            val gid = readU32(bytes, pos); pos += 4
            val atime = readU64(bytes, pos); pos += 8; pos += 4 // 12-byte TimeSpec (sec + nsec)
            val mtime = readU64(bytes, pos); pos += 8; pos += 4 // 12-byte TimeSpec
            val ctime = readU64(bytes, pos); pos += 8; pos += 4 // 12-byte TimeSpec

            val nameStart = pos
            while (pos < bytes.size && bytes[pos] != 0.toByte()) pos++
            if (pos >= bytes.size) throw CryfsConfigException("Truncated directory entry (unterminated name)")
            val name = String(bytes, nameStart, pos - nameStart, Charsets.UTF_8)
            pos += 1

            if (pos + 16 > bytes.size) throw CryfsConfigException("Truncated directory entry (missing blob id)")
            val blobId = CryfsBlockId(bytes.copyOfRange(pos, pos + 16)); pos += 16

            out.add(CryfsDirEntry(type, name, blobId, mode, uid, gid, atime, mtime, ctime))
        }
        return out
    }

    fun serialize(entries: List<CryfsDirEntry>): ByteArray {
        val sortedEntries = entries.sortedWith(blockIdComparator)
        val out = java.io.ByteArrayOutputStream()
        for (e in sortedEntries) {
            out.write(e.type.wireValue)
            out.write(u32(e.mode))
            out.write(u32(e.uid))
            out.write(u32(e.gid))
            out.write(u64(e.atimeEpochSec)); out.write(u32(0))
            out.write(u64(e.mtimeEpochSec)); out.write(u32(0))
            out.write(u64(e.ctimeEpochSec)); out.write(u32(0))
            val nameBytes = e.name.toByteArray(Charsets.UTF_8)
            out.write(nameBytes)
            out.write(0)
            out.write(e.blobId.bytes)
        }
        return out.toByteArray()
    }

    fun newEntry(
        type: CryfsEntryType, name: String, blobId: CryfsBlockId,
        mode: Int, nowEpochSec: Long, uid: Int = 0, gid: Int = 0,
    ) = CryfsDirEntry(type, name, blobId, mode, uid, gid, nowEpochSec, nowEpochSec, nowEpochSec)

    private const val FIXED_FIELDS_SIZE = 1 + 4 + 4 + 4 + 12 + 12 + 12
    private fun u32(v: Int) = ByteArray(4).also { writeU32(it, 0, v) }
    private fun u64(v: Long) = ByteArray(8).also { writeU64(it, 0, v) }

    private fun writeU32(dst: ByteArray, off: Int, v: Int) {
        dst[off] = (v and 0xFF).toByte()
        dst[off + 1] = ((v ushr 8) and 0xFF).toByte()
        dst[off + 2] = ((v ushr 16) and 0xFF).toByte()
        dst[off + 3] = ((v ushr 24) and 0xFF).toByte()
    }

    private fun writeU64(dst: ByteArray, off: Int, v: Long) {
        for (i in 0 until 8) dst[off + i] = ((v ushr (8 * i)) and 0xFF).toByte()
    }

    private fun readU32(src: ByteArray, off: Int): Int =
        (src[off].toInt() and 0xFF) or
            ((src[off + 1].toInt() and 0xFF) shl 8) or
            ((src[off + 2].toInt() and 0xFF) shl 16) or
            ((src[off + 3].toInt() and 0xFF) shl 24)

    private fun readU64(src: ByteArray, off: Int): Long {
        var v = 0L
        for (i in 0 until 8) v = v or ((src[off + i].toLong() and 0xFF) shl (8 * i))
        return v
    }
}