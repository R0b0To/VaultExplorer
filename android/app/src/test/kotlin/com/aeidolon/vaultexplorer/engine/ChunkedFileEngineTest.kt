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
 * thumbnail read for those two backends -- and it previously had zero test
 * coverage despite the class's own comments documenting a real,
 * unmitigated eviction race (see the comment above [ChunkedFileEngine]'s
 * `openReads` field).
 *
 * These tests don't reproduce that race deterministically -- it depends on
 * LruCache's internal eviction running concurrently with a specific
 * in-flight read, which isn't reliably triggerable from outside without
 * hooks into the cache itself. What they do cover is the seek/cache
 * correctness that any future attempt to fix that race must not regress:
 * sequential reads, chunk-cache hits, forward and backward seeks (the
 * backward-seek path is exactly what ThumbnailHandlers.extractImageThumbnail's
 * bounds-then-full-decode pattern exercises), eviction under the 32-entry
 * cap, and concurrent readers on the same path (which is what the per-path
 * `pathLocks` guard above is actually for).
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
}
