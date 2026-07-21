package com.aeidolon.vaultexplorer

/**
 * Upcall target for native disk_read/disk_write when a volume's backing
 * store is a USB mass-storage device rather than a container file.
 * vaultexplorer.cpp resolves this class + these two @JvmStatic methods once
 * in JNI_OnLoad and calls them directly from disk_read/disk_write — this
 * class never calls into native itself.
 *
 * register()/unregister() are owned by the USB unlock/lock flow in
 * MainActivity: native code never opens or closes the USB connection.
 */
object UsbBlockBridge {
    // ConcurrentHashMap, not a plain map: register()/unregister() run on the
    // lock/unlock flow's thread while readSectors()/writeSectors() are
    // called from whichever JNI/ioExecutor thread is doing native I/O for
    // one of potentially several concurrently-mounted USB volumes. A plain
    // mutableMapOf() has no safety guarantee under that kind of concurrent
    // get/put from different threads.
    private val devices = java.util.concurrent.ConcurrentHashMap<Int, UsbMassStorageDevice>()

    fun register(volId: Int, device: UsbMassStorageDevice) {
        devices[volId] = device
    }

    fun unregister(volId: Int) {
        devices.remove(volId)?.close()
    }

    @JvmStatic
    fun readSectors(volId: Int, startSector: Long, count: Int): ByteArray? {
        val device = devices[volId] ?: return null
        val out = ByteArray(count * device.sectorSize)
        return if (device.readSectors(startSector, count, out)) out else null
    }

    @JvmStatic
    fun writeSectors(volId: Int, startSector: Long, count: Int, data: ByteArray): Boolean {
        val device = devices[volId] ?: return false
        return device.writeSectors(startSector, count, data)
    }
}