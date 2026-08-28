package com.aeidolon.vaultexplorer

import com.aeidolon.vaultexplorer.automation.GlobMatcher
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GlobMatcherTest {

    @Test
    fun `exact match without wildcards`() {
        val matcher = GlobMatcher.compile("document.pdf")
        assertTrue(matcher.matches("document.pdf"))
        assertFalse(matcher.matches("other.pdf"))
        assertFalse(matcher.matches("document.pdf.bak"))
    }

    @Test
    fun `case insensitivity by default`() {
        val matcher = GlobMatcher.compile("*.PDF")
        assertTrue(matcher.matches("document.pdf"))
        assertTrue(matcher.matches("REPORT.PDF"))
        assertTrue(matcher.matches("doc.Pdf"))
    }

    @Test
    fun `case sensitive option`() {
        val matcher = GlobMatcher.compile("*.PDF", caseSensitive = true)
        assertTrue(matcher.matches("REPORT.PDF"))
        assertFalse(matcher.matches("document.pdf"))
    }

    @Test
    fun `single asterisk wildcard does not cross directory separators`() {
        val matcher = GlobMatcher.compile("*.txt")
        assertTrue(matcher.matches("notes.txt"))
        assertTrue(matcher.matches("a.txt"))
        assertFalse(matcher.matches("dir/notes.txt"))
        assertFalse(matcher.matches("a/b/c.txt"))
    }

    @Test
    fun `globstar wildcard matches cross directory`() {
        val matcher = GlobMatcher.compile("**/*.pdf")
        assertTrue(matcher.matches("report.pdf"))
        assertTrue(matcher.matches("docs/report.pdf"))
        assertTrue(matcher.matches("a/b/c/report.pdf"))
        assertFalse(matcher.matches("a/b/c/report.docx"))
    }

    @Test
    fun `question mark matches single character`() {
        val matcher = GlobMatcher.compile("image_???.jpg")
        assertTrue(matcher.matches("image_001.jpg"))
        assertTrue(matcher.matches("image_abc.jpg"))
        assertFalse(matcher.matches("image_01.jpg"))
        assertFalse(matcher.matches("image_0001.jpg"))
        assertFalse(matcher.matches("image_a/b.jpg"))
    }

    @Test
    fun `character ranges and negations`() {
        val rangeMatcher = GlobMatcher.compile("file_[0-9].dat")
        assertTrue(rangeMatcher.matches("file_1.dat"))
        assertTrue(rangeMatcher.matches("file_9.dat"))
        assertFalse(rangeMatcher.matches("file_a.dat"))

        val negMatcher1 = GlobMatcher.compile("file_[!0-9].dat")
        assertTrue(negMatcher1.matches("file_a.dat"))
        assertFalse(negMatcher1.matches("file_1.dat"))

        val negMatcher2 = GlobMatcher.compile("file_[^0-9].dat")
        assertTrue(negMatcher2.matches("file_a.dat"))
        assertFalse(negMatcher2.matches("file_1.dat"))
    }

    @Test
    fun `braced group alternates`() {
        val matcher = GlobMatcher.compile("*.{jpg,jpeg,png,webp}")
        assertTrue(matcher.matches("photo.jpg"))
        assertTrue(matcher.matches("photo.jpeg"))
        assertTrue(matcher.matches("photo.png"))
        assertTrue(matcher.matches("photo.webp"))
        assertFalse(matcher.matches("photo.gif"))
        assertFalse(matcher.matches("photo.txt"))
    }

    @Test
    fun `escapes special regex characters in filenames`() {
        val matcher = GlobMatcher.compile("data (copy)+$1.txt")
        assertTrue(matcher.matches("data (copy)+$1.txt"))
        assertFalse(matcher.matches("data copy1.txt"))
    }

    @Test
    fun `handles leading and trailing slashes gracefully`() {
        val matcher = GlobMatcher.compile("/photos/*.jpg")
        assertTrue(matcher.matches("/photos/sunset.jpg"))
        assertTrue(matcher.matches("photos/sunset.jpg"))
        assertTrue(matcher.matches("photos/sunset.jpg/"))
    }

    @Test
    fun `handles null and empty patterns`() {
        val nullMatcher = GlobMatcher.compile(null)
        assertTrue(nullMatcher.matches("any/path/file.txt"))

        val blankMatcher = GlobMatcher.compile("  ")
        assertTrue(blankMatcher.matches("any/path/file.txt"))
    }

    @Test
    fun `complex wildcard patterns with directory prefixes`() {
        val matcher = GlobMatcher.compile("receipts/**/2026_*.{pdf,csv}")
        assertTrue(matcher.matches("receipts/jan/2026_01.pdf"))
        assertTrue(matcher.matches("receipts/q1/tax/2026_expenses.csv"))
        assertFalse(matcher.matches("receipts/jan/2025_01.pdf"))
        assertFalse(matcher.matches("invoices/jan/2026_01.pdf"))
    }
}
