package com.aeidolon.vaultexplorer.usb

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The native layer addresses USB media in 512-byte units; [SectorMath.span] maps that onto a drive's
 * real logical sector size (512 or 4096). A wrong mapping reads/writes the wrong place on the device,
 * so every boundary shape is pinned here.
 */
class SectorMathTest {

    @Test
    fun `512-byte drive maps one to one and is always aligned`() {
        val s = SectorMath.span(5, 3, 512)!!
        assertEquals(SectorMath.Span(5, 3, 0, 1536), s)
        assertTrue(s.isAligned(512))
    }

    @Test
    fun `4Kn drive, 4 KiB-aligned request covers exactly the matching device sectors`() {
        val s = SectorMath.span(8, 16, 4096)!! // native sectors 8..23 = bytes 4096..12287
        assertEquals(SectorMath.Span(1, 2, 0, 8192), s)
        assertTrue(s.isAligned(4096))
    }

    @Test
    fun `4Kn drive, request inside one device sector needs read-modify-write`() {
        val s = SectorMath.span(9, 3, 4096)!! // bytes 4608..6143 live in device sector 1
        assertEquals(SectorMath.Span(1, 1, 512, 1536), s)
        assertFalse(s.isAligned(4096))
    }

    @Test
    fun `4Kn drive, request straddling a device-sector boundary covers both sectors`() {
        val s = SectorMath.span(15, 2, 4096)!! // bytes 7680..8703: end of sector 1, start of sector 2
        assertEquals(SectorMath.Span(1, 2, 3584, 1024), s)
        assertFalse(s.isAligned(4096))
    }

    @Test
    fun `MBR and GPT probes (native sectors 0 and 1 to 33) on a 4Kn drive`() {
        assertEquals(SectorMath.Span(0, 1, 0, 512), SectorMath.span(0, 1, 4096))
        // bytes 512..17407 span device sectors 0..4, starting 512 bytes into the first one
        assertEquals(SectorMath.Span(0, 5, 512, 16896), SectorMath.span(1, 33, 4096))
    }

    @Test
    fun `zero-length request is an empty aligned span`() {
        val s = SectorMath.span(8, 0, 4096)!!
        assertEquals(0, s.deviceCount)
        assertEquals(0, s.length)
        assertTrue(s.isAligned(4096))
    }

    @Test
    fun `large LBA does not overflow`() {
        val s = SectorMath.span(7_000_000_000L, 1, 4096)!! // ~3.5 TB offset
        assertEquals(7_000_000_000L * 512 / 4096, s.deviceStart)
        assertEquals(1, s.deviceCount)
    }

    @Test
    fun `invalid requests are rejected`() {
        assertNull(SectorMath.span(-1, 1, 512))
        assertNull(SectorMath.span(0, -1, 512))
        assertNull(SectorMath.span(0, 1, 256))   // smaller than the native unit
        assertNull(SectorMath.span(0, 1, 520))   // not a multiple of 512
        assertNull(SectorMath.span(0, Int.MAX_VALUE, 512)) // more than one buffer can hold
    }
}
