package com.aeidolon.vaultexplorer.gocryptfs

import java.security.SecureRandom
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GocryptfsVaultTreeTest {
    private val random = SecureRandom()
    private fun newCryptor(longNameMax: Int = 0, plaintextNames: Boolean = false) =
        GocryptfsFileNameCryptor(ByteArray(32).also { random.nextBytes(it) }, longNameMax, plaintextNames)

    private fun randomDirIv() = ByteArray(16).also { random.nextBytes(it) }

    @Test
    fun `direct name lookup uses exact deterministic ciphertext`() {
        val cryptor = newCryptor()
        val dirIv = randomDirIv()
        val plainName = "vacation_video.mp4"
        val cipherName1 = cryptor.encryptName(plainName, dirIv)
        val cipherName2 = cryptor.encryptName(plainName, dirIv)

        assertEquals("EME name encryption must be deterministic for identical name and dirIv", cipherName1, cipherName2)
        assertEquals("Decrypted name matches plain name", plainName, cryptor.decryptName(cipherName1, dirIv))
    }

    @Test
    fun `different dirIvs produce distinct ciphertext names`() {
        val cryptor = newCryptor()
        val dirIv1 = randomDirIv()
        val dirIv2 = randomDirIv()
        val plainName = "vacation_video.mp4"
        val cipherName1 = cryptor.encryptName(plainName, dirIv1)
        val cipherName2 = cryptor.encryptName(plainName, dirIv2)

        assertNotEquals("Different directory IVs must produce distinct ciphertexts", cipherName1, cipherName2)
    }

    @Test
    fun `case sensitivity in ciphertext names is preserved`() {
        val cryptor = newCryptor()
        val dirIv = randomDirIv()
        val plainName1 = "file_a.txt"
        val plainName2 = "file_b.txt"
        val c1 = cryptor.encryptName(plainName1, dirIv)
        val c2 = cryptor.encryptName(plainName2, dirIv)

        // Ensure base64 ciphertext names with different cases are not equal
        val c1Lower = c1.lowercase()
        val c2Lower = c2.lowercase()
        // Ciphertext names are Base64 and case-sensitive
        assertEquals(plainName1, cryptor.decryptName(c1, dirIv))
        assertEquals(plainName2, cryptor.decryptName(c2, dirIv))
    }

    @Test
    fun `long name hashing produces expected prefix and deterministic output`() {
        val cryptor = newCryptor(longNameMax = 30)
        val dirIv = randomDirIv()
        val longPlainName = "a_very_long_file_name_that_exceeds_threshold.mp4"
        val cipherName = cryptor.encryptName(longPlainName, dirIv)

        assertTrue(cryptor.isOverLongNameLimit(cipherName))
        val shortName1 = cryptor.hashLongName(cipherName)
        val shortName2 = cryptor.hashLongName(cipherName)
        assertEquals(shortName1, shortName2)
        assertTrue(shortName1.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX))
    }
}
