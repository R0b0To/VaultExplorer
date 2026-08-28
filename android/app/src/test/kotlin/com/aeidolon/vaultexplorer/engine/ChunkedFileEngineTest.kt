package com.aeidolon.vaultexplorer.engine

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.random.Random

/**
 * ChunkedFileEngine is the shared chunked-read/seek/cache engine gocryptfs
 * and Cryptomator route every read through -- including every image/video
 * thumbnail read for those two backends. It previously had zero test
 * coverage despite the class's own comments documenting a real,
 * unmitigated eviction race between openReads' LRU trimming and the
 * per-path `pathLocks` guard (see the comment above [ChunkedFileEngine]'s
 * `openReads`/`pendingClose` fields for the fix and why it's now
 * deadlock-free).
 *
 * Most of these tests cover the seek/cache correctness that the eviction
 * fix had to avoid regressing: sequential reads, chunk-cache hits, forward
 * and backward seeks (the backward-seek path is exactly what
 * ThumbnailHandlers.extractImageThumbnail's bounds-then-full-decode
 * pattern exercises), eviction under the 32-entry cap, and concurrent
 * readers on the same path (what `pathLocks` is for on its own).
 *
 * The "cache thrashing" group below targets the eviction race itself: many
 * threads reading many distinct paths that exceed the cache's capacity, so
 * openReads' LRU trimming is firing continuously and concurrently with
 * in-flight reads on the paths it's trimming -- the exact scenario
 * entryRemoved()'s old direct `oldValue.close()` could race against. It's
 * a stress test, not a formal proof: correctness under the pendingClose
 * fix no longer depends on timing at all (it's guaranteed by lock
 * discipline -- see the comment on `pendingClose`), so this should now
 * pass reliably rather than "usually," which is itself the thing worth
 * asserting. Before the fix, running this against the old direct-close
 * entryRemoved() would be expected to eventually surface either a
 * mismatch or a read exception under enough iterations.
 *
 * A tiny reversible XOR "cryptor" stands in for real chunk crypto so these
 * tests only exercise ChunkedFileEngine's own offset/chunk-index/seek
 * logic -- if the engine ever passes the wrong chunk number or the wrong
 * offset to the cryptor, XOR-ing with the wrong chunk index produces
 * visibly wrong bytes rather than silently "still valid-looking" output.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class ChunkedFileEngineTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    /** Reversible XOR cipher. decrypt(encrypt(x, n), n) == x for any n; using
     * the wrong chunk number produces different (wrong) output, so a bug
     * that reads the wrong chunk index shows up as a data mismatch. */
    private class FakeCryptor(
        override val headerSize: Int = 16,
        override val cleartextChunkSize: Int = 64,
    ) : VaultChunkCryptor<ByteArray> {
        override val ciphertextChunkSize: Int = cleartextChunkSize

        override fun createHeader(): ByteArray = ByteArray(headerSize) { it.toByte() }
        override fun encodeHeader(header: ByteArray): ByteArray = header
        override fun decodeHeader(bytes: ByteArray): ByteArray = bytes.copyOf()

        private fun transform(data: ByteArray, chunkNumber: Long): ByteArray =
            ByteArray(data.size) { i ->
                (data[i].toInt() xor (chunkNumber.toInt() and 0xFF) xor 0x5A).toByte()
            }

        override fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: ByteArray): ByteArray =
            transform(cleartext, chunkNumber)

        override fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: ByteArray): ByteArray =
            transform(ciphertext, chunkNumber)
    }

    private class FakeDelegate(
        override val context: Context,
        override val cryptor: VaultChunkCryptor<ByteArray>,
        private val files: MutableMap<String, DocumentFile>,
    ) : ChunkedEngineDelegate<ByteArray> {
        override val readOnly: Boolean = true
        override var batchWriteActive: Boolean = false

        override fun getPhysicalFileForRead(virtualPath: String): DocumentFile? = files[virtualPath]
        override fun getOrCreatePhysicalFileForWrite(virtualPath: String): DocumentFile =
            throw UnsupportedOperationException("read-only fake")
        override fun invalidateCacheAfterWrite(virtualPath: String) {}
    }

    /** Writable counterpart to [FakeDelegate], for writeFileChunk/finishWrite/
     *  writeBackFile coverage. getOrCreatePhysicalFileForWrite creates the
     *  target under [dir] (context.filesDir in these tests), which resolves
     *  via RawFileResolver's app-private fast path -- see the "raw-path vs
     *  SAF fallback" group above -- so WriteHandle's directFile != null
     *  branch (the one that writes raw ciphertext straight to disk
     *  incrementally, i.e. the branch this session's fix is actually
     *  about) is what gets exercised, not the SAF/tempFile fallback. */
    private class WritableFakeDelegate(
        override val context: Context,
        override val cryptor: VaultChunkCryptor<ByteArray>,
        private val dir: File,
        private val files: MutableMap<String, DocumentFile> = java.util.concurrent.ConcurrentHashMap(),
    ) : ChunkedEngineDelegate<ByteArray> {
        override val readOnly: Boolean = false
        override var batchWriteActive: Boolean = false
        val invalidated = java.util.Collections.synchronizedList(mutableListOf<String>())

        override fun getPhysicalFileForRead(virtualPath: String): DocumentFile? = files[virtualPath]
        override fun getOrCreatePhysicalFileForWrite(virtualPath: String): DocumentFile =
            files.getOrPut(virtualPath) {
                DocumentFile.fromFile(File(dir, virtualPath).also { it.createNewFile() })
            }
        override fun invalidateCacheAfterWrite(virtualPath: String) {
            invalidated.add(virtualPath)
        }
    }

    /** Writes [cleartext] to a new physical file as header + concatenated
     * encrypted chunks, exactly the layout ChunkedFileEngine.readRange()
     * expects to parse back. */
    private fun writeEncryptedFile(dir: File, name: String, cryptor: FakeCryptor, cleartext: ByteArray): File {
        val header = cryptor.createHeader()
        val out = ByteArrayOutputStream()
        out.write(cryptor.encodeHeader(header))
        var offset = 0
        var chunkNumber = 0L
        while (offset < cleartext.size) {
            val end = minOf(offset + cryptor.cleartextChunkSize, cleartext.size)
            out.write(cryptor.encryptChunk(cleartext.copyOfRange(offset, end), chunkNumber, header))
            chunkNumber++
            offset = end
        }
        val file = File(dir, name)
        file.writeBytes(out.toByteArray())
        return file
    }

    private fun randomBytes(size: Int, seed: Int): ByteArray {
        val rng = Random(seed)
        return ByteArray(size) { rng.nextBytes(1)[0] }
    }

    // ---- basic correctness -----------------------------------------------

    @Test
    fun `single chunk read at offset zero returns correct bytes`() {
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(40, seed = 1) // smaller than one chunk
        val physical = writeEncryptedFile(context.filesDir, "single.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("single.bin" to DocumentFile.fromFile(physical)))
        )

        val result = engine.readFileChunk("single.bin", 0, cleartext.size)

        assertNotNull(result)
        assertArrayEquals(cleartext, result)
    }

    @Test
    fun `read spanning multiple chunks returns correct bytes`() {
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(cryptor.cleartextChunkSize * 5 + 17, seed = 2) // 5 full chunks + a short tail
        val physical = writeEncryptedFile(context.filesDir, "multi.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("multi.bin" to DocumentFile.fromFile(physical)))
        )

        val result = engine.readFileChunk("multi.bin", 0, cleartext.size)

        assertNotNull(result)
        assertArrayEquals(cleartext, result)
    }

    @Test
    fun `unaligned offset and length spanning a chunk boundary returns correct slice`() {
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(cryptor.cleartextChunkSize * 4, seed = 3)
        val physical = writeEncryptedFile(context.filesDir, "unaligned.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("unaligned.bin" to DocumentFile.fromFile(physical)))
        )

        // Straddles the boundary between chunk 1 and chunk 2.
        val offset = cryptor.cleartextChunkSize + 10
        val length = cryptor.cleartextChunkSize
        val expected = cleartext.copyOfRange(offset, offset + length)

        val result = engine.readFileChunk("unaligned.bin", offset.toLong(), length)

        assertNotNull(result)
        assertArrayEquals(expected, result)
    }

    @Test
    fun `reading past end of file returns only the bytes actually available`() {
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(30, seed = 4) // shorter than one chunk
        val physical = writeEncryptedFile(context.filesDir, "short.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("short.bin" to DocumentFile.fromFile(physical)))
        )

        val result = engine.readFileChunk("short.bin", 0, 1000)

        assertNotNull(result)
        assertArrayEquals(cleartext, result)
    }

    // ---- the pattern extractImageThumbnail's bounds-then-full-decode pass exercises ----

    @Test
    fun `forward read followed by a backward seek to offset zero returns correct bytes both times`() {
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(cryptor.cleartextChunkSize * 6, seed = 5)
        val physical = writeEncryptedFile(context.filesDir, "seek.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("seek.bin" to DocumentFile.fromFile(physical)))
        )

        // Mirrors extractImageThumbnail: a small forward read (bounds pass),
        // then a full read starting back at offset 0 (decode pass) on the
        // same underlying handle/cache.
        val boundsPass = engine.readFileChunk("seek.bin", 0, 20)
        assertArrayEquals(cleartext.copyOfRange(0, 20), boundsPass)

        val decodePass = engine.readFileChunk("seek.bin", 0, cleartext.size)
        assertArrayEquals(cleartext, decodePass)
    }

    @Test
    fun `reading the same chunk twice hits the single-chunk cache and returns identical bytes`() {
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(cryptor.cleartextChunkSize * 3, seed = 6)
        val physical = writeEncryptedFile(context.filesDir, "cachehit.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("cachehit.bin" to DocumentFile.fromFile(physical)))
        )

        val first = engine.readFileChunk("cachehit.bin", 0, 10)
        val second = engine.readFileChunk("cachehit.bin", 0, 10)

        assertArrayEquals(cleartext.copyOfRange(0, 10), first)
        assertArrayEquals(first, second)
    }

    // ---- eviction under the 32-entry cap ----------------------------------

    @Test
    fun `re-reading a file evicted from the 32-entry handle cache still returns correct bytes`() {
        val cryptor = FakeCryptor()
        val files = mutableMapOf<String, DocumentFile>()
        val cleartexts = mutableMapOf<String, ByteArray>()

        // One more than openReads' capacity (32) so the first file's handle
        // is guaranteed to have been evicted by the time we get back to it.
        for (i in 0 until 40) {
            val name = "evict_$i.bin"
            val ct = randomBytes(20, seed = 100 + i)
            val physical = writeEncryptedFile(context.filesDir, name, cryptor, ct)
            files[name] = DocumentFile.fromFile(physical)
            cleartexts[name] = ct
        }

        val engine = ChunkedFileEngine(FakeDelegate(context, cryptor, files))

        for (i in 0 until 40) {
            val name = "evict_$i.bin"
            val result = engine.readFileChunk(name, 0, 20)
            assertArrayEquals("mismatch on first pass for $name", cleartexts[name], result)
        }

        // evict_0 should now be cold; re-reading it must transparently
        // reopen + re-decrypt rather than return stale/garbled data.
        val reread = engine.readFileChunk("evict_0.bin", 0, 20)
        assertArrayEquals(cleartexts["evict_0.bin"], reread)
    }

    // ---- cache thrashing: the eviction race itself -------------------------

    @Test
    fun `many threads reading many distinct paths under sustained cache thrashing never see corrupted or missing data`() {
        val cryptor = FakeCryptor()
        // Comfortably more than openReads' 32-entry capacity, so with
        // threadCount readers cycling through all of them the cache is
        // evicting almost continuously -- entryRemoved() fires for some
        // *other* thread's path on essentially every put().
        val pathCount = 60
        val files = mutableMapOf<String, DocumentFile>()
        val cleartexts = mutableMapOf<String, ByteArray>()
        for (i in 0 until pathCount) {
            val name = "thrash_$i.bin"
            // A few chunks each, not just one, so a thread can land mid-file
            // (cachedChunkIndex hit) as well as on a fresh open.
            val ct = randomBytes(cryptor.cleartextChunkSize * 3 + 5, seed = 200 + i)
            val physical = writeEncryptedFile(context.filesDir, name, cryptor, ct)
            files[name] = DocumentFile.fromFile(physical)
            cleartexts[name] = ct
        }

        val engine = ChunkedFileEngine(FakeDelegate(context, cryptor, files))

        val threadCount = 24
        val readsPerThread = 150
        val pool = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)
        val mismatches = AtomicInteger(0)
        val nullReads = AtomicInteger(0)

        // Precompute (path, offset, length) jobs up front -- Random isn't
        // guaranteed thread-safe for concurrent nextInt() calls, and this
        // keeps each thread's workload reproducible across runs.
        val jobs = List(threadCount) { t ->
            val rng = Random(1000 + t)
            List(readsPerThread) {
                val pathIndex = rng.nextInt(0, pathCount)
                val name = "thrash_$pathIndex.bin"
                val ct = cleartexts.getValue(name)
                val len = rng.nextInt(1, ct.size)
                val offset = rng.nextInt(0, ct.size - len + 1)
                Triple(name, offset, len)
            }
        }

        for (t in 0 until threadCount) {
            pool.submit {
                try {
                    for ((name, offset, len) in jobs[t]) {
                        val result = engine.readFileChunk(name, offset.toLong(), len)
                        if (result == null) {
                            nullReads.incrementAndGet()
                            continue
                        }
                        val expected = cleartexts.getValue(name).copyOfRange(offset, offset + len)
                        if (!expected.contentEquals(result)) {
                            mismatches.incrementAndGet()
                        }
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        assertTrue("threads did not finish in time", latch.await(60, TimeUnit.SECONDS))
        pool.shutdown()
        assertEquals("cache thrashing produced unexpected null reads (a race closed a handle out from under an in-flight read)", 0, nullReads.get())
        assertEquals("cache thrashing produced corrupted/wrong data (the eviction race garbled a concurrent read)", 0, mismatches.get())
    }

    @Test
    fun `invalidateAll under concurrent readers never leaks or double-closes a handle`() {
        // Exercises invalidateAll()'s own path-locked drain (see the
        // comment on invalidateAll()) racing against live readers rather
        // than just against openReads' internal LRU trimming.
        val cryptor = FakeCryptor()
        val pathCount = 40
        val files = mutableMapOf<String, DocumentFile>()
        val cleartexts = mutableMapOf<String, ByteArray>()
        for (i in 0 until pathCount) {
            val name = "inv_$i.bin"
            val ct = randomBytes(cryptor.cleartextChunkSize * 2 + 3, seed = 300 + i)
            val physical = writeEncryptedFile(context.filesDir, name, cryptor, ct)
            files[name] = DocumentFile.fromFile(physical)
            cleartexts[name] = ct
        }
        val engine = ChunkedFileEngine(FakeDelegate(context, cryptor, files))

        val readerThreads = 8
        val roundsPerThread = 40
        val pool = Executors.newFixedThreadPool(readerThreads + 1)
        val latch = CountDownLatch(readerThreads + 1)
        val mismatches = AtomicInteger(0)
        val nullReads = AtomicInteger(0)

        for (t in 0 until readerThreads) {
            val rng = Random(2000 + t)
            pool.submit {
                try {
                    repeat(roundsPerThread) {
                        val name = "inv_${rng.nextInt(0, pathCount)}.bin"
                        val result = engine.readFileChunk(name, 0, 10)
                        if (result == null) {
                            nullReads.incrementAndGet()
                        } else if (!cleartexts.getValue(name).copyOfRange(0, 10).contentEquals(result)) {
                            mismatches.incrementAndGet()
                        }
                    }
                } finally {
                    latch.countDown()
                }
            }
        }
        pool.submit {
            try {
                repeat(20) {
                    engine.invalidateAll()
                    Thread.yield()
                }
            } finally {
                latch.countDown()
            }
        }

        assertTrue("threads did not finish in time", latch.await(60, TimeUnit.SECONDS))
        pool.shutdown()
        assertEquals(0, nullReads.get())
        assertEquals(0, mismatches.get())
    }

    // ---- concurrent readers on the same path -------------------------------

    @Test
    fun `many threads reading different ranges of the same path never see corrupted data`() {
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(cryptor.cleartextChunkSize * 20, seed = 7)
        val physical = writeEncryptedFile(context.filesDir, "concurrent.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("concurrent.bin" to DocumentFile.fromFile(physical)))
        )

        val threadCount = 16
        val readsPerThread = 10
        val pool = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)
        val mismatches = AtomicInteger(0)
        val rng = Random(42)
        // Precompute (offset, length) pairs up front -- Random isn't
        // guaranteed thread-safe for concurrent nextInt() calls.
        val jobs = List(threadCount) {
            List(readsPerThread) {
                val len = rng.nextInt(1, cryptor.cleartextChunkSize * 3)
                val offset = rng.nextInt(0, (cleartext.size - len).coerceAtLeast(1))
                offset to len
            }
        }

        for (t in 0 until threadCount) {
            pool.submit {
                try {
                    for ((offset, len) in jobs[t]) {
                        val result = engine.readFileChunk("concurrent.bin", offset.toLong(), len)
                        val expected = cleartext.copyOfRange(offset, offset + len)
                        if (result == null || !expected.contentEquals(result)) {
                            mismatches.incrementAndGet()
                        }
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        assertTrue("threads did not finish in time", latch.await(30, TimeUnit.SECONDS))
        pool.shutdown()
        assertEquals("concurrent reads on the same path returned corrupted/wrong data", 0, mismatches.get())
    }

    // ---- raw-path vs SAF fallback, both correct ----------------------------

    @Test
    fun `raw-path-resolvable file under app-private storage reads correctly`() {
        // Files under context.filesDir resolve via RawFileResolver's
        // app-private fast path (see RawFileResolverTest), so this exercises
        // ChunkedFileEngine.readRange()'s new FileInputStream(rawFile) branch.
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(100, seed = 8)
        val physical = writeEncryptedFile(context.filesDir, "rawpath.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("rawpath.bin" to DocumentFile.fromFile(physical)))
        )

        val result = engine.readFileChunk("rawpath.bin", 0, cleartext.size)

        assertArrayEquals(cleartext, result)
    }

    @Test
    fun `file outside app-private storage with no raw path falls back to SAF and still reads correctly`() {
        // TemporaryFolder's directory is outside context.filesDir and no
        // external storage permission is granted under Robolectric by
        // default, so RawFileResolver returns null here (see
        // RawFileResolverTest) and readRange() must fall back to
        // contentResolver.openFileDescriptor/openInputStream.
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(100, seed = 9)
        val physical = writeEncryptedFile(tempFolder.root, "safpath.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("safpath.bin" to DocumentFile.fromFile(physical)))
        )

        val result = engine.readFileChunk("safpath.bin", 0, cleartext.size)

        assertArrayEquals(cleartext, result)
    }

    // ---- invalidateRead ----------------------------------------------------

    @Test
    fun `invalidateRead drops the cached handle so a subsequent read still succeeds`() {
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(50, seed = 10)
        val physical = writeEncryptedFile(context.filesDir, "invalidate.bin", cryptor, cleartext)
        val engine = ChunkedFileEngine(
            FakeDelegate(context, cryptor, mutableMapOf("invalidate.bin" to DocumentFile.fromFile(physical)))
        )

        engine.readFileChunk("invalidate.bin", 0, 10)
        engine.invalidateRead("invalidate.bin")
        val result = engine.readFileChunk("invalidate.bin", 0, cleartext.size)

        assertArrayEquals(cleartext, result)
    }

    @Test
    fun `reading a path with no physical file returns null instead of throwing`() {
        val cryptor = FakeCryptor()
        val engine = ChunkedFileEngine(FakeDelegate(context, cryptor, mutableMapOf()))

        val result = engine.readFileChunk("does_not_exist.bin", 0, 10)

        assertNull(result)
    }

    // ---- incremental writer (writeFileChunk/finishWrite) vs concurrent reads ----
    // ---- regression tests for this session's fix -----------------------------

    @Test
    fun `writeFileChunk then finishWrite round-trips correctly and a subsequent read sees the full content`() {
        // Basic correctness first, before the concurrency-specific tests
        // below: writeFileChunk/finishWrite had zero test coverage at all
        // before this session (FakeDelegate above is read-only), so this
        // establishes the happy path actually works before testing the race.
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(cryptor.cleartextChunkSize * 3 + 11, seed = 20)
        val delegate = WritableFakeDelegate(context, cryptor, context.filesDir)
        val engine = ChunkedFileEngine(delegate)

        var offset = 0L
        val chunkSize = 17 // deliberately not aligned to cryptor.cleartextChunkSize
        while (offset < cleartext.size) {
            val end = minOf(offset + chunkSize, cleartext.size.toLong())
            val piece = cleartext.copyOfRange(offset.toInt(), end.toInt())
            assertTrue(engine.writeFileChunk("roundtrip.bin", offset, piece))
            offset = end
        }
        assertTrue(engine.finishWrite("roundtrip.bin"))

        val result = engine.readFileChunk("roundtrip.bin", 0, cleartext.size)
        assertArrayEquals(cleartext, result)
        assertEquals(listOf("roundtrip.bin"), delegate.invalidated)
    }

    @Test
    fun `writeFileChunk at a mismatched offset aborts the handle and readFileChunk is not left blocked`() {
        // The offset-mismatch abort branch is one of writeInProgress's
        // cleanup paths (see writeFileChunk's doc comment) -- confirms it
        // actually releases a reader rather than leaking the latch.
        val cryptor = FakeCryptor()
        val delegate = WritableFakeDelegate(context, cryptor, context.filesDir)
        val engine = ChunkedFileEngine(delegate)

        assertTrue(engine.writeFileChunk("mismatch.bin", 0, byteArrayOf(1, 2, 3)))
        // Wrong offset -- should abort and return false, not hang anything.
        assertEquals(false, engine.writeFileChunk("mismatch.bin", 999, byteArrayOf(4, 5)))

        // A read for the same path must return promptly (not block forever)
        // once the aborted session's latch was released. Whatever partial
        // physical file resulted is fine either way -- this is checking for
        // a hang, not a specific content outcome from an aborted write.
        val readCompleted = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(1)
        pool.submit {
            engine.readFileChunk("mismatch.bin", 0, 3)
            readCompleted.countDown()
        }
        assertTrue("read stayed blocked after an aborted write session", readCompleted.await(10, TimeUnit.SECONDS))
        pool.shutdown()
    }

    @Test
    fun `a read for the same path blocks until an in-progress incremental write finishes, then sees complete data`() {
        // The core regression test for this session's fix: reproduces
        // VaultVideoRecorder's shape (many separate writeFileChunk() calls
        // over time, on threads that are not guaranteed to be the same
        // thread) racing a concurrent readFileChunk() for that exact path.
        // Before the fix, readFileChunk could open its own raw
        // FileInputStream on the partially-written target mid-write and
        // read a truncated prefix; after it, readFileChunk must not even
        // start until finishWrite() has committed.
        val cryptor = FakeCryptor()
        val cleartext = randomBytes(cryptor.cleartextChunkSize * 4 + 9, seed = 21)
        val delegate = WritableFakeDelegate(context, cryptor, context.filesDir)
        val engine = ChunkedFileEngine(delegate)

        val firstChunkWritten = CountDownLatch(1)
        val readerMayProceed = CountDownLatch(1) // gates the reader's readFileChunk call
        val readerStarted = CountDownLatch(1)
        val readerFinished = CountDownLatch(1)
        var readResult: ByteArray? = null

        val pool = Executors.newFixedThreadPool(2)
        // Separate, larger pool purely for dispatching each individual
        // writeFileChunk() call onto a fresh thread -- kept apart from the
        // 2-thread coordination pool above so the outer writer/reader tasks
        // (which each occupy one of THOSE 2 threads for the whole test)
        // never contend with the per-chunk dispatch for a thread to run on.
        val chunkDispatchPool = Executors.newCachedThreadPool()

        // Writer: appends the whole file across many small, separately
        // dispatched writeFileChunk() calls (via chunkDispatchPool.submit
        // each time, so consecutive calls are not pinned to one thread),
        // with a deliberate pause after the first chunk so the reader has a
        // real window to try to land mid-write.
        val writerDone = CountDownLatch(1)
        pool.submit {
            var offset = 0L
            val pieceSize = 23
            var firstDone = false
            while (offset < cleartext.size) {
                val end = minOf(offset + pieceSize, cleartext.size.toLong())
                val piece = cleartext.copyOfRange(offset.toInt(), end.toInt())
                val ok = chunkDispatchPool.submit<Boolean> { engine.writeFileChunk("racing.bin", offset, piece) }.get()
                assertTrue("writeFileChunk failed at offset $offset", ok)
                offset = end
                if (!firstDone) {
                    firstDone = true
                    firstChunkWritten.countDown()
                    // Give the reader a real chance to attempt (and, before
                    // the fix, incorrectly succeed at) a mid-write read.
                    readerMayProceed.await(5, TimeUnit.SECONDS)
                    assertTrue(
                        "reader should have entered readFileChunk (and be blocked in it) before the writer resumes",
                        readerStarted.await(5, TimeUnit.SECONDS),
                    )
                    Thread.sleep(200)
                }
            }
            assertTrue(engine.finishWrite("racing.bin"))
            writerDone.countDown()
        }

        // Reader: waits for the first chunk to land, then starts a read for
        // the SAME path while the writer is deliberately paused mid-write.
        pool.submit {
            assertTrue(firstChunkWritten.await(5, TimeUnit.SECONDS))
            readerStarted.countDown()
            readerMayProceed.countDown()
            readResult = engine.readFileChunk("racing.bin", 0, cleartext.size)
            readerFinished.countDown()
        }

        assertTrue("writer did not finish in time", writerDone.await(30, TimeUnit.SECONDS))
        assertTrue("reader did not finish in time", readerFinished.await(30, TimeUnit.SECONDS))
        pool.shutdown()
        chunkDispatchPool.shutdown()

        // The read must see the COMPLETE, correct file -- never a truncated
        // prefix reflecting only the first piece(s) written before the
        // reader entered readFileChunk.
        assertArrayEquals(
            "read overlapping an in-progress incremental write must see the finished file, not a partial one",
            cleartext,
            readResult,
        )
    }

    @Test
    fun `close releases a reader parked waiting on an in-progress write instead of hanging it forever`() {
        // writeInProgress's doc comment on close(): tearing down the engine
        // aborts every open WriteHandle, so a reader that's parked in
        // readFileChunk's wait loop for one of those paths must be released
        // rather than left blocked forever.
        val cryptor = FakeCryptor()
        val delegate = WritableFakeDelegate(context, cryptor, context.filesDir)
        val engine = ChunkedFileEngine(delegate)

        assertTrue(engine.writeFileChunk("neverfinished.bin", 0, byteArrayOf(1, 2, 3)))
        // Deliberately never call finishWrite() -- simulates the engine
        // being torn down (session lock, app backgrounding) mid-recording.

        val readerStarted = CountDownLatch(1)
        val readerFinished = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(1)
        pool.submit {
            readerStarted.countDown()
            engine.readFileChunk("neverfinished.bin", 0, 3)
            readerFinished.countDown()
        }

        assertTrue(readerStarted.await(5, TimeUnit.SECONDS))
        Thread.sleep(200) // let the reader actually reach and block in the wait loop
        engine.close()

        assertTrue("close() must release a reader waiting on an in-progress write, not leave it hanging", readerFinished.await(10, TimeUnit.SECONDS))
        pool.shutdown()
    }
}