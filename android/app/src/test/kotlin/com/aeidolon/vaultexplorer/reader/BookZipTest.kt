package com.aeidolon.vaultexplorer.reader

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** In-memory [BookByteSource]; counts reads so tests can prove access is ranged. */
class ByteArraySource(private val data: ByteArray, name: String = "mem") : BookByteSource {
    var bytesRead = 0L
        private set
    override val size: Long = data.size.toLong()
    override val cacheKey: String = "t:$name:$size"

    override fun read(offset: Long, length: Int): ByteArray {
        if (length <= 0 || offset < 0 || offset >= size) return ByteArray(0)
        val end = minOf(size, offset + length).toInt()
        val out = data.copyOfRange(offset.toInt(), end)
        bytesRead += out.size
        return out
    }

    override fun close() {}
}

class BookZipTest {

    private fun zip(vararg entries: Triple<String, ByteArray, Int>): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zos ->
            for ((name, bytes, method) in entries) {
                val e = ZipEntry(name)
                e.method = method
                if (method == ZipEntry.STORED) {
                    e.size = bytes.size.toLong()
                    e.compressedSize = bytes.size.toLong()
                    val crc = java.util.zip.CRC32().also { it.update(bytes) }
                    e.crc = crc.value
                }
                zos.putNextEntry(e)
                zos.write(bytes)
                zos.closeEntry()
            }
        }
        return out.toByteArray()
    }

    private fun deflated(name: String, bytes: ByteArray) = Triple(name, bytes, ZipEntry.DEFLATED)
    private fun stored(name: String, bytes: ByteArray) = Triple(name, bytes, ZipEntry.STORED)

    @Test
    fun `lists entries and reads stored and deflated content back`() {
        val text = "hello hello hello hello hello".repeat(50).toByteArray()
        val raw = ByteArray(4096) { (it * 31).toByte() }
        val src = ByteArraySource(zip(deflated("a/page 1.txt", text), stored("b.bin", raw), deflated("dir/", ByteArray(0))))

        val dir = ZipReader.readDirectory(src)
        assertEquals(listOf("a/page 1.txt", "b.bin", "dir/"), dir.entries.map { it.name })
        assertTrue(dir.find("dir/")!!.isDirectory)

        assertArrayEquals(text, ZipReader.readEntry(src, dir.find("a/page 1.txt")!!))
        assertArrayEquals(raw, ZipReader.readEntry(src, dir.find("b.bin")!!))
    }

    @Test
    fun `find falls back to a case-insensitive match`() {
        val src = ByteArraySource(zip(deflated("OEBPS/Text/Ch1.xhtml", "x".toByteArray())))
        val dir = ZipReader.readDirectory(src)
        assertNotNull(dir.find("oebps/text/ch1.xhtml"))
        assertNull(dir.find("oebps/text/missing.xhtml"))
    }

    @Test
    fun `reading one entry of a large archive reads only a small part of it`() {
        // Incompressible filler so the archive really is big.
        val filler = java.util.Random(7).let { r -> ByteArray(3 * 1024 * 1024).also { r.nextBytes(it) } }
        val page = "tiny page".toByteArray()
        val src = ByteArraySource(zip(stored("big.bin", filler), deflated("page.txt", page)))

        val dir = ZipReader.readDirectory(src)
        val afterDirectory = src.bytesRead
        assertArrayEquals(page, ZipReader.readEntry(src, dir.find("page.txt")!!))

        // The whole point of the reader: no scan from the start, no whole-file copy.
        assertTrue("read ${src.bytesRead} of ${src.size}", src.bytesRead < src.size / 10)
        assertTrue(src.bytesRead - afterDirectory < 4096)
    }

    @Test
    fun `utf-8 names survive`() {
        val src = ByteArraySource(zip(deflated("漫画/第01話.jpg", byteArrayOf(1, 2, 3))))
        val dir = ZipReader.readDirectory(src)
        assertEquals("漫画/第01話.jpg", dir.entries.single().name)
    }

    @Test
    fun `a file that is not a zip is reported as NOT_ZIP`() {
        val src = ByteArraySource("Rar!\u001a\u0007\u0001\u0000".repeat(10).toByteArray())
        try {
            ZipReader.readDirectory(src)
            fail("expected NOT_ZIP")
        } catch (e: BookFormatException) {
            assertEquals(BookError.NOT_ZIP, e.error)
        }
    }

    @Test
    fun `a tiny file is NOT_ZIP too`() {
        try {
            ZipReader.readDirectory(ByteArraySource(ByteArray(5)))
            fail("expected NOT_ZIP")
        } catch (e: BookFormatException) {
            assertEquals(BookError.NOT_ZIP, e.error)
        }
    }

    @Test
    fun `encrypted entries are refused so the caller can fall back`() {
        val bytes = zip(deflated("secret.jpg", ByteArray(100) { 5 }))
        // Set the "encrypted" general-purpose flag (bit 0) in the central directory record.
        val patched = bytes.copyOf()
        var i = patched.size - 22
        while (i >= 0) {
            if (patched[i] == 0x50.toByte() && patched[i + 1] == 0x4b.toByte() &&
                patched[i + 2] == 0x01.toByte() && patched[i + 3] == 0x02.toByte()
            ) {
                patched[i + 8] = (patched[i + 8].toInt() or 1).toByte()
                break
            }
            i--
        }
        val src = ByteArraySource(patched)
        val entry = ZipReader.readDirectory(src).entries.single()
        assertTrue(entry.isEncrypted)
        try {
            ZipReader.readEntry(src, entry)
            fail("expected ENCRYPTED")
        } catch (e: BookFormatException) {
            assertEquals(BookError.ENCRYPTED, e.error)
        }
    }

    @Test
    fun `a decompression bomb is cut off at the entry cap`() {
        val zeros = ByteArray(2 * 1024 * 1024)
        val src = ByteArraySource(zip(deflated("bomb.bin", zeros)))
        val entry = ZipReader.readDirectory(src).entries.single()
        try {
            ZipReader.readEntry(src, entry, maxBytes = 1024)
            fail("expected TOO_LARGE")
        } catch (e: BookFormatException) {
            assertEquals(BookError.TOO_LARGE, e.error)
        }
    }

    @Test
    fun `a truncated archive does not hang or crash`() {
        val full = zip(deflated("a.txt", ByteArray(5000) { it.toByte() }))
        val cut = full.copyOf(full.size / 2)
        try {
            val src = ByteArraySource(cut)
            val dir = ZipReader.readDirectory(src)
            dir.entries.forEach { ZipReader.readEntry(src, it) }
            fail("expected a format exception")
        } catch (e: BookFormatException) {
            assertFalse(e.message.isNullOrEmpty())
        }
    }
}
