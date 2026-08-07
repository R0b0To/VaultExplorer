package com.aeidolon.vaultexplorer.saf

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * These four functions were previously hand-duplicated, byte-identical,
 * across CryptomatorSession/GocryptfsSession/CryfsSession. Pinning the
 * behavior here means a future change only needs to happen once, and any
 * accidental behavior drift shows up immediately instead of only in
 * whichever vault format someone happened to be testing by hand.
 */
class VaultPathUtilsTest {

    @Test
    fun `normalize strips leading and trailing slashes only`() {
        assertEquals("a/b/c", VaultPathUtils.normalize("/a/b/c/"))
        assertEquals("a/b/c", VaultPathUtils.normalize("a/b/c"))
        assertEquals("", VaultPathUtils.normalize("/"))
        assertEquals("", VaultPathUtils.normalize(""))
        // Interior slashes are untouched, including doubled ones.
        assertEquals("a//b", VaultPathUtils.normalize("/a//b/"))
    }

    @Test
    fun `parentOf returns empty string for a top-level entry`() {
        assertEquals("", VaultPathUtils.parentOf("file.txt"))
    }

    @Test
    fun `parentOf returns everything before the last slash`() {
        assertEquals("a/b", VaultPathUtils.parentOf("a/b/c.txt"))
        assertEquals("a", VaultPathUtils.parentOf("a/b"))
    }

    @Test
    fun `nameOf returns the whole string when there is no slash`() {
        assertEquals("file.txt", VaultPathUtils.nameOf("file.txt"))
    }

    @Test
    fun `nameOf returns everything after the last slash`() {
        assertEquals("c.txt", VaultPathUtils.nameOf("a/b/c.txt"))
    }

    @Test
    fun `nameOf on a trailing-slash-normalized path with no basename returns empty string`() {
        // normalize() already strips trailing slashes before nameOf ever
        // sees a path in real call sites, but nameOf's own contract for an
        // already-empty parent segment (e.g. "a/") should still resolve
        // predictably rather than throw.
        assertEquals("", VaultPathUtils.nameOf("a/"))
    }

    @Test
    fun `joinPath joins with a single slash`() {
        assertEquals("a/b", VaultPathUtils.joinPath("a", "b"))
    }

    @Test
    fun `joinPath with empty parent returns just the name (root-level join)`() {
        assertEquals("b", VaultPathUtils.joinPath("", "b"))
    }

    @Test
    fun `parentOf and nameOf are inverses of joinPath for a normalized path`() {
        val path = VaultPathUtils.normalize("/photos/2026/summer.jpg")
        val rejoined = VaultPathUtils.joinPath(VaultPathUtils.parentOf(path), VaultPathUtils.nameOf(path))
        assertEquals(path, rejoined)
    }
}
