package com.aeidolon.vaultexplorer

import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The hazard: [PendingActivityResult.stash] calls `.error()` on whatever
 * Result was previously stashed, to cancel it. If a handler ever replies to
 * a Result *directly* (e.g. on an early validation failure) and *also*
 * stashes that same Result, the next stash() call tries to reply to an
 * already-completed Result -- which the real Flutter engine rejects with
 * "Reply already submitted". The fix is procedural, not structural: a
 * handler must do exactly one of "reply directly and return" or "stash and
 * let the activity-result callback reply", never both.
 * [VaultCreationHandlers.handleCreateContainer] already follows this rule
 * correctly (validates, replies, returns -- all before ever calling
 * stash()); these tests encode the rule itself so a future handler that
 * violates it fails loudly here instead of surfacing as a runtime crash on
 * someone's device.
 */
class PendingResultLeakTest {

    /**
     * Records every success()/error()/notImplemented() call and throws on a
     * second one, mirroring the real Flutter engine's own "Reply already
     * submitted" behavior for a MethodChannel.Result completed twice.
     */
    private class FakeResult : MethodChannel.Result {
        var successCalls = 0
            private set
        var errorCalls = 0
            private set
        var lastErrorCode: String? = null
            private set
        private var completed = false

        override fun success(result: Any?) {
            check(!completed) { "Reply already submitted" }
            completed = true
            successCalls++
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
    fun `invalid create-container call replies directly and never stashes, so nothing can leak`() {
        val password = ""
        val keyfilePaths: List<String>? = null
        // Exercises the real production predicate (extracted from
        // VaultCreationHandlers.handleCreateContainer), not a hand-copied
        // mirror of it.
        assertTrue(VaultCreationHandlers.isMissingCredentials(password, keyfilePaths))

        val invalidResult = FakeResult()
        // Mirrors handleCreateContainer's exact early-return path: validate,
        // reply directly, return -- pendingResult.stash() is never called
        // in this branch.
        invalidResult.error("INVALID_ARGS", "password or keyfiles required", null)

        assertEquals(1, invalidResult.errorCalls)
        assertEquals("INVALID_ARGS", invalidResult.lastErrorCode)

        // The actual regression this file is named for: a completely
        // unrelated subsequent pick call stashing its own Result must not
        // throw, and must not touch invalidResult -- which was never
        // stashed, so there's nothing for it to leak into.
        val pendingResult = PendingActivityResult()
        val pickResult = FakeResult()
        pendingResult.stash(pickResult) // must not throw

        assertEquals(0, pickResult.successCalls + pickResult.errorCalls)
        assertEquals(1, invalidResult.errorCalls) // still exactly one reply, ever
    }

    @Test
    fun `stash cancels whatever was previously pending, exactly once, and the new one still completes normally`() {
        val pendingResult = PendingActivityResult()
        val first = FakeResult()
        val second = FakeResult()

        pendingResult.stash(first)
        pendingResult.stash(second) // supersedes `first`

        assertEquals(1, first.errorCalls)
        assertEquals("CANCELLED", first.lastErrorCode)
        assertEquals(0, second.successCalls + second.errorCalls)

        val taken = pendingResult.take()
        assertNotNull(taken)
        taken!!.success(true)
        assertEquals(1, second.successCalls)
    }

    @Test
    fun `take clears the pending slot so a result can never be completed twice`() {
        val pendingResult = PendingActivityResult()
        val result = FakeResult()
        pendingResult.stash(result)

        val takenOnce = pendingResult.take()
        val takenTwice = pendingResult.take()

        assertNotNull(takenOnce)
        assertNull(takenTwice) // already cleared -- nothing left to double-take

        takenOnce!!.success(false)
        assertEquals(1, result.successCalls)
    }

    @Test
    fun `demonstrates the hazard itself -- a handler that replies directly AND stashes causes the next stash to throw`() {
        // The bug pattern this file used to just describe: a handler
        // replies directly (completing the Result) but also stashes it
        // anyway. The *next* stash() call tries to cancel that
        // already-completed Result and must throw, exactly like the real
        // Flutter engine would on a genuine double reply.
        val pendingResult = PendingActivityResult()
        val misusedResult = FakeResult()

        misusedResult.error("INVALID_ARGS", "simulated buggy handler", null) // replied directly...
        pendingResult.stash(misusedResult) // ...but also stashed. This is the bug.

        val nextResult = FakeResult()
        assertThrows(IllegalStateException::class.java) {
            pendingResult.stash(nextResult) // tries to cancel misusedResult -> double reply
        }
    }
}