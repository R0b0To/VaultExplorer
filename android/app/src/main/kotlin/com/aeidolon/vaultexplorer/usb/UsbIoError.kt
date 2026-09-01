package com.aeidolon.vaultexplorer.usb

/**
 * Structured diagnostics for the most recent failed [UsbMassStorageDevice]
 * command. Populated by [UsbMassStorageDevice.executeCommand] on any
 * non-success outcome and exposed read-only via
 * [UsbMassStorageDevice.lastError] (and, for a registered volume, via
 * `UsbBlockBridge.lastError(volId)`) so a caller several layers up — e.g.
 * the USB container-creation flow — can enrich an otherwise-generic
 * "write failed" into something a user's bug report is actually useful
 * for, without every intermediate layer (physicalWrite, disk_write, the
 * JNI bridge) needing its own copy of this shape.
 *
 * `stage` records which part of the Bulk-Only Transport sequence failed —
 * "CBW_SEND" / "DATA_TRANSFER" / "CSW_READ" / "CSW_SIGNATURE" /
 * "CSW_STATUS" — since a command can fail before a CSW ever comes back at
 * all, in which case [cswStatus]/[senseKey]/[asc]/[ascq] are unavailable
 * (left at their default/-1 values) rather than misleadingly zero.
 *
 * Never carries raw transfer buffers, only shape/status metadata — see the
 * "no raw data buffers, no per-4KB logging" guidance this mirrors.
 */
data class UsbIoError(
    val opcode: Int,
    val lba: Long,
    val sectorCount: Int,
    val requestedBytes: Int,
    val transferredBytes: Int,
    val direction: String,       // "IN" or "OUT"
    val cdbSize: Int,
    val stage: String,           // CBW_SEND / DATA_TRANSFER / CSW_READ / CSW_SIGNATURE / CSW_STATUS
    val cswStatus: Int = -1,     // -1 = no CSW was read
    val senseKey: Int = -1,
    val asc: Int = -1,
    val ascq: Int = -1,
    val requestSenseFailed: Boolean = false,
    val elapsedMs: Double = 0.0,
    val retryNumber: Int = 0,
) {
    /** One-line, log-friendly rendering — matches the USB_SCSI_FAIL field
     *  set from the reliability-fix spec (opcode/lba/sectors/bytes/status/
     *  sense), without ever including a raw buffer. */
    fun toLogString(): String =
        "opcode=0x${opcode.toString(16)} lba=$lba sectors=$sectorCount " +
            "requestedBytes=$requestedBytes transferredBytes=$transferredBytes " +
            "dir=$direction cdbSize=$cdbSize stage=$stage cswStatus=$cswStatus " +
            "senseKey=$senseKey asc=$asc ascq=$ascq requestSenseFailed=$requestSenseFailed " +
            "retry=$retryNumber elapsedMs=${"%.2f".format(elapsedMs)}"
}
