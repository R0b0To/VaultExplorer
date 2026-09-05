package com.aeidolon.vaultexplorer.handlers

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * guessFormat is purely informational (see its own doc comment -- this
 * app's own join never reads the manifest field back), so this is a thin
 * test, but the case-insensitivity and the "everything else defaults to
 * VeraCrypt" fallback are still real, checkable behavior.
 */
class SplitJoinHandlersGuessFormatTest {

    @Test
    fun `recognizes luks and bitlocker by filename, case-insensitively`() {
        assertEquals("LUKS", SplitJoinHandlers.guessFormat("backup.luks.img"))
        assertEquals("LUKS", SplitJoinHandlers.guessFormat("BACKUP.LUKS.IMG"))
        assertEquals("BITLOCKER", SplitJoinHandlers.guessFormat("Windows-BitLocker-Drive.vhd"))
    }

    @Test
    fun `anything else defaults to veracrypt`() {
        assertEquals("VERACRYPT", SplitJoinHandlers.guessFormat("my_container.hc"))
        assertEquals("VERACRYPT", SplitJoinHandlers.guessFormat(""))
    }
}
