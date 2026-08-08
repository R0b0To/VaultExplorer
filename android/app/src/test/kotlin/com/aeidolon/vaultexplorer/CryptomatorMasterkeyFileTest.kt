package com.aeidolon.vaultexplorer.cryptomator

import java.security.SecureRandom
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Pure-JVM (org.json + javax.crypto only, no NativeEngine/JNI dependency)
 * coverage for masterkey.cryptomator's wrap/unwrap round trip -- the same
 * parse -> unlock -> lock sequence CryptomatorVault.changePassword uses to
 * rewrap a vault under a new passphrase. See CryptomatorContentCryptorTest's
 * doc comment for why this suite stays clear of anything routing through
 * NativeEngine's JNI init.
 */
class CryptomatorMasterkeyFileTest {

    private val random = SecureRandom()

    @Test
    fun `lock then unlock recovers the same masterkey bytes`() {
        val masterkey = CryptomatorMasterkey.generate(random)
        val passphrase = "correct horse battery staple".toCharArray()

        val fileBytes = CryptomatorMasterkeyFile.lock(masterkey, passphrase, random, vaultVersion = 8)
        val parsed = CryptomatorMasterkeyFile.parse(fileBytes)
        val unlocked = CryptomatorMasterkeyFile.unlock(parsed, passphrase)

        assertArrayEquals(masterkey.rawKeyBytes(), unlocked.rawKeyBytes())
    }

    @Test
    fun `wrong passphrase is rejected`() {
        val masterkey = CryptomatorMasterkey.generate(random)
        val fileBytes = CryptomatorMasterkeyFile.lock(masterkey, "right password".toCharArray(), random)
        val parsed = CryptomatorMasterkeyFile.parse(fileBytes)

        assertThrows(InvalidPassphraseException::class.java) {
            CryptomatorMasterkeyFile.unlock(parsed, "wrong password".toCharArray())
        }
    }

    @Test
    fun `changing password preserves the masterkey but rotates the wrapping`() {
        // Mirrors CryptomatorVault.changePassword: parse+unlock with the old
        // passphrase, then lock the SAME masterkey object under a new one.
        val masterkey = CryptomatorMasterkey.generate(random)
        val oldPassphrase = "old passphrase".toCharArray()
        val newPassphrase = "new passphrase".toCharArray()

        val oldFileBytes = CryptomatorMasterkeyFile.lock(masterkey, oldPassphrase, random, vaultVersion = 8)
        val oldParsed = CryptomatorMasterkeyFile.parse(oldFileBytes)
        val unlocked = CryptomatorMasterkeyFile.unlock(oldParsed, oldPassphrase)

        val newFileBytes = CryptomatorMasterkeyFile.lock(unlocked, newPassphrase, random, vaultVersion = oldParsed.version)
        val newParsed = CryptomatorMasterkeyFile.parse(newFileBytes)

        // New password unlocks it and recovers the identical masterkey.
        val reunlocked = CryptomatorMasterkeyFile.unlock(newParsed, newPassphrase)
        assertArrayEquals(masterkey.rawKeyBytes(), reunlocked.rawKeyBytes())
        assertEquals(oldParsed.version, newParsed.version)

        // Old password no longer works against the rewrapped file.
        assertThrows(InvalidPassphraseException::class.java) {
            CryptomatorMasterkeyFile.unlock(newParsed, oldPassphrase)
        }

        // The salt (and therefore the wrapped-key ciphertext) actually
        // rotated -- this isn't just re-parsing the same bytes.
        assertFalse(oldParsed.scryptSalt.contentEquals(newParsed.scryptSalt))
        assertFalse(oldParsed.encMasterKeyWrapped.contentEquals(newParsed.encMasterKeyWrapped))
    }
}
