package com.aeidolon.vaultexplorer.usb

import android.hardware.usb.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import com.aeidolon.vaultexplorer.VeLog

sealed class UsbOpenResult {
    data class Success(val device: UsbMassStorageDevice) : UsbOpenResult()
    data class Failure(val code: String, val message: String) : UsbOpenResult()
}

/**
 * Minimal USB Mass Storage (Bulk-Only Transport) client.
 * Talks SCSI READ(10)/WRITE(10) (or READ(16)/WRITE(16) for drives >2TB),
 * READ CAPACITY, and SYNCHRONIZE CACHE directly to a USB device.
 */
class UsbMassStorageDevice private constructor(
    private val connection: UsbDeviceConnection,
    private val intf: UsbInterface,
    private val epIn: UsbEndpoint,
    private val epOut: UsbEndpoint,
) {
    var sectorSize: Int = 512; private set
    var sectorCount: Long = 0; private set

    var lastError: UsbIoError? = null; private set
    private var use16ByteCdb: Boolean = false
    private var tag: Int = 1

    private val ioLock = Any()
    // 128 KB (256 sectors @ 512B) is the proven maximum size for stable USB BOT transfers
    private var maxSectorsPerCommand: Int = INITIAL_MAX_SECTORS_PER_COMMAND

    companion object {
        private const val CBW_SIGNATURE = 0x43425355 // "USBC"
        private const val CSW_SIGNATURE = 0x53425355 // "USBS"
        private const val TIMEOUT_MS = 5000
        private const val TAG = "UsbMassStorage"
        
        // CRITICAL: Linux kernel drivers/usb/core/devio.c enforces MAX_USBFS_BUFFER_SIZE = 16384.
        // Single bulkTransfer calls larger than 16 KB fail with -EINVAL (-1) immediately.
        private const val MAX_BULK_CHUNK_BYTES = 16 * 1024
        
        // 128 KB per SCSI command provides optimal throughput without endpoint stalls
        private const val INITIAL_MAX_SECTORS_PER_COMMAND = 256
        private const val MIN_SECTORS_PER_COMMAND = 16 // 8 KB floor

        internal fun buildCbw(tag: Int, cdb: ByteArray, dataLen: Int, dirIn: Boolean): ByteArray {
            val buf = ByteBuffer.allocate(31).order(ByteOrder.LITTLE_ENDIAN)
            buf.putInt(CBW_SIGNATURE)
            buf.putInt(tag)
            buf.putInt(dataLen)
            buf.put(if (dirIn) 0x80.toByte() else 0x00)
            buf.put(0) // LUN 0
            buf.put(cdb.size.toByte())
            buf.put(cdb)
            buf.put(ByteArray(31 - buf.position()))
            return buf.array()
        }

        fun open(usbManager: UsbManager, device: UsbDevice): UsbMassStorageDevice? =
            (openDiagnostic(usbManager, device) as? UsbOpenResult.Success)?.device

        fun openDiagnostic(usbManager: UsbManager, device: UsbDevice): UsbOpenResult {
            for (i in 0 until device.interfaceCount) {
                val intf = device.getInterface(i)
                if (intf.interfaceClass == 0x08 &&
                    intf.interfaceSubclass == 0x06 &&
                    intf.interfaceProtocol == 0x50) {
                    logDeviceIdentity(device, intf)
                    val connection = usbManager.openDevice(device)
                    if (connection == null) {
                        VeLog.w(TAG) { "open: usbManager.openDevice() returned null for ${device.deviceName}" }
                        return UsbOpenResult.Failure("USB_OPEN_FAILED", "Failed to open USB device connection")
                    }

                    val claimed = connection.claimInterface(intf, true)
                    if (!claimed) {
                        VeLog.w(TAG) { "open: claimInterface failed for ${device.deviceName} interfaceId=${intf.id}" }
                        connection.close()
                        return UsbOpenResult.Failure("USB_INTERFACE_CLAIM_FAILED", "Failed to claim USB mass-storage interface")
                    }

                    var epIn: UsbEndpoint? = null
                    var epOut: UsbEndpoint? = null
                    for (e in 0 until intf.endpointCount) {
                        val ep = intf.getEndpoint(e)
                        if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
                        if (ep.direction == UsbConstants.USB_DIR_IN) epIn = ep else epOut = ep
                    }
                    if (epIn == null || epOut == null) {
                        VeLog.w(TAG) { "open: missing bulk endpoint(s) for ${device.deviceName} (epIn=${epIn != null} epOut=${epOut != null})" }
                        connection.releaseInterface(intf)
                        connection.close()
                        return UsbOpenResult.Failure("USB_ENDPOINT_ERROR", "USB device is missing a required bulk endpoint")
                    }

                    val msd = UsbMassStorageDevice(connection, intf, epIn, epOut)
                    val capacityOk = msd.readCapacity()
                    if (!capacityOk) {
                        VeLog.w(TAG) { "open: READ CAPACITY failed for ${device.deviceName}" }
                        msd.close()
                        return UsbOpenResult.Failure("USB_CAPACITY_FAILED", "Failed to read USB device capacity")
                    }
                    VeLog.i(TAG) {
                        "open: ready device=${device.deviceName} sectorSize=${msd.sectorSize} " +
                            "sectorCount=${msd.sectorCount} totalCapacityBytes=${msd.sectorCount * msd.sectorSize} " +
                            "use16ByteCdb=${msd.use16ByteCdb}"
                    }
                    return UsbOpenResult.Success(msd)
                }
            }
            return UsbOpenResult.Failure("USB_NOT_FOUND", "No USB mass-storage interface found on device")
        }

        private fun logDeviceIdentity(device: UsbDevice, intf: UsbInterface) {
            val epDescriptions = (0 until intf.endpointCount).joinToString(", ") { e ->
                val ep = intf.getEndpoint(e)
                "addr=0x${ep.address.toString(16)} type=${ep.type} dir=${if (ep.direction == UsbConstants.USB_DIR_IN) "IN" else "OUT"} maxPacketSize=${ep.maxPacketSize}"
            }
            VeLog.i(TAG) {
                "open: deviceName=${device.deviceName} vendorId=0x${device.vendorId.toString(16)} " +
                    "productId=0x${device.productId.toString(16)} deviceClass=${device.deviceClass} " +
                    "deviceSubclass=${device.deviceSubclass} deviceProtocol=${device.deviceProtocol} " +
                    "manufacturer=${device.manufacturerName ?: "<unknown>"} product=${device.productName ?: "<unknown>"} " +
                    "interfaceId=${intf.id} endpoints=[$epDescriptions]"
            }
        }
    }

    private fun resetRecovery(reason: String = "unknown") {
        val start = System.nanoTime()
        try {
            // Use 1000ms timeout for reset recovery so stalled pipes fail fast instead of hanging the UI for 15s
            connection.controlTransfer(
                0x21,
                0xFF,
                0, intf.id, null, 0, 1000
            )
            clearHalt(epIn)
            clearHalt(epOut)
        } catch (e: Exception) {
            VeLog.w(TAG) { "resetRecovery: failed: ${e.message}" }
        } finally {
            val ms = (System.nanoTime() - start) / 1_000_000.0
            VeLog.d(TAG) { "resetRecovery: reason=$reason took ${"%.2f".format(ms)}ms" }
        }
    }

    private fun clearHalt(endpoint: UsbEndpoint) {
        connection.controlTransfer(
            0x02,
            0x01,
            0x00,
            endpoint.address, null, 0, 1000
        )
    }

    private fun requestSense(): Triple<Int, Int, Int>? {
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
        }
        val csw = ByteArray(13)
        connection.bulkTransfer(epIn, csw, 13, TIMEOUT_MS)
        return result
    }

    private fun buildCbw(cdb: ByteArray, dataLen: Int, dirIn: Boolean): ByteArray =
        buildCbw(tag, cdb, dataLen, dirIn)

    private fun executeCommand(
        cdb: ByteArray,
        buffer: ByteArray?,
        bufferOffset: Int,
        dataLen: Int,
        dirIn: Boolean,
        lba: Long = -1,
        sectorCount: Int = 0,
        retryNumber: Int = 0,
    ): Boolean {
        val cmdStart = System.nanoTime()
        fun elapsedMs() = (System.nanoTime() - cmdStart) / 1_000_000.0
        val opcode = if (cdb.isNotEmpty()) cdb[0].toInt() and 0xFF else 0
        val dirLabel = if (dirIn) "IN" else "OUT"

        fun recordError(stage: String, cswStatus: Int = -1, sense: Triple<Int, Int, Int>? = null,
                        requestSenseFailed: Boolean = false, transferredBytes: Int = 0) {
            lastError = UsbIoError(
                opcode = opcode, lba = lba, sectorCount = sectorCount,
                requestedBytes = dataLen, transferredBytes = transferredBytes, direction = dirLabel,
                cdbSize = cdb.size, stage = stage, cswStatus = cswStatus,
                senseKey = sense?.first ?: -1, asc = sense?.second ?: -1, ascq = sense?.third ?: -1,
                requestSenseFailed = requestSenseFailed, elapsedMs = elapsedMs(), retryNumber = retryNumber,
            )
        }

        tag++
        val cbw = buildCbw(cdb, dataLen, dirIn)
        val cbwSent = connection.bulkTransfer(epOut, cbw, cbw.size, TIMEOUT_MS)
        if (cbwSent != cbw.size) {
            recordError("CBW_SEND")
            VeLog.w(TAG) { "USB_SCSI_FAIL ${lastError?.toLogString()} note=cbwSent($cbwSent)!=expected(${cbw.size})" }
            resetRecovery("cbw_send_failed")
            return false
        }

        var totalTransferred = 0
        if (dataLen > 0 && buffer != null) {
            val endpoint = if (dirIn) epIn else epOut
            while (totalTransferred < dataLen) {
                // Must not exceed MAX_BULK_CHUNK_BYTES (16 KB) for Linux devio compatibility
                val chunkSize = minOf(MAX_BULK_CHUNK_BYTES, dataLen - totalTransferred)
                val result = connection.bulkTransfer(
                    endpoint,
                    buffer,
                    bufferOffset + totalTransferred,
                    chunkSize,
                    TIMEOUT_MS
                )
                if (result <= 0) {
                    recordError("DATA_TRANSFER", transferredBytes = totalTransferred)
                    VeLog.w(TAG) { "USB_SCSI_FAIL ${lastError?.toLogString()} note=chunkResult($result)atOffset($totalTransferred)" }
                    resetRecovery("data_transfer_failed")
                    return false
                }
                totalTransferred += result
                if (dirIn && result < chunkSize) break
            }
        }

        val csw = ByteArray(13)
        val cswLen = connection.bulkTransfer(epIn, csw, 13, TIMEOUT_MS)
        if (cswLen != 13) {
            recordError("CSW_READ", transferredBytes = totalTransferred)
            VeLog.w(TAG) { "USB_SCSI_FAIL ${lastError?.toLogString()} note=cswLen($cswLen)!=13" }
            resetRecovery("csw_read_failed")
            return false
        }
        val sig = ByteBuffer.wrap(csw, 0, 4).order(ByteOrder.LITTLE_ENDIAN).int
        val status = csw[12].toInt()
        if (sig != CSW_SIGNATURE) {
            recordError("CSW_SIGNATURE", transferredBytes = totalTransferred)
            VeLog.w(TAG) { "USB_SCSI_FAIL ${lastError?.toLogString()} note=sig=0x${sig.toString(16)}" }
            resetRecovery("csw_signature_mismatch")
            return false
        }
        if (status != 0) {
            var sense: Triple<Int, Int, Int>? = null
            var senseFailed = false
            if (status == 1) {
                sense = requestSense()
                senseFailed = sense == null
                if (senseFailed) VeLog.w(TAG) { "executeCommand: REQUEST SENSE itself failed after status=1" }
            } else {
                resetRecovery("csw_status_$status")
            }
            recordError("CSW_STATUS", cswStatus = status, sense = sense,
                       requestSenseFailed = senseFailed, transferredBytes = totalTransferred)
            VeLog.w(TAG) { "USB_SCSI_FAIL ${lastError?.toLogString()}" }
        }
        return status == 0
    }

    private fun readCapacity(): Boolean {
        if (!readCapacity10()) return false
        if (sectorCount == 0x100000000L) {
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
            this[13] = 32
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
        return synchronized(ioLock) {
            val totalLen = count * sectorSize
            require(out.size >= totalLen)
            var done = 0
            var minAttemptedChunk = maxSectorsPerCommand
            while (done < count) {
                val remaining = count - done
                var chunk = minOf(maxSectorsPerCommand, remaining)
                val attemptChunk = chunk
                var succeeded = false
                var retryNumber = 0
                while (chunk > 0) {
                    if (chunk < minAttemptedChunk) minAttemptedChunk = chunk
                    val chunkLen = chunk * sectorSize
                    val offset = done * sectorSize
                    val cdb = if (use16ByteCdb) buildReadWriteCdb16(0x88, startSector + done, chunk)
                    else buildReadWriteCdb10(0x28, startSector + done, chunk)
                    val ok = executeCommand(cdb, out, offset, chunkLen, dirIn = true,
                                            lba = startSector + done, sectorCount = chunk, retryNumber = retryNumber)
                    if (ok) {
                        succeeded = true
                        break
                    }
                    if (chunk <= MIN_SECTORS_PER_COMMAND) break
                    val smaller = chunk / 2
                    retryNumber++
                    chunk = smaller
                }
                if (!succeeded) {
                    VeLog.e(TAG) { "readSectors: failed at sector ${startSector + done}" }
                    return false
                }
                if (chunk < attemptChunk && chunk < maxSectorsPerCommand) {
                    maxSectorsPerCommand = chunk
                }
                done += chunk
            }
            true
        }
    }

    fun writeSectors(startSector: Long, count: Int, data: ByteArray): Boolean {
        return synchronized(ioLock) {
            val totalLen = count * sectorSize
            require(data.size >= totalLen)
            var done = 0
            var minAttemptedChunk = maxSectorsPerCommand
            while (done < count) {
                val remaining = count - done
                var chunk = minOf(maxSectorsPerCommand, remaining)
                val attemptChunk = chunk
                var succeeded = false
                var retryNumber = 0
                while (chunk > 0) {
                    if (chunk < minAttemptedChunk) minAttemptedChunk = chunk
                    val chunkLen = chunk * sectorSize
                    val offset = done * sectorSize
                    val cdb = if (use16ByteCdb) buildReadWriteCdb16(0x8A, startSector + done, chunk)
                    else buildReadWriteCdb10(0x2A, startSector + done, chunk)
                    val ok = executeCommand(cdb, data, offset, chunkLen, dirIn = false,
                                            lba = startSector + done, sectorCount = chunk, retryNumber = retryNumber)
                    if (ok) {
                        succeeded = true
                        break
                    }
                    if (chunk <= MIN_SECTORS_PER_COMMAND) break
                    val smaller = chunk / 2
                    retryNumber++
                    chunk = smaller
                }
                if (!succeeded) {
                    VeLog.e(TAG) { "writeSectors: failed at sector ${startSector + done}" }
                    return false
                }
                if (chunk < attemptChunk && chunk < maxSectorsPerCommand) {
                    maxSectorsPerCommand = chunk
                }
                done += chunk
            }
            true
        }
    }

    fun sync(): Boolean {
        return synchronized(ioLock) {
            val cdb = ByteArray(10).apply {
                this[0] = 0x35.toByte() // SYNCHRONIZE CACHE (10)
            }
            val ok = executeCommand(cdb, null, 0, 0, dirIn = false)
            if (!ok) {
                if (lastError?.senseKey == 0x05) {
                    VeLog.d(TAG) { "sync: drive reported ILLEGAL REQUEST for SYNCHRONIZE CACHE (no volatile cache)" }
                    return true
                }
                VeLog.w(TAG) { "sync: SYNCHRONIZE CACHE failed on device" }
                return false
            }
            VeLog.d(TAG) { "sync: SYNCHRONIZE CACHE successful" }
            true
        }
    }

    private fun buildReadWriteCdb10(opcode: Int, startSector: Long, count: Int): ByteArray =
        ByteBuffer.allocate(10).order(ByteOrder.BIG_ENDIAN).apply {
            put(opcode.toByte())
            put(0.toByte())
            putInt(startSector.toInt())
            put(0.toByte())
            putShort(count.toShort())
        }.array()

    private fun buildReadWriteCdb16(opcode: Int, startSector: Long, count: Int): ByteArray =
        ByteBuffer.allocate(16).order(ByteOrder.BIG_ENDIAN).apply {
            put(opcode.toByte())
            put(0.toByte())
            putLong(startSector)
            putInt(count)
            put(0.toByte())
            put(0.toByte())
        }.array()

    fun close() {
        synchronized(ioLock) {
            connection.releaseInterface(intf)
            connection.close()
        }
    }
}