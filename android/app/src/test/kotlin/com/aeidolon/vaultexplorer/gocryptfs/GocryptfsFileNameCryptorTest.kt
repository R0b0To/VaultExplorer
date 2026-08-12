package com.aeidolon.vaultexplorer.gocryptfs

import java.security.SecureRandom
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class GocryptfsFileNameCryptorTest {
    private val random = SecureRandom()
    private fun newCryptor(longNameMax: Int = 0, plaintextNames: Boolean = false) =
        GocryptfsFileNameCryptor(ByteArray(32).also { random.nextBytes(it) }, longNameMax, plaintextNames)

    private fun randomDirIv() = ByteArray(16).also { random.nextBytes(it) }

    @Test
    fun `encryptName and decryptName round trip across pad16 block-size boundaries`() {
        val cryptor = newCryptor()
        val dirIv = randomDirIv()
        for (name in listOf("", "a".repeat(15), "a".repeat(16), "a".repeat(17), "üñïçødé.txt")) {
            val encrypted = cryptor.encryptName(name, dirIv)
            assertEquals(name, cryptor.decryptName(encrypted, dirIv))
        }
    }

    @Test
    fun `encryptName is deterministic for the same key, name, and dirIv`() {
        val cryptor = newCryptor()
        val dirIv = randomDirIv()
        assertEquals(cryptor.encryptName("same.txt", dirIv), cryptor.encryptName("same.txt", dirIv))
    }

    @Test
    fun `encryptName differs for the same name under different dirIvs`() {
        val cryptor = newCryptor()
        val a = cryptor.encryptName("same.txt", randomDirIv())
        val b = cryptor.encryptName("same.txt", randomDirIv())
        assertTrue(a != b)
    }

    @Test
    fun `decryptName rejects malformed base64`() {
        val cryptor = newCryptor()
        assertThrows(GocryptfsNameException::class.java) {
            cryptor.decryptName("not valid base64url!!!", randomDirIv())
        }
    }

    @Test
    fun `decryptName rejects ciphertext whose decoded length is not a multiple of 16`() {
        val cryptor = newCryptor()
        val notBlockAligned = java.util.Base64.getUrlEncoder().withoutPadding()
            .encodeToString(ByteArray(17))
        assertThrows(GocryptfsNameException::class.java) {
            cryptor.decryptName(notBlockAligned, randomDirIv())
        }
    }

    @Test
    fun `decryptName rejects empty ciphertext`() {
        val cryptor = newCryptor()
        assertThrows(GocryptfsNameException::class.java) {
            cryptor.decryptName("", randomDirIv())
        }
    }

    @Test
    fun `hashLongName has the expected prefix and is deterministic`() {
        val cryptor = newCryptor()
        val h1 = cryptor.hashLongName("some-ciphertext-name")
        val h2 = cryptor.hashLongName("some-ciphertext-name")
        assertEquals(h1, h2)
        assertTrue(h1.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX))
    }

    @Test
    fun `effectiveLongNameMax falls back to the default when configured value is non-positive`() {
        assertEquals(255, newCryptor(longNameMax = 0).effectiveLongNameMax)
        assertEquals(255, newCryptor(longNameMax = -1).effectiveLongNameMax)
        assertEquals(180, newCryptor(longNameMax = 180).effectiveLongNameMax)
    }

    @Test
    fun `isOverLongNameLimit is a strict length comparison against effectiveLongNameMax`() {
        val cryptor = newCryptor(longNameMax = 10)
        assertFalse(cryptor.isOverLongNameLimit("a".repeat(10)))
        assertTrue(cryptor.isOverLongNameLimit("a".repeat(11)))
    }
    
    @Test
    fun `plaintextNames bypasses encryption and hashing`() {
        val cryptor = newCryptor(plaintextNames = true)
        val dirIv = randomDirIv()
        assertEquals("secret.txt", cryptor.encryptName("secret.txt", dirIv))
        assertEquals("secret.txt", cryptor.decryptName("secret.txt", dirIv))
        // isOverLongNameLimit should always be false when PlaintextNames is set.
        assertFalse(cryptor.isOverLongNameLimit("a".repeat(300)))
    }
}