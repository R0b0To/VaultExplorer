package com.aeidolon.vaultexplorer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageDecodeGuardTest {

    /** SOI + SOF segment with the given marker and (id, h<<4|v) components. */
    private fun jpegHeader(sofMarker: Int, vararg sampling: Int): ByteArray {
        val components = sampling.size
        val length = 8 + 3 * components
        val out = ArrayList<Byte>()
        fun put(vararg v: Int) = v.forEach { out.add(it.toByte()) }
        put(0xFF, 0xD8)
        // A leading APP0 segment, so the scanner has to skip over something.
        put(0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00)
        put(0xFF, sofMarker, length shr 8, length and 0xFF, 8, 0x00, 0x10, 0x00, 0x10, components)
        sampling.forEachIndexed { index, hv -> put(index + 1, hv, 0) }
        return out.toByteArray()
    }

    private fun pngHeader(interlaceMethod: Int): ByteArray {
        val b = ByteArray(33)
        val signature = intArrayOf(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        signature.forEachIndexed { i, v -> b[i] = v.toByte() }
        b[11] = 13
        b[12] = 0x49 // I
        b[13] = 0x48 // H
        b[14] = 0x44 // D
        b[15] = 0x52 // R
        b[28] = interlaceMethod.toByte()
        return b
    }

    @Test
    fun baselineJpegIsAStreamingDecodeHoweverBigItIs() {
        val header = jpegHeader(0xC0, 0x11, 0x11, 0x11)
        assertEquals(
            ImageDecodeGuard.STREAMING_DECODE_BYTES,
            ImageDecodeGuard.estimateWorkingSetBytes(header, 47770, 17949),
        )
    }

    @Test
    fun progressiveFullChromaJpegNeedsSixBytesPerPixel() {
        val header = jpegHeader(0xC2, 0x11, 0x11, 0x11)
        val pixels = 47770L * 17949L
        assertEquals(
            ImageDecodeGuard.STREAMING_DECODE_BYTES + pixels * 6,
            ImageDecodeGuard.estimateWorkingSetBytes(header, 47770, 17949),
        )
        // ~5 GB: far beyond the limit, which is what the low-memory killer enforced.
        assertTrue(
            ImageDecodeGuard.estimateWorkingSetBytes(header, 47770, 17949) >
                ImageDecodeGuard.MAX_DECODE_ESTIMATE_BYTES,
        )
    }

    @Test
    fun progressiveSubsampledJpegNeedsThreeBytesPerPixel() {
        // 4:2:0 -- luma 2x2, both chroma 1x1.
        val header = jpegHeader(0xC2, 0x22, 0x11, 0x11)
        val pixels = 10_000L * 10_000L
        assertEquals(
            ImageDecodeGuard.STREAMING_DECODE_BYTES + pixels * 3,
            ImageDecodeGuard.estimateWorkingSetBytes(header, 10_000, 10_000),
        )
    }

    @Test
    fun pngInterlacingDecidesWhetherItStreams() {
        assertEquals(false, ImageDecodeGuard.sniffPngInterlaced(pngHeader(0)))
        assertEquals(true, ImageDecodeGuard.sniffPngInterlaced(pngHeader(1)))
        assertEquals(
            ImageDecodeGuard.STREAMING_DECODE_BYTES,
            ImageDecodeGuard.estimateWorkingSetBytes(pngHeader(0), 30_000, 30_000),
        )
        assertEquals(
            30_000L * 30_000L * 8,
            ImageDecodeGuard.estimateWorkingSetBytes(pngHeader(1), 30_000, 30_000),
        )
    }

    @Test
    fun unknownOrMissingHeaderAssumesTheWorstCase() {
        val worst = 1000L * 1000L * ImageDecodeGuard.WORST_CASE_BYTES_PER_PIXEL
        assertEquals(worst, ImageDecodeGuard.estimateWorkingSetBytes(null, 1000, 1000))
        assertEquals(
            worst,
            ImageDecodeGuard.estimateWorkingSetBytes(ByteArray(64) { 7 }, 1000, 1000),
        )
    }

    @Test
    fun truncatedOrForeignHeadersAreNotMisread() {
        assertNull(ImageDecodeGuard.sniffJpeg(byteArrayOf(0x00, 0x01, 0x02, 0x03)))
        // SOI then a scan marker with no SOF before it.
        assertNull(ImageDecodeGuard.sniffJpeg(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xDA.toByte(), 0, 0)))
        assertNull(ImageDecodeGuard.sniffPngInterlaced(ByteArray(40)))
        assertNotNull(ImageDecodeGuard.sniffJpeg(jpegHeader(0xC0, 0x11)))
        assertFalse(ImageDecodeGuard.sniffJpeg(jpegHeader(0xC1, 0x11))!!.progressive)
    }
}
