package com.aeidolon.vaultexplorer.bridge
import com.aeidolon.vaultexplorer.usb.UsbIoError
import com.aeidolon.vaultexplorer.usb.UsbMassStorageDevice
import com.aeidolon.vaultexplorer.MainActivity

/**
 * Upcall target for native disk_read/disk_write when a volume's backing
 * store is a USB mass-storage device rather than a container file.
 * vaultexplorer.cpp resolves this class + these two @JvmStatic methods once
 * in JNI_OnLoad and calls them directly from disk_read/disk_write — this
 * class never calls into native itself.
 *
 * register()/unregister() are owned by the USB unlock/lock/create flow in
 * MainActivity: native code never opens or closes the USB connection.
 */
object UsbBlockBridge {
    // ConcurrentHashMap, not a plain map: register()/unregister() run on the
    // lock/unlock/create flow's thread while readSectors()/writeSectors()
    // are called from whichever JNI/ioExecutor thread is doing native I/O
    // for one of potentially several concurrently-mounted USB volumes. A
    // plain mutableMapOf() has no safety guarantee under that kind of
    // concurrent get/put from different threads.
    private val devices = java.util.concurrent.ConcurrentHashMap<Int, UsbMassStorageDevice>()

    // volId -> deviceName, kept alongside `devices` so onDeviceDetached()
    // (which only knows the UsbDevice/deviceName that was unplugged) can
    // find the matching in-flight volId even before a ContainerSession
    // exists for it — which is the case for the whole duration of a USB
    // container *create* (a session is only registered on success), unlike
    // an already-unlocked/mounted container.
    private val deviceNames = java.util.concurrent.ConcurrentHashMap<Int, String>()

    // Set (as a marker map) once onDeviceDetached() observes the physical
    // device backing this volId disappear mid-operation. Checked after a
    // native call fails so a generic write/read failure can be reported as
    // USB_DEVICE_DISCONNECTED instead of a less specific error — see
    // UsbContainerHandlers.handleCreateUsbContainer. Bounded by MAX_VOLUMES
    // (a small, fixed slot count), and every entry is removed again by the
    // next register() for that slot, so this can't grow unbounded.
    private val detachedVolIds = java.util.concurrent.ConcurrentHashMap<Int, Boolean>()

    fun register(volId: Int, device: UsbMassStorageDevice, deviceName: String? = null) {
        devices[volId] = device
        detachedVolIds.remove(volId)
        if (deviceName != null) deviceNames[volId] = deviceName else deviceNames.remove(volId)
    }

    fun unregister(volId: Int) {
        devices.remove(volId)?.close()
        deviceNames.remove(volId)
    }

    /** Looks up the volId currently registered for [deviceName], if any —
     *  used by onDeviceDetached() to find an in-flight create/unlock that
     *  has no ContainerSession yet. */
    fun volIdForDeviceName(deviceName: String): Int? =
        deviceNames.entries.firstOrNull { it.value == deviceName }?.key

    /** Marks [volId] as having lost its physical device mid-operation
     *  (called by onDeviceDetached before/instead of a normal unregister,
     *  when there's no mounted session to tear down) without touching
     *  [devices]/[deviceNames] here — the caller decides separately whether
     *  to also unregister(). */
    fun markDetached(volId: Int) {
        detachedVolIds[volId] = true
    }

    fun wasDetached(volId: Int): Boolean = detachedVolIds.containsKey(volId)

    /** Most recent low-level SCSI/transport failure recorded for [volId]'s
     *  device, if any — see [UsbMassStorageDevice.lastError]. Read-only
     *  diagnostic side channel; does not affect read/write behavior. */
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
        return device.writeSectors(startSector, count, data)
    }
}
