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

    /** True when READ CAPACITY(10) overflowed (device > 2 TiB) but the bridge does not implement
     *  READ CAPACITY(16): only the first 2^32 sectors are addressable, so [sectorCount] is capped. */
    var capacityTruncated: Boolean = false; private set

    /** Compact per-command outcome log of the capacity discovery, appended to the open failure
     *  message so a user's bug report says *why* it failed without needing debug logging. */
    private val openTrace = StringBuilder()
    private var tracing = true
    private var startUnitSent = false
    private var discoveryDeadlineNs = Long.MAX_VALUE
    private fun overBudget(): Boolean = System.nanoTime() > discoveryDeadlineNs

    // How long one command may wait for the device to *answer* (IN data / CSW) before we give up on it
    // and reset. Normal I/O keeps the old single 5 s timeout; capacity discovery is far more patient
    // because a bridge that is spinning up a large HDD can sit on the very first command for 10+ s.
    private var inPatienceMs: Long = TIMEOUT_MS.toLong()
    private var lastTimedOut = false      // did the most recent command end in a timeout (vs a quick STALL/error)?
    private var sawInTraffic = false      // has *anything* come back on the IN pipe in this discovery round?
    private var silentDevice = false      // INQUIRY and TEST UNIT READY both got no answer at all

    private val ioLock = Any()
    // 128 KB per command is the proven maximum size for stable USB BOT transfers; re-derived from the
    // real sector size once it is known (256 sectors @ 512 B, 32 @ 4 KiB).
    private var maxSectorsPerCommand: Int = INITIAL_MAX_SECTORS_PER_COMMAND
    private var minSectorsPerCommand: Int = MIN_SECTORS_PER_COMMAND

    companion object {
        private const val CBW_SIGNATURE = 0x43425355 // "USBC"
        private const val CSW_SIGNATURE = 0x53425355 // "USBS"
        private const val TIMEOUT_MS = 5000
        private const val TAG = "UsbMassStorage"
        private const val READINESS_RETRY_ATTEMPTS = 5
        private const val CAPACITY_RETRY_ATTEMPTS = 3
        private const val CAPACITY_RETRY_DELAY_MS = 250L
        private const val MAX_RETRY_DELAY_MS = 1000L
        // A bulk call that returns an error after (almost) the full timeout is a dead link; one that
        // fails quickly is a STALL, which BOT (§6.7) says to clear and carry on from.
        private const val TIMEOUT_SLACK_MS = 250L
        // NOT READY ("becoming ready" / spinning up) is given this long before giving up.
        private const val NOT_READY_BUDGET_MS = 8000L
        private const val MAX_TRACE_CHARS = 760
        // Safety net for the whole capacity discovery ladder (see readCapacity()).
        private const val DISCOVERY_BUDGET_MS = 120_000L
        // Per-command patience while discovering capacity: first round, then after a reset.
        private const val FIRST_ROUND_PATIENCE_MS = 20_000L
        private const val RESET_ROUND_PATIENCE_MS = 15_000L
        // After a port reset the bridge re-initialises its USB side (and often the disk link).
        private const val PORT_RESET_SETTLE_MS = 1500L
        
        // CRITICAL: Linux kernel drivers/usb/core/devio.c enforces MAX_USBFS_BUFFER_SIZE = 16384.
        // Single bulkTransfer calls larger than 16 KB fail with -EINVAL (-1) immediately.
        private const val MAX_BULK_CHUNK_BYTES = 16 * 1024
        
        // 128 KB per SCSI command provides optimal throughput without endpoint stalls
        private const val INITIAL_MAX_SECTORS_PER_COMMAND = 256
        private const val MIN_SECTORS_PER_COMMAND = 16 // 8 KB floor
        private const val MAX_BYTES_PER_COMMAND = 128 * 1024
        private const val MIN_BYTES_PER_COMMAND = 8 * 1024

        internal fun isSupportedSectorSize(size: Int): Boolean =
            size in 512..65536 && (size and (size - 1)) == 0

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

                    // Select the Bulk-Only alternate setting explicitly (drives that also expose UASP
                    // have a second alt setting) and put the endpoints into a known state. The kernel
                    // driver we just force-detached may have been aborted mid-command. Best effort.
                    val setIfOk = connection.setInterface(intf)
                    if (!setIfOk) {
                        VeLog.d(TAG) { "open: setInterface(alt=${intf.alternateSetting}) not accepted; continuing" }
                    }

                    val msd = UsbMassStorageDevice(connection, intf, epIn, epOut)
                    // Hardware fingerprint first, so a bug report on a non-reproducible drive says what it is:
                    // ids, endpoint packet size (1024 = SuperSpeed, 512 = High-Speed), what the drive asks the
                    // port to supply, and which protocols (50 = BOT, 62 = UASP) its alternate settings offer.
                    msd.trace(deviceFingerprint(device, intf, epIn, setIfOk))
                    val capacityOk = msd.readCapacity()
                    msd.tracing = false
                    if (!capacityOk) {
                        VeLog.w(TAG) {
                            "open: READ CAPACITY failed for ${device.deviceName} " +
                                "lastError=${msd.lastError?.toLogString() ?: "none"} trace=${msd.openTrace}"
                        }
                        val detail = msd.openTrace.toString().trim()
                        msd.close()
                        return UsbOpenResult.Failure(
                            "USB_CAPACITY_FAILED",
                            if (detail.isEmpty()) "Failed to read USB device capacity"
                            else "Failed to read USB device capacity [$detail]",
                        )
                    }
                    VeLog.i(TAG) {
                        "open: ready device=${device.deviceName} sectorSize=${msd.sectorSize} " +
                            "sectorCount=${msd.sectorCount} totalCapacityBytes=${msd.sectorCount * msd.sectorSize} " +
                            "use16ByteCdb=${msd.use16ByteCdb} capacityTruncated=${msd.capacityTruncated} trace=${msd.openTrace}"
                    }
                    return UsbOpenResult.Success(msd)
                }
            }
            return UsbOpenResult.Failure("USB_NOT_FOUND", "No USB mass-storage interface found on device")
        }

        private fun deviceFingerprint(device: UsbDevice, intf: UsbInterface, epIn: UsbEndpoint, setIfOk: Boolean): String {
            val protocols = (0 until device.interfaceCount).map { device.getInterface(it) }
                .filter { it.interfaceClass == 0x08 }
                .joinToString(",") { "%d.%d=%02x".format(it.id, it.alternateSetting, it.interfaceProtocol) }
            val power = try {
                if (device.configurationCount > 0) "${device.getConfiguration(0).maxPower}mA" else "?"
            } catch (_: Exception) { "?" }
            return "dev=%04x:%04x mps=%d pwr=%s if=%s%s".format(
                device.vendorId, device.productId, epIn.maxPacketSize, power, protocols,
                if (setIfOk) "" else " setif=fail",
            )
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
            // A raw CLEAR_FEATURE(ENDPOINT_HALT) only clears the *device* side. SET_INTERFACE goes
            // through the kernel's usb_set_interface(), which also resets the host-side endpoint
            // state (data toggle / xHCI ring) -- without it a drive can time out on every command
            // after the first STALL. Falls back to the kernel's manual clear-halt on single-alt devices.
            connection.setInterface(intf)
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

    /**
     * Reads the 13-byte Command Status Wrapper. Per BOT §6.5 a STALL on the CSW read is cleared and
     * the read retried exactly once; a timeout (dead link) is not retried.
     */
    private fun readCsw(): ByteArray? {
        val csw = ByteArray(13)
        var n = bulkInPatient(csw, 0, 13)
        if (n == 13) return csw
        if (n < 0 && !lastTimedOut) {
            clearHalt(epIn)
            n = bulkInPatient(csw, 0, 13)
            if (n == 13) return csw
        }
        return null
    }

    /**
     * One bulk-IN read that waits up to [inPatienceMs] for the device to answer. A timeout is *not*
     * an error until the patience is used up: the command block was already accepted, so the device is
     * simply not done yet (a bridge waiting for a disk to spin up looks exactly like this), and
     * resetting it would abort that work and start the wait over. A quick failure is a STALL and is
     * returned immediately so the caller can clear the halt (BOT §6.7). Sets [lastTimedOut].
     */
    private fun bulkInPatient(buffer: ByteArray, offset: Int, length: Int): Int {
        val start = System.nanoTime()
        lastTimedOut = false
        while (true) {
            val callStart = System.nanoTime()
            val r = connection.bulkTransfer(epIn, buffer, offset, length, TIMEOUT_MS)
            if (r > 0) sawInTraffic = true
            if (r >= 0) return r
            val callMs = (System.nanoTime() - callStart) / 1_000_000
            if (callMs < TIMEOUT_MS - TIMEOUT_SLACK_MS) return r   // quick failure: STALL / error
            val totalMs = (System.nanoTime() - start) / 1_000_000
            if (totalMs >= inPatienceMs - TIMEOUT_SLACK_MS) { lastTimedOut = true; return r }
            // still within patience: keep waiting without disturbing the device
        }
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
        val got = bulkInPatient(data, 0, 18)
        if (got >= 14) {
            val senseKey = data[2].toInt() and 0x0F
            val asc = data[12].toInt() and 0xFF
            val ascq = data[13].toInt() and 0xFF
            result = Triple(senseKey, asc, ascq)
        } else if (got < 0) {
            clearHalt(epIn)
        }
        if (readCsw() == null) {
            // Phase error: the next command would be sent into an out-of-sync device.
            resetRecovery("request_sense_csw_failed")
        }
        return result
    }

    private fun buildCbw(cdb: ByteArray, dataLen: Int, dirIn: Boolean): ByteArray =
        buildCbw(tag, cdb, dataLen, dirIn)

    private fun briefError(e: UsbIoError?): String = when {
        e == null -> "?"
        e.stage == "CSW_STATUS" && e.senseKey >= 0 ->
            "sense=%d/%02x/%02x".format(e.senseKey, e.asc, e.ascq)
        e.stage == "CSW_STATUS" -> "csw=${e.cswStatus}" + if (e.requestSenseFailed) "(no-sense)" else ""
        // transport failure: say whether the device went silent (timeout) or failed fast (stall/error), and how long it took
        else -> e.stage.lowercase() + (if (lastTimedOut) "+timeout" else "") + "@%.1fs".format(e.elapsedMs / 1000.0)
    }

    internal fun trace(text: String) {
        if (tracing && openTrace.length < MAX_TRACE_CHARS) openTrace.append(text).append(' ')
    }

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
        val ok = executeCommandOnce(cdb, buffer, bufferOffset, dataLen, dirIn, lba, sectorCount, retryNumber)
        if (tracing) {
            val op = if (cdb.isNotEmpty()) cdb[0].toInt() and 0xFF else 0
            trace("%02x=%s".format(op, if (ok) "ok" else briefError(lastError)))
        }
        return ok
    }

    private fun executeCommandOnce(
        cdb: ByteArray,
        buffer: ByteArray?,
        bufferOffset: Int,
        dataLen: Int,
        dirIn: Boolean,
        lba: Long,
        sectorCount: Int,
        retryNumber: Int,
    ): Boolean {
        val cmdStart = System.nanoTime()
        lastTimedOut = false
        fun elapsedMs() = (System.nanoTime() - cmdStart) / 1_000_000.0
        val opcode = if (cdb.isNotEmpty()) cdb[0].toInt() and 0xFF else 0
        val dirLabel = if (dirIn) "IN" else "OUT"
        // READ(10)/READ(16) must deliver every byte; INQUIRY & co. may legitimately return less.
        val mustBeFull = dirIn && (opcode == 0x28 || opcode == 0x88)

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
        var dataStageStalled = false
        if (dataLen > 0 && buffer != null) {
            val endpoint = if (dirIn) epIn else epOut
            while (totalTransferred < dataLen) {
                // Must not exceed MAX_BULK_CHUNK_BYTES (16 KB) for Linux devio compatibility
                val chunkSize = minOf(MAX_BULK_CHUNK_BYTES, dataLen - totalTransferred)
                val callStart = System.nanoTime()
                val result = if (dirIn) {
                    bulkInPatient(buffer, bufferOffset + totalTransferred, chunkSize)
                } else {
                    connection.bulkTransfer(endpoint, buffer, bufferOffset + totalTransferred, chunkSize, TIMEOUT_MS)
                }
                if (result < 0 || (result == 0 && !dirIn)) {
                    val waitedMs = (System.nanoTime() - callStart) / 1_000_000
                    val timedOut = if (dirIn) lastTimedOut else waitedMs >= TIMEOUT_MS - TIMEOUT_SLACK_MS
                    if (timedOut) {
                        // Timeout (after the full patience): the device is not answering at all -- reset.
                        lastTimedOut = true
                        recordError("DATA_TRANSFER", transferredBytes = totalTransferred)
                        VeLog.w(TAG) { "USB_SCSI_FAIL ${lastError?.toLogString()} note=chunkTimeout($result)atOffset($totalTransferred)" }
                        resetRecovery("data_transfer_timeout")
                        return false
                    }
                    // Quick failure = STALL. BOT §6.7.2/§6.7.3: a device that fails a command with a
                    // data phase pending STALLs the pipe and still sends a CSW (with the sense data
                    // available via REQUEST SENSE). Clear the halt and collect that CSW below instead
                    // of resetting, otherwise the sense data is lost and the reset itself raises a
                    // fresh UNIT ATTENTION on the next command.
                    dataStageStalled = true
                    VeLog.d(TAG) { "executeCommand: opcode=0x${opcode.toString(16)} data stage stalled at offset=$totalTransferred" }
                    clearHalt(endpoint)
                    break
                }
                totalTransferred += result
                // A short IN transfer (or a zero-length packet) ends the data phase.
                if (dirIn && result < chunkSize) break
            }
        }

        val csw = readCsw()
        if (csw == null) {
            recordError(if (dataStageStalled) "DATA_TRANSFER" else "CSW_READ", transferredBytes = totalTransferred)
            VeLog.w(TAG) { "USB_SCSI_FAIL ${lastError?.toLogString()} note=cswRead failed (dataStageStalled=$dataStageStalled)" }
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
            return false
        }
        if (dataStageStalled || (mustBeFull && totalTransferred < dataLen)) {
            // The device says "good" but did not deliver the data: never hand that back as a success.
            recordError("DATA_TRANSFER", cswStatus = 0, transferredBytes = totalTransferred)
            VeLog.w(TAG) { "USB_SCSI_FAIL ${lastError?.toLogString()} note=short/stalled data with good status" }
            return false
        }
        return true
    }

    /**
     * Capacity discovery with an escalating recovery ladder. Each rung is only tried if the previous one
     * failed at the *transport* level (the device did not answer, as opposed to answering with a SCSI
     * error, which no reset can fix):
     *
     *  1. plain discovery, very patient (a bridge spinning up a big HDD can need 10+ s for its first answer);
     *  2. Bulk-Only reset recovery, then discover again   (skipped when the device was completely silent,
     *     because a BOT reset is a request to the same firmware that is not answering);
     *  3. USB port reset (hidden `resetDevice()`, best effort -- see [portReset]), settle, re-claim, discover
     *     again: the heavy hammer that un-wedges a hung bridge or a host-side endpoint left half-aborted by
     *     the force-detached kernel driver. Where it is unavailable this is one more patient round.
     */
    private fun readCapacity(): Boolean {
        discoveryDeadlineNs = System.nanoTime() + DISCOVERY_BUDGET_MS * 1_000_000L
        try {
            for (rung in 1..3) {
                when (rung) {
                    1 -> inPatienceMs = FIRST_ROUND_PATIENCE_MS
                    2 -> {
                        if (silentDevice) continue
                        trace("|bot-reset|")
                        resetRecovery("capacity_ladder")
                        inPatienceMs = RESET_ROUND_PATIENCE_MS
                    }
                    3 -> {
                        // No public API resets a USB port; UsbDeviceConnection.resetDevice() is hidden and
                        // may be absent or blocked. Without it this rung is simply one more patient round
                        // (a drive that needs 30+ s to come up still gets its chance).
                        val performed = portReset()
                        if (performed == null) {
                            trace("|port-reset=n/a|")
                            connection.setInterface(intf)
                        } else {
                            trace("|port-reset|")
                        }
                        inPatienceMs = RESET_ROUND_PATIENCE_MS
                    }
                }
                silentDevice = false
                sawInTraffic = false
                if (discoverCapacity()) return finishGeometry()
                val stage = lastError?.stage
                // A real SCSI answer (CHECK CONDITION) is final; so is running out of time.
                if ((stage != null && stage == "CSW_STATUS") || overBudget()) break
            }
            return false
        } finally {
            inPatienceMs = TIMEOUT_MS.toLong()
        }
    }

    /**
     * USB port reset, which re-initialises a hung bridge without touching our claim on the interface.
     * `UsbDeviceConnection.resetDevice()` is **not part of the public SDK** (calling it directly does not
     * compile), so it is looked up reflectively. Returns null when it is unavailable (removed, or blocked
     * by the platform's non-SDK-interface restrictions) and otherwise the reset's own result.
     */
    private fun portReset(): Boolean? {
        val method = try {
            UsbDeviceConnection::class.java.getMethod("resetDevice")
        } catch (e: Throwable) {
            VeLog.i(TAG) { "portReset: resetDevice() not available (${e.javaClass.simpleName})" }
            return null
        }
        val ok = try {
            method.invoke(connection) as? Boolean ?: false
        } catch (e: Throwable) {
            VeLog.w(TAG) { "portReset: resetDevice() blocked/failed (${e.javaClass.simpleName}: ${e.message})" }
            return null
        }
        VeLog.i(TAG) { "portReset: resetDevice() -> $ok" }
        try { Thread.sleep(PORT_RESET_SETTLE_MS) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
        // A reset can drop the claim on some stacks; claiming again is a no-op if we still hold it.
        connection.claimInterface(intf, true)
        connection.setInterface(intf)
        startUnitSent = false
        return ok
    }

    private fun finishGeometry(): Boolean {
        // Size the per-command transfer from the real sector size (was a fixed 256 sectors, i.e. 1 MiB
        // per command on a 4Kn drive).
        maxSectorsPerCommand = maxOf(1, MAX_BYTES_PER_COMMAND / sectorSize)
        minSectorsPerCommand = maxOf(1, MIN_BYTES_PER_COMMAND / sectorSize)
        return true
    }

    private fun discoverCapacity(): Boolean {
        sectorSize = 512
        sectorCount = 0
        use16ByteCdb = false
        capacityTruncated = false
        prepareLun()
        if (silentDevice) return false   // nothing is answering; don't spend more patience on RC10/RC16
        if (readCapacity10WithRetry()) {
            if (sectorCount == 0x100000000L) {
                // lastLba == 0xFFFFFFFF: the capacity does not fit in 32 bits, ask READ CAPACITY(16).
                if (readCapacity16WithRetry()) {
                    use16ByteCdb = true
                } else {
                    // Bridge without READ CAPACITY(16): the first 2^32 sectors are still addressable
                    // with 10-byte CDBs. Better a drive that mounts its first 2 TiB than none at all.
                    VeLog.w(TAG) { "discoverCapacity: RC10 overflowed and RC16 failed; capping at 2^32 sectors" }
                    sectorCount = 0x100000000L
                    capacityTruncated = true
                }
            }
        } else {
            // Any RC10 failure (not only ILLEGAL REQUEST): some bridges only implement the 16-byte form,
            // and a STALLed failure used to hide the sense key that this check relied on.
            if (overBudget() || !readCapacity16WithRetry()) return false
            use16ByteCdb = true
        }
        return sectorCount > 0 && isSupportedSectorSize(sectorSize)
    }

    /**
     * Some USB-to-NVMe bridges report UNIT ATTENTION or NOT READY briefly after
     * their interface is claimed. Run the usual SCSI discovery/readiness probes
     * first, but keep them best-effort so a bridge with incomplete support for
     * either command can still pass the authoritative READ CAPACITY check.
     */
    private fun prepareLun() {
        val inquiry = byteArrayOf(0x12, 0, 0, 0, 36, 0)
        val inquiryData = ByteArray(36)
        var inquirySilent = false
        if (!executeCommand(inquiry, inquiryData, 0, 36, dirIn = true)) {
            VeLog.d(TAG) { "prepareLun: INQUIRY failed; continuing with readiness probe" }
            inquirySilent = lastTimedOut && !sawInTraffic
        } else {
            trace("inq(type=%d,ver=%d)".format(inquiryData[0].toInt() and 0x1F, inquiryData[2].toInt() and 0xFF))
        }

        val testUnitReady = byteArrayOf(0, 0, 0, 0, 0, 0)
        val deadline = System.nanoTime() + NOT_READY_BUDGET_MS * 1_000_000L
        var attempt = 0
        if (inquirySilent) {
            // INQUIRY got no answer in the full patience window. One cheap second opinion (a bridge that
            // only chokes on INQUIRY would still answer this) before declaring the device silent.
            val saved = inPatienceMs
            inPatienceMs = TIMEOUT_MS.toLong()
            val ready = executeCommand(testUnitReady, null, 0, 0, dirIn = false)
            inPatienceMs = saved
            if (ready) return
            if (lastTimedOut && !sawInTraffic) { silentDevice = true; return }
        }
        while (true) {
            if (executeCommand(testUnitReady, null, 0, 0, dirIn = false)) return
            val error = lastError
            val unitAttention = error?.senseKey == 0x06
            val notReady = error?.senseKey == 0x02
            if (notReady && spinUpIfRequired(error)) continue
            // UNIT ATTENTION clears after one report; NOT READY gets a longer, time-based budget.
            val withinBudget = if (notReady) System.nanoTime() < deadline else attempt < READINESS_RETRY_ATTEMPTS - 1
            if ((!unitAttention && !notReady) || !withinBudget) {
                VeLog.d(TAG) {
                    "prepareLun: TEST UNIT READY did not succeed; continuing to READ CAPACITY " +
                        "lastError=${error?.toLogString() ?: "none"}"
                }
                return
            }
            if (!waitBeforeRetry(attempt)) return
            attempt++
        }
    }

    /**
     * NOT READY / "initializing command required" (ASC 04h ASCQ 02h) means the unit is stopped and
     * will stay NOT READY until it gets START STOP UNIT -- waiting never helps. Linux's
     * sd_spinup_disk() sends it here too. Sent at most once per open.
     */
    private fun spinUpIfRequired(error: UsbIoError?): Boolean {
        if (startUnitSent || error?.stage != "CSW_STATUS" ||
            error.senseKey != 0x02 || error.asc != 0x04 || error.ascq != 0x02) return false
        startUnitSent = true
        VeLog.i(TAG) { "spinUpIfRequired: unit stopped (04/02), sending START STOP UNIT" }
        // IMMED=1 so the command itself cannot outlive our bulk timeout; callers keep polling.
        executeCommand(byteArrayOf(0x1B, 0x01, 0, 0, 0x01, 0), null, 0, 0, dirIn = false)
        return true
    }

    private fun readCapacity10WithRetry(): Boolean = retryCapacityRead("READ CAPACITY(10)") {
        readCapacity10()
    }

    private fun readCapacity16WithRetry(): Boolean = retryCapacityRead("READ CAPACITY(16)") {
        readCapacity16()
    }

    private inline fun retryCapacityRead(command: String, read: () -> Boolean): Boolean {
        for (attempt in 0 until CAPACITY_RETRY_ATTEMPTS) {
            if (read()) return true
            val error = lastError
            val retryable = when (error?.stage) {
                "CSW_STATUS" -> error.senseKey == 0x02 || error.senseKey == 0x06
                // One retry can recover a transient BOT transfer failure. A command that already
                // waited out its whole patience window is not retried: the ladder handles that.
                "CBW_SEND", "DATA_TRANSFER", "CSW_READ", "CSW_SIGNATURE" -> attempt == 0 && !lastTimedOut
                else -> false
            }
            if (!retryable || attempt == CAPACITY_RETRY_ATTEMPTS - 1 || overBudget()) {
                VeLog.d(TAG) {
                    "$command stopped retrying at attempt ${attempt + 1}; " +
                        "lastError=${error?.toLogString() ?: "none"}"
                }
                return false
            }
            VeLog.d(TAG) {
                "$command retry ${attempt + 1}/${CAPACITY_RETRY_ATTEMPTS - 1}; " +
                    "lastError=${error?.toLogString() ?: "none"}"
            }
            if (spinUpIfRequired(error)) continue
            if (!waitBeforeRetry(attempt)) return false
        }
        return false
    }

    private fun waitBeforeRetry(attempt: Int): Boolean {
        val delayMs = minOf(CAPACITY_RETRY_DELAY_MS * (attempt + 1), MAX_RETRY_DELAY_MS)
        return try {
            Thread.sleep(delayMs)
            true
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
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

    private fun rangeValid(startSector: Long, count: Int): Boolean =
        count >= 0 && startSector >= 0 && startSector + count <= sectorCount &&
            count.toLong() * sectorSize <= Int.MAX_VALUE

    fun readSectors(startSector: Long, count: Int, out: ByteArray): Boolean {
        if (!rangeValid(startSector, count)) {
            VeLog.e(TAG) { "readSectors: range out of bounds start=$startSector count=$count deviceSectors=$sectorCount" }
            return false
        }
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
                    if (chunk <= minSectorsPerCommand) break
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
        if (!rangeValid(startSector, count)) {
            VeLog.e(TAG) { "writeSectors: range out of bounds start=$startSector count=$count deviceSectors=$sectorCount" }
            return false
        }
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
                    if (chunk <= minSectorsPerCommand) break
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
