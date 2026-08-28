package com.aeidolon.vaultexplorer.saf

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * [MirrorSyncCoordinator] previously had zero test coverage despite being
 * more concurrency-heavy than [com.aeidolon.vaultexplorer.CryfsConcurrencyTest]
 * covers, and despite its own comments documenting two real,
 * production-observed races:
 *
 * 1. A directory re-listing ([MirrorSyncCoordinator.pullListingIfMissing])
 *    running between a raw-I/O write finishing and its content push being
 *    pushed back could see a stale "already synced" flag, read the
 *    mismatched size as "the real file changed under us", and delete the
 *    not-yet-pushed mirror content -- silently destroying the pending
 *    write. Fixed by [MirrorRegistry.ContentState] (see that class's
 *    tests for the state-machine-level regression test); the tests here
 *    cover the same scenario through the coordinator's actual public API.
 *
 * 2. [MirrorSyncCoordinator.pushFileWrite] reading a freshly-written
 *    mirror file's length as 0 moments after the write completed,
 *    addressed with a short bounded retry rather than removed outright --
 *    see that method's doc comment for why a retry is the right fix here
 *    (there's no lock to take on a write that isn't necessarily this
 *    call's own caller) and why "still 0 after every retry" now logs an
 *    explicit unconfirmed-zero warning instead of silently proceeding as
 *    if it had been confirmed legitimate.
 *
 * A third area, [MirrorSyncCoordinator.ensureReadyOrStreamDirect] (the
 * large-file cold-open path: stream directly from the real SAF document
 * while a background pull warms the mirror, instead of blocking on a full
 * synchronous download), had no direct tests at all despite being the
 * newest and least-exercised part of this class and despite its own doc
 * comment (see that method) already documenting the exact failure mode a
 * naive implementation could hit: firing a duplicate STARTED phase for a
 * pull already in flight, which would leave a real listener (a video
 * player's "downloading" indicator) with one STARTED phase unaccounted for
 * by a matching FINISHED/FAILED -- i.e. a permanently stuck loading spinner
 * on an actual player, not a hypothetical. The tests below exercise the
 * threshold boundary, both success and failure on both the synchronous and
 * background paths, and specifically the in-flight-dedup invariant that
 * failure mode depends on.
 *
 * These tests use two real [SafDocumentOps] instances over plain
 * filesystem directories under Robolectric (file-backed [DocumentFile]s,
 * same pattern as ChunkedFileEngineTest) -- one standing in for the "real"
 * SAF-exposed tree, one being the coordinator's own mirror -- so pulls and
 * pushes exercise the actual ContentResolver-backed I/O paths rather than
 * a mock.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MirrorSyncCoordinatorTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private lateinit var realRoot: File
    private lateinit var realOps: SafDocumentOps
    private lateinit var realRootDoc: DocumentFile
    private lateinit var sync: MirrorSyncCoordinator

    private fun setUp() {
        // Deliberately placed under context.filesDir, NOT tempFolder's own
        // temp directory: RawFileResolver.isAppPrivatePath() only treats a
        // path as always-raw-accessible when it's under context.filesDir
        // (or an external-files-dir) -- see that function's doc comment.
        // A TemporaryFolder-provided directory typically lives under the
        // JVM's system temp dir instead, which isAppPrivatePath doesn't
        // recognize; canAccessRawFile then falls through to the external-
        // storage permission check, which a bare Robolectric Context
        // hasn't been granted, so getRawFile() returns null and
        // queryChildrenRaw falls through to the REAL DocumentsContract/
        // ContentResolver.query() branch -- which cannot succeed against a
        // file://-only fake URI (DocumentFile.fromFile's URI has no real
        // tree-document ID for DocumentsContract to resolve), surfacing as
        // a FileNotFoundException from deep inside SafDocumentOps rather
        // than any actual bug in the sync logic under test. Using a
        // filesDir-rooted directory keeps every real-side file on the raw
        // fast path, exactly like a real mirrored-vault session's actual
        // real SAF tree does whenever it happens to resolve to an
        // app-private path, and matches how mirrorRoot itself is already
        // constructed (also under context.filesDir).
        realRoot = File(context.filesDir, "test_real_root_${System.nanoTime()}").apply { mkdirs() }
        realOps = SafDocumentOps(context)
        realRootDoc = DocumentFile.fromFile(realRoot)
        sync = MirrorSyncCoordinator(context, sessionTag = "test-session-${System.nanoTime()}", realOps = realOps)
        sync.reset(realRootDoc)
    }

    private fun tearDown() {
        sync.teardown()
        try {
            realRoot.deleteRecursively()
        } catch (_: Exception) {
        }
    }

    private fun <T> withFixture(block: () -> T): T {
        setUp()
        try {
            return block()
        } finally {
            tearDown()
        }
    }

    // ---- pullFileIfMissing: basic correctness -----------------------------------

    @Test
    fun `pullFileIfMissing copies real content into the mirror`() = withFixture {
        val realFile = File(realRoot, "hello.txt").apply { writeText("hello world") }
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "hello.txt"))

        val mirrored = sync.pullFileIfMissing(realDoc)

        assertEquals("hello world", mirrored.readText())
        assertTrue(sync.hasContent(realDoc))
    }

    @Test
    fun `pullFileIfMissing on an already-pulled file does not re-copy`() = withFixture {
        val realFile = File(realRoot, "hello.txt").apply { writeText("version 1") }
        val realDoc = DocumentFile.fromFile(realFile)
        val mirrorFile = File(File(sync.mirrorRoot, "root"), "hello.txt")
        sync.registerExisting(realDoc, mirrorFile)
        sync.pullFileIfMissing(realDoc)

        // Real file changes after the pull -- pullFileIfMissing should NOT
        // notice, because hasContent() is already true.
        realFile.writeText("version 2 -- should not be seen")
        val mirrored = sync.pullFileIfMissing(realDoc)

        assertEquals("version 1", mirrored.readText())
    }

    // ---- pullFileIfMissing vs a pending local write: regression test for the -----
    // ---- production batch-import bug (16/50 files truncated to 0 bytes) ----------

    @Test
    fun `pullFileIfMissing never overwrites a pending local write it was never pulled from`() = withFixture {
        // Reproduces the batch-import corruption from the field report: a
        // NEW file (unlike the reconciliation regression test below, this
        // one was never pulled/synced first -- there is no real-side
        // content yet at all, exactly like an import target mid-batch,
        // before endBatchWrite has pushed anything). The import worker
        // stages ciphertext directly into the mirror and marks it pending,
        // all before the real SAF document has any content.
        val realFile = File(realRoot, "photo.png") // not created yet -- mirrors a SAF placeholder/not-yet-pushed doc
        val realDoc = DocumentFile.fromFile(realFile)
        val mirrorFile = File(File(sync.mirrorRoot, "root"), "photo.png").apply {
            parentFile?.mkdirs()
            writeBytes(ByteArray(4_684_347) { 0x42 }) // stand-in for the encrypted image content
        }
        sync.registerExisting(realDoc, mirrorFile)
        sync.markPendingLocalWrite(mirrorFile)

        // A background thumbnailer/media-scanner reads the file before
        // endBatchWrite has pushed it -- exactly the pullFileIfMissing call
        // from the logcat trace. Before the fix, hasContent(key) is false
        // (the state is PENDING_LOCAL_WRITE, not SYNCED), so this fell
        // through to "not yet pulled", read 0 bytes from the not-yet-real
        // realFile, and clobbered the mirror via tmp.renameTo(mirrored).
        val result = sync.pullFileIfMissing(realDoc)

        assertEquals(
            "a pending local write must survive a pullFileIfMissing call that races the deferred push",
            4_684_347,
            result.length(),
        )
        assertEquals(4_684_347, mirrorFile.length())
    }

    // ---- pushFileWrite: basic correctness ----------------------------------------

    @Test
    fun `pushFileWrite copies mirror content back to an existing real file`() = withFixture {
        val realFile = File(realRoot, "doc.txt").apply { writeText("original") }
        val realDoc = DocumentFile.fromFile(realFile)
        val mirrorFile = File(File(sync.mirrorRoot, "root"), "doc.txt").apply { parentFile?.mkdirs(); writeText("edited content") }

        sync.pushFileWrite(mirrorFile, realParent = null, existingRealDoc = realDoc, displayName = "doc.txt", mimeType = "text/plain")

        assertEquals("edited content", realFile.readText())
        assertTrue(sync.hasContent(realDoc))
    }

    @Test
    fun `pushFileWrite creates a new real file when existingRealDoc is null`() = withFixture {
        val mirrorFile = File(File(sync.mirrorRoot, "root"), "new.txt").apply { parentFile?.mkdirs(); writeText("new content") }

        sync.pushFileWrite(mirrorFile, realParent = realRootDoc, existingRealDoc = null, displayName = "new.txt", mimeType = "text/plain")

        val createdReal = File(realRoot, "new.txt")
        assertTrue(createdReal.exists())
        assertEquals("new content", createdReal.readText())
    }

    @Test
    fun `pushFileWrite of a genuinely empty file to an existing real file succeeds`() = withFixture {
        // The "unconfirmed zero" warning path must NOT block a legitimate
        // empty-content push (e.g. truncating a document) -- it only logs.
        val realFile = File(realRoot, "doc.txt").apply { writeText("had content before") }
        val realDoc = DocumentFile.fromFile(realFile)
        val mirrorFile = File(File(sync.mirrorRoot, "root"), "doc.txt").apply { parentFile?.mkdirs(); writeBytes(ByteArray(0)) }

        sync.pushFileWrite(mirrorFile, realParent = null, existingRealDoc = realDoc, displayName = "doc.txt", mimeType = "text/plain")

        assertEquals(0L, realFile.length())
    }

    // ---- markPendingLocalWrite / pushFileWrite: pending state clears on push ----

    @Test
    fun `pushFileWrite clears the pending-local-write flag it had before the push`() = withFixture {
        val realFile = File(realRoot, "doc.txt").apply { writeText("v1") }
        val realDoc = DocumentFile.fromFile(realFile)
        val mirrorFile = File(File(sync.mirrorRoot, "root"), "doc.txt").apply { parentFile?.mkdirs(); writeText("v1") }
        sync.registerExisting(realDoc, mirrorFile)

        sync.markPendingLocalWrite(mirrorFile)
        mirrorFile.writeText("v2 -- local edit in flight")
        sync.pushFileWrite(mirrorFile, realParent = null, existingRealDoc = realDoc, displayName = "doc.txt", mimeType = "text/plain")

        assertEquals("v2 -- local edit in flight", realFile.readText())
        assertTrue(sync.hasContent(realDoc))
    }

    // ---- THE regression test: reconciliation must never delete a pending write ---

    @Test
    fun `pullListingIfMissing never reconciles away a pending local write -- regression test for the production bug`() = withFixture {
        // Reproduces the exact scenario from MirrorSyncCoordinator's and
        // MirrorRegistry's doc comments: a file is pulled and synced
        // first (so it starts out with a real "already pulled" marker,
        // same as the creation-time placeholder push in real code), then
        // a raw local write updates the MIRROR file's bytes directly
        // (simulating a batched import writing content ahead of its
        // deferred push) and calls markPendingLocalWrite -- all BEFORE the
        // content push happens. A directory listing runs in that window.
        //
        // Before the fix, the stale "synced" flag (still true from the
        // initial pull/push) combined with a size mismatch between the
        // now-larger mirror file and the real file (which hasn't received
        // the new content yet) would make pullListingIfMissing conclude
        // "the real file changed under us" and delete the mirror file's
        // new content -- destroying the pending write with no error.
        val realFile = File(realRoot, "doc.txt").apply { writeText("original") }
        val realDoc = DocumentFile.fromFile(realFile)
        val mirrorFile = File(File(sync.mirrorRoot, "root"), "doc.txt")
        sync.registerExisting(realDoc, mirrorFile)
        sync.pullFileIfMissing(realDoc) // now hasContent(realDoc) == true, mirror == "original"

        // Simulate a raw local write landing directly on the mirror file,
        // ahead of its deferred push -- exactly what a batched import's
        // raw-I/O write path does.
        sync.markPendingLocalWrite(mirrorFile)
        mirrorFile.writeText("locally edited, not yet pushed -- much longer content than original")

        // A directory re-listing runs in the deferred-push window (e.g.
        // triggered by an unrelated setLastModifiedTime call resolving the
        // parent directory, per the original bug report).
        val rootMirrorDir = File(sync.mirrorRoot, "root")
        sync.pullListingIfMissing(realRootDoc, rootMirrorDir)

        // The pending write must have survived the listing untouched.
        assertEquals(
            "a pending local write must survive a concurrent directory re-listing",
            "locally edited, not yet pushed -- much longer content than original",
            mirrorFile.readText(),
        )
    }

    @Test
    fun `pullListingIfMissing DOES reconcile a stale synced entry with no pending write`() = withFixture {
        // The flip side of the regression test above: without a pending
        // write, a real content change (simulating an external edit to
        // the real SAF file after this app last pulled it) SHOULD still
        // be detected and the stale mirror content dropped. The fix must
        // not have disabled reconciliation entirely -- only protected the
        // pending-write case.
        val realFile = File(realRoot, "doc.txt").apply { writeText("original") }
        val realDoc = DocumentFile.fromFile(realFile)
        val mirrorFile = File(File(sync.mirrorRoot, "root"), "doc.txt")
        sync.registerExisting(realDoc, mirrorFile)
        sync.pullFileIfMissing(realDoc)
        assertTrue(sync.hasContent(realDoc))

        // Real file changed size externally, with no local pending write
        // recorded on this key at all.
        Thread.sleep(5) // ensure a distinguishable lastModified
        realFile.writeText("changed externally, much longer than original")

        val rootMirrorDir = File(sync.mirrorRoot, "root")
        sync.pullListingIfMissing(realRootDoc, rootMirrorDir)

        assertFalse(
            "a stale synced entry with no pending write should be reconciled (marked not-yet-pulled)",
            sync.hasContent(realDoc),
        )
    }

    // ---- pushFileWrite + pullListingIfMissing: regression test for the ----------
    // ---- production .thumbcache batch-push crash ("no real parent for new file") --

    @Test
    fun `a freshly-created file survives a listing that races the real provider's own propagation delay`() = withFixture {
        // Reproduces the field report's second bug: thumbnail generation
        // creates a file (e.g. ".thumbcache/<hash>.c9r") via the same
        // creation path an ordinary import uses -- pushFileWrite with
        // existingRealDoc == null -- which creates the real document AND
        // registers + markNeverListed's the mapping (see that method's
        // freshlyCreatedTarget branch). A directory listing then runs
        // before the real SAF provider's OWN listing has caught up to
        // include the just-created child -- confirmed in the field log via
        // "Failed query ... FileNotFoundException" immediately followed by
        // "pullListingIfMissing: removing stale mirror entry". Before this
        // fix, staleChildKeys had no way to tell that apart from a genuine
        // deletion and forget() dropped the mapping outright; the next
        // pushContentWrite for the same file then failed with
        // MirrorPushException("no real parent for new file ..."), since
        // pushContentWrite always passes realParent = null and relies
        // entirely on the (now-gone) registered mapping.
        //
        // The propagation delay itself is simulated by pointing
        // pullListingIfMissing at an EMPTY real folder while still passing
        // the actual mirrored parent directory the new file lives under --
        // i.e. "this listing call's view of the real tree doesn't have the
        // new child yet", independent of whether a real on-disk listing
        // would (a genuine local filesystem has no propagation delay to
        // reproduce naturally, unlike a real cloud-backed SAF provider).
        val thumbDir = File(realRoot, "thumbdir").apply { mkdirs() }
        val thumbDirDoc = DocumentFile.fromFile(thumbDir)
        val mirrorThumbDir = File(File(sync.mirrorRoot, "root"), "thumbdir").apply { mkdirs() }
        sync.registerExisting(thumbDirDoc, mirrorThumbDir)

        val mirrorFile = File(mirrorThumbDir, "hash123.c9r").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        sync.pushFileWrite(mirrorFile, realParent = thumbDirDoc, existingRealDoc = null, displayName = "hash123.c9r", mimeType = "application/octet-stream")
        val createdReal = File(thumbDir, "hash123.c9r")
        assertTrue("sanity: the real file was actually created", createdReal.exists())

        // A listing pass sees an EMPTY real folder -- the propagation-delay
        // window -- even though mirrorThumbDir (the mirror side) already
        // has the new child registered under it.
        val emptyRealFolder = File(realRoot, "empty_view_of_thumbdir").apply { mkdirs() }
        sync.pullListingIfMissing(DocumentFile.fromFile(emptyRealFolder), mirrorThumbDir)

        // The registration must have survived -- this is the assertion
        // that was failing before the fix (forget() had already dropped
        // it during the listing call above). Resolve via the coordinator's
        // own lookup (realUriFor) rather than asserting file identity
        // directly, to exercise the real path the production code depends
        // on (pushContentWrite calls realDocFor, which is realUriFor under
        // the hood).
        val realDocKey = DocumentFile.fromFile(createdReal)
        assertEquals(
            "a freshly-created child's mapping must survive a listing that simply hasn't caught up to it yet",
            realDocKey.uri.toString(),
            sync.realUriFor(mirrorFile)?.toString(),
        )

        // And a SECOND push to the same (still-registered) file, exactly
        // like endBatchWrite's later pushContentFor call in the real flow,
        // must succeed instead of throwing "no real parent for new file".
        mirrorFile.writeBytes(byteArrayOf(4, 5, 6, 7))
        sync.pushFileWrite(mirrorFile, realParent = null, existingRealDoc = realDocKey, displayName = "hash123.c9r", mimeType = "application/octet-stream")
        assertArrayEquals(byteArrayOf(4, 5, 6, 7), createdReal.readBytes())
    }

    @Test
    fun `a genuinely deleted file is still reconciled away after a second consecutive miss`() = withFixture {
        // The flip side, matching MirrorRegistryTest's equivalent pair:
        // the neverListed protection must expire. A file that keeps
        // missing from the real listing across TWO separate
        // pullListingIfMissing calls is actually gone, not just racing a
        // propagation delay, and must eventually be forgotten -- otherwise
        // this fix would turn every genuine external deletion of a
        // never-listed child into a permanent phantom mapping.
        val thumbDir = File(realRoot, "thumbdir2").apply { mkdirs() }
        val thumbDirDoc = DocumentFile.fromFile(thumbDir)
        val mirrorThumbDir = File(File(sync.mirrorRoot, "root"), "thumbdir2").apply { mkdirs() }
        sync.registerExisting(thumbDirDoc, mirrorThumbDir)

        val mirrorFile = File(mirrorThumbDir, "ghost.c9r").apply { writeBytes(byteArrayOf(1)) }
        sync.pushFileWrite(mirrorFile, realParent = thumbDirDoc, existingRealDoc = null, displayName = "ghost.c9r", mimeType = "application/octet-stream")
        val createdReal = File(thumbDir, "ghost.c9r")
        createdReal.delete() // simulate the real file being genuinely removed externally, right after creation

        val emptyRealFolder = File(realRoot, "empty_view2").apply { mkdirs() }
        // First listing pass: still absent -- protected (this is the same
        // shape as the propagation-delay case, indistinguishable from it
        // at this point).
        sync.pullListingIfMissing(DocumentFile.fromFile(emptyRealFolder), mirrorThumbDir)
        assertTrue(
            "still protected after exactly one miss",
            sync.realUriFor(mirrorFile) != null,
        )

        // Second, independent listing pass (a fresh empty-listing view):
        // still absent -- now treated as a genuine deletion.
        val emptyRealFolder2 = File(realRoot, "empty_view2b").apply { mkdirs() }
        sync.pullListingIfMissing(DocumentFile.fromFile(emptyRealFolder2), mirrorThumbDir)

        assertFalse(
            "a child absent across two independent listings must eventually be reconciled away, not protected forever",
            sync.realUriFor(mirrorFile) != null,
        )
    }

    // ---- concurrency: hammer markPendingLocalWrite + pullListingIfMissing --------

    @Test
    fun `concurrent pending-writes and listings never lose a pending write`() = withFixture {
        // Stress-test version of the regression test above: many files,
        // each independently getting a pending write flagged right before
        // a listing pass runs concurrently on another thread. Not a
        // formal proof, but this should reliably pass now (previously it
        // would be expected to eventually corrupt at least one file's
        // content under enough iterations/thread interleavings).
        val fileCount = 20
        val realFiles = (0 until fileCount).map { i ->
            File(realRoot, "f$i.txt").apply { writeText("original-$i") }
        }
        val realDocs = realFiles.map { DocumentFile.fromFile(it) }
        val mirrorFiles = (0 until fileCount).map { i -> File(File(sync.mirrorRoot, "root"), "f$i.txt") }
        realDocs.zip(mirrorFiles).forEach { (doc, mirrorFile) ->
            sync.registerExisting(doc, mirrorFile)
            sync.pullFileIfMissing(doc)
        }

        val rootMirrorDir = File(sync.mirrorRoot, "root")
        val failure = AtomicBoolean(false)
        val startLatch = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(4)

        // Writer threads: mark pending + write much-longer content for each file.
        val writerDone = CountDownLatch(fileCount)
        mirrorFiles.forEachIndexed { i, mirrorFile ->
            pool.execute {
                startLatch.await()
                try {
                    sync.markPendingLocalWrite(mirrorFile)
                    mirrorFile.writeText("pending-write-$i-" + "x".repeat(50))
                } catch (e: Throwable) {
                    failure.set(true)
                } finally {
                    writerDone.countDown()
                }
            }
        }
        // Listing threads: force re-listings concurrently with the writers.
        val listingsDone = CountDownLatch(3)
        repeat(3) {
            pool.execute {
                startLatch.await()
                try {
                    repeat(5) {
                        sync.invalidateListing(realRootDoc)
                        sync.pullListingIfMissing(realRootDoc, rootMirrorDir)
                    }
                } catch (e: Throwable) {
                    failure.set(true)
                } finally {
                    listingsDone.countDown()
                }
            }
        }

        startLatch.countDown()
        assertTrue(writerDone.await(30, TimeUnit.SECONDS))
        assertTrue(listingsDone.await(30, TimeUnit.SECONDS))
        pool.shutdown()

        assertFalse("no thread should have thrown", failure.get())
        mirrorFiles.forEachIndexed { i, mirrorFile ->
            assertTrue(
                "file $i's pending write must have survived concurrent listings, got: ${mirrorFile.readText()}",
                mirrorFile.readText().startsWith("pending-write-$i-"),
            )
        }
    }

    // ---- reset / teardown ---------------------------------------------------------

    @Test
    fun `reset clears all bookkeeping and re-links the root`() = withFixture {
        val realFile = File(realRoot, "hello.txt").apply { writeText("hello") }
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "hello.txt"))
        sync.pullFileIfMissing(realDoc)
        assertTrue(sync.hasContent(realDoc))

        sync.reset(realRootDoc)

        assertFalse(sync.hasContent(realDoc))
        assertFalse(sync.hasListed(realRootDoc))
    }

    @Test
    fun `teardown deletes the mirror root directory`() = withFixture {
        assertTrue(sync.mirrorRoot.exists())
        sync.teardown()
        assertFalse(sync.mirrorRoot.exists())
    }

    // ---- ensureReadyOrStreamDirect: large-file cold-open path --------------------

    /** Creates a real file of exactly [sizeBytes] under [realRoot], filled
     *  with actual non-zero bytes (not a sparse hole) so a real byte-for-
     *  byte copy through [MirrorSyncCoordinator.pullFileIfMissing] has
     *  something genuine to move and verify, without paying to write tens
     *  of megabytes through Kotlin's `writeText`. */
    private fun realFileOfSize(name: String, sizeBytes: Long): File {
        val f = File(realRoot, name)
        java.io.RandomAccessFile(f, "rw").use { raf ->
            raf.setLength(sizeBytes)
            // Touch a handful of bytes so the file isn't a pure sparse
            // hole -- enough for a content check without writing the
            // whole thing by hand.
            raf.seek(0); raf.write(ByteArray(64) { (it % 251).toByte() })
            if (sizeBytes > 128) {
                raf.seek(sizeBytes - 64)
                raf.write(ByteArray(64) { ((it + 7) % 251).toByte() })
            }
        }
        return f
    }

    @Test
    fun `ensureReadyOrStreamDirect pulls synchronously and returns true for a file under the threshold`() = withFixture {
        val realFile = File(realRoot, "small.bin").apply { writeBytes(ByteArray(1024) { it.toByte() }) }
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "small.bin"))

        val ready = sync.ensureReadyOrStreamDirect(realDoc)

        assertTrue("a small file should be pulled synchronously and report ready", ready)
        assertTrue(sync.hasContent(realDoc))
    }

    @Test
    fun `ensureReadyOrStreamDirect returns true immediately when content is already synced, regardless of size`() = withFixture {
        // hasContent() short-circuits before the size check -- a file that
        // happens to be large but was already pulled earlier (e.g. a
        // second open in the same session) must not re-trigger the
        // large-file background-pull machinery at all.
        val realFile = realFileOfSize("already-synced.bin", MirrorSyncCoordinator.LARGE_FILE_STREAM_THRESHOLD_BYTES + 1024)
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "already-synced.bin"))
        sync.pullFileIfMissing(realDoc)
        assertTrue(sync.hasContent(realDoc))

        var phaseCalls = 0
        val ready = sync.ensureReadyOrStreamDirect(realDoc) { phaseCalls++ }

        assertTrue(ready)
        assertEquals("no phase callback should fire when content was already synced", 0, phaseCalls)
    }

    @Test
    fun `ensureReadyOrStreamDirect returns false and streams direct for a file at or over the threshold`() = withFixture {
        val realFile = realFileOfSize("large.bin", MirrorSyncCoordinator.LARGE_FILE_STREAM_THRESHOLD_BYTES)
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "large.bin"))

        val finished = CountDownLatch(1)
        val phases = java.util.Collections.synchronizedList(mutableListOf<MirrorPullEvents.Phase>())
        val ready = sync.ensureReadyOrStreamDirect(realDoc) { phase ->
            phases.add(phase)
            if (phase == MirrorPullEvents.Phase.FINISHED || phase == MirrorPullEvents.Phase.FAILED) finished.countDown()
        }

        assertFalse("a file at the threshold (>=) must stream direct, not pull synchronously", ready)
        assertTrue("background pull did not complete in time", finished.await(10, TimeUnit.SECONDS))
        assertEquals(listOf(MirrorPullEvents.Phase.STARTED, MirrorPullEvents.Phase.FINISHED), phases)
        assertTrue(
            "the background pull should have populated the mirror by the time FINISHED fires",
            sync.hasContent(realDoc),
        )
    }

    @Test
    fun `ensureReadyOrStreamDirect below the threshold streams direct without throwing when the pull itself fails`() = withFixture {
        // A small file whose real DocumentFile is registered but whose
        // underlying real bytes are deleted out from under it before the
        // pull runs -- pullFileIfMissing's ContentResolver open will fail,
        // and ensureReadyOrStreamDirect's job is to swallow that
        // (SafIOException) and report "stream direct" rather than let the
        // exception propagate to the caller.
        val realFile = File(realRoot, "vanishing.bin").apply { writeBytes(ByteArray(512)) }
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "vanishing.bin"))
        realFile.delete() // real bytes gone; ContentResolver.openInputStream on this file:// URI will now fail

        val ready = sync.ensureReadyOrStreamDirect(realDoc)

        assertFalse("a failed synchronous pull must report false (stream direct), not throw", ready)
        assertFalse(sync.hasContent(realDoc))
    }

    @Test
    fun `ensureReadyOrStreamDirect fires FAILED, not FINISHED, when the background pull fails`() = withFixture {
        // Same idea as the below-threshold failure case above, but for the
        // background-pull path: the real file needs to still exist (with
        // its real size) at the moment ensureReadyOrStreamDirect reads
        // realDoc.length() for the threshold check -- deleting it any
        // earlier makes File.length() read back 0 for the now-missing
        // file (confirmed: java.io.File.length() returns 0 for a
        // nonexistent path, not the file's last real size), which is
        // always < the threshold and silently sends this down the
        // SYNCHRONOUS branch instead -- a real bug this test had the
        // first time around, caught by the resulting stack trace pointing
        // at MirrorSyncCoordinator.kt's synchronous branch instead of the
        // background-executor one. Deleting the file from inside the
        // STARTED callback instead is safe: STARTED fires synchronously,
        // strictly before pullExecutor.execute() is even called (see the
        // in-flight-dedup test's comment for the same guarantee), so the
        // size check has already happened and returned a genuine
        // over-threshold size by the time this callback runs, and the
        // delete still lands before the background Runnable's own
        // pullFileIfMissing call gets to actually read the file.
        val realFile = realFileOfSize("large-vanishing.bin", MirrorSyncCoordinator.LARGE_FILE_STREAM_THRESHOLD_BYTES)
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "large-vanishing.bin"))

        val finished = CountDownLatch(1)
        val phases = java.util.Collections.synchronizedList(mutableListOf<MirrorPullEvents.Phase>())
        val ready = sync.ensureReadyOrStreamDirect(realDoc) { phase ->
            phases.add(phase)
            if (phase == MirrorPullEvents.Phase.STARTED) realFile.delete()
            if (phase == MirrorPullEvents.Phase.FINISHED || phase == MirrorPullEvents.Phase.FAILED) finished.countDown()
        }

        assertFalse(ready)
        assertTrue("background pull did not report completion in time", finished.await(10, TimeUnit.SECONDS))
        assertEquals(listOf(MirrorPullEvents.Phase.STARTED, MirrorPullEvents.Phase.FAILED), phases)
        assertFalse(sync.hasContent(realDoc))
    }

    @Test
    fun `ensureReadyOrStreamDirect does not fire a second STARTED for a pull already in flight for the same key -- regression test for a stuck loading indicator`() = withFixture {
        // This is the scenario the method's own doc comment (lines 312-318)
        // warns about: a naive implementation could fire STARTED on every
        // call regardless of whether a pull for this exact file is already
        // running, which would leave a listener that treats phases as a
        // per-call STARTED/FINISHED pair with one FINISHED unaccounted
        // for -- a permanently-stuck "downloading" indicator on a real
        // video player, per this class's own doc comment. Uses a huge file
        // (well over the threshold) so the background pull has enough real
        // work to still be running when the second call arrives.
        val realFile = realFileOfSize("contended.bin", MirrorSyncCoordinator.LARGE_FILE_STREAM_THRESHOLD_BYTES * 4)
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "contended.bin"))

        val firstCallStarted = CountDownLatch(1)
        val firstCallFinished = CountDownLatch(1)
        val firstCallPhases = java.util.Collections.synchronizedList(mutableListOf<MirrorPullEvents.Phase>())

        // Fires the second, overlapping call from inside the FIRST call's
        // onBackgroundPullPhase(STARTED) handler itself, which is
        // guaranteed to run on the calling thread that invoked
        // ensureReadyOrStreamDirect, synchronously, strictly before
        // pullExecutor.execute() is even called (see that method's source:
        // STARTED fires on line 293, execute() isn't called until line 295)
        // -- so the second call is guaranteed to land while pullsInFlight
        // still contains the key, regardless of how fast the real
        // background I/O happens to run. No sleep, no polling, no race.
        var secondCallReady: Boolean? = null
        val secondCallPhases = java.util.Collections.synchronizedList(mutableListOf<MirrorPullEvents.Phase>())

        sync.ensureReadyOrStreamDirect(realDoc) { phase ->
            firstCallPhases.add(phase)
            if (phase == MirrorPullEvents.Phase.STARTED) {
                // Fire the second call synchronously, still inside the
                // window where pullsInFlight definitely still contains
                // the key (the background Runnable hasn't reached its
                // own finally block yet -- we are ON the calling thread
                // here, and STARTED fires before pullExecutor.execute
                // returns, i.e. before the background thread has had any
                // chance to run at all).
                secondCallReady = sync.ensureReadyOrStreamDirect(realDoc) { p -> secondCallPhases.add(p) }
                firstCallStarted.countDown()
            }
            if (phase == MirrorPullEvents.Phase.FINISHED || phase == MirrorPullEvents.Phase.FAILED) {
                firstCallFinished.countDown()
            }
        }

        assertTrue("first call's STARTED should have fired synchronously", firstCallStarted.await(5, TimeUnit.SECONDS))
        assertEquals("the second, overlapping call must not report ready synchronously", false, secondCallReady)
        assertTrue(
            "the second call must not fire its own STARTED for a pull it didn't initiate",
            secondCallPhases.isEmpty(),
        )

        assertTrue("background pull did not complete in time", firstCallFinished.await(15, TimeUnit.SECONDS))
        assertEquals(listOf(MirrorPullEvents.Phase.STARTED, MirrorPullEvents.Phase.FINISHED), firstCallPhases)
        assertTrue(sync.hasContent(realDoc))
    }

    @Test
    fun `ensureReadyOrStreamDirect allows a fresh background pull once the earlier one for the same key has finished`() = withFixture {
        // Flip side of the in-flight-dedup test: pullsInFlight must be
        // cleared once a pull completes, not leak the key forever -- a
        // leaked key would make every future cold-open of this same file
        // silently no-op (no STARTED, no pull, just `return false` at the
        // tail) for the rest of the session.
        //
        // hasContent() short-circuits a second call once the first pull
        // has actually finished (see the "already synced" test above), so
        // to exercise pullsInFlight's own cleanup specifically -- rather
        // than that earlier, different short-circuit -- this needs content
        // pushed back to "not yet pulled" for the SAME key without going
        // through the full reset()/listing machinery (which would also
        // reset pullsInFlight itself, proving nothing about cleanup).
        // There's no public API on MirrorSyncCoordinator for "forget this
        // one file's content but leave everything else alone" -- reset()
        // is all-or-nothing by design (see its own doc comment) -- so
        // this reaches into the coordinator's private `registry` field via
        // reflection specifically to avoid that blast radius.
        // MirrorRegistry.forgetContent itself is a plain public method
        // once reached; only the field lookup needs reflection.
        val realFile = realFileOfSize("reusable.bin", MirrorSyncCoordinator.LARGE_FILE_STREAM_THRESHOLD_BYTES)
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "reusable.bin"))

        val firstFinished = CountDownLatch(1)
        sync.ensureReadyOrStreamDirect(realDoc) { phase ->
            if (phase == MirrorPullEvents.Phase.FINISHED || phase == MirrorPullEvents.Phase.FAILED) firstFinished.countDown()
        }
        assertTrue(firstFinished.await(10, TimeUnit.SECONDS))
        assertTrue(sync.hasContent(realDoc))

        val registryField = MirrorSyncCoordinator::class.java.getDeclaredField("registry").apply { isAccessible = true }
        val registry = registryField.get(sync) as MirrorRegistry
        registry.forgetContent(realDoc.uri.toString())
        assertFalse(sync.hasContent(realDoc))

        val secondPhases = java.util.Collections.synchronizedList(mutableListOf<MirrorPullEvents.Phase>())
        val secondFinished = CountDownLatch(1)
        val secondReady = sync.ensureReadyOrStreamDirect(realDoc) { phase ->
            secondPhases.add(phase)
            if (phase == MirrorPullEvents.Phase.FINISHED || phase == MirrorPullEvents.Phase.FAILED) secondFinished.countDown()
        }

        assertFalse(secondReady)
        assertTrue(secondFinished.await(10, TimeUnit.SECONDS))
        assertEquals(
            "a fresh pull for the same key, after the previous one fully completed, must fire its own STARTED/FINISHED pair",
            listOf(MirrorPullEvents.Phase.STARTED, MirrorPullEvents.Phase.FINISHED),
            secondPhases,
        )
    }

    // ---- pushFileWrite: real-file rollback on a failed NEW-file push --------------

    @Test
    fun `pushFileWrite rolls back a freshly-created real file when the copy into it fails -- regression test for an orphaned empty real file`() = withFixture {
        // Reproduces the gap found while reviewing MirroredSafDocumentOps.
        // createFileSafe's own error handling: that method's catch block
        // only ever cleans up the MIRROR side
        // (runCatching { mirrorFile.delete() }) on a MirrorPushException
        // from pushFileWrite -- it has no way to know pushFileWrite may
        // have ALREADY created a real file via realOps.createFileSafe
        // before some LATER step in that same call (the actual content
        // copy) failed. Before this fix, that left a stray empty real
        // file on the actual SAF-exposed storage with no mirror
        // counterpart and nothing in MirrorRegistry -- not permanent data
        // loss (the next listing of that folder discovers it as an
        // ordinary new child and mirrors it fresh), but a spurious empty
        // file surviving a failed create until then.
        //
        // Forces the failure by pointing `mirrored` at a File that does
        // not exist on disk: existingRealDoc is null (this is a NEW-file
        // push, the only case where a real file even gets freshly created
        // inside pushFileWrite), so the zero-length retry block above is
        // skipped entirely (it's gated on existingRealDoc != null) and the
        // function proceeds straight to creating the real file -- which
        // succeeds -- before attempting to open the nonexistent `mirrored`
        // for reading, which fails.
        val nonExistentMirrorFile = File(File(sync.mirrorRoot, "root"), "never-actually-written.bin")
        assertFalse(nonExistentMirrorFile.exists())

        var thrown: Exception? = null
        try {
            sync.pushFileWrite(
                nonExistentMirrorFile,
                realParent = realRootDoc,
                existingRealDoc = null,
                displayName = "never-actually-written.bin",
                mimeType = "application/octet-stream",
            )
        } catch (e: Exception) {
            thrown = e
        }

        assertTrue("pushFileWrite should have thrown for a copy source that doesn't exist", thrown is MirrorPushException)
        val orphan = File(realRoot, "never-actually-written.bin")
        assertFalse(
            "the real file pushFileWrite created before the copy failed must be rolled back, not left orphaned",
            orphan.exists(),
        )
    }

    @Test
    fun `pushFileWrite does NOT roll back an existing real file when a push to it fails`() = withFixture {
        // The rollback must be scoped to files THIS call created
        // (existingRealDoc == null) -- a failed push to an ALREADY-existing
        // real file must never delete that file. Same failure trigger
        // (nonexistent mirror source), but existingRealDoc is non-null
        // this time.
        //
        // This test originally caught a SEPARATE, more serious bug than
        // the one it was written to check: pushFileWrite used to open the
        // existing real file directly in "wt" (write+truncate) mode before
        // attempting to read the (in this test, nonexistent) mirror
        // source -- "wt" truncates to 0 bytes the instant it's opened,
        // before any new content is written, so the failed push destroyed
        // "do not delete me" outright rather than merely failing to update
        // it (same class of bug as CVE-2023-21036, "aCropalypse": open-
        // truncating-then-write is unsafe for any overwrite of existing
        // content because the truncate and the write aren't atomic with
        // each other). Fixed by staging the copy into a sibling temp file
        // and only replacing the original via atomic rename once the ENTIRE
        // copy has succeeded -- see pushFileWrite's own doc comment on that
        // branch. This test's assertions did not change; the bug was in
        // pushFileWrite, not here.
        val realFile = File(realRoot, "already-existed.bin").apply { writeText("do not delete me") }
        val realDoc = DocumentFile.fromFile(realFile)
        val nonExistentMirrorFile = File(File(sync.mirrorRoot, "root"), "already-existed.bin")
        assertFalse(nonExistentMirrorFile.exists())

        var thrown: Exception? = null
        try {
            sync.pushFileWrite(
                nonExistentMirrorFile,
                realParent = null,
                existingRealDoc = realDoc,
                displayName = "already-existed.bin",
                mimeType = "application/octet-stream",
            )
        } catch (e: Exception) {
            thrown = e
        }

        assertTrue(thrown is MirrorPushException)
        assertTrue("an existing real file must survive a failed push to it", realFile.exists())
        assertEquals("do not delete me", realFile.readText())
    }

    @Test
    fun `pushFileWrite successfully overwrites an existing real file's content via the staging path`() = withFixture {
        // Flip side of the test above: a SUCCESSFUL overwrite must still
        // genuinely replace the old content with the new, through the
        // stage-into-temp-then-atomic-rename path -- confirms that fix
        // didn't just make failures safe at the cost of breaking the
        // ordinary, successful case.
        val realFile = File(realRoot, "to-overwrite.bin").apply { writeText("old content") }
        val realDoc = DocumentFile.fromFile(realFile)
        val mirrorFile = File(File(sync.mirrorRoot, "root"), "to-overwrite.bin").apply {
            parentFile?.mkdirs()
            writeText("new content, much longer than the old content was")
        }

        sync.pushFileWrite(
            mirrorFile,
            realParent = null,
            existingRealDoc = realDoc,
            displayName = "to-overwrite.bin",
            mimeType = "text/plain",
        )

        assertEquals("new content, much longer than the old content was", realFile.readText())
        assertTrue(sync.hasContent(realDoc))
        // No leftover ".pushing" staging file should survive a successful push.
        val leftoverStaging = File(realRoot, "to-overwrite.bin.pushing")
        assertFalse("a successful push must not leave its staging temp file behind", leftoverStaging.exists())
    }

    @Test
    fun `pullFileIfMissing correctly pulls 16-byte gocryptfs diriv metadata`() = withFixture {
        val dirivBytes = ByteArray(16) { it.toByte() }
        val realFile = File(realRoot, "gocryptfs.diriv").apply { writeBytes(dirivBytes) }
        val realDoc = DocumentFile.fromFile(realFile)
        sync.registerExisting(realDoc, File(File(sync.mirrorRoot, "root"), "gocryptfs.diriv"))

        val mirrored = sync.pullFileIfMissing(realDoc)

        assertEquals(16, mirrored.length())
        assertArrayEquals(dirivBytes, mirrored.readBytes())
        assertTrue(sync.hasContent(realDoc))
    }

    @Test
    fun `pullListingIfMissing and pullFileIfMissing round-trip gocryptfs diriv accurately`() = withFixture {
        val dirivBytes = ByteArray(16) { (it + 42).toByte() }
        val realFile = File(realRoot, "gocryptfs.diriv").apply { writeBytes(dirivBytes) }
        val rootMirror = File(sync.mirrorRoot, "root")

        // First list parent folder
        sync.pullListingIfMissing(realRootDoc, rootMirror)
        val mirroredFile = File(rootMirror, "gocryptfs.diriv")
        assertTrue("Placeholder should exist after listing", mirroredFile.exists())

        // Now pull content
        val realDoc = DocumentFile.fromFile(realFile)
        val pulled = sync.pullFileIfMissing(realDoc)
        assertEquals(16, pulled.length())
        assertArrayEquals(dirivBytes, pulled.readBytes())
        assertTrue(sync.hasContent(realDoc))
    }
}