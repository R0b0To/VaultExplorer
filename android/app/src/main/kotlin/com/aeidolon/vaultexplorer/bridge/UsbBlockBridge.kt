package com.aeidolon.vaultexplorer.bridge

import com.aeidolon.vaultexplorer.usb.SectorMath
import com.aeidolon.vaultexplorer.usb.UsbIoError
import com.aeidolon.vaultexplorer.usb.UsbMassStorageDevice
import java.util.concurrent.ConcurrentHashMap

object UsbBlockBridge {
    private val devices = ConcurrentHashMap<Int, UsbMassStorageDevice>()
    private val deviceNames = ConcurrentHashMap<Int, String>()
    private val detachedVolIds = ConcurrentHashMap<Int, Boolean>()

    fun register(volId: Int, device: UsbMassStorageDevice, deviceName: String? = null) {
        devices[volId] = device
        detachedVolIds.remove(volId)
        if (deviceName != null) deviceNames[volId] = deviceName else deviceNames.remove(volId)
    }

    fun unregister(volId: Int) {
        devices.remove(volId)?.close()
        deviceNames.remove(volId)
    }

    fun volIdForDeviceName(deviceName: String): Int? =
        deviceNames.entries.firstOrNull { it.value == deviceName }?.key

    fun markDetached(volId: Int) {
        detachedVolIds[volId] = true
    }

    fun wasDetached(volId: Int): Boolean = detachedVolIds.containsKey(volId)

    fun lastError(volId: Int): UsbIoError? = devices[volId]?.lastError

    /**
     * [startSector]/[count] are in the native layer's fixed 512-byte units (see [SectorMath]); the
     * returned array is always exactly `count * 512` bytes, whatever the drive's logical sector size.
     */
    @JvmStatic
    fun readSectors(volId: Int, startSector: Long, count: Int): ByteArray? {
        val device = devices[volId] ?: return null
        val ss = device.sectorSize
        if (ss == SectorMath.NATIVE_SECTOR) {
            val out = ByteArray(count * ss)
            return if (device.readSectors(startSector, count, out)) out else null
        }
        val span = SectorMath.span(startSector, count, ss) ?: return null
        val buf = ByteArray(span.deviceCount * ss)
        if (!device.readSectors(span.deviceStart, span.deviceCount, buf)) return null
        return if (span.isAligned(ss)) buf else buf.copyOfRange(span.innerOffset, span.innerOffset + span.length)
    }

    @JvmStatic
    fun writeSectors(volId: Int, startSector: Long, count: Int, data: ByteArray): Boolean {
        val device = devices[volId] ?: return false
        val ss = device.sectorSize
        // Direct zero-copy: UsbMassStorageDevice already streams up to 512 KB bursts in place
        if (ss == SectorMath.NATIVE_SECTOR) return device.writeSectors(startSector, count, data)
        val span = SectorMath.span(startSector, count, ss) ?: return false
        if (data.size < span.length) return false
        if (span.isAligned(ss)) return device.writeSectors(span.deviceStart, span.deviceCount, data)
        // Not on a device-sector boundary: read-modify-write the covering sectors.
        val buf = ByteArray(span.deviceCount * ss)
        if (!device.readSectors(span.deviceStart, span.deviceCount, buf)) return false
        System.arraycopy(data, 0, buf, span.innerOffset, span.length)
        return device.writeSectors(span.deviceStart, span.deviceCount, buf)
    }

    @JvmStatic
    fun syncDevice(volId: Int): Boolean {
        val device = devices[volId] ?: return false
        return device.sync()
    }
}