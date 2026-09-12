package com.aeidolon.vaultexplorer.handlers

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * fitsWithinSafetyMargin is the predicate behind rejectIfInsufficientSpace
 * -- it was extracted from a private method into an internal companion
 * function specifically so it's testable without a live container session
 * (which ContainerFileSystem.getSpaceInfo, the caller supplying `available`,
 * actually needs) -- same pattern as uniqueNameAgainst in
 * ImportExportHandlersUniqueNameTest.
 *
 * The margin was dropped from 5% to SPACE_SAFETY_MARGIN (1%) after it
 * rejected a real, legitimate import: 8 files totalling 138MB into a vault
 * reporting 142MB free failed outright as one batch, but succeeded when
 * split into a 7-file import followed by a 1-file import -- because each
 * smaller batch was checked against a fresh (and by then smaller, already
 * mostly-consumed) free-space reading rather than the one 5%-of-142MB
 * margin the combined check had to clear. See ImportExportHandlers.kt's
 * doc comments on SPACE_SAFETY_MARGIN and rejectIfInsufficientSpace.
 */
class ImportExportHandlersFitsWithinSafetyMarginTest {

    @Test
    fun `a transfer well under the available space fits`() {
        assertTrue(ImportExportHandlers.fitsWithinSafetyMargin(totalBytes = 500L, available = 1000L))
    }

    @Test
    fun `a transfer exactly at the 1 percent safety-margin boundary fits`() {
        // available * 0.99 = 990 -- the largest totalBytes still accepted.
        assertTrue(ImportExportHandlers.fitsWithinSafetyMargin(totalBytes = 990L, available = 1000L))
    }

    @Test
    fun `a transfer one byte past the safety-margin boundary does not fit`() {
        assertFalse(ImportExportHandlers.fitsWithinSafetyMargin(totalBytes = 991L, available = 1000L))
    }

    @Test
    fun `a transfer larger than the available space does not fit`() {
        assertFalse(ImportExportHandlers.fitsWithinSafetyMargin(totalBytes = 1001L, available = 1000L))
    }

    @Test
    fun `the motivating regression case -- 138MB into 142MB free -- now fits`() {
        val oneMib = 1024L * 1024L
        val totalBytes = 138L * oneMib
        val available = 142L * oneMib
        assertTrue(ImportExportHandlers.fitsWithinSafetyMargin(totalBytes, available))
    }

    @Test
    fun `the same 138MB into 142MB free would NOT have fit under the old 5 percent margin`() {
        // Documents why the bug existed in the first place: this is the
        // exact formula rejectIfInsufficientSpace used before this fix.
        val oneMib = 1024L * 1024L
        val totalBytes = 138L * oneMib
        val available = 142L * oneMib
        val oldMarginFits = totalBytes <= (available * 0.95).toLong()
        assertFalse(oldMarginFits)
    }

    @Test
    fun `zero-byte transfer always fits, even with zero available space`() {
        assertTrue(ImportExportHandlers.fitsWithinSafetyMargin(totalBytes = 0L, available = 0L))
    }
}
