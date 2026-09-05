package com.aeidolon.vaultexplorer.handlers

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * isMissingCredentials previously had only incidental coverage: one fixed
 * input (password="", keyfilePaths=null) via PendingResultLeakTest's
 * stash-timing check. This exercises the actual truth table.
 */
class VaultCreationHandlersIsMissingCredentialsTest {

    @Test
    fun `no password and no keyfiles is missing credentials`() {
        assertTrue(VaultCreationHandlers.isMissingCredentials("", null))
        assertTrue(VaultCreationHandlers.isMissingCredentials("", emptyList()))
    }

    @Test
    fun `a password alone is sufficient`() {
        assertFalse(VaultCreationHandlers.isMissingCredentials("hunter2", null))
        assertFalse(VaultCreationHandlers.isMissingCredentials("hunter2", emptyList()))
    }

    @Test
    fun `keyfiles alone are sufficient, even with an empty password`() {
        assertFalse(VaultCreationHandlers.isMissingCredentials("", listOf("/sdcard/key.bin")))
    }

    @Test
    fun `both a password and keyfiles is not missing credentials`() {
        assertFalse(VaultCreationHandlers.isMissingCredentials("hunter2", listOf("/sdcard/key.bin")))
    }
}
