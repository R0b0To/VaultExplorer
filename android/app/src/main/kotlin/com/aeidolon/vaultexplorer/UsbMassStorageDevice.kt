package com.aeidolon.vaultexplorer

import android.hardware.usb.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import android.util.Log
import android.os.Build
/**
 * Minimal USB Mass Storage (Bulk-Only Transport) client.
 * Talks SCSI READ(10)/WRITE(10) (or READ(16)/WRITE(16) for drives >2TB —
 * see readCapacity() below) and READ CAPACITY directly to a USB device,
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

    // Flags whether to use 16-byte Command Descriptor Blocks (CDBs). Set to true by readCapacity()
    // if the drive's total sectors exceed the 32-bit limit of standard READ(10)/WRITE(10) (>2TB).
    // Defaults to false (using 10-byte commands) to ensure compatibility with older or cheaper USB
    // mass storage controllers that do not support 16-byte SCSI commands.
    private var use16ByteCdb: Boolean = false

    private var tag: Int = 1

    companion object {
        private const val CBW_SIGNATURE = 0x43425355 // "USBC"
        private const val CSW_SIGNATURE = 0x53425355 // "USBS"
        private const val TIMEOUT_MS = 5000
        private const val TAG = "UsbMassStorage"
        private const val MAX_BULK_CHUNK_BYTES = 16 * 1024
        private const val INITIAL_MAX_SECTORS_PER_COMMAND = 1024 // 512 KB @ 512B — slightly more conservative starting guess
        private const val MIN_SECTORS_PER_COMMAND = 8             // 4 KB floor

        @Volatile private var maxSectorsPerCommand: Int = INITIAL_MAX_SECTORS_PER_COMMAND
        

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

    /** USB Mass Storage Class Bulk-Only Transport §5.3.4 "Reset Recovery".
 *  Must be run after any command that fails mid-transfer (CBW sent but the
 *  data phase or CSW never completed cleanly) — without this, the device's
 *  BOT state machine stays desynced and every subsequent command fails,
 *  even ones that would otherwise succeed at a smaller size. */
private fun resetRecovery() {
    try {
        connection.controlTransfer(
            0x21, // host-to-device, class, interface
            0xFF, // Bulk-Only Mass Storage Reset
            0, intf.id, null, 0, TIMEOUT_MS
        )
        clearHalt(epIn)
        clearHalt(epOut)
    } catch (e: Exception) {
        Log.w(TAG, "resetRecovery: failed: ${e.message}")
    }
}

private fun clearHalt(endpoint: UsbEndpoint) {
    // ClearFeature(ENDPOINT_HALT) — standard USB request, sent as a raw
    // control transfer for broad API-level compatibility.
    connection.controlTransfer(
        0x02,               // host-to-device, standard, endpoint
        0x01,               // CLEAR_FEATURE
        0x00,               // ENDPOINT_HALT
        endpoint.address, null, 0, TIMEOUT_MS
    )
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
    cdb: ByteArray, 
    buffer: ByteArray?, 
    bufferOffset: Int, 
    dataLen: Int, 
    dirIn: Boolean
): Boolean {
    tag++
    val cbw = buildCbw(cdb, dataLen, dirIn)
    val cbwSent = connection.bulkTransfer(epOut, cbw, cbw.size, TIMEOUT_MS)
    if (cbwSent != cbw.size) {
        Log.w(TAG, "executeCommand: CBW send failed (sent=$cbwSent, expected=${cbw.size})")
        resetRecovery()
        return false
    }

    if (dataLen > 0 && buffer != null) {
        var totalTransferred = 0
        val endpoint = if (dirIn) epIn else epOut
        
        while (totalTransferred < dataLen) {
            val chunkSize = minOf(MAX_BULK_CHUNK_BYTES, dataLen - totalTransferred)
            
            // ZERO-COPY: Write/Read directly from/to the exact offset of the master array
            val result = connection.bulkTransfer(
                endpoint, 
                buffer, 
                bufferOffset + totalTransferred, 
                chunkSize, 
                TIMEOUT_MS
            )
            
            if (result <= 0) {
                Log.w(TAG, "executeCommand: bulk transfer failed at offset=$totalTransferred chunkSize=$chunkSize (result=$result)")
                resetRecovery()
                return false
            }
            
            totalTransferred += result
            
            // For IN transfers, receiving less data than requested might indicate the end
            if (dirIn && result < chunkSize) break 
        }
    }

    val csw = ByteArray(13)
    val cswLen = connection.bulkTransfer(epIn, csw, 13, TIMEOUT_MS)
    if (cswLen != 13) {
        Log.w(TAG, "executeCommand: CSW read failed (got=$cswLen)")
        resetRecovery()
        return false
    }
    val sig = ByteBuffer.wrap(csw, 0, 4).order(ByteOrder.LITTLE_ENDIAN).int
    val status = csw[12].toInt()
    if (sig != CSW_SIGNATURE) {
        Log.w(TAG, "executeCommand: CSW signature mismatch")
        resetRecovery()
        return false
    }
    if (status != 0) {
        if (status == 1) requestSense() else resetRecovery()
    }
    return status == 0
}
    // ── SCSI commands ────────────────────────────────────────────────────

    private fun readCapacity(): Boolean {
        if (!readCapacity10()) return false
        if (sectorCount == 0x100000000L) {
            // lastLba == 0xFFFFFFFF (sentinel) → sectorCount computed as
            // lastLba + 1 == 2^32. Real capacity needs the 16-byte command.
            if (!readCapacity16()) return false
            use16ByteCdb = true
        }
        return sectorSize > 0 && sectorCount > 0
    }

    private fun readCapacity10(): Boolean {
    val cdb = byteArrayOf(0x25, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    val data = ByteArray(8)
    
    if (executeCommand(cdb, data, 0, 8, dirIn = true)) {
        val bb = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        val lastLba = bb.int.toLong() and 0xFFFFFFFFL
        sectorCount = lastLba + 1
        sectorSize = bb.int
        return true
    }
    return false
}

private fun readCapacity16(): Boolean {
    val cdb = ByteArray(16).apply {
        this[0] = 0x9E.toByte()
        this[1] = 0x10
        this[13] = 32 // allocLen
    }
    val data = ByteArray(32)
    
    if (executeCommand(cdb, data, 0, 32, dirIn = true)) {
        val bb = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        val lastLba = bb.long
        sectorCount = lastLba + 1
        sectorSize = bb.int
        return true
    }
    return false
}

 fun readSectors(startSector: Long, count: Int, out: ByteArray): Boolean {
    val totalLen = count * sectorSize
    require(out.size >= totalLen)
    var done = 0
    while (done < count) {
        val remaining = count - done
        var chunk = minOf(maxSectorsPerCommand, remaining)
        val attemptChunk = chunk // Remember what we originally attempted
        var succeeded = false
        
        while (chunk > 0) {
            val chunkLen = chunk * sectorSize
            val offset = done * sectorSize
            val cdb = if (use16ByteCdb) buildReadWriteCdb16(0x88, startSector + done, chunk)
          else buildReadWriteCdb10(0x28, startSector + done, chunk)
            
            val ok = executeCommand(cdb, out, offset, chunkLen, dirIn = true)
            if (ok) { 
                succeeded = true
                break 
            }
            
            // If the command failed, stop backing off if we're already at/below the minimum threshold
            if (chunk <= MIN_SECTORS_PER_COMMAND) {
                break
            }
            
            val smaller = chunk / 2
            Log.w(TAG, "readSectors: $chunk-sector command failed, backing off to $smaller")
            chunk = smaller
        }
        
        if (!succeeded) {
            Log.e(TAG, "readSectors: failed even at minimum chunk size at sector ${startSector + done}")
            return false
        }
        
        // Only throttle global maxSectorsPerCommand if we actually had to back off to succeed
        if (chunk < attemptChunk && chunk < maxSectorsPerCommand) {
            maxSectorsPerCommand = chunk
        }
        
        done += chunk
    }
    return true
}

fun writeSectors(startSector: Long, count: Int, data: ByteArray): Boolean {
    val totalLen = count * sectorSize
    require(data.size >= totalLen)
    var done = 0
    while (done < count) {
        val remaining = count - done
        var chunk = minOf(maxSectorsPerCommand, remaining)
        val attemptChunk = chunk // Remember what we originally attempted
        var succeeded = false
        
        while (chunk > 0) {
            val chunkLen = chunk * sectorSize
            val offset = done * sectorSize

            val cdb = if (use16ByteCdb) buildReadWriteCdb16(0x8A, startSector + done, chunk)
            else buildReadWriteCdb10(0x2A, startSector + done, chunk)


            val ok = executeCommand(cdb, data, offset, chunkLen, dirIn = false)
            if (ok) { 
                succeeded = true
                break 
            }
            
            // If the command failed, stop backing off if we're already at/below the minimum threshold
            if (chunk <= MIN_SECTORS_PER_COMMAND) {
                break
            }
            
            val smaller = chunk / 2
            Log.w(TAG, "writeSectors: $chunk-sector command failed, backing off to $smaller")
            chunk = smaller
        }
        
        if (!succeeded) {
            Log.e(TAG, "writeSectors: failed even at minimum chunk size at sector ${startSector + done}")
            return false
        }
        
        // Only throttle global maxSectorsPerCommand if we actually had to back off to succeed
        if (chunk < attemptChunk && chunk < maxSectorsPerCommand) {
            maxSectorsPerCommand = chunk
        }
        
        done += chunk
    }
    return true
}

    // READ(10) opcode 0x28 / WRITE(10) opcode 0x2A — 10-byte CDB, 32-bit
    // LBA field, max addressable sector 0xFFFFFFFE (~2TB at 512B sectors).
    // Used for every drive that readCapacity() determined doesn't need the
    // 16-byte form, which is the overwhelming majority of USB flash drives —
    // kept as the default for maximum compatibility with older/cheaper
    // controllers that may not implement the 16-byte command set at all.
    private fun buildReadWriteCdb10(opcode: Int, startSector: Long, count: Int): ByteArray =
        ByteBuffer.allocate(10).order(ByteOrder.BIG_ENDIAN).apply {
            put(opcode.toByte())
            put(0.toByte())
            putInt(startSector.toInt())
            put(0.toByte())
            putShort(count.toShort())
        }.array()

    // READ(16) opcode 0x88 / WRITE(16) opcode 0x8A — 16-byte CDB, 64-bit
    // LBA field. Only used once readCapacity() has determined the device
    // needs it (see use16ByteCdb doc comment above) — a device reporting
    // the READ CAPACITY(10) sentinel is spec-required to also support
    // these, so switching is safe at that point.
    private fun buildReadWriteCdb16(opcode: Int, startSector: Long, count: Int): ByteArray =
        ByteBuffer.allocate(16).order(ByteOrder.BIG_ENDIAN).apply {
            put(opcode.toByte())
            put(0.toByte())
            putLong(startSector)
            putInt(count)
            put(0.toByte()) // group number
            put(0.toByte()) // control
        }.array()

    fun close() {
        connection.releaseInterface(intf)
        connection.close()
    }
}