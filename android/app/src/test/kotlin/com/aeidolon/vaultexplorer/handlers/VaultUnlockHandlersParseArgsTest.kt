package com.aeidolon.vaultexplorer.handlers

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

/**
 * parseUnlockArgs is the argument-validation entry point every container
 * unlock request passes through (regular unlock, hidden-volume unlock,
 * automation-triggered unlock) before any native code runs -- and, like the
 * rest of handlers/, had zero test coverage before this file (see the
 * tech-debt audit). It needs neither Robolectric nor a real MainActivity:
 * MethodCall and MethodChannel.Result are plain Flutter-embedding types, so
 * this is a pure JVM test, matching PendingResultLeakTest's approach of
 * testing handler-adjacent logic without standing up the whole handler.
 *
 * The empty-password case is the one worth calling out: this function
 * deliberately treats an empty-string password as valid (only a *null*
 * password is rejected) -- see the comment above that check in
 * parseUnlockArgs for why (a plain, unencrypted VHD/VHDX needs no
 * password, and native unlock is the real source of truth for whether an
 * empty password is actually acceptable for a given container). A test
 * that assumed empty-string was invalid would be testing the wrong thing.
 */
class VaultUnlockHandlersParseArgsTest {

    private class FakeResult : MethodChannel.Result {
        var errorCode: String? = null
            private set
        var errorMessage: String? = null
            private set
        var successCalls = 0
            private set

        override fun success(result: Any?) {
            successCalls++
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            this.errorCode = errorCode
            this.errorMessage = errorMessage
        }

        override fun notImplemented() {}
    }

    private fun call(args: Map<String, Any?>) = MethodCall("unlockContainer", args)

    @Test
    fun `missing password is rejected`() {
        val result = FakeResult()
        val parsed = parseUnlockArgs(
            call(emptyMap()), result,
            sourceIdentifier = "content://some-container", sourceIdentifierArgName = "containerUri",
        )
        assertNull(parsed)
        assertEquals("INVALID_ARGS", result.errorCode)
        assertEquals(0, result.successCalls)
    }

    @Test
    fun `missing source identifier is rejected even with a password present`() {
        val result = FakeResult()
        val parsed = parseUnlockArgs(
            call(mapOf("password" to "hunter2")), result,
            sourceIdentifier = null, sourceIdentifierArgName = "containerUri",
        )
        assertNull(parsed)
        assertEquals("INVALID_ARGS", result.errorCode)
    }

    @Test
    fun `empty string password is accepted, not rejected -- only null is`() {
        val result = FakeResult()
        val parsed = parseUnlockArgs(
            call(mapOf("password" to "")), result,
            sourceIdentifier = "content://some-container", sourceIdentifierArgName = "containerUri",
        )
        assertNotNull("an empty password must reach native unlock, not be rejected here", parsed)
        assertNull(result.errorCode)
        assertEquals("", parsed!!.password)
    }

    @Test
    fun `minimal valid call fills in documented defaults`() {
        val result = FakeResult()
        val parsed = parseUnlockArgs(
            call(mapOf("password" to "hunter2")), result,
            sourceIdentifier = "content://some-container", sourceIdentifierArgName = "containerUri",
        )
        assertNotNull(parsed)
        assertNull(result.errorCode)
        val args = parsed!!
        assertEquals(0, args.pim)
        assertEquals(255, args.cipherId)
        assertEquals(255, args.hashId)
        assertFalse(args.docProvider)
        assertFalse(args.cacheDerivedKey)
        assertFalse(args.readOnly)
        assertFalse(args.protectHiddenVolume)
        assertNull(args.preservedKey)
        assertNull(args.keyfilePaths)
        assertNull(args.autoMountFolders)
        assertEquals(0, args.hiddenPim)
        assertEquals(255, args.hiddenCipherId)
        assertEquals(255, args.hiddenHashId)
    }

    @Test
    fun `protecting a hidden volume without a hidden password or keyfiles is rejected`() {
        val result = FakeResult()
        val parsed = parseUnlockArgs(
            call(
                mapOf(
                    "password" to "hunter2",
                    "protectHiddenVolume" to true,
                    // no hiddenVolumePassword, no hiddenVolumeKeyfilePaths
                ),
            ),
            result,
            sourceIdentifier = "content://some-container", sourceIdentifierArgName = "containerUri",
        )
        assertNull(parsed)
        assertEquals("INVALID_ARGS", result.errorCode)
        assertTrue(result.errorMessage.orEmpty().contains("hidden volume"))
    }

    @Test
    fun `protecting a hidden volume with keyfiles but no password is accepted`() {
        val result = FakeResult()
        val parsed = parseUnlockArgs(
            call(
                mapOf(
                    "password" to "hunter2",
                    "protectHiddenVolume" to true,
                    "hiddenVolumeKeyfilePaths" to listOf("/sdcard/key.bin"),
                ),
            ),
            result,
            sourceIdentifier = "content://some-container", sourceIdentifierArgName = "containerUri",
        )
        assertNotNull(parsed)
        assertNull(result.errorCode)
        assertEquals(listOf("/sdcard/key.bin"), parsed!!.hiddenKeyfilePaths)
    }

    @Test
    fun `preservedKey is base64-decoded from the wire argument`() {
        val keyBytes = ByteArray(32) { it.toByte() }
        val result = FakeResult()
        val parsed = parseUnlockArgs(
            call(
                mapOf(
                    "password" to "hunter2",
                    "preservedKey" to Base64.getEncoder().encodeToString(keyBytes),
                ),
            ),
            result,
            sourceIdentifier = "content://some-container", sourceIdentifierArgName = "containerUri",
        )
        assertNotNull(parsed)
        assertArrayEquals(keyBytes, parsed!!.preservedKey)
    }

    @Test
    fun `numeric fields passed as non-default Ints round-trip correctly`() {
        val result = FakeResult()
        val parsed = parseUnlockArgs(
            call(
                mapOf(
                    "password" to "hunter2",
                    "pim" to 500,
                    "cipherId" to 3,
                    "hashId" to 2,
                    "documentProvider" to true,
                    "readOnly" to true,
                    "autoMountFolders" to listOf("Documents", "Photos"),
                ),
            ),
            result,
            sourceIdentifier = "content://some-container", sourceIdentifierArgName = "containerUri",
        )
        assertNotNull(parsed)
        val args = parsed!!
        assertEquals(500, args.pim)
        assertEquals(3, args.cipherId)
        assertEquals(2, args.hashId)
        assertTrue(args.docProvider)
        assertTrue(args.readOnly)
        assertEquals(listOf("Documents", "Photos"), args.autoMountFolders)
    }
}
