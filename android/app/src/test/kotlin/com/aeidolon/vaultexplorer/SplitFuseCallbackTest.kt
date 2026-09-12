package com.aeidolon.vaultexplorer

import android.content.Context
import android.net.Uri
import android.system.ErrnoException
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * SplitFuseCallback.onRead/onWrite (see LocalSplitFuseCallback.kt --
 * SplitFuseCallback is the current class name, kept in the file the
 * typealias comment describes) is the part-boundary orchestration for a
 * FUSE-mounted split container: given a byte range that may span several
 * on-disk parts, find which part(s) it falls into via partIndexFor,
 * clamp to each part's own bounds, and loop. This -- along with
 * SafSplitResolver.isSplitFileName and looksLikeRwModeUnsupported below --
 * previously had zero test coverage despite being exactly the kind of
 * off-by-one-prone logic that would otherwise only surface as silent data
 * corruption at a part boundary. looksLikeRwModeUnsupported is widened
 * from `private` to `internal` (visibility only, no logic touched) so it's
 * directly testable, matching the same pattern already used for
 * FolderVaultChecker's per-format check/repair functions.
 *
 * These tests use genuine on-disk part files (via SplitPartInfo.file),
 * which routes every read/write through the local RandomAccessFile path
 * (see readFromPart/writeToPart's `localFile != null` branch) -- pure
 * java.io, no SAF ContentResolver and no native container code involved,
 * so unlike most of this package this class's core logic is fully
 * testable on a bare JVM. The SAF-pfd fallback path (pread/pwrite,
 * mirror staging for providers that reject random access) is not covered
 * here; it would need a fake DocumentsProvider/ContentResolver, which is a
 * separate, larger effort.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class SplitFuseCallbackTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    /** Writes [content] to a fresh file named [name] under the temp folder and
     *  wraps it as a local (non-SAF) SplitPartInfo. */
    private fun localPart(name: String, content: ByteArray): SplitPartInfo {
        val file = tempFolder.newFile(name)
        file.writeBytes(content)
        return SplitPartInfo(Uri.fromFile(file), content.size.toLong(), file)
    }

    private fun bytesOf(vararg values: Int): ByteArray = ByteArray(values.size) { values[it].toByte() }

    private fun repeated(value: Int, count: Int): ByteArray = ByteArray(count) { value.toByte() }

    // ── onGetSize ────────────────────────────────────────────────────────

    @Test
    fun `onGetSize is the sum of all part sizes`() {
        val parts = listOf(
            localPart("p1", repeated(1, 10)),
            localPart("p2", repeated(2, 20)),
            localPart("p3", repeated(3, 5)),
        )
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        assertEquals(35L, callback.onGetSize())
    }

    @Test
    fun `onGetSize for a single part is that part's size`() {
        val parts = listOf(localPart("solo", repeated(7, 42)))
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        assertEquals(42L, callback.onGetSize())
    }

    // ── onRead: single part ─────────────────────────────────────────────

    @Test
    fun `onRead within a single part returns exactly that slice`() {
        val parts = listOf(localPart("a", bytesOf(10, 11, 12, 13, 14, 15, 16, 17, 18, 19)))
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        val out = ByteArray(4)
        val n = callback.onRead(3, 4, out)

        assertEquals(4, n)
        assertArrayEquals(bytesOf(13, 14, 15, 16), out)
    }

    @Test
    fun `onRead at offset 0 of the first part`() {
        val parts = listOf(localPart("a", bytesOf(1, 2, 3, 4, 5)))
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        val out = ByteArray(3)
        callback.onRead(0, 3, out)

        assertArrayEquals(bytesOf(1, 2, 3), out)
    }

    @Test
    fun `onRead past end of file returns 0`() {
        val parts = listOf(localPart("a", bytesOf(1, 2, 3)))
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        val out = ByteArray(4)
        val n = callback.onRead(3, 4, out)

        assertEquals(0, n)
    }

    @Test
    fun `onRead clamps a request that runs past end of file`() {
        val parts = listOf(localPart("a", bytesOf(1, 2, 3, 4, 5)))
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        val out = ByteArray(10)
        val n = callback.onRead(3, 10, out)

        assertEquals(2, n)
        assertArrayEquals(bytesOf(4, 5), out.copyOf(2))
    }

    // ── onRead: crossing part boundaries -- the actual bug-prone case ──

    @Test
    fun `onRead spanning exactly two parts merges both correctly`() {
        // part0 = [0..4] (5 bytes), part1 = [5..9] (5 bytes) at the global offset space
        val parts = listOf(
            localPart("p0", bytesOf(0, 1, 2, 3, 4)),
            localPart("p1", bytesOf(5, 6, 7, 8, 9)),
        )
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        val out = ByteArray(4)
        // Bytes at global offsets 3,4,5,6 = last two of part0 + first two of part1
        val n = callback.onRead(3, 4, out)

        assertEquals(4, n)
        assertArrayEquals(bytesOf(3, 4, 5, 6), out)
    }

    @Test
    fun `onRead spanning three parts merges all three correctly`() {
        val parts = listOf(
            localPart("p0", repeated(0, 3)),
            localPart("p1", repeated(1, 3)),
            localPart("p2", repeated(2, 3)),
        )
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        // Global layout: [0,0,0, 1,1,1, 2,2,2] -- read offset 2..7 (6 bytes)
        // should be [0, 1,1,1, 2,2]
        val out = ByteArray(6)
        val n = callback.onRead(2, 6, out)

        assertEquals(6, n)
        assertArrayEquals(bytesOf(0, 1, 1, 1, 2, 2), out)
    }

    @Test
    fun `onRead starting exactly at a part boundary`() {
        val parts = listOf(
            localPart("p0", repeated(9, 5)),
            localPart("p1", bytesOf(20, 21, 22)),
        )
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        val out = ByteArray(2)
        // Offset 5 is exactly partStarts[1] -- must resolve to part1, not part0
        val n = callback.onRead(5, 2, out)

        assertEquals(2, n)
        assertArrayEquals(bytesOf(20, 21), out)
    }

    @Test
    fun `onRead ending exactly at a part boundary stays within the first part`() {
        val parts = listOf(
            localPart("p0", bytesOf(1, 2, 3, 4, 5)),
            localPart("p1", bytesOf(100, 101, 102)),
        )
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        val out = ByteArray(2)
        // Offset 3, length 2 -> bytes 4,5 -- the last two bytes of part0, must
        // not spill into part1.
        val n = callback.onRead(3, 2, out)

        assertEquals(2, n)
        assertArrayEquals(bytesOf(4, 5), out)
    }

    @Test
    fun `onRead of zero size returns 0 without touching any part`() {
        val parts = listOf(localPart("a", bytesOf(1, 2, 3)))
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        assertEquals(0, callback.onRead(0, 0, ByteArray(0)))
    }

    @Test
    fun `onRead with a negative offset fails loudly`() {
        val parts = listOf(localPart("a", bytesOf(1, 2, 3)))
        val callback = SplitFuseCallback(context, parts, onReleased = {})

        assertThrows(ErrnoException::class.java) {
            callback.onRead(-1, 1, ByteArray(1))
        }
    }

    // ── onWrite ──────────────────────────────────────────────────────────

    @Test
    fun `onWrite within a single part updates only that part's file`() {
        val p0 = localPart("p0", repeated(0, 5))
        val p1 = localPart("p1", repeated(0, 5))
        val callback = SplitFuseCallback(context, listOf(p0, p1), onReleased = {})

        val n = callback.onWrite(1, 3, bytesOf(9, 9, 9))

        assertEquals(3, n)
        assertArrayEquals(bytesOf(0, 9, 9, 9, 0), p0.file!!.readBytes())
        assertArrayEquals(repeated(0, 5), p1.file!!.readBytes())
    }

    @Test
    fun `onWrite spanning two parts updates both files at the right offsets`() {
        val p0 = localPart("p0", repeated(0, 5))
        val p1 = localPart("p1", repeated(0, 5))
        val callback = SplitFuseCallback(context, listOf(p0, p1), onReleased = {})

        // Global offset 3, length 4 -> last 2 bytes of p0, first 2 of p1
        val n = callback.onWrite(3, 4, bytesOf(9, 9, 9, 9))

        assertEquals(4, n)
        assertArrayEquals(bytesOf(0, 0, 0, 9, 9), p0.file!!.readBytes())
        assertArrayEquals(bytesOf(9, 9, 0, 0, 0), p1.file!!.readBytes())
    }

    @Test
    fun `onWrite then onRead round-trips across a part boundary`() {
        val p0 = localPart("p0", repeated(0, 4))
        val p1 = localPart("p1", repeated(0, 4))
        val callback = SplitFuseCallback(context, listOf(p0, p1), onReleased = {})

        val payload = bytesOf(1, 2, 3, 4, 5, 6)
        callback.onWrite(2, payload.size, payload)

        val out = ByteArray(payload.size)
        val n = callback.onRead(2, payload.size, out)

        assertEquals(payload.size, n)
        assertArrayEquals(payload, out)
    }

    @Test
    fun `onWrite to a read-only callback fails without touching the file`() {
        val p0 = localPart("p0", repeated(0, 5))
        val callback = SplitFuseCallback(context, listOf(p0), readOnly = true, onReleased = {})

        assertThrows(ErrnoException::class.java) {
            callback.onWrite(0, 1, bytesOf(9))
        }
        assertArrayEquals(repeated(0, 5), p0.file!!.readBytes())
    }

    @Test
    fun `onWrite with a negative size fails loudly`() {
        val p0 = localPart("p0", repeated(0, 5))
        val callback = SplitFuseCallback(context, listOf(p0), onReleased = {})

        assertThrows(ErrnoException::class.java) {
            callback.onWrite(0, -1, ByteArray(0))
        }
    }

    // ── onRelease ────────────────────────────────────────────────────────

    @Test
    fun `onRelease invokes the onReleased callback`() {
        var released = false
        val parts = listOf(localPart("a", bytesOf(1)))
        val callback = SplitFuseCallback(context, parts, onReleased = { released = true })

        callback.onRelease()

        assertTrue(released)
    }

    // ── construction guard ───────────────────────────────────────────────

    @Test
    fun `constructing with no parts is rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            SplitFuseCallback(context, emptyList(), onReleased = {})
        }
    }

    // ── SafSplitResolver.isSplitFileName ─────────────────────────────────

    @Test
    fun `isSplitFileName recognizes numeric part suffixes`() {
        assertTrue(SafSplitResolver.isSplitFileName("archive.7z.001"))
        assertTrue(SafSplitResolver.isSplitFileName("movie.mkv.002"))
    }

    @Test
    fun `isSplitFileName recognizes partN suffixes case-insensitively`() {
        assertTrue(SafSplitResolver.isSplitFileName("backup.tar.part1"))
        assertTrue(SafSplitResolver.isSplitFileName("backup.tar.PART2"))
    }

    @Test
    fun `isSplitFileName rejects ordinary filenames`() {
        assertTrue(!SafSplitResolver.isSplitFileName("movie.mkv"))
        assertTrue(!SafSplitResolver.isSplitFileName("readme.txt"))
        assertTrue(!SafSplitResolver.isSplitFileName("archive.7z"))
    }

    // ── looksLikeRwModeUnsupported ───────────────────────────────────────

    @Test
    fun `looksLikeRwModeUnsupported is true for UnsupportedOperationException regardless of message`() {
        assertTrue(looksLikeRwModeUnsupported(UnsupportedOperationException("anything")))
        assertTrue(looksLikeRwModeUnsupported(UnsupportedOperationException()))
    }

    @Test
    fun `looksLikeRwModeUnsupported matches known provider rejection messages`() {
        assertTrue(looksLikeRwModeUnsupported(Exception("Unsupported mode: rw")))
        assertTrue(looksLikeRwModeUnsupported(Exception("mode rw is not permitted for this document")))
    }

    @Test
    fun `looksLikeRwModeUnsupported is false for unrelated errors`() {
        assertTrue(!looksLikeRwModeUnsupported(Exception("network timeout")))
        assertTrue(!looksLikeRwModeUnsupported(java.io.IOException("disk full")))
    }

    @Test
    fun `looksLikeRwModeUnsupported is false for a null message`() {
        assertTrue(!looksLikeRwModeUnsupported(Exception()))
    }
}
