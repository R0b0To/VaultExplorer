package com.aeidolon.vaultexplorer.usb

import org.junit.Assert.assertEquals
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * buildCbw's byte layout follows the USB Mass Storage Bulk-Only Transport
 * spec: a fixed 31-byte Command Block Wrapper (4-byte signature, 4-byte
 * tag, 4-byte transfer length, 1-byte direction flag, 1-byte LUN, 1-byte
 * CDB length, then a 16-byte CDB field, right-padded with zeros if the
 * actual CDB is shorter). It was extracted from an instance method (which
 * reads its own tag counter) into this companion function taking the tag
 * explicitly, so the wire layout is testable without a live USB connection.
 *
 * Reads back through a ByteBuffer in the same little-endian byte order the
 * production code writes in, rather than hand-decoding bytes, so a mistake
 * in this test's own byte arithmetic can't silently cancel out a mistake
 * in the code being tested.
 */
class UsbMassStorageDeviceBuildCbwTest {

    private fun readLeInt(cbw: ByteArray, offset: Int): Int =
        ByteBuffer.wrap(cbw, offset, 4).order(ByteOrder.LITTLE_ENDIAN).int

    @Test
    fun `total length is always the fixed 31-byte CBW size`() {
        assertEquals(31, UsbMassStorageDevice.buildCbw(1, byteArrayOf(0x25), 0, dirIn = true).size) // READ CAPACITY(10), 1-byte CDB
        assertEquals(31, UsbMassStorageDevice.buildCbw(1, ByteArray(16) { 0x88.toByte() }, 512, dirIn = true).size) // full 16-byte CDB, e.g. READ(16)
    }

    @Test
    fun `signature decodes to USBC in little-endian`() {
        val cbw = UsbMassStorageDevice.buildCbw(1, byteArrayOf(0x25), 0, dirIn = true)
        assertEquals(0x43425355, readLeInt(cbw, 0))
        assertArrayEquals(byteArrayOf('U'.code.toByte(), 'S'.code.toByte(), 'B'.code.toByte(), 'C'.code.toByte()), cbw.copyOfRange(0, 4))
    }

    @Test
    fun `tag and data transfer length are written little-endian at their fixed offsets`() {
        val cbw = UsbMassStorageDevice.buildCbw(tag = 0x12345678, cdb = byteArrayOf(0x28), dataLen = 8192, dirIn = true)
        assertEquals(0x12345678, readLeInt(cbw, 4))
        assertEquals(8192, readLeInt(cbw, 8))
    }

    @Test
    fun `direction flag is 0x80 for a device-to-host transfer and 0x00 for host-to-device`() {
        val readCbw = UsbMassStorageDevice.buildCbw(1, byteArrayOf(0x28), 512, dirIn = true)
        val writeCbw = UsbMassStorageDevice.buildCbw(1, byteArrayOf(0x2A), 512, dirIn = false)
        assertEquals(0x80.toByte(), readCbw[12])
        assertEquals(0x00.toByte(), writeCbw[12])
    }

    @Test
    fun `LUN byte is always zero -- this client only ever talks to LUN 0`() {
        val cbw = UsbMassStorageDevice.buildCbw(1, byteArrayOf(0x28), 512, dirIn = true)
        assertEquals(0.toByte(), cbw[13])
    }

    @Test
    fun `CDB length byte, the CDB bytes themselves, and zero padding land at the right offsets`() {
        val cdb = byteArrayOf(0x28, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00) // READ(10), 10-byte CDB
        val cbw = UsbMassStorageDevice.buildCbw(1, cdb, 512, dirIn = true)

        assertEquals(10.toByte(), cbw[14])
        assertArrayEquals(cdb, cbw.copyOfRange(15, 25))
        // The 16-byte CDB field runs from offset 15 to 31; a 10-byte CDB
        // leaves 6 bytes of padding, which must be zero, not leftover
        // buffer garbage from a previous command.
        assertTrue(cbw.copyOfRange(25, 31).all { it == 0.toByte() })
    }

    @Test
    fun `a full 16-byte CDB leaves no padding and is not truncated`() {
        val cdb = ByteArray(16) { (it + 1).toByte() }
        val cbw = UsbMassStorageDevice.buildCbw(1, cdb, 0, dirIn = true)
        assertArrayEquals(cdb, cbw.copyOfRange(15, 31))
    }
}