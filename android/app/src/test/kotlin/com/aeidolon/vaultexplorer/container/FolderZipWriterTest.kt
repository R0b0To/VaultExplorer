package com.aeidolon.vaultexplorer.container

import com.aeidolon.vaultexplorer.DirEntryWire
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.zip.ZipInputStream

/**
 * FolderZipWriter is the engine behind sharing a folder out of a vault. It's
 * pure JVM on purpose (the vault is reached only through its Source
 * interface), so these tests need neither a live session nor JNI -- the
 * same extract-for-testability pattern as uniqueNameAgainst /
 * fitsWithinSafetyMargin in ImportExportHandlers.
 *
 * The failure tests matter most: a share that dies halfway must look
 * corrupt to the receiver, never like a complete archive of fewer files.
 */
class FolderZipWriterTest {

    private class FakeVault(
        val dirs: Map<String, List<String>>,
        val files: Map<String, ByteArray> = emptyMap(),
    ) : FolderZipWriter.Source {
        var opened = 0
        var closed = 0

        override fun list(dirPath: String): Array<String>? = dirs[dirPath]?.toTypedArray()

        override fun openFile(path: String): FolderZipWriter.FileReader {
            val data = files[path] ?: throw IOException("missing")
            opened++
            return object : FolderZipWriter.FileReader {
                override val size: Long = data.size.toLong()
                override fun read(offset: Long, buffer: ByteArray, length: Int): Int {
                    val n = minOf(length, data.size - offset.toInt())
                    System.arraycopy(data, offset.toInt(), buffer, 0, n)
                    return n
                }
                override fun close() { closed++ }
            }
        }
    }

    private fun dir(name: String) = DirEntryWire.encode(name, true, 0, 1_700_000_000)
    private fun file(name: String, size: Int) = DirEntryWire.encode(name, false, size.toLong(), 1_700_000_000)

    private fun unzip(bytes: ByteArray): Map<String, ByteArray?> {
        val out = linkedMapOf<String, ByteArray?>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                out[entry.name] = if (entry.isDirectory) null else zip.readBytes()
            }
        }
        return out
    }

    /** End-of-central-directory signature: present iff the archive was finalized. */
    private fun isFinalized(bytes: ByteArray): Boolean =
        (0..bytes.size - 4).any {
            bytes[it] == 0x50.toByte() && bytes[it + 1] == 0x4b.toByte() &&
                bytes[it + 2] == 5.toByte() && bytes[it + 3] == 6.toByte()
        }

    private val big = ByteArray(700_000) { (it * 31).toByte() } // spans several read chunks

    private fun sampleVault() = FakeVault(
        dirs = mapOf(
            "Photos" to listOf(dir("trip"), dir("empty"), file("a.txt", 5), file("pw.password", 3), "System:OTHER"),
            "Photos/trip" to listOf(file("big.bin", big.size), dir("deep")),
            "Photos/trip/deep" to listOf(file("same.txt", 1)),
            "Photos/empty" to emptyList(),
        ),
        files = mapOf(
            "Photos/a.txt" to "hello".toByteArray(),
            "Photos/pw.password" to "secret".toByteArray(),
            "Photos/trip/big.bin" to big,
            "Photos/trip/deep/same.txt" to "z".toByteArray(),
        ),
    )

    @Test
    fun `archive is rooted at the folder name and keeps empty folders`() {
        val out = ByteArrayOutputStream()
        FolderZipWriter(sampleVault(), skipExtensions = setOf("password")).write("Photos", out)
        assertEquals(
            setOf(
                "Photos/", "Photos/trip/", "Photos/trip/deep/", "Photos/empty/",
                "Photos/a.txt", "Photos/trip/big.bin", "Photos/trip/deep/same.txt",
            ),
            unzip(out.toByteArray()).keys,
        )
    }

    @Test
    fun `file contents round-trip including files larger than one chunk`() {
        val out = ByteArrayOutputStream()
        FolderZipWriter(sampleVault()).write("Photos", out)
        val entries = unzip(out.toByteArray())
        assertEquals("hello", String(entries["Photos/a.txt"]!!))
        assertArrayEquals(big, entries["Photos/trip/big.bin"])
    }

    @Test
    fun `skipped extensions never reach the archive`() {
        val out = ByteArrayOutputStream()
        FolderZipWriter(sampleVault(), skipExtensions = setOf("password")).write("Photos", out)
        assertFalse(unzip(out.toByteArray()).containsKey("Photos/pw.password"))
    }

    @Test
    fun `a nested folder is archived under its own name`() {
        val out = ByteArrayOutputStream()
        FolderZipWriter(sampleVault()).write("Photos/trip", out)
        assertEquals("trip/", unzip(out.toByteArray()).keys.first())
    }

    @Test
    fun `every opened file is closed`() {
        val vault = sampleVault()
        FolderZipWriter(vault).write("Photos", ByteArrayOutputStream())
        assertEquals(vault.opened, vault.closed)
    }

    @Test
    fun `a truncated listing fails instead of producing a partial archive`() {
        val vault = FakeVault(
            dirs = mapOf("T" to listOf(file("a.txt", 1), "System:TRUNCATED")),
            files = mapOf("T/a.txt" to "a".toByteArray()),
        )
        val out = ByteArrayOutputStream()
        try {
            FolderZipWriter(vault).write("T", out)
            fail("expected IOException")
        } catch (_: IOException) {
        }
        assertFalse("failed archive must not be finalized", isFinalized(out.toByteArray()))
        assertEquals(vault.opened, vault.closed)
    }

    @Test
    fun `aborting stops promptly, releases the file and leaves the archive unfinalized`() {
        val vault = FakeVault(
            dirs = mapOf("A" to listOf(file("big.bin", big.size))),
            files = mapOf("A/big.bin" to big),
        )
        var polls = 0
        val out = ByteArrayOutputStream()
        try {
            FolderZipWriter(vault, shouldAbort = { ++polls > 3 }).write("A", out)
            fail("expected AbortedException")
        } catch (_: FolderZipWriter.AbortedException) {
        }
        assertEquals(vault.opened, vault.closed)
        assertFalse(isFinalized(out.toByteArray()))
    }

    @Test
    fun `an entry name containing a slash is refused`() {
        val vault = FakeVault(dirs = mapOf("U" to listOf(file("../evil", 1))))
        try {
            FolderZipWriter(vault).write("U", ByteArrayOutputStream())
            fail("expected IOException")
        } catch (_: IOException) {
        }
    }

    @Test
    fun `a file that shrinks mid-read fails instead of being silently truncated`() {
        val shrinking = object : FolderZipWriter.Source {
            override fun list(dirPath: String) = arrayOf(file("s.bin", 10))
            override fun openFile(path: String) = object : FolderZipWriter.FileReader {
                override val size = 10L
                override fun read(offset: Long, buffer: ByteArray, length: Int) = 0
                override fun close() {}
            }
        }
        try {
            FolderZipWriter(shrinking).write("S", ByteArrayOutputStream())
            fail("expected IOException")
        } catch (_: IOException) {
        }
    }

    @Test
    fun `a file of unknown size is read to end of stream`() {
        val data = ByteArray(600_000) { (it * 13).toByte() }
        val streaming = object : FolderZipWriter.Source {
            override fun list(dirPath: String) = arrayOf(file("cloud.bin", 0))
            override fun openFile(path: String) = object : FolderZipWriter.FileReader {
                override val size = FolderZipWriter.UNKNOWN_SIZE
                override fun read(offset: Long, buffer: ByteArray, length: Int): Int {
                    if (offset >= data.size) return 0
                    val n = minOf(length, data.size - offset.toInt(), 100_000)
                    System.arraycopy(data, offset.toInt(), buffer, 0, n)
                    return n
                }
                override fun close() {}
            }
        }
        val out = ByteArrayOutputStream()
        FolderZipWriter(streaming).write("S", out)
        assertArrayEquals(data, unzip(out.toByteArray())["S/cloud.bin"])
    }

    @Test
    fun `a size other than a length or UNKNOWN_SIZE is refused`() {
        val bad = object : FolderZipWriter.Source {
            override fun list(dirPath: String) = arrayOf(file("b.bin", 1))
            override fun openFile(path: String) = object : FolderZipWriter.FileReader {
                override val size = -5L
                override fun read(offset: Long, buffer: ByteArray, length: Int) = 0
                override fun close() {}
            }
        }
        try {
            FolderZipWriter(bad).write("S", ByteArrayOutputStream())
            fail("expected IOException")
        } catch (_: IOException) {
        }
    }

    @Test
    fun `the vault root cannot be archived`() {
        try {
            FolderZipWriter(sampleVault()).write("", ByteArrayOutputStream())
            fail("expected IOException")
        } catch (_: IOException) {
        }
    }

    @Test
    fun `a receiver hanging up mid-stream propagates as an IOException`() {
        var writes = 0
        val hangsUp = object : OutputStream() {
            override fun write(b: Int) { throw IOException("EPIPE") }
            override fun write(b: ByteArray, off: Int, len: Int) {
                if (++writes > 1) throw IOException("EPIPE")
            }
        }
        try {
            FolderZipWriter(sampleVault()).write("Photos", hangsUp)
            fail("expected IOException")
        } catch (_: IOException) {
        }
    }
}
