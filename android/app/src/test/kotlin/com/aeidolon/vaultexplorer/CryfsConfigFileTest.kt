package com.aeidolon.vaultexplorer.cryfs

import java.security.SecureRandom
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Pure-JVM (org.json + javax.crypto only) coverage for cryfs.config's
 * build/parse round trip -- the same parse -> build sequence
 * CryfsVault.changePassword uses to rewrap a vault under a new password.
 * build() always uses CryfsConfigFile's default scrypt cost params (no
 * override hook), so these tests run real scrypt at that cost; expect each
 * build() call to take a moment.
 */
class CryfsConfigFileTest {

    private val random = SecureRandom()

    @Test
    fun `build then parse recovers the same config`() {
        val config = CryfsConfigFile.newVaultConfig(random)
        val password = "correct horse battery staple".toCharArray()

        val raw = CryfsConfigFile.build(config, password, random)
        val parsed = CryfsConfigFile.parse(raw, password)

        assertArrayEquals(config.encryptionKey, parsed.encryptionKey)
        assertArrayEquals(config.filesystemId, parsed.filesystemId)
        assertEquals(config.rootBlobId.hex, parsed.rootBlobId.hex)
        assertEquals(config.blockCipherName, parsed.blockCipherName)
    }

    @Test
    fun `wrong password is rejected`() {
        val config = CryfsConfigFile.newVaultConfig(random)
        val raw = CryfsConfigFile.build(config, "right password".toCharArray(), random)

        assertThrows(CryfsWrongPasswordException::class.java) {
            CryfsConfigFile.parse(raw, "wrong password".toCharArray())
        }
    }

    @Test
    fun `changing password preserves the config but rotates the encrypted bytes`() {
        // Mirrors CryfsVault.changePassword: parse with the old password,
        // then build the SAME (unchanged) config under a new one.
        val oldPassword = "old password".toCharArray()
        val newPassword = "new password".toCharArray()

        val original = CryfsConfigFile.newVaultConfig(random)
        val oldRaw = CryfsConfigFile.build(original, oldPassword, random)
        val decrypted = CryfsConfigFile.parse(oldRaw, oldPassword)

        val newRaw = CryfsConfigFile.build(decrypted, newPassword, random)
        val reparsed = CryfsConfigFile.parse(newRaw, newPassword)

        // Same encryption key (and therefore the same encrypted block
        // store stays readable) and root blob -- only the wrapping changed.
        assertArrayEquals(original.encryptionKey, reparsed.encryptionKey)
        assertEquals(original.rootBlobId.hex, reparsed.rootBlobId.hex)
        assertArrayEquals(original.filesystemId, reparsed.filesystemId)

        // Old password no longer works against the rewrapped file.
        assertThrows(CryfsWrongPasswordException::class.java) {
            CryfsConfigFile.parse(newRaw, oldPassword)
        }

        // The on-disk bytes actually changed (fresh salt/nonce/padding) --
        // this isn't just re-parsing the same file.
        assertFalse(oldRaw.contentEquals(newRaw))
    }
}
