package com.aeidolon.vaultexplorer.container

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * ContainerDocumentsProvider is the SAF DocumentsProvider that exposes an
 * unlocked vault to other apps; almost every method on it either builds a
 * Cursor or calls into native container code, which makes most of the
 * class unreachable from a bare-JVM test (see the tech-debt audit that
 * flagged this file's zero coverage in the first place). isReservedCachePath
 * and documentIdChain are the pieces of plain logic in it -- respectively,
 * whether to hide the in-container thumbnail cache directory from anything
 * browsing the vault via SAF, and building the ancestor-chain document IDs
 * findDocumentPath hands back -- so they're what's covered here. Both
 * widened from `private` to `internal` (visibility only, no logic touched)
 * to make this possible; see this file's tests for the same pattern.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class ContainerDocumentsProviderTest {

    private val provider = ContainerDocumentsProvider()

    @Test
    fun `the cache directory itself is reserved`() {
        assertTrue(provider.isReservedCachePath(".thumbcache"))
    }

    @Test
    fun `anything inside the cache directory is reserved`() {
        assertTrue(provider.isReservedCachePath(".thumbcache/abc123.jpg"))
        assertTrue(provider.isReservedCachePath(".thumbcache/nested/deeper.jpg"))
    }

    @Test
    fun `ordinary files and folders are not reserved`() {
        assertFalse(provider.isReservedCachePath("Documents"))
        assertFalse(provider.isReservedCachePath("photo.jpg"))
        assertFalse(provider.isReservedCachePath(""))
    }

    @Test
    fun `a user folder named thumbcache elsewhere in the tree is not reserved`() {
        // Matched against the *full* path -- only the reserved root-level
        // directory and its contents are hidden, per isReservedCachePath's
        // own doc comment.
        assertFalse(provider.isReservedCachePath("Documents/.thumbcache"))
        assertFalse(provider.isReservedCachePath("Documents/.thumbcache/file.jpg"))
    }

    @Test
    fun `a similarly-named but distinct directory is not reserved`() {
        // Starts with the reserved name but isn't it or a child of it --
        // must not match on a bare prefix check.
        assertFalse(provider.isReservedCachePath(".thumbcache2"))
        assertFalse(provider.isReservedCachePath(".thumbcacheextra/file.jpg"))
    }

    // documentIdChain -- no session is registered for any volId in these
    // tests, so DocumentId.toString()'s stableId lookup falls through to
    // its documented fallback (the bare volId), same as it would for a
    // document ID stringified after its session has already vanished.
    // That fallback is deterministic, which is what makes this function
    // testable without standing up a fake ContainerSession at all.

    @Test
    fun `root itself has no chain`() {
        assertTrue(provider.documentIdChain(3, "", "dir").isEmpty())
    }

    @Test
    fun `a top-level file is a chain of one`() {
        assertEquals(
            listOf("5:file:notes.md"),
            provider.documentIdChain(5, "notes.md", "file")
        )
    }

    @Test
    fun `a nested file's chain includes every ancestor folder as dir`() {
        assertEquals(
            listOf("2:dir:Folder", "2:dir:Folder/Sub", "2:file:Folder/Sub/notes.md"),
            provider.documentIdChain(2, "Folder/Sub/notes.md", "file")
        )
    }

    @Test
    fun `a nested folder's own chain ends with itself typed as the leaf`() {
        // Requesting the path *to a folder* rather than a file inside it --
        // the leaf entry should still carry leafType, not be hardcoded dir.
        assertEquals(
            listOf("2:dir:A", "2:dir:A/B"),
            provider.documentIdChain(2, "A/B", "dir")
        )
    }
}