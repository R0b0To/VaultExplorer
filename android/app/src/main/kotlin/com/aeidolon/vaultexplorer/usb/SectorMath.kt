package com.aeidolon.vaultexplorer.usb

/**
 * The native layer (jni_callbacks.cpp `usbReadSectors`/`usbWriteSectors`, partition/MBR/GPT code,
 * bitlocker/session_prepare byte helpers) addresses USB media in fixed 512-byte units. A drive whose
 * logical sector is larger (4Kn: 4096) is addressed by [UsbMassStorageDevice] in *its* sectors, so
 * [com.aeidolon.vaultexplorer.bridge.UsbBlockBridge] must translate between the two. This is the pure
 * arithmetic for that, kept free of Android types so it can be unit-tested on the JVM.
 */
object SectorMath {
    /** Unit the native code uses. */
    const val NATIVE_SECTOR = 512

    /**
     * @property deviceStart first device sector to touch
     * @property deviceCount number of device sectors to touch
     * @property innerOffset byte offset of the requested range inside the device-sector buffer
     * @property length requested length in bytes
     */
    data class Span(val deviceStart: Long, val deviceCount: Int, val innerOffset: Int, val length: Int) {
        /** True when the request lies exactly on device-sector boundaries (no read-modify-write needed). */
        fun isAligned(deviceSectorSize: Int): Boolean =
            innerOffset == 0 && length == deviceCount * deviceSectorSize
    }

    /**
     * Maps [count512] native sectors starting at [start512] onto device sectors of [deviceSectorSize]
     * bytes. Returns null for an invalid request (negative values, a sector size that isn't a multiple
     * of 512, or a span too large for one buffer).
     */
    fun span(start512: Long, count512: Int, deviceSectorSize: Int): Span? {
        if (start512 < 0 || count512 < 0) return null
        if (deviceSectorSize < NATIVE_SECTOR || deviceSectorSize % NATIVE_SECTOR != 0) return null
        val byteStart = start512 * NATIVE_SECTOR
        val byteLen = count512.toLong() * NATIVE_SECTOR
        if (byteLen > Int.MAX_VALUE) return null
        val devStart = byteStart / deviceSectorSize
        val devEnd = (byteStart + byteLen + deviceSectorSize - 1) / deviceSectorSize
        val devCount = devEnd - devStart
        if (devCount * deviceSectorSize > Int.MAX_VALUE) return null
        return Span(devStart, devCount.toInt(), (byteStart - devStart * deviceSectorSize).toInt(), byteLen.toInt())
    }
}
