package com.aeidolon.vaultexplorer.panic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PanicTierTest {

    @Test
    fun `levels match the architecture plan's numbering`() {
        assertEquals(1, PanicTier.SESSION_PURGE.level)
        assertEquals(2, PanicTier.CREDENTIAL_PURGE.level)
        assertEquals(3, PanicTier.NUCLEAR_WIPE.level)
    }

    @Test
    fun `atLeast is reflexive -- every tier is at least itself`() {
        for (tier in PanicTier.entries) {
            assertTrue(tier.atLeast(tier))
        }
    }

    @Test
    fun `a higher tier is at least every lower tier`() {
        assertTrue(PanicTier.NUCLEAR_WIPE.atLeast(PanicTier.CREDENTIAL_PURGE))
        assertTrue(PanicTier.NUCLEAR_WIPE.atLeast(PanicTier.SESSION_PURGE))
        assertTrue(PanicTier.CREDENTIAL_PURGE.atLeast(PanicTier.SESSION_PURGE))
    }

    @Test
    fun `a lower tier is never at least a higher tier`() {
        assertFalse(PanicTier.SESSION_PURGE.atLeast(PanicTier.CREDENTIAL_PURGE))
        assertFalse(PanicTier.SESSION_PURGE.atLeast(PanicTier.NUCLEAR_WIPE))
        assertFalse(PanicTier.CREDENTIAL_PURGE.atLeast(PanicTier.NUCLEAR_WIPE))
    }

    @Test
    fun `fromLevel round-trips every declared tier's own level`() {
        for (tier in PanicTier.entries) {
            assertEquals(tier, PanicTier.fromLevel(tier.level))
        }
    }

    @Test
    fun `fromLevel returns null for a level no tier declares`() {
        assertNull(PanicTier.fromLevel(0))
        assertNull(PanicTier.fromLevel(4))
        assertNull(PanicTier.fromLevel(-1))
    }
}
