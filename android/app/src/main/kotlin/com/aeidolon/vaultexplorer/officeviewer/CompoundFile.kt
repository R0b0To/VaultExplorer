package com.aeidolon.vaultexplorer.officeviewer

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Minimal read-only reader for OLE2 / Compound File Binary containers (the
 * wrapper around legacy `.ppt`, and around password-protected OOXML files).
 * Bounds-checked everywhere; malformed files throw [OfficeException].
 */
internal class CompoundFile(private val data: ByteArray) {

    private class Entry(val name: String, val type: Int, val start: Int, val size: Long)

    private val buf: ByteBuffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
    private val sectorShift: Int
    private val sectorSize: Int
    private val miniSectorSize: Int
    private val miniCutoff: Int
    private val fat: IntArray
    private val miniFat: IntArray
    private val entries = ArrayList<Entry>()
    private var miniStream: ByteArray? = null

    init {
        if (!OfficePackage.isCompoundFile(data) || data.size < 512) fail("not a compound file")
        sectorShift = buf.getShort(30).toInt() and 0xFFFF
        if (sectorShift != 9 && sectorShift != 12) fail("unsupported sector size")
        sectorSize = 1 shl sectorShift
        miniSectorSize = 1 shl (buf.getShort(32).toInt() and 0xFFFF).coerceIn(0, 12)
        miniCutoff = buf.getInt(56)
        val numFatSectors = buf.getInt(44)
        val firstDir = buf.getInt(48)
        val firstMiniFat = buf.getInt(60)
        val numMiniFat = buf.getInt(64)
        var difatSector = buf.getInt(68)
        val numDifat = buf.getInt(72)
        if (numFatSectors < 0 || numFatSectors > MAX_SECTORS || numDifat < 0 || numDifat > MAX_SECTORS) fail("bad header")

        val fatSectorIds = ArrayList<Int>()
        for (i in 0 until 109) {
            val id = buf.getInt(76 + i * 4)
            if (id >= 0 && fatSectorIds.size < numFatSectors) fatSectorIds.add(id)
        }
        var guard = 0
        while (difatSector >= 0 && fatSectorIds.size < numFatSectors && guard++ < numDifat + 1) {
            val off = sectorOffset(difatSector)
            for (i in 0 until sectorSize / 4 - 1) {
                val id = intAt(off + i * 4)
                if (id >= 0 && fatSectorIds.size < numFatSectors) fatSectorIds.add(id)
            }
            difatSector = intAt(off + sectorSize - 4)
        }
        val perSector = sectorSize / 4
        fat = IntArray(fatSectorIds.size * perSector)
        for ((k, id) in fatSectorIds.withIndex()) {
            val off = sectorOffset(id)
            for (i in 0 until perSector) fat[k * perSector + i] = intAt(off + i * 4)
        }

        val dirBytes = readChain(firstDir, -1L)
        var p = 0
        while (p + 128 <= dirBytes.size) {
            val nameLen = ((dirBytes[p + 64].toInt() and 0xFF) or ((dirBytes[p + 65].toInt() and 0xFF) shl 8))
            val type = dirBytes[p + 66].toInt() and 0xFF
            val name = if (nameLen >= 2 && nameLen <= 64) String(dirBytes, p, nameLen - 2, Charsets.UTF_16LE) else ""
            val bb = ByteBuffer.wrap(dirBytes, p, 128).order(ByteOrder.LITTLE_ENDIAN)
            val start = bb.getInt(p + 116)
            val size = if (sectorShift == 9) bb.getInt(p + 120).toLong() and 0xFFFFFFFFL else bb.getLong(p + 120)
            entries.add(Entry(name, type, start, size))
            p += 128
        }
        if (entries.isEmpty()) fail("empty directory")

        val mf = ArrayList<Int>()
        var ms = firstMiniFat
        var steps = 0
        while (ms >= 0 && steps++ < numMiniFat + 1) {
            val off = sectorOffset(ms)
            for (i in 0 until perSector) mf.add(intAt(off + i * 4))
            ms = fatNext(ms)
        }
        miniFat = mf.toIntArray()
    }

    val streamNames: List<String> get() = entries.filter { it.type == 2 }.map { it.name }

    fun has(name: String): Boolean = entries.any { it.type == 2 && it.name == name }

    fun stream(name: String): ByteArray? {
        val e = entries.firstOrNull { it.type == 2 && it.name == name } ?: return null
        if (e.size > MAX_STREAM) throw OfficeException(OfficeError.TOO_LARGE, "stream too large")
        return if (e.size < miniCutoff) readMini(e.start, e.size.toInt()) else readChain(e.start, e.size)
    }

    private fun fail(msg: String): Nothing = throw OfficeException(OfficeError.UNSUPPORTED, "compound file: $msg")

    private fun sectorOffset(id: Int): Int {
        val off = (id.toLong() + 1L) shl sectorShift
        if (id < 0 || off + sectorSize > data.size) fail("sector out of range")
        return off.toInt()
    }

    private fun intAt(off: Int): Int {
        if (off < 0 || off + 4 > data.size) fail("read out of range")
        return buf.getInt(off)
    }

    private fun fatNext(id: Int): Int = if (id in fat.indices) fat[id] else -2

    private fun readChain(start: Int, size: Long): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        var id = start
        var steps = 0
        val max = fat.size + 1
        while (id >= 0 && steps++ <= max) {
            val off = sectorOffset(id)
            out.write(data, off, sectorSize)
            if (size >= 0 && out.size() >= size) break
            id = fatNext(id)
        }
        val bytes = out.toByteArray()
        return if (size >= 0 && bytes.size > size) bytes.copyOf(size.toInt()) else bytes
    }

    private fun readMini(start: Int, size: Int): ByteArray {
        val root = entries.firstOrNull { it.type == 5 } ?: fail("no root entry")
        val ms = miniStream ?: readChain(root.start, root.size).also { miniStream = it }
        val out = java.io.ByteArrayOutputStream()
        var id = start
        var steps = 0
        while (id >= 0 && out.size() < size && steps++ <= miniFat.size + 1) {
            val off = id.toLong() * miniSectorSize
            if (off + miniSectorSize > ms.size) fail("mini sector out of range")
            out.write(ms, off.toInt(), miniSectorSize)
            id = if (id in miniFat.indices) miniFat[id] else -2
        }
        val bytes = out.toByteArray()
        return if (bytes.size > size) bytes.copyOf(size) else bytes
    }

    private companion object {
        const val MAX_SECTORS = 1 shl 20
        const val MAX_STREAM = 128L * 1024 * 1024
    }
}
