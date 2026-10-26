package com.aeidolon.vaultexplorer.audioedit

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Random

class ReadAheadReaderTest {
    private val data = ByteArray(5_000_000).also { Random(42).nextBytes(it) }

    /** A source over [data] with the MediaDataSource contract: -1 at the end, short reads allowed. */
    private fun source(maxPerRead: Int = Int.MAX_VALUE): (Long, ByteArray, Int, Int) -> Int = { pos, buf, off, size ->
        if (pos >= data.size) {
            -1
        } else {
            val n = minOf(size.toLong(), data.size - pos, maxPerRead.toLong()).toInt()
            System.arraycopy(data, pos.toInt(), buf, off, n)
            n
        }
    }

    private fun readAll(r: ReadAheadReader, position: Long, size: Int): ByteArray {
        val out = ByteArray(size)
        val n = r.readAt(position, out, 0, size)
        return out.copyOf(maxOf(n, 0))
    }

    @Test
    fun aScanInSmallStepsHitsTheSourceOncePerBlock() {
        val r = ReadAheadReader(1_000_000, source())
        var pos = 0L
        while (pos < data.size) {
            val got = readAll(r, pos, 400)
            assertArrayEquals(data.copyOfRange(pos.toInt(), (pos + got.size).toInt()), got)
            pos += got.size
        }
        // 5 MB in 1 MB blocks. A source read per 400-byte step would have been 12,500 of them.
        assertEquals(5, r.sourceReads)
    }

    @Test
    fun readsAreCorrectAnywhereInTheFile() {
        val r = ReadAheadReader(65_536, source())
        val rnd = Random(7)
        repeat(2_000) {
            val pos = rnd.nextInt(data.size - 1).toLong()
            val size = 1 + rnd.nextInt(3_000)
            val got = readAll(r, pos, size)
            assertArrayEquals(data.copyOfRange(pos.toInt(), (pos + got.size).toInt()), got)
        }
    }

    @Test
    fun aReadStraddlingTheEndOfTheBlockReturnsWhatThereIsAndTheNextOneContinues() {
        val r = ReadAheadReader(1_000, source())
        assertEquals(500, readAll(r, 0, 500).size) // loads the block [0, 1000)
        val first = readAll(r, 900, 400) // only 100 bytes of the block are left
        assertEquals(100, first.size)
        val second = readAll(r, 1_000, 300)
        assertArrayEquals(data.copyOfRange(1_000, 1_300), second)
    }

    @Test
    fun aBigReadBypassesTheBlock() {
        val r = ReadAheadReader(1_000, source())
        val got = readAll(r, 10, 5_000)
        assertArrayEquals(data.copyOfRange(10, 5_010), got)
        assertEquals(1, r.sourceReads)
    }

    @Test
    fun theEndOfTheDataIsReportedAsTheSourceReportsIt() {
        val r = ReadAheadReader(1_000_000, source())
        assertEquals(-1, r.readAt(data.size.toLong(), ByteArray(10), 0, 10))
        val tail = readAll(r, data.size - 5L, 100)
        assertArrayEquals(data.copyOfRange(data.size - 5, data.size), tail)
    }

    @Test
    fun aSourceThatReturnsLessThanAskedStillWorks() {
        val r = ReadAheadReader(10_000, source(maxPerRead = 777))
        var pos = 0L
        while (pos < 50_000) {
            val got = readAll(r, pos, 500)
            assertArrayEquals(data.copyOfRange(pos.toInt(), (pos + got.size).toInt()), got)
            pos += got.size
        }
    }

    @Test
    fun zeroSizeReadsDoNothing() {
        val r = ReadAheadReader(1_000, source())
        assertEquals(0, r.readAt(0, ByteArray(1), 0, 0))
        assertEquals(0, r.sourceReads)
    }
}
