package com.aeidolon.vaultexplorer.saf

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [PendingListingChanges] corrects a provider's stale folder listing right
 * after a server-side move/copy (RSAF answers from a directory cache that the
 * move bypasses). These cover the three ways a record ends: the provider
 * catches up, the app changes the entry itself, or the time limit passes --
 * and the "is the provider ready for this entry yet" bookkeeping that lets
 * size/read/thumbnail requests wait for it instead of failing.
 */
class PendingListingChangesTest {
    private fun entry(name: String, size: Long = 1L) =
        SafEntry(name, isDir = false, size = size, lastModified = 0L, docId = "doc:$name", mimeType = "text/plain")

    private fun names(list: List<SafEntry>) = list.map { it.name }.sorted()

    @Test
    fun movedOutEntryStaysHiddenWhileTheProviderStillListsIt() {
        val pending = PendingListingChanges()
        pending.expectRemoved("a.txt", expiresAt = 100L)

        val stale = listOf(entry("a.txt"), entry("b.txt"))
        assertEquals(listOf("b.txt"), names(pending.reconcile(stale, now = 10L)))
        // Still pending: a second stale listing is corrected the same way.
        assertFalse(pending.isEmpty())
        assertEquals(listOf("b.txt"), names(pending.reconcile(stale, now = 20L)))
    }

    @Test
    fun movedOutEntryIsForgottenOnceTheProviderNoLongerListsIt() {
        val pending = PendingListingChanges()
        pending.expectRemoved("a.txt", expiresAt = 100L)

        val fresh = listOf(entry("b.txt"))
        assertEquals(listOf("b.txt"), names(pending.reconcile(fresh, now = 10L)))
        assertTrue(pending.isEmpty())

        // A file the user later puts back under that name must not be hidden.
        assertEquals(listOf("a.txt", "b.txt"), names(pending.reconcile(listOf(entry("a.txt"), entry("b.txt")), now = 11L)))
    }

    @Test
    fun movedInEntryIsInjectedUntilTheProviderListsIt() {
        val pending = PendingListingChanges()
        pending.expectAdded(entry("new.txt", size = 42L), expiresAt = 100L)

        val stale = listOf(entry("b.txt"))
        val shown = pending.reconcile(stale, now = 10L)
        assertEquals(listOf("b.txt", "new.txt"), names(shown))
        assertEquals(42L, shown.first { it.name == "new.txt" }.size)

        // The provider's own entry wins as soon as it exists, and tracking ends.
        val fresh = listOf(entry("b.txt"), entry("new.txt", size = 40L))
        val confirmed = pending.reconcile(fresh, now = 11L)
        assertEquals(40L, confirmed.first { it.name == "new.txt" }.size)
        assertTrue(pending.isEmpty())
    }

    @Test
    fun changingTheEntryAgainVoidsTheExpectation() {
        val pending = PendingListingChanges()
        pending.expectRemoved("a.txt", expiresAt = 100L)
        pending.forget("a.txt")

        assertEquals(listOf("a.txt"), names(pending.reconcile(listOf(entry("a.txt")), now = 10L)))
        assertTrue(pending.isEmpty())
    }

    @Test
    fun expectationsEndAtTheirDeadline() {
        val pending = PendingListingChanges()
        pending.expectRemoved("a.txt", expiresAt = 100L)
        pending.expectAdded(entry("new.txt"), expiresAt = 100L)

        val stale = listOf(entry("a.txt"))
        assertEquals(listOf("a.txt"), names(pending.reconcile(stale, now = 100L)))
        assertTrue(pending.isEmpty())
    }

    @Test
    fun aLaterExpectationReplacesAnEarlierOneForTheSameName() {
        val pending = PendingListingChanges()
        pending.expectAdded(entry("x.txt"), expiresAt = 100L)
        pending.expectRemoved("x.txt", expiresAt = 100L)

        // Added then moved away again: it must not be injected.
        assertEquals(emptyList<String>(), names(pending.reconcile(emptyList(), now = 10L)))
    }

    @Test
    fun anAddedEntryIsAwaitedUntilTheProviderAnswersForIt() {
        val pending = PendingListingChanges()
        pending.expectAdded(entry("m.heic", size = 7L), expiresAt = 100L)

        assertTrue(pending.awaitingProvider("m.heic", now = 10L))
        assertEquals(7L, pending.addedEntry("m.heic", now = 10L)?.size)
        assertFalse(pending.awaitingProvider("other.heic", now = 10L))

        pending.stopAwaiting("m.heic")
        assertFalse(pending.awaitingProvider("m.heic", now = 10L))
        // Nobody waits any more, but the user keeps seeing the entry.
        assertEquals(listOf("m.heic"), names(pending.reconcile(emptyList(), now = 11L)))
    }

    @Test
    fun waitingAndInjectionBothEndAtTheDeadline() {
        val pending = PendingListingChanges()
        pending.expectAdded(entry("a.txt"), expiresAt = 100L)

        assertTrue(pending.awaitingProvider("a.txt", now = 99L))
        assertFalse(pending.awaitingProvider("a.txt", now = 100L))
        assertEquals("a.txt", pending.addedEntry("a.txt", now = 99L)?.name)
        assertEquals(null, pending.addedEntry("a.txt", now = 100L))
    }

    @Test
    fun aNewExpectationForTheSameNameWaitsAgain() {
        val pending = PendingListingChanges()
        pending.expectAdded(entry("a.txt"), expiresAt = 100L)
        pending.stopAwaiting("a.txt")
        pending.expectAdded(entry("a.txt"), expiresAt = 200L)

        assertTrue(pending.awaitingProvider("a.txt", now = 10L))
    }

    @Test
    fun theProviderCatchingUpEndsTheWaitTooAndAReAddWaitsAgain() {
        val pending = PendingListingChanges()
        pending.expectAdded(entry("a.txt"), expiresAt = 100L)
        pending.stopAwaiting("a.txt")

        pending.reconcile(listOf(entry("a.txt")), now = 5L)
        assertTrue(pending.isEmpty())
        assertFalse(pending.awaitingProvider("a.txt", now = 5L))

        pending.expectAdded(entry("a.txt"), expiresAt = 100L)
        assertTrue(pending.awaitingProvider("a.txt", now = 6L))
    }

    @Test
    fun aTimedOutWaitReleasesEveryOtherWaiterInTheFolder() {
        val pending = PendingListingChanges()
        pending.expectAdded(entry("a.txt"), expiresAt = 100L)
        pending.expectAdded(entry("b.txt"), expiresAt = 100L)

        pending.stopAwaitingAll()

        assertFalse(pending.awaitingProvider("a.txt", now = 1L))
        assertFalse(pending.awaitingProvider("b.txt", now = 1L))
        assertEquals(listOf("a.txt", "b.txt"), names(pending.reconcile(emptyList(), now = 2L)))
    }

    @Test
    fun aMovedAwayEntryIsReportedAsRemovedUntilItsDeadline() {
        val pending = PendingListingChanges()
        pending.expectRemoved("a.txt", expiresAt = 100L)

        assertTrue(pending.isRemoved("a.txt", now = 99L))
        assertFalse(pending.isRemoved("a.txt", now = 100L))
        assertFalse(pending.isRemoved("b.txt", now = 1L))
    }

    @Test
    fun removingAnEntryEndsTheWaitForItsEarlierAdd() {
        val pending = PendingListingChanges()
        pending.expectAdded(entry("a.txt"), expiresAt = 100L)
        pending.expectRemoved("a.txt", expiresAt = 100L)

        assertFalse(pending.awaitingProvider("a.txt", now = 1L))
        assertEquals(null, pending.addedEntry("a.txt", now = 1L))
    }
}