package com.aeidolon.vaultexplorer

import android.hardware.usb.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import android.util.Log
/**
 * Minimal USB Mass Storage (Bulk-Only Transport) client.
 * Talks SCSI READ(10)/WRITE(10)/READ CAPACITY(10) directly to a USB device,
 * bypassing any Android-side block/filesystem driver. No root required —
 * claimInterface(force=true) detaches the kernel driver for us.
 */
class UsbMassStorageDevice private constructor(
    private val connection: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val epIn: UsbEndpoint,
    private val epOut: UsbEndpoint,
) {
    var sectorSize: Int = 512; private set
    var sectorCount: Long = 0; private set
    private var tag: Int = 1

    companion object {
        private const val CBW_SIGNATURE = 0x43425355 // "USBC"
        private const val CSW_SIGNATURE = 0x53425355 // "USBS"
        private const val TIMEOUT_MS = 5000
        private const val TAG = "UsbMassStorage"

        fun open(usbManager: UsbManager, device: UsbDevice): UsbMassStorageDevice? {

    for (i in 0 until device.interfaceCount) {
        val intf = device.getInterface(i)

        if (intf.interfaceClass == 0x08 &&
            intf.interfaceSubclass == 0x06 &&
            intf.interfaceProtocol == 0x50) {

            val connection = usbManager.openDevice(device)
            if (connection == null) {
                return null
            }

            val claimed = connection.claimInterface(intf, true)
            if (!claimed) {
                connection.close()
                return null
            }

            var epIn: UsbEndpoint? = null
            var epOut: UsbEndpoint? = null
            for (e in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(e)
                if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
                if (ep.direction == UsbConstants.USB_DIR_IN) epIn = ep else epOut = ep
            }
            if (epIn == null || epOut == null) {
                connection.releaseInterface(intf)
                connection.close()
                return null
            }

            val msd = UsbMassStorageDevice(connection, intf, epIn, epOut)
            val capacityOk = msd.readCapacity()
            if (!capacityOk) {
                msd.close()
                return null
            }
            return msd
        }
    }
    return null
}
    }

    private fun requestSense(): Triple<Int, Int, Int>? {
    // REQUEST SENSE(6) — must use its own CBW/CSW cycle, separate from
    // the failed command. Returns (senseKey, additionalSenseCode, ascQualifier).
    val cdb = byteArrayOf(0x03, 0, 0, 0, 18, 0)
    var result: Triple<Int, Int, Int>? = null

    tag++
    val cbw = buildCbw(cdb, 18, dirIn = true)
    if (connection.bulkTransfer(epOut, cbw, cbw.size, TIMEOUT_MS) != cbw.size) {
        return null
    }
    val data = ByteArray(18)
    val got = connection.bulkTransfer(epIn, data, 18, TIMEOUT_MS)
    if (got >= 14) {
        val senseKey = data[2].toInt() and 0x0F
        val asc = data[12].toInt() and 0xFF
        val ascq = data[13].toInt() and 0xFF
        result = Triple(senseKey, asc, ascq)
    } else {
    }
    val csw = ByteArray(13)
    connection.bulkTransfer(epIn, csw, 13, TIMEOUT_MS) // drain CSW regardless
    return result
}

    // ── Bulk-Only Transport primitives ──────────────────────────────────

    private fun buildCbw(cdb: ByteArray, dataLen: Int, dirIn: Boolean): ByteArray {
        val buf = ByteBuffer.allocate(31).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(CBW_SIGNATURE)
        buf.putInt(tag)
        buf.putInt(dataLen)
        buf.put(if (dirIn) 0x80.toByte() else 0x00)
        buf.put(0) // LUN 0
        buf.put(cdb.size.toByte())
        buf.put(cdb)
        buf.put(ByteArray(31 - buf.position())) // pad CDB field to 16 bytes total layout
        return buf.array()
    }

    /** Sends CBW, transfers [dataLen] bytes via [transfer], reads CSW. Returns true on success. */
    private fun executeCommand(
    cdb: ByteArray, dataLen: Int, dirIn: Boolean,
    transfer: ((ByteArray) -> Unit)?
): Boolean {
    tag++
    val cbw = buildCbw(cdb, dataLen, dirIn)
    val cbwSent = connection.bulkTransfer(epOut, cbw, cbw.size, TIMEOUT_MS)
    if (cbwSent != cbw.size) {
        return false
    }

    if (dataLen > 0 && transfer != null) {
        val dataBuf = ByteArray(dataLen)
        if (dirIn) {
            val got = connection.bulkTransfer(epIn, dataBuf, dataLen, TIMEOUT_MS)
            if (got < 0) return false
            transfer(dataBuf.copyOf(got))
        } else {
            transfer(dataBuf)
            val sent = connection.bulkTransfer(epOut, dataBuf, dataLen, TIMEOUT_MS)
            if (sent != dataLen) return false
        }
    }

    val csw = ByteArray(13)
    val cswLen = connection.bulkTransfer(epIn, csw, 13, TIMEOUT_MS)
    if (cswLen != 13) {
        return false
    }
    val sig = ByteBuffer.wrap(csw, 0, 4).order(ByteOrder.LITTLE_ENDIAN).int
    val status = csw[12].toInt()
    if (sig != CSW_SIGNATURE || status != 0) {
        if (status == 1) {
            requestSense()
        }
    }
    return sig == CSW_SIGNATURE && status == 0
}
    // ── SCSI commands ────────────────────────────────────────────────────

    private fun readCapacity(): Boolean {
        val cdb = byteArrayOf(0x25, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var ok = false
        ok = executeCommand(cdb, 8, dirIn = true) { data ->
            val bb = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
            val lastLba = bb.int.toLong() and 0xFFFFFFFFL
            val blockSize = bb.int
            sectorCount = lastLba + 1
            sectorSize = blockSize
        }
        return ok && sectorSize > 0
    }

 fun readSectors(startSector: Long, count: Int, out: ByteArray): Boolean {
    val dataLen = count * sectorSize
    require(out.size >= dataLen)
    val cdb = ByteBuffer.allocate(10).order(ByteOrder.BIG_ENDIAN).apply {
        put(0x28.toByte()) // READ(10) explicitly Byte
        put(0.toByte())
        putInt(startSector.toInt())
        put(0.toByte())
        putShort(count.toShort())
    }.array()
      
    return executeCommand(cdb, dataLen, dirIn = true) { data ->
        System.arraycopy(data, 0, out, 0, minOf(data.size, dataLen))
    }
}

    /** Writes [count] sectors starting at [startSector] from [data] (count*sectorSize bytes). */
    fun writeSectors(startSector: Long, count: Int, data: ByteArray): Boolean {
        val dataLen = count * sectorSize
        require(data.size >= dataLen)
        val cdb = ByteBuffer.allocate(10).order(ByteOrder.BIG_ENDIAN).apply {
            put(0x2A) // WRITE(10)
            put(0)
            putInt(startSector.toInt())
            put(0)
            putShort(count.toShort())
        }.array()
        return executeCommand(cdb, dataLen, dirIn = false) { buf ->
            System.arraycopy(data, 0, buf, 0, dataLen)
        }
    }

    fun close() {
        connection.releaseInterface(intf)
        connection.close()
    }
}