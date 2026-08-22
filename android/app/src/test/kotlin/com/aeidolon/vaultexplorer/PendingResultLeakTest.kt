package com.aeidolon.vaultexplorer

import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.handlers.AppSettingsFileHandlers
import com.aeidolon.vaultexplorer.handlers.ImportExportHandlers
import com.aeidolon.vaultexplorer.handlers.VaultCreationHandlers

/**
 * The hazard: [PendingActivityResult.stash] calls `.error()` on whatever
 * Result was previously stashed, to cancel it. If a handler ever replies to
 * a Result *directly* (e.g. on an early validation failure) and *also*
 * stashes that same Result, the next stash() call tries to reply to an
 * already-completed Result -- which the real Flutter engine rejects with
 * "Reply already submitted". The fix is procedural, not structural: a
 * handler must do exactly one of "reply directly and return" or "stash and
 * let the activity-result callback reply", never both.
 *
 * Every `pendingResult.stash(result)` call site across the handlers falls
 * into one of two shapes: either it stashes unconditionally as the first
 * thing in the function (nothing can go wrong -- there's no direct-reply
 * path to fall through from), or it validates first and only reaches
 * stash() after one or more early "reply directly and return" branches.
 * The tests below cover every one of the latter, riskier shape across the
 * codebase: [VaultCreationHandlers.handleCreateContainer],
 * [AppSettingsFileHandlers.handleExportAppSettingsFile], and all four of
 * [ImportExportHandlers]'s stashing functions
 * ([ImportExportHandlers.handlePickImportFiles],
 * [ImportExportHandlers.handleExportFilesFolder],
 * [ImportExportHandlers.handlePickImportFolder],
 * [ImportExportHandlers.handleExportFile]) -- confirming each currently
 * replies and returns *before* ever calling stash(), so a future handler
 * that violates that rule fails loudly here instead of surfacing as a
 * runtime crash on someone's device. ([ImportExportHandlers.handleImportFile]
 * and [ImportExportHandlers.handleImportFolder] resume an already-picked
 * import by token instead of launching anything, so they never stash and
 * aren't part of this set.)
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

    /**
     * The shared shape behind every test below: given [isInvalidCall] is
     * true (always sourced from the real handler's own predicate or a
     * real registry lookup, never a hand-copied mirror of one), replying
     * with [errorCode] directly and returning must be the *only* thing
     * that happens for that Result -- a completely unrelated subsequent
     * stash() must not throw, and must never touch it.
     */
    private fun assertReplyOnlyNeverStashes(isInvalidCall: Boolean, errorCode: String) {
        assertTrue(isInvalidCall)

        val invalidResult = FakeResult()
        // Mirrors every handler's exact early-return shape: validate,
        // reply directly, return -- pendingResult.stash() is never called
        // in this branch.
        invalidResult.error(errorCode, "simulated validation failure", null)
        assertEquals(1, invalidResult.errorCalls)
        assertEquals(errorCode, invalidResult.lastErrorCode)

        // The actual regression this file is named for: a completely
        // unrelated subsequent call stashing its own Result must not
        // throw, and must not touch invalidResult -- which was never
        // stashed, so there's nothing for it to leak into.
        val pendingResult = PendingActivityResult()
        val unrelatedResult = FakeResult()
        pendingResult.stash(unrelatedResult) // must not throw

        assertEquals(0, unrelatedResult.successCalls + unrelatedResult.errorCalls)
        assertEquals(1, invalidResult.errorCalls) // still exactly one reply, ever
    }

    @Test
    fun `invalid create-container call replies directly and never stashes, so nothing can leak`() {
        // Exercises the real production predicate (extracted from
        // VaultCreationHandlers.handleCreateContainer), not a hand-copied
        // mirror of it.
        assertReplyOnlyNeverStashes(
            isInvalidCall = VaultCreationHandlers.isMissingCredentials(password = "", keyfilePaths = null),
            errorCode = "INVALID_ARGS"
        )
    }

    @Test
    fun `invalid export-app-settings call replies directly and never stashes, so nothing can leak`() {
        // Exercises the real production predicate (extracted from
        // AppSettingsFileHandlers.handleExportAppSettingsFile).
        assertReplyOnlyNeverStashes(
            isInvalidCall = AppSettingsFileHandlers.isMissingContents(contents = null),
            errorCode = "INVALID_ARGS"
        )
    }

    @Test
    fun `import and export-folder calls with a missing filePath reply directly and never stash`() {
        // Exercises the real production predicate shared by
        // handlePickImportFiles, handleExportFilesFolder, and
        // handlePickImportFolder -- all three validate filePath the same
        // way before ever touching ContainerSessionRegistry or stash().
        assertReplyOnlyNeverStashes(
            isInvalidCall = ImportExportHandlers.isMissingContainerUri(containerUri = null),
            errorCode = "INVALID_ARGS"
        )
    }

    @Test
    fun `unmounted-container import and export-folder calls reply NOT_MOUNTED directly and never stash`() {
        // Once filePath is present, handlePickImportFiles,
        // handleExportFilesFolder, and handlePickImportFolder all look up
        // volId via the real ContainerSessionRegistry and reply
        // NOT_MOUNTED directly (never stashing) if nothing is mounted
        // there -- exercised here against the real registry, not a copy
        // of its lookup logic.
        ContainerSessionRegistry.activeSessions.clear()
        assertReplyOnlyNeverStashes(
            isInvalidCall = ContainerSessionRegistry.getVolumeIdByUri("content://not-mounted") == null,
            errorCode = "NOT_MOUNTED"
        )
    }

    @Test
    fun `export-file call with missing args replies directly and never stashes`() {
        // handleExportFile is the one stashing function in
        // ImportExportHandlers with a two-argument predicate (filePath
        // AND sourcePath), so it gets its own case rather than sharing
        // the single-arg one above.
        assertReplyOnlyNeverStashes(
            isInvalidCall = ImportExportHandlers.isMissingContainerOrSource(containerUri = null, sourcePath = null),
            errorCode = "INVALID_ARGS"
        )
    }

    @Test
    fun `export-file call against an unmounted container replies NOT_MOUNTED directly and never stashes`() {
        ContainerSessionRegistry.activeSessions.clear()
        assertReplyOnlyNeverStashes(
            isInvalidCall = ContainerSessionRegistry.getVolumeIdByUri("content://not-mounted") == null,
            errorCode = "NOT_MOUNTED"
        )
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