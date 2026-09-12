package com.aeidolon.vaultexplorer.container

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
 * is the one piece of plain logic in it -- whether to hide the in-container
 * thumbnail cache directory from anything browsing the vault via SAF -- so
 * it's the one thing covered here. Widened from `private` to `internal`
 * (visibility only, no logic touched) to make that possible; see this
 * file's other tests for the same pattern.
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
}
