package com.aeidolon.vaultexplorer

import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * Per-USB-device pending permission requests.
 *
 * [UsbContainerHandlers] used to keep a single global
 * `pendingUsbPermissionResult`/`pendingUsbPermissionDeviceName` pair, so a
 * second in-flight `requestUsbPermission()` call (for a *different* device)
 * would silently overwrite the first request's callback — the first
 * caller's [MethodChannel.Result] then never completes. Keying by device
 * name here means concurrent requests for different devices are fully
 * independent, and a duplicate request for the *same* device is rejected
 * explicitly (see [put]) rather than silently clobbering the earlier one.
 *
 * A plain [ConcurrentHashMap] (not `synchronized`) is enough on its own:
 * [put] uses `putIfAbsent` and [take]/[cancelAll] use `remove`, both single
 * atomic map operations, so the broadcast receiver's "extract the pending
 * request and complete it" step can't race a fresh `requestUsbPermission()`
 * call for the same device.
 */
class PendingUsbPermissions {
    data class Entry(
        val result: MethodChannel.Result,
        val requestedAtMs: Long,
    )

    private val pending = ConcurrentHashMap<String, Entry>()

    /** True if a request is already pending for [deviceName]. */
    fun isPending(deviceName: String): Boolean = pending.containsKey(deviceName)

    /**
     * Stores [result] as the pending request for [deviceName]. Returns
     * `true` if stored, or `false` (storing nothing) if a request was
     * already pending for that exact device — callers should reject the
     * duplicate (e.g. `USB_PERMISSION_PENDING`) rather than overwrite the
     * earlier caller's [MethodChannel.Result], which would otherwise never
     * complete.
     */
    fun put(deviceName: String, result: MethodChannel.Result, nowMs: Long = System.currentTimeMillis()): Boolean =
        pending.putIfAbsent(deviceName, Entry(result, nowMs)) == null

    /** Atomically removes and returns the pending entry for [deviceName], or null if none. */
    fun take(deviceName: String): Entry? = pending.remove(deviceName)

    /**
     * Removes and completes every still-pending entry with an error —
     * called on Activity destruction so no [MethodChannel.Result] is left
     * unresolved forever (a leaked Result silently drops its Dart-side
     * Future, which never completes).
     */
    fun cancelAll(
        errorCode: String = "USB_PERMISSION_CANCELLED",
        message: String = "Activity destroyed with a pending USB permission request",
    ) {
        // Snapshot the keys first: completing a Result runs arbitrary
        // Flutter-engine code, which must not run while iterating the map
        // it's about to be removed from.
        for (deviceName in pending.keys.toList()) {
            pending.remove(deviceName)?.result?.error(errorCode, message, null)
        }
    }

    fun size(): Int = pending.size
}
