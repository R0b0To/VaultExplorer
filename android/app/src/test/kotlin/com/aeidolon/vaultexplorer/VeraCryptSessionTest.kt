package com.aeidolon.vaultexplorer

import org.junit.Test
import org.junit.Assert.*

class VeraCryptSessionTest {

    @Test
    fun `getVolumeIdByUri returns null when no session is active for that uri`() {
        VeraCryptSession.activeSessions.clear()
        assertNull(VeraCryptSession.getVolumeIdByUri("content://fake/uri"))
    }

    @Test
    fun `isUnlocked reflects activeSessions membership exactly`() {
        VeraCryptSession.activeSessions.clear()
        val volId = 2
        assertFalse(VeraCryptSession.isUnlocked(volId))

        VeraCryptSession.activeSessions[volId] = ContainerSession(
            uri = "content://test", volId = volId, cachedFilesList = emptyList()
        )
        assertTrue(VeraCryptSession.isUnlocked(volId))

        VeraCryptSession.removeSession(volId)
        assertFalse(VeraCryptSession.isUnlocked(volId))
    }

    @Test
    fun `getFreeVolumeId skips occupied slots and returns the first open one`() {
        VeraCryptSession.activeSessions.clear()
        VeraCryptSession.activeSessions[0] = ContainerSession("u0", 0, emptyList())
        VeraCryptSession.activeSessions[1] = ContainerSession("u1", 1, emptyList())
        assertEquals(2, VeraCryptSession.getFreeVolumeId())
    }

    @Test
    fun `getFreeVolumeId returns null when all MAX_VOLUMES slots are occupied`() {
        VeraCryptSession.activeSessions.clear()
        for (i in 0 until VeraCryptSession.MAX_VOLUMES) {
            VeraCryptSession.activeSessions[i] = ContainerSession("u$i", i, emptyList())
        }
        assertNull(VeraCryptSession.getFreeVolumeId())
    }
}