package com.aeidolon.vaultexplorer.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * [BookCover.naturalCompare] must order names exactly as `naturalCompare` in
 * `comic_pages.dart` does (the first four tests are that file's own cases), or
 * a comic's thumbnail would not be the page the reader opens on.
 */
class BookCoverTest {

    private fun sorted(vararg names: String) = names.sortedWith { a, b -> BookCover.naturalCompare(a, b) }

    private fun directory(vararg names: String): ZipDirectory {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zos ->
            for (name in names) {
                zos.putNextEntry(ZipEntry(name))
                if (!name.endsWith("/")) zos.write(1)
                zos.closeEntry()
            }
        }
        return ZipReader.readDirectory(ByteArraySource(out.toByteArray()))
    }

    private fun covers(vararg names: String, limit: Int = 3) =
        BookCover.comicCoverCandidates(directory(*names), limit).map { it.name }

    // -- naturalCompare ----------------------------------------------------

    @Test
    fun `compares digit runs by value`() {
        assertEquals(
            listOf("page1.jpg", "page2.jpg", "page10.jpg", "page20.jpg"),
            sorted("page10.jpg", "page2.jpg", "page1.jpg", "page20.jpg"),
        )
    }

    @Test
    fun `is not thrown by leading zeros or differing widths`() {
        assertEquals(
            listOf("1.jpg", "002.jpg", "0003.jpg", "010.jpg"),
            sorted("010.jpg", "002.jpg", "1.jpg", "0003.jpg"),
        )
    }

    @Test
    fun `ignores case`() {
        assertEquals(listOf("A.jpg", "b.jpg", "c.jpg"), sorted("b.jpg", "A.jpg", "c.jpg"))
    }

    @Test
    fun `orders folders before their contents by path`() {
        assertEquals(
            listOf("ch1/01.jpg", "ch1/02.jpg", "ch2/01.jpg", "ch10/01.jpg"),
            sorted("ch2/01.jpg", "ch10/01.jpg", "ch1/02.jpg", "ch1/01.jpg"),
        )
    }

    @Test
    fun `is a consistent total order`() {
        assertEquals(0, BookCover.naturalCompare("a.jpg", "a.jpg"))
        assertNotEquals(0, BookCover.naturalCompare("A.jpg", "a.jpg"))
    }

    // -- comicCoverCandidates ---------------------------------------------

    @Test
    fun `the cover is the first page in natural order`() {
        assertEquals(
            listOf("1.webp", "2.jpg", "10.png"),
            covers("10.png", "2.jpg", "ComicInfo.xml", "1.webp", "notes.txt", "Thumbs.db"),
        )
    }

    @Test
    fun `skips macOS resource forks, hidden files and directories`() {
        assertEquals(
            listOf("001.jpg", "dir/003.jpg"),
            covers("__MACOSX/._001.jpg", "001.jpg", ".hidden/002.jpg", "dir/", "dir/.DS_Store", "dir/003.jpg"),
        )
    }

    @Test
    fun `offers at most the requested number of candidates`() {
        assertEquals(listOf("1.jpg", "2.jpg"), covers("3.jpg", "2.jpg", "1.jpg", "4.jpg", limit = 2))
        assertEquals(3, covers("1.jpg", "2.jpg", "3.jpg", "4.jpg", "5.jpg").size)
    }

    @Test
    fun `extension matching is case-insensitive and needs an actual extension`() {
        assertEquals(listOf("A.JPG", "b.PnG"), covers("b.PnG", "A.JPG", "jpg", "png."))
    }

    @Test
    fun `an archive with no images has no cover`() {
        assertTrue(covers("readme.txt", "a.xml").isEmpty())
        assertTrue(covers().isEmpty())
    }

    @Test
    fun `an unreadable first page can be skipped for the next`() {
        // Candidates are returned in order so the caller can fall through.
        val names = covers("p1.avif", "p2.jpg", "p3.jpg")
        assertEquals("p1.avif", names.first())
        assertTrue("p2.jpg" in names)
    }
}
