package com.aeidolon.vaultexplorer

import java.io.ByteArrayInputStream
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Fixtures are tiny progressive JPEGs written by Pillow (quality 95). The
 * expected pixels come from a reference implementation of the same DC-only
 * decode; the tolerance covers integer-vs-float rounding.
 */
class JpegDcPreviewTest {

    // 40x24, 4:4:4, progressive -> 5x3 blocks.
    private val fullChroma: ByteArray = Base64.getDecoder().decode(
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUGBgYFBgYGBwkIBgcJBwYGCAsICQoK" +
        "CgoKBggLDAsKDAkKCgr/2wBDAQICAgICAgUDAwUKBwYHCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoK" +
        "CgoKCgoKCgr/wgARCAAYACgDAREAAhEBAxEB/8QAGAAAAwEBAAAAAAAAAAAAAAAAAQcIAgb/xAAbAQACAgMBAAAAAAAAAAAAAAAC" +
        "CAEGAAQHCf/aAAwDAQACEAMQAAABXdBbQ4fWaSx9boLGcNIsa42oNr8korX5HRTBR56UmYOg1Ws9AqtaNCf/xAAbEAACAgMBAAAA" +
        "AAAAAAAAAAAAEAcWAQUVBv/aAAgBAQABBQJeZWDoHRIy1NjKEUJwW//EAC8RAAACBAkNAAAAAAAAAAAAAAABEBESZAQGBxQXoqPi" +
        "4wgTIUFDRWFjcoGDwcP/2gAIAQMBAT8BBDKO3X5/kCRTE5WmGClicrTDEdoTShN9E3m7XMazjPQpTHFa9ShRg91L4KTB7qX0EIu7" +
        "Tt7QQ//EAC4RAAABBgsJAAAAAAAAAAAAAAABEBESExcCBBZBYWNkoqPh4wUHCBQjMUWDw//aAAgBAgEBPwEpo5MCmczbsLUDmrdh" +
        "ag3pbAd/ynUbNmkyiFFKYSUrUdhKeqvZCVFVeyPxM+K9/wAT/wD/xAAnEAAAAgcIAwAAAAAAAAAAAAAAEBESEzM1oqMDBAUjQoKD" +
        "4cHC0f/aAAgBAQAGPwIrbb5N1MHMwvuexYs9KyUrfBFaHYitDs8U4fc//8QAHRAAAgICAwEAAAAAAAAAAAAAAAEQETHwUcHR4f/a" +
        "AAgBAQABPyERjMK+3QtPg25vyq9QqoVCj1mP/9oADAMBAAIAAwAAABByoUDVg0f/xAAcEQACAgIDAAAAAAAAAAAAAAABEAAxESGR" +
        "ofD/2gAIAQMBAT8QFttIINljYXKeg8wbBUoWlJxaf//EAB4RAAIBAwUAAAAAAAAAAAAAAAEQMQARwSAhUfDx/9oACAECAQE/EJLL" +
        "ipIpM7PV8S5X2N6qmNCGa//EAB4QAAEEAwADAAAAAAAAAAAAAAABETFxECFBUYHw/9oACAEBAAE/ECCVmfQyckCA1n3Q5rv4NtHK" +
        "2GnH2SSydDix/9k="
    )

    private val fullChromaExpected = intArrayOf(
        220, 40, 39, 223, 40, 40, 135, 120, 50, 49, 201, 59, 51, 200, 60,
        135, 50, 130, 138, 50, 130, 141, 130, 93, 144, 210, 55, 146, 210, 54,
        50, 60, 220, 53, 60, 220, 146, 141, 135, 238, 220, 50, 241, 220, 49
    )

    // 53x41, 4:2:0, progressive (partial edge blocks and MCUs) -> 7x6 blocks.
    private val subsampled: ByteArray = Base64.getDecoder().decode(
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUGBgYFBgYGBwkIBgcJBwYGCAsICQoK" +
        "CgoKBggLDAsKDAkKCgr/2wBDAQICAgICAgUDAwUKBwYHCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoK" +
        "CgoKCgoKCgr/wgARCAApADUDASIAAhEBAxEB/8QAGgAAAgMBAQAAAAAAAAAAAAAAAQIABwgFCf/EABwBAAICAgMAAAAAAAAAAAAA" +
        "AAMIAgYEBwEFCf/aAAwDAQACEAMQAAABrsg0FtmsGvrBxNG9dlbrU+Mk4JRzcsuMxvU0FmvYWnRq1hFW8WvZYkiTz1IPqDUm2Fj3" +
        "YS/2GwiClV0aSRJ//8QAHhAAAAUFAQAAAAAAAAAAAAAAAAYHFSABBRAWNjX/2gAIAQEAAQUCzZPLpKyeXTLgHEOIJBWeSxoQ0IaF" +
        "BLeFklvCyS3hc//EAC4RAAADAwYPAAAAAAAAAAAAAAABAgMGEQUQIlSi0gQHCBMUFiExNDZBcnSzwf/aAAgBAwEBPwEhlB8lsPIT" +
        "62oKYsYr5VmwzuDCJWlB9GehSyvOsk0yKBJpFsjFBJPco+sATjuvV7S7w1Hder2l3gQd/jD7fpApv//EACwRAAADAwgLAAAAAAAA" +
        "AAAAAAECAwAFBgQHEBEVU6HRCBMiMTM2VHSis9L/2gAIAQIBAT8BaV8OkZt4L6XzU+2nth1zQtCqMrdaWrUMsUojWY2yJFBqqMIh" +
        "vAGtx6XmAZNbj0vMAyYW0jeSJP3BfWrT/8QAKhAAAAIFCwUAAAAAAAAAAAAAACABAgQREwMFMzWBg6KjsbPhEBIUIlH/2gAIAQEA" +
        "Bj8C6yduqTyduqSUWIUOIUOIM04+dDid/pCe5y6UfRWuRyK1yORWuRyRhvNxY7Debix2G83Fif/EAB4QAAIBBAMBAAAAAAAAAAAA" +
        "AAABMRARIPBRweHx/9oACAEBAAE/IRCitxVQorcVFft0LTwafB6nxFZwKwqFVxULD9QIQsP1AhCw/UCP/9oADAMBAAIAAwAAABBb" +
        "0IGLSX8FVX7/xAAaEQEAAgMBAAAAAAAAAAAAAAABEBEAITGh/9oACAEDAQE/EIl+cORINXIaLBNgUGlbWlgk1lvtSf/EABsRAQAD" +
        "AQADAAAAAAAAAAAAAAEAETEQIXGx/9oACAECAQE/EHZl7PjHOWI2qgUiejrVYD4q6UYM2Rtdvuz/xAAeEAACAgIDAQEAAAAAAAAA" +
        "AAAAMQEREIEgQXEh8P/aAAgBAQABPxASPBWCuw+spHgrBXYfWKVkRAIpFA/bSD6b+1FXXV4T7h0rGuxo94bqF2LsaPeG6hdi7Gj3" +
        "huoXZ//Z"
    )

    private val subsampledExpected = intArrayOf(
        222, 40, 39, 222, 40, 40, 143, 84, 31, 176, 116, 63, 52, 200, 59,
        53, 201, 60, 56, 200, 59, 222, 40, 39, 222, 40, 40, 143, 84, 31,
        176, 116, 63, 52, 200, 59, 53, 201, 60, 56, 200, 59, 99, 59, 178,
        100, 60, 179, 97, 79, 93, 162, 144, 158, 177, 198, 35, 178, 199, 36,
        182, 198, 35, 90, 50, 169, 90, 51, 170, 88, 70, 84, 185, 167, 181,
        211, 232, 69, 212, 232, 69, 216, 232, 69, 51, 60, 220, 51, 60, 220,
        76, 72, 108, 173, 169, 205, 242, 220, 49, 243, 220, 50, 246, 220, 49,
        51, 60, 220, 51, 60, 220, 76, 72, 108, 173, 169, 205, 242, 220, 49,
        243, 220, 50, 246, 220, 49
    )

    private fun assertPixels(expected: IntArray, preview: JpegDcPreview.Preview, tolerance: Int) {
        assertEquals(expected.size, preview.width * preview.height * 3)
        for (i in 0 until preview.width * preview.height) {
            val argb = preview.argb[i]
            val actual = intArrayOf((argb shr 16) and 0xFF, (argb shr 8) and 0xFF, argb and 0xFF)
            for (c in 0..2) {
                assertTrue(
                    "pixel $i channel $c: expected ${expected[i * 3 + c]} but was ${actual[c]}",
                    Math.abs(actual[c] - expected[i * 3 + c]) <= tolerance,
                )
            }
            assertEquals(0xFF, (argb shr 24) and 0xFF)
        }
    }

    @Test
    fun fullChromaJpegDecodesToOneBlockPerPixel() {
        val preview = JpegDcPreview.decode(ByteArrayInputStream(fullChroma), 4096)
        assertNotNull(preview)
        assertEquals(5, preview!!.width)
        assertEquals(3, preview.height)
        assertPixels(fullChromaExpected, preview, tolerance = 4)
    }

    @Test
    fun subsampledJpegWithPartialEdgeBlocksDecodes() {
        val preview = JpegDcPreview.decode(ByteArrayInputStream(subsampled), 4096)
        assertNotNull(preview)
        assertEquals(7, preview!!.width)
        assertEquals(6, preview.height)
        assertPixels(subsampledExpected, preview, tolerance = 4)
    }

    @Test
    fun smallTargetBoxFiltersTheBlocksDown() {
        // 5x3 blocks with target 2 -> k = max(1, 5 / 2) = 2 -> ceil(5/2) x ceil(3/2).
        val preview = JpegDcPreview.decode(ByteArrayInputStream(fullChroma), 2)
        assertNotNull(preview)
        assertEquals(3, preview!!.width)
        assertEquals(2, preview.height)
    }

    @Test
    fun truncatedScanDataIsRejectedNotMisdecoded() {
        // Keep the headers and only 10 bytes of the first scan (it has 41).
        var sos = 0
        while (!(fullChroma[sos] == 0xFF.toByte() && fullChroma[sos + 1] == 0xDA.toByte())) sos++
        val segmentLength =
            ((fullChroma[sos + 2].toInt() and 0xFF) shl 8) or (fullChroma[sos + 3].toInt() and 0xFF)
        val cut = fullChroma.copyOf(sos + 2 + segmentLength + 10)
        assertNull(JpegDcPreview.decode(ByteArrayInputStream(cut), 4096))
    }

    @Test
    fun nonJpegAndGarbageReturnNull() {
        assertNull(JpegDcPreview.decode(ByteArrayInputStream(ByteArray(64) { 7 }), 4096))
        assertNull(JpegDcPreview.decode(ByteArrayInputStream(ByteArray(0)), 4096))
    }
}
