package com.aeidolon.vaultexplorer

import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The hazard: before [PendingUsbPermissions] existed, UsbContainerHandlers
 * kept a single global `pendingUsbPermissionResult`/`pendingUsbPermissionDeviceName`
 * pair. A second `requestUsbPermission()` call for a *different* device
 * while the first was still awaiting its broadcast would silently
 * overwrite that pair -- the first caller's [MethodChannel.Result] then
 * never completes (no success, no error; the Dart-side Future just hangs
 * forever). These tests exercise the real [PendingUsbPermissions] class
 * directly, the same way [PendingResultLeakTest] exercises
 * [PendingActivityResult].
 */
class PendingUsbPermissionsTest {

    /** Mirrors PendingResultLeakTest.FakeResult: records every
     *  success()/error()/notImplemented() call and throws on a second one,
     *  matching the real Flutter engine's "Reply already submitted". */
    private class FakeResult : MethodChannel.Result {
        var successCalls = 0
            private set
        var errorCalls = 0
            private set
        var lastSuccessValue: Any? = null
            private set
        var lastErrorCode: String? = null
            private set
        private var completed = false

        override fun success(result: Any?) {
            check(!completed) { "Reply already submitted" }
            completed = true
            successCalls++
            lastSuccessValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            check(!completed) { "Reply already submitted" }
            completed = true
            errorCalls++
            lastErrorCode = errorCode
        }

        override fun notImplemented() {
            check(!completed) { "Reply already submitted" }
            completed = true
        }
    }

    @Test
    fun `two different devices can both have a pending request at once, independently`() {
        val pending = PendingUsbPermissions()
        val resultA = FakeResult()
        val resultB = FakeResult()

        assertTrue(pending.put("deviceA", resultA))
        assertTrue(pending.put("deviceB", resultB))
        assertEquals(2, pending.size())

        // Resolving deviceA must not touch deviceB's still-pending result --
        // this is the exact scenario the old single global field lost.
        val takenA = pending.take("deviceA")
        assertNotNull(takenA)
        takenA!!.result.success(true)
        assertEquals(1, resultA.successCalls)
        assertEquals(0, resultB.successCalls + resultB.errorCalls)
        assertTrue(pending.isPending("deviceB"))

        val takenB = pending.take("deviceB")
        assertNotNull(takenB)
        takenB!!.result.success(false)
        assertEquals(1, resultB.successCalls)
        assertEquals(false, resultB.lastSuccessValue)
    }

    @Test
    fun `a duplicate request for the same device is rejected without touching the first`() {
        val pending = PendingUsbPermissions()
        val first = FakeResult()
        val second = FakeResult()

        assertTrue(pending.put("deviceA", first))
        // Second put for the SAME device must fail (not overwrite) --
        // this is the specific bug the old global-field design had.
        assertFalse(pending.put("deviceA", second))
        assertEquals(1, pending.size())

        // The first request is still the one that resolves; the rejected
        // second caller was never stored, so it's the handler's job (not
        // this class's) to reply USB_PERMISSION_PENDING to it directly --
        // nothing here should have touched `second` at all.
        assertEquals(0, second.successCalls + second.errorCalls)

        val taken = pending.take("deviceA")
        assertNotNull(taken)
        taken!!.result.success(true)
        assertEquals(1, first.successCalls)
    }

    @Test
    fun `take clears the slot so a resolved request can never be completed twice`() {
        val pending = PendingUsbPermissions()
        val result = FakeResult()
        pending.put("deviceA", result)

        val takenOnce = pending.take("deviceA")
        val takenTwice = pending.take("deviceA")

        assertNotNull(takenOnce)
        assertNull(takenTwice)
        assertFalse(pending.isPending("deviceA"))

        takenOnce!!.result.success(true)
        assertEquals(1, result.successCalls)
    }

    @Test
    fun `taking one device's request never resolves an unrelated pending device`() {
        val pending = PendingUsbPermissions()
        val resultA = FakeResult()
        val resultB = FakeResult()
        pending.put("deviceA", resultA)
        pending.put("deviceB", resultB)

        pending.take("deviceA")

        assertNull(pending.take("deviceA")) // already taken
        assertNotNull(pending.take("deviceB")) // still there, unaffected
    }

    @Test
    fun `an unmatched device name resolves nothing and does not throw`() {
        val pending = PendingUsbPermissions()
        assertNull(pending.take("neverRequested"))
    }

    @Test
    fun `cancelAll completes every still-pending request with an error and clears them all`() {
        val pending = PendingUsbPermissions()
        val resultA = FakeResult()
        val resultB = FakeResult()
        pending.put("deviceA", resultA)
        pending.put("deviceB", resultB)

        pending.cancelAll()

        assertEquals(1, resultA.errorCalls)
        assertEquals(1, resultB.errorCalls)
        assertEquals("USB_PERMISSION_CANCELLED", resultA.lastErrorCode)
        assertEquals("USB_PERMISSION_CANCELLED", resultB.lastErrorCode)
        assertEquals(0, pending.size())
    }

    @Test
    fun `cancelAll on an empty registry does nothing and does not throw`() {
        val pending = PendingUsbPermissions()
        pending.cancelAll() // must not throw
        assertEquals(0, pending.size())
    }

    @Test
    fun `after cancelAll, a fresh request for the same device is accepted again`() {
        // Regression guard for onActivityDestroyed()/a fresh Activity:
        // cancelAll() must fully clear the slot, not just mark it
        // cancelled, so the device isn't permanently stuck rejecting new
        // requests as "already pending".
        val pending = PendingUsbPermissions()
        pending.put("deviceA", FakeResult())
        pending.cancelAll()

        val fresh = FakeResult()
        assertTrue(pending.put("deviceA", fresh))
        pending.take("deviceA")!!.result.success(true)
        assertEquals(1, fresh.successCalls)
    }
}
