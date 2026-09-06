package com.aeidolon.vaultexplorer.bridge

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

    @JvmStatic
    fun readSectors(volId: Int, startSector: Long, count: Int): ByteArray? {
        val device = devices[volId] ?: return null
        val out = ByteArray(count * device.sectorSize)
        return if (device.readSectors(startSector, count, out)) out else null
    }

    @JvmStatic
    fun writeSectors(volId: Int, startSector: Long, count: Int, data: ByteArray): Boolean {
        val device = devices[volId] ?: return false
        // Direct zero-copy: UsbMassStorageDevice already streams up to 512 KB bursts in place
        return device.writeSectors(startSector, count, data)
    }

    @JvmStatic
    fun syncDevice(volId: Int): Boolean {
        val device = devices[volId] ?: return false
        return device.sync()
    }
}