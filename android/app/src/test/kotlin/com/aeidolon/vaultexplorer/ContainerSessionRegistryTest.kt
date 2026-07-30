package com.aeidolon.vaultexplorer

import org.junit.Test
import org.junit.Assert.*


class ContainerSessionRegistryTest {

    @Test
    fun `getVolumeIdByUri returns null when no session is active for that uri`() {
        ContainerSessionRegistry.activeSessions.clear()
        assertNull(ContainerSessionRegistry.getVolumeIdByUri("content://fake/uri"))
    }

    @Test
    fun `isUnlocked reflects activeSessions membership exactly`() {
        ContainerSessionRegistry.activeSessions.clear()
        val volId = 2
        assertFalse(ContainerSessionRegistry.isUnlocked(volId))

        ContainerSessionRegistry.activeSessions[volId] = ContainerSession(
            uri = "content://test", volId = volId, cachedFilesList = emptyList()
        )
        assertTrue(ContainerSessionRegistry.isUnlocked(volId))

        ContainerSessionRegistry.removeSession(volId)
        assertFalse(ContainerSessionRegistry.isUnlocked(volId))
    }

    @Test
    fun `getVolumeIdByUri finds the session whose uri matches, ignoring others`() {
        ContainerSessionRegistry.activeSessions.clear()
        ContainerSessionRegistry.activeSessions[0] =
            ContainerSession(uri = "content://a", volId = 0, cachedFilesList = emptyList())
        ContainerSessionRegistry.activeSessions[1] =
            ContainerSession(uri = "content://b", volId = 1, cachedFilesList = emptyList())

        assertEquals(1, ContainerSessionRegistry.getVolumeIdByUri("content://b"))

        ContainerSessionRegistry.activeSessions.clear()
    }

    @Test
    fun `hasAnyActiveSessions reflects emptiness of activeSessions`() {
        ContainerSessionRegistry.activeSessions.clear()
        assertFalse(ContainerSessionRegistry.hasAnyActiveSessions())

        ContainerSessionRegistry.activeSessions[0] =
            ContainerSession(uri = "content://a", volId = 0, cachedFilesList = emptyList())
        assertTrue(ContainerSessionRegistry.hasAnyActiveSessions())

        ContainerSessionRegistry.activeSessions.clear()
    }
}
