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
        // (An empty name is not a name: gocryptfs refuses to encrypt or decrypt one.)
        for (name in listOf("a".repeat(15), "a".repeat(16), "a".repeat(17), "üñïçødé.txt")) {
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

    // ---- compatibility with the official gocryptfs (nametransform.IsValidName / base64.Strict) ----

    @Test
    fun `every name gocryptfs allows round trips, including ones this app used to hide`() {
        val cryptor = newCryptor()
        val dirIv = randomDirIv()
        for (name in listOf("nl\nname", "cr\rname", "repl-\uFFFD-char", " lead trail ", "...", ".hidden", "a".repeat(255), "gocryptfs.conf")) {
            assertEquals(name, cryptor.decryptName(cryptor.encryptName(name, dirIv), dirIv))
        }
    }

    @Test
    fun `names gocryptfs refuses are refused`() {
        val cryptor = newCryptor()
        val dirIv = randomDirIv()
        for (name in listOf("", ".", "..", "a/b", "a\u0000b", "a".repeat(256))) {
            assertThrows(GocryptfsNameException::class.java) { cryptor.encryptName(name, dirIv) }
        }
        assertFalse(GocryptfsFileNameCryptor.isValidName(ByteArray(0)))
        assertTrue(GocryptfsFileNameCryptor.isValidName("\n".toByteArray()))
    }

    @Test
    fun `a block of pure padding is not a name`() {
        val key = ByteArray(32).also { random.nextBytes(it) }
        val dirIv = randomDirIv()
        val forged = GocryptfsEme(key).encrypt(dirIv, ByteArray(16) { 16 })
        val name = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(forged)
        assertThrows(GocryptfsNameException::class.java) { GocryptfsFileNameCryptor(key, 0).decryptName(name, dirIv) }
    }

    @Test
    fun `decryptName insists on the canonical base64 spelling`() {
        val cryptor = newCryptor()
        val dirIv = randomDirIv()
        val c = cryptor.encryptName("x", dirIv)   // 16 bytes -> 22 chars; the last carries 4 zero bits
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        val i = alphabet.indexOf(c.last())
        assertEquals(0, i and 15)
        // the same bytes spelled with non-zero trailing bits: Java's decoder accepts it, gocryptfs does not
        assertThrows(GocryptfsNameException::class.java) { cryptor.decryptName(c.dropLast(1) + alphabet[i or 1], dirIv) }
        assertThrows(GocryptfsNameException::class.java) { cryptor.decryptName(c + "=", dirIv) }
    }

    @Test
    fun `padded base64 vaults (no Raw64) pad names and long-name hashes`() {
        val key = ByteArray(32).also { random.nextBytes(it) }
        val dirIv = randomDirIv()
        val padded = GocryptfsFileNameCryptor(key, 0, false, raw64 = false)
        val raw = GocryptfsFileNameCryptor(key, 0, false, raw64 = true)
        val c = padded.encryptName("x", dirIv)
        assertEquals(24, c.length)
        assertTrue(c.endsWith("=="))
        assertEquals("x", padded.decryptName(c, dirIv))
        assertThrows(GocryptfsNameException::class.java) { padded.decryptName(c.dropLast(2), dirIv) }   // padding is mandatory
        assertThrows(GocryptfsNameException::class.java) { raw.decryptName(c, dirIv) }                   // and forbidden with Raw64
        assertTrue(padded.hashLongName("abc").endsWith("="))
        assertFalse(raw.hashLongName("abc").endsWith("="))
    }
}
