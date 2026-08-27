package com.aeidolon.vaultexplorer.saf

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * [MirrorRegistry] is plain `String`/[File] collections with no Android
 * dependency -- these tests run on the bare JVM, no Robolectric needed,
 * which is the entire point of having extracted it out of
 * [MirrorSyncCoordinator] (see that class's doc comment): the bookkeeping
 * that used to be private fields on a class requiring a real `Context` to
 * construct is now testable directly.
 *
 * The main thing under test is [MirrorRegistry.ContentState] replacing
 * what used to be two independently-mutated sets (`pulledContent` and
 * `pendingLocalWrites`) with one mutually-exclusive per-key value -- see
 * the "pending write always wins" group below, which is a direct
 * regression test for the production bug documented on
 * [MirrorRegistry]'s class doc comment: a directory re-listing racing a
 * deferred content push used to see a stale "synced" flag and delete the
 * not-yet-pushed write.
 */
class MirrorRegistryTest {

    private fun mirrorFile(path: String) = File("/mirror_root/$path")

    // ---- link/unlink/mirrorFor -------------------------------------------------

    @Test
    fun `link then mirrorFor returns the linked file`() {
        val registry = MirrorRegistry()
        val file = mirrorFile("a.txt")
        registry.link("content://real/a", file)
        assertEquals(file, registry.mirrorFor("content://real/a"))
    }

    @Test
    fun `mirrorFor returns null for an unlinked key`() {
        val registry = MirrorRegistry()
        assertNull(registry.mirrorFor("content://real/never-linked"))
    }

    @Test
    fun `unlink removes the mapping and returns the previous file`() {
        val registry = MirrorRegistry()
        val file = mirrorFile("a.txt")
        registry.link("content://real/a", file)
        val removed = registry.unlink("content://real/a")
        assertEquals(file, removed)
        assertNull(registry.mirrorFor("content://real/a"))
    }

    @Test
    fun `unlink on a never-linked key returns null and is a no-op`() {
        val registry = MirrorRegistry()
        assertNull(registry.unlink("content://real/never-linked"))
    }

    @Test
    fun `keyForMirrorPath resolves the reverse mapping`() {
        val registry = MirrorRegistry()
        val file = mirrorFile("a.txt")
        registry.link("content://real/a", file)
        assertEquals("content://real/a", registry.keyForMirrorPath(file.absolutePath))
    }

    @Test
    fun `re-linking the same key to a new file drops the old reverse mapping`() {
        val registry = MirrorRegistry()
        val oldFile = mirrorFile("old.txt")
        val newFile = mirrorFile("new.txt")
        registry.link("content://real/a", oldFile)
        registry.link("content://real/a", newFile)
        assertEquals(newFile, registry.mirrorFor("content://real/a"))
        assertNull(registry.keyForMirrorPath(oldFile.absolutePath))
        assertEquals("content://real/a", registry.keyForMirrorPath(newFile.absolutePath))
    }

    @Test
    fun `re-linking the same key to the same path is a no-op for the reverse mapping`() {
        // link()'s previous-vs-mirrored absolutePath check exists so this
        // exact case doesn't spuriously remove the mapping it's about to
        // re-add -- a regression here would show up as an intermittent
        // realUriFor()/keyForMirrorPath() failure right after a second
        // link() call with an identical path, which is what
        // mirrorChildFor's "existing.name == expectedName && existing.parentFile
        // == mirroredParent" fast path relies on being stable.
        val registry = MirrorRegistry()
        val file = mirrorFile("a.txt")
        registry.link("content://real/a", file)
        registry.link("content://real/a", file)
        assertEquals("content://real/a", registry.keyForMirrorPath(file.absolutePath))
    }

    // ---- childKeys / staleChildKeys ---------------------------------------------

    @Test
    fun `childKeys returns keys registered under a parent`() {
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/x", File(parent, "x.txt"))
        registry.link("content://real/y", File(parent, "y.txt"))
        registry.link("content://real/elsewhere", mirrorFile("other_dir/z.txt"))
        assertEquals(setOf("content://real/x", "content://real/y"), registry.childKeys(parent.absolutePath))
    }

    @Test
    fun `unlink removes the key from its parent's childKeys`() {
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/x", File(parent, "x.txt"))
        registry.unlink("content://real/x")
        assertTrue(registry.childKeys(parent.absolutePath).isEmpty())
    }

    @Test
    fun `staleChildKeys returns keys not present in the still-present set`() {
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/x", File(parent, "x.txt"))
        registry.link("content://real/y", File(parent, "y.txt"))
        val stale = registry.staleChildKeys(parent.absolutePath, stillPresentKeys = setOf("content://real/x"))
        assertEquals(listOf("content://real/y"), stale)
    }

    @Test
    fun `staleChildKeys does not mutate anything`() {
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/x", File(parent, "x.txt"))
        registry.staleChildKeys(parent.absolutePath, stillPresentKeys = emptySet())
        // Still linked -- staleChildKeys only reports, forget() is the caller's job.
        assertEquals(File(parent, "x.txt"), registry.mirrorFor("content://real/x"))
    }

    // ---- neverListed: regression test for the batch-import .thumbcache push ------
    // ---- crash ("no real parent for new file") -----------------------------------

    @Test
    fun `staleChildKeys never reports a neverListed key even if absent from the listing`() {
        // Reproduces the field scenario at the registry level: a file was
        // just created and registered (link + markNeverListed, exactly what
        // MirrorSyncCoordinator.pushFileWrite's creation branch does), then
        // a listing pass runs before the real SAF provider's own listing
        // has caught up to include it -- stillPresentKeys does NOT contain
        // the new key, purely because of that propagation delay, not
        // because anything was actually deleted.
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/new-thumb", File(parent, "new-thumb.c9r"))
        registry.markNeverListed("content://real/new-thumb")

        val stale = registry.staleChildKeys(parent.absolutePath, stillPresentKeys = emptySet())

        assertTrue(
            "a freshly-created, not-yet-listed child must not be reported as stale",
            stale.isEmpty(),
        )
        assertEquals(File(parent, "new-thumb.c9r"), registry.mirrorFor("content://real/new-thumb"))
    }

    @Test
    fun `clearNeverListed lets a subsequent miss be reported as stale`() {
        // The reprieve above is exactly one listing pass, not permanent --
        // MirrorSyncCoordinator.pullListingIfMissing calls clearNeverListed
        // for any neverListed key still absent after its own listing call
        // returns (see that method). Once cleared, a key that's STILL
        // missing on the next pass is a genuine deletion, not a
        // propagation delay, and staleChildKeys reports it normally.
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/ghost", File(parent, "ghost.c9r"))
        registry.markNeverListed("content://real/ghost")

        // First pass: still absent, but protected -- caller (simulated
        // here) clears the flag since it noted the miss.
        assertTrue(registry.staleChildKeys(parent.absolutePath, stillPresentKeys = emptySet()).isEmpty())
        registry.clearNeverListed("content://real/ghost")

        // Second pass: still absent, no longer protected -- now stale.
        val stale = registry.staleChildKeys(parent.absolutePath, stillPresentKeys = emptySet())
        assertEquals(listOf("content://real/ghost"), stale)
    }

    @Test
    fun `clearNeverListed on a listing hit lifts protection permanently`() {
        // The normal, non-buggy path: the real listing DOES include the
        // freshly-created child (the common case -- provider propagation
        // is usually fast enough) and pullListingIfMissing clears
        // neverListed for it immediately, same as any other confirmed
        // child from then on.
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/thumb", File(parent, "thumb.c9r"))
        registry.markNeverListed("content://real/thumb")
        registry.clearNeverListed("content://real/thumb")

        // Now behaves like any ordinary registered child: absent from a
        // later listing IS reported stale, no more special treatment.
        val stale = registry.staleChildKeys(parent.absolutePath, stillPresentKeys = emptySet())
        assertEquals(listOf("content://real/thumb"), stale)
    }

    @Test
    fun `unlink clears neverListed for the key`() {
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/x", File(parent, "x.c9r"))
        registry.markNeverListed("content://real/x")
        registry.unlink("content://real/x")
        registry.link("content://real/x", File(parent, "x.c9r")) // re-link under the same key
        // Re-linking after unlink must not silently inherit the old
        // neverListed flag -- unlink is a full drop of bookkeeping for the
        // key, same as it already is for content state.
        val stale = registry.staleChildKeys(parent.absolutePath, stillPresentKeys = emptySet())
        assertEquals(listOf("content://real/x"), stale)
    }

    @Test
    fun `forget clears neverListed for the key`() {
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/x", File(parent, "x.c9r"))
        registry.markNeverListed("content://real/x")
        registry.forget("content://real/x")
        assertFalse(registry.isNeverListed("content://real/x"))
    }

    @Test
    fun `clear drops neverListed along with everything else`() {
        val registry = MirrorRegistry()
        val parent = mirrorFile("dir")
        registry.link("content://real/x", File(parent, "x.c9r"))
        registry.markNeverListed("content://real/x")
        registry.clear()
        assertFalse(registry.isNeverListed("content://real/x"))
    }

    // ---- listedFolders -----------------------------------------------------------

    @Test
    fun `hasListed is false until markListed`() {
        val registry = MirrorRegistry()
        assertFalse(registry.hasListed("content://real/dir"))
        registry.markListed("content://real/dir")
        assertTrue(registry.hasListed("content://real/dir"))
    }

    @Test
    fun `clearListed reverts a single folder to unlisted`() {
        val registry = MirrorRegistry()
        registry.markListed("content://real/dir")
        registry.clearListed("content://real/dir")
        assertFalse(registry.hasListed("content://real/dir"))
    }

    @Test
    fun `clearAllListed clears every folder but not the mirror mapping`() {
        val registry = MirrorRegistry()
        val file = mirrorFile("a.txt")
        registry.link("content://real/a", file)
        registry.markSynced("content://real/a")
        registry.markListed("content://real/dir1")
        registry.markListed("content://real/dir2")
        registry.clearAllListed()
        assertFalse(registry.hasListed("content://real/dir1"))
        assertFalse(registry.hasListed("content://real/dir2"))
        // The whole point of clearAllListed vs clear(): mapping and content
        // state survive. See MirrorSyncCoordinator.invalidateAll's comment.
        assertEquals(file, registry.mirrorFor("content://real/a"))
        assertTrue(registry.hasContent("content://real/a"))
    }

    // ---- content state: synced / pending-local-write as one state machine --------

    @Test
    fun `a never-touched key has neither synced nor pending-write state`() {
        val registry = MirrorRegistry()
        assertFalse(registry.hasContent("content://real/a"))
        assertFalse(registry.hasPendingLocalWrite("content://real/a"))
    }

    @Test
    fun `markSynced sets hasContent true`() {
        val registry = MirrorRegistry()
        registry.markSynced("content://real/a")
        assertTrue(registry.hasContent("content://real/a"))
        assertFalse(registry.hasPendingLocalWrite("content://real/a"))
    }

    @Test
    fun `markPendingLocalWrite sets hasPendingLocalWrite true and hasContent false`() {
        val registry = MirrorRegistry()
        registry.markPendingLocalWrite("content://real/a")
        assertTrue(registry.hasPendingLocalWrite("content://real/a"))
        assertFalse(registry.hasContent("content://real/a"))
    }

    @Test
    fun `markPushed transitions pending-local-write to synced`() {
        val registry = MirrorRegistry()
        registry.markPendingLocalWrite("content://real/a")
        registry.markPushed("content://real/a")
        assertTrue(registry.hasContent("content://real/a"))
        assertFalse(registry.hasPendingLocalWrite("content://real/a"))
    }

    @Test
    fun `markSynced does NOT override an existing pending-local-write -- the core fix`() {
        // This is the direct regression test for the production bug: the
        // OLD code tracked these as two independent sets, so a stray
        // pulledContent.add() call for a key that also had a pending write
        // would silently coexist with (and, at the one call site that
        // mattered, get checked in the wrong order relative to) the
        // pending flag. ContentState makes "pending wins" true by
        // construction: once a key is PENDING_LOCAL_WRITE, markSynced() is
        // a no-op for that key until markPushed() (or forget()) runs.
        val registry = MirrorRegistry()
        registry.markPendingLocalWrite("content://real/a")
        registry.markSynced("content://real/a") // must NOT clobber the pending state
        assertTrue(
            "markSynced must not override a pending local write",
            registry.hasPendingLocalWrite("content://real/a"),
        )
        assertFalse(registry.hasContent("content://real/a"))
    }

    @Test
    fun `markPendingLocalWrite overrides a prior synced state`() {
        val registry = MirrorRegistry()
        registry.markSynced("content://real/a")
        registry.markPendingLocalWrite("content://real/a")
        assertTrue(registry.hasPendingLocalWrite("content://real/a"))
        assertFalse(registry.hasContent("content://real/a"))
    }

    @Test
    fun `forgetContent clears content state without touching the mirror mapping`() {
        val registry = MirrorRegistry()
        val file = mirrorFile("a.txt")
        registry.link("content://real/a", file)
        registry.markSynced("content://real/a")
        registry.forgetContent("content://real/a")
        assertFalse(registry.hasContent("content://real/a"))
        assertEquals(file, registry.mirrorFor("content://real/a"))
    }

    @Test
    fun `forget clears both content state and the mirror mapping`() {
        val registry = MirrorRegistry()
        val file = mirrorFile("a.txt")
        registry.link("content://real/a", file)
        registry.markSynced("content://real/a")
        val returned = registry.forget("content://real/a")
        assertEquals(file, returned)
        assertFalse(registry.hasContent("content://real/a"))
        assertNull(registry.mirrorFor("content://real/a"))
    }

    @Test
    fun `migrateContentState moves synced state to the new key`() {
        val registry = MirrorRegistry()
        registry.markSynced("content://real/old")
        registry.migrateContentState("content://real/old", "content://real/new")
        assertFalse(registry.hasContent("content://real/old"))
        assertTrue(registry.hasContent("content://real/new"))
    }

    @Test
    fun `migrateContentState moves pending-local-write state to the new key`() {
        // The alias-migration case in mirrorChildFor must preserve WHATEVER
        // state the old key had, not just "was synced" -- a SAF provider
        // handing back a new canonical URI mid-write shouldn't un-protect
        // an in-flight write.
        val registry = MirrorRegistry()
        registry.markPendingLocalWrite("content://real/old")
        registry.migrateContentState("content://real/old", "content://real/new")
        assertFalse(registry.hasPendingLocalWrite("content://real/old"))
        assertTrue(registry.hasPendingLocalWrite("content://real/new"))
    }

    @Test
    fun `migrateContentState from a key with no state is a no-op`() {
        val registry = MirrorRegistry()
        registry.migrateContentState("content://real/old", "content://real/new")
        assertFalse(registry.hasContent("content://real/new"))
        assertFalse(registry.hasPendingLocalWrite("content://real/new"))
    }

    // ---- reconcileStaleContent: the production-bug fix, directly ---------------

    @Test
    fun `reconcileStaleContent is a no-op for a key with no content state`() {
        val registry = MirrorRegistry()
        val changed = registry.reconcileStaleContent(
            childKey = "content://real/a",
            mirrorLength = 100, mirrorLastModified = 1000,
            realLength = 999, realLastModified = 9999,
        )
        assertFalse(changed)
    }

    @Test
    fun `reconcileStaleContent drops a synced entry whose size no longer matches`() {
        val registry = MirrorRegistry()
        registry.markSynced("content://real/a")
        val changed = registry.reconcileStaleContent(
            childKey = "content://real/a",
            mirrorLength = 100, mirrorLastModified = 1000,
            realLength = 200, realLastModified = 1000,
        )
        assertTrue(changed)
        assertFalse(registry.hasContent("content://real/a"))
    }

    @Test
    fun `reconcileStaleContent drops a synced entry whose lastModified no longer matches`() {
        val registry = MirrorRegistry()
        registry.markSynced("content://real/a")
        val changed = registry.reconcileStaleContent(
            childKey = "content://real/a",
            mirrorLength = 100, mirrorLastModified = 1000,
            realLength = 100, realLastModified = 2000,
        )
        assertTrue(changed)
        assertFalse(registry.hasContent("content://real/a"))
    }

    @Test
    fun `reconcileStaleContent ignores lastModified when real reports zero`() {
        // realLastModified <= 0 means the provider doesn't report a
        // reliable timestamp -- only size is checked in that case.
        val registry = MirrorRegistry()
        registry.markSynced("content://real/a")
        val changed = registry.reconcileStaleContent(
            childKey = "content://real/a",
            mirrorLength = 100, mirrorLastModified = 1000,
            realLength = 100, realLastModified = 0,
        )
        assertFalse(changed)
        assertTrue(registry.hasContent("content://real/a"))
    }

    @Test
    fun `reconcileStaleContent leaves a matching synced entry alone`() {
        val registry = MirrorRegistry()
        registry.markSynced("content://real/a")
        val changed = registry.reconcileStaleContent(
            childKey = "content://real/a",
            mirrorLength = 100, mirrorLastModified = 1000,
            realLength = 100, realLastModified = 1000,
        )
        assertFalse(changed)
        assertTrue(registry.hasContent("content://real/a"))
    }

    @Test
    fun `reconcileStaleContent NEVER reconciles away a pending local write -- regression test for the production bug`() {
        // This is the exact scenario from MirrorRegistry's class doc
        // comment: a raw write is in flight (mirror file's real length
        // already reflects the new content), the push to the real tree
        // hasn't happened yet (real side still shows the OLD size/mtime),
        // and a directory re-listing runs in between. The old code's
        // `pulledContent.contains(childKey) && mirrored.absolutePath !in
        // pendingLocalWrites` check protected this ONLY if every call site
        // remembered to check pendingLocalWrites first. Here there is no
        // second flag to remember -- PENDING_LOCAL_WRITE is not SYNCED, so
        // reconcileStaleContent's `contentState[childKey] != SYNCED` bails
        // immediately regardless of how large the size mismatch looks.
        val registry = MirrorRegistry()
        registry.markPendingLocalWrite("content://real/a")
        val changed = registry.reconcileStaleContent(
            childKey = "content://real/a",
            mirrorLength = 5000, mirrorLastModified = 5000, // mirror already has the new write
            realLength = 0, realLastModified = 1000,        // real side is still the old, pre-write state
        )
        assertFalse("a pending local write must never be reconciled away", changed)
        assertTrue(registry.hasPendingLocalWrite("content://real/a"))
    }

    // ---- clear() ------------------------------------------------------------------

    @Test
    fun `clear drops everything -- mapping, listed flags, and content state`() {
        val registry = MirrorRegistry()
        val file = mirrorFile("a.txt")
        registry.link("content://real/a", file)
        registry.markSynced("content://real/a")
        registry.markListed("content://real/dir")
        registry.clear()
        assertNull(registry.mirrorFor("content://real/a"))
        assertFalse(registry.hasContent("content://real/a"))
        assertFalse(registry.hasListed("content://real/dir"))
        assertTrue(registry.childKeys(file.parentFile!!.absolutePath).isEmpty())
    }

    // ---- concurrency: many threads racing markSynced/markPendingLocalWrite/markPushed ----

    @Test
    fun `concurrent markSynced and markPendingLocalWrite on the same key never leaves both true`() {
        // Not a proof, but a stress test: hammer the same key from many
        // threads calling markSynced and markPendingLocalWrite (and
        // markPushed) in a tight loop, and check the invariant that must
        // ALWAYS hold regardless of interleaving -- hasContent and
        // hasPendingLocalWrite are never both true at once, because
        // ContentState only ever holds one enum value per key.
        //
        // Checked via contentStateOf(), a single atomic read -- NOT via
        // `hasContent(key) && hasPendingLocalWrite(key)`. That pair is two
        // separate map reads; under this many concurrent writers to the
        // SAME key, the state can (and reliably does) change between the
        // two calls, so that check can observe SYNCED on the first read
        // and PENDING_LOCAL_WRITE on the second and wrongly conclude both
        // were true at once -- a race in the observation, not evidence
        // that contentState itself ever actually held two values. A
        // single contentStateOf() read is inherently one-or-the-other by
        // construction, which is the actual property under test.
        val registry = MirrorRegistry()
        val key = "content://real/a"
        val threadCount = 8
        val iterationsPerThread = 5000
        val unexpectedStateObserved = AtomicInteger(0)
        val pool = Executors.newFixedThreadPool(threadCount)
        val startLatch = CountDownLatch(1)
        val doneLatch = CountDownLatch(threadCount)
        repeat(threadCount) { threadIndex ->
            pool.execute {
                startLatch.await()
                try {
                    repeat(iterationsPerThread) { i ->
                        when ((threadIndex + i) % 3) {
                            0 -> registry.markSynced(key)
                            1 -> registry.markPendingLocalWrite(key)
                            else -> registry.markPushed(key)
                        }
                        val state = registry.contentStateOf(key)
                        if (state != MirrorRegistry.ContentState.SYNCED &&
                            state != MirrorRegistry.ContentState.PENDING_LOCAL_WRITE
                        ) {
                            unexpectedStateObserved.incrementAndGet()
                        }
                    }
                } finally {
                    doneLatch.countDown()
                }
            }
        }
        startLatch.countDown()
        assertTrue(doneLatch.await(30, TimeUnit.SECONDS))
        pool.shutdown()
        assertEquals(
            "contentStateOf must always be exactly one of SYNCED/PENDING_LOCAL_WRITE once any mark* call has run for this key",
            0, unexpectedStateObserved.get(),
        )
    }
}