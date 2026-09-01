package com.aeidolon.vaultexplorer.usb

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A non-blocking exclusive lock for a USB device that supports cross-thread
 * ownership.
 *
 * Unlike [java.util.concurrent.locks.ReentrantLock], this does not enforce
 * thread affinity: [tryLock] can be called on the calling/platform thread
 * to fail fast before queueing work, while [unlock] can be called from a
 * background worker thread inside `ioExecutor` when the operation completes.
 *
 * Backed by [AtomicBoolean] to make [unlock] idempotent and immune to permit
 * inflation (unlike [java.util.concurrent.Semaphore]).
 */
class UsbDeviceLock {
    private val inUse = AtomicBoolean(false)

    /**
     * Atomically attempts to acquire exclusive access to the device.
     * @return `true` if acquired, `false` if an operation is already in progress.
     */
    fun tryLock(): Boolean = inUse.compareAndSet(false, true)

    /**
     * Releases exclusive access to the device. Safe to call from any thread
     * and idempotent.
     */
    fun unlock() {
        inUse.set(false)
    }

    val isLocked: Boolean get() = inUse.get()
}

/**
 * One [UsbDeviceLock] per USB device name, handed out on demand.
 *
 * Used to serialize container-creation against the same physical device:
 * two concurrent "create container on deviceName=X" requests must not both
 * partition and format the same drive at once (the second would corrupt
 * whatever the first just wrote), while two creates for *different* device
 * names must run fully concurrently rather than queueing behind each
 * other. [com.aeidolon.vaultexplorer.handlers.UsbContainerHandlers.handleCreateUsbContainer]
 * takes the lock with [UsbDeviceLock.tryLock] (non-blocking) synchronously,
 * before ever touching [java.util.concurrent.ExecutorService] or opening the device,
 * so a second request for a busy device gets an immediate
 * `USB_CREATE_IN_PROGRESS` instead of silently queueing behind a
 * multi-minute format.
 */
object UsbDeviceLocks {
    private val locks = ConcurrentHashMap<String, UsbDeviceLock>()

    fun forDevice(deviceName: String): UsbDeviceLock =
        locks.computeIfAbsent(deviceName) { UsbDeviceLock() }
}