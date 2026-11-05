package com.aeidolon.vaultexplorer

import com.aeidolon.vaultexplorer.handlers.CategoryIndexQuery
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CategoryIndexQueryTest {

    @Test
    fun `extensions are lower-cased, stripped of a leading dot and de-duplicated`() {
        val result = CategoryIndexQuery.sanitizeExtensions(listOf("JPG", ".png", "Mp4", "jpg", " gif "))
        assertEquals(listOf("jpg", "png", "mp4", "gif"), result)
    }

    @Test
    fun `anything that is not a plain extension is dropped, never escaped`() {
        val result = CategoryIndexQuery.sanitizeExtensions(
            listOf("", ".", "a/b", "x y", "%", "_", "j_pg", "tar.gz", "m4a", "3gp"),
        )
        assertEquals(listOf("m4a", "3gp"), result)
    }

    @Test
    fun `the prefix always ends in exactly one slash`() {
        assertEquals("/storage/emulated/0/", CategoryIndexQuery.prefixFor("/storage/emulated/0"))
        assertEquals("/storage/emulated/0/", CategoryIndexQuery.prefixFor("/storage/emulated/0/"))
        assertEquals("/", CategoryIndexQuery.prefixFor("/"))
    }

    @Test
    fun `selection has one placeholder for the root and one per extension`() {
        val sql = CategoryIndexQuery.selection("_data", 3)
        assertEquals("_data LIKE ? AND (_data LIKE ? OR _data LIKE ? OR _data LIKE ?)", sql)
        assertEquals(4, sql.count { it == '?' })
    }

    @Test
    fun `a single extension needs no OR`() {
        assertEquals("_data LIKE ? AND (_data LIKE ?)", CategoryIndexQuery.selection("_data", 1))
    }

    @Test
    fun `selection with no extension is refused rather than producing invalid SQL`() {
        var refused = false
        try {
            CategoryIndexQuery.selection("_data", 0)
        } catch (e: IllegalArgumentException) {
            refused = true
        }
        assertTrue(refused)
    }

    @Test
    fun `arguments are the root prefix then a suffix pattern per extension, matching the placeholders`() {
        val args = CategoryIndexQuery.selectionArgs("/storage/emulated/0", listOf("jpg", "png"))
        assertEquals(listOf("/storage/emulated/0/%", "%.jpg", "%.png"), args.toList())
        assertEquals(
            CategoryIndexQuery.selection("_data", 2).count { it == '?' },
            args.size,
        )
    }

    @Test
    fun `a path under the root is made relative to it`() {
        assertEquals(
            "DCIM/Camera/a.jpg",
            CategoryIndexQuery.relativePath("/storage/emulated/0", "/storage/emulated/0/DCIM/Camera/a.jpg"),
        )
        assertEquals("a.jpg", CategoryIndexQuery.relativePath("/storage/emulated/0/", "/storage/emulated/0/a.jpg"))
    }

    @Test
    fun `wildcard look-alikes of the root are rejected by the exact check`() {
        // `_` in a LIKE pattern matches any character, so the query can return
        // "My-Folder" for a root of "My_Folder"; only the exact check removes it.
        assertNull(CategoryIndexQuery.relativePath("/sdcard/My_Folder", "/sdcard/My-Folder/a.jpg"))
        assertEquals("a.jpg", CategoryIndexQuery.relativePath("/sdcard/My_Folder", "/sdcard/My_Folder/a.jpg"))
    }

    @Test
    fun `a sibling that merely starts with the root name is not under it`() {
        assertNull(CategoryIndexQuery.relativePath("/sdcard/Pictures", "/sdcard/Pictures2/a.jpg"))
    }

    @Test
    fun `the root itself and paths outside it have no relative form`() {
        assertNull(CategoryIndexQuery.relativePath("/sdcard/Pictures", "/sdcard/Pictures"))
        assertNull(CategoryIndexQuery.relativePath("/sdcard/Pictures", "/sdcard/Pictures/"))
        assertNull(CategoryIndexQuery.relativePath("/sdcard/Pictures", "/other/a.jpg"))
    }

    @Test
    fun `matching on the root is case sensitive`() {
        assertNull(CategoryIndexQuery.relativePath("/sdcard/Pictures", "/sdcard/pictures/a.jpg"))
    }
}
