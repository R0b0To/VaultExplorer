package com.aeidolon.vaultexplorer.handlers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The pure predicates behind the relocation preconditions. A split container's
 * parts must never be moved one at a time (the vault would be left broken),
 * and USB / composite vaults have no single file or folder to copy.
 */
class VaultRelocationHandlersTest {

    @Test
    fun splitPartNamesAreRecognised() {
        for (name in listOf("backup.001", "backup.002", "vault.hc.001", "a.part1", "a.PART12", "x.0001")) {
            assertTrue(name, VaultRelocationHandlers.looksLikeSplitPart(name))
        }
    }

    @Test
    fun ordinaryContainerNamesAreNotTreatedAsSplitParts() {
        for (name in listOf("vault.hc", "vault", "notes.tc", "photos.vault", "vault.hc.bak", "part1", "a.partx", "my.001vault")) {
            assertFalse(name, VaultRelocationHandlers.looksLikeSplitPart(name))
        }
        assertFalse(VaultRelocationHandlers.looksLikeSplitPart(null))
        assertFalse(VaultRelocationHandlers.looksLikeSplitPart(""))
    }

    @Test
    fun usbAndCompositeSourcesAreUnsupported() {
        assertTrue(VaultRelocationHandlers.isUnsupportedScheme("usb:/dev/bus/usb/001/002"))
        assertTrue(VaultRelocationHandlers.isUnsupportedScheme("composite:abc"))
    }

    @Test
    fun contentAndFileSourcesAreSupported() {
        assertFalse(VaultRelocationHandlers.isUnsupportedScheme("content://com.android.externalstorage.documents/document/primary%3Av.hc"))
        assertFalse(VaultRelocationHandlers.isUnsupportedScheme("content://com.android.externalstorage.documents/tree/primary%3AVault"))
        assertFalse(VaultRelocationHandlers.isUnsupportedScheme("file:///storage/emulated/0/v.hc"))
    }

    @Test
    fun spaceMarginKeepsRoomForTheOs() {
        assertEquals(32L * 1024 * 1024, VaultRelocationHandlers.SPACE_MARGIN_BYTES)
    }
}
