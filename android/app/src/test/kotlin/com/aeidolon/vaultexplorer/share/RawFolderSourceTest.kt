package com.aeidolon.vaultexplorer.share

import com.aeidolon.vaultexplorer.container.FolderZipWriter
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.zip.ZipInputStream

/**
 * RawFolderSource backs sharing a folder from the decoy's local storage
 * explorer. It runs against a real temp directory rather than a fake: the
 * whole point is that it turns what's actually on disk into the wire format
 * and bytes FolderZipWriter expects.
 */
class RawFolderSourceTest {

    private fun withTree(block: (File) -> Unit) {
        val root = Files.createTempDirectory("rawfoldersource").toFile()
        try {
            block(root)
        } finally {
            root.deleteRecursively()
        }
    }

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

    @Test
    fun `a directory on disk archives with its structure and contents`() = withTree { root ->
        val big = ByteArray(600_000) { (it * 7).toByte() }
        val album = File(root, "Album").apply { mkdir() }
        File(album, "note.txt").writeText("hello")
        File(album, "empty").mkdir()
        File(File(album, "sub").apply { mkdir() }, "big.bin").writeBytes(big)

        val out = ByteArrayOutputStream()
        FolderZipWriter(RawFolderSource()).write(album.absolutePath, out)
        val entries = unzip(out.toByteArray())

        assertEquals(
            setOf("Album/", "Album/empty/", "Album/sub/", "Album/note.txt", "Album/sub/big.bin"),
            entries.keys,
        )
        assertEquals("hello", String(entries["Album/note.txt"]!!))
        assertArrayEquals(big, entries["Album/sub/big.bin"])
    }

    @Test
    fun `an empty file is archived as an empty entry`() = withTree { root ->
        val dir = File(root, "D").apply { mkdir() }
        File(dir, "zero.bin").createNewFile()

        val out = ByteArrayOutputStream()
        FolderZipWriter(RawFolderSource()).write(dir.absolutePath, out)

        assertEquals(0, unzip(out.toByteArray())["D/zero.bin"]!!.size)
    }

    @Test
    fun `listing a missing directory reports it as unlistable`() = withTree { root ->
        assertEquals(null, RawFolderSource().list(File(root, "nope").absolutePath))
    }

    @Test
    fun `sharing a folder that vanished fails instead of producing an empty archive`() = withTree { root ->
        try {
            FolderZipWriter(RawFolderSource()).write(File(root, "gone").absolutePath, ByteArrayOutputStream())
            fail("expected IOException")
        } catch (_: IOException) {
        }
    }

    @Test
    fun `opening a missing file throws`() = withTree { root ->
        try {
            RawFolderSource().openFile(File(root, "missing.bin").absolutePath)
            fail("expected IOException")
        } catch (_: IOException) {
        }
    }
}
