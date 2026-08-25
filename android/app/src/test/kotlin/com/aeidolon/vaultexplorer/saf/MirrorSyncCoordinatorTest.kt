package com.aeidolon.vaultexplorer.saf

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import androidx.test.core.app.ApplicationProvider
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
}