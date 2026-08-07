package com.aeidolon.vaultexplorer.cryptomator

import java.security.SecureRandom
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class Base32Test {
    // RFC 4648 §10 test vectors, padding stripped -- this implementation
    // (see hashDirectoryId's doc comment) deliberately produces unpadded
    // output to match Guava's BaseEncoding.base32(), so the reference
    // vectors below have their trailing '=' characters removed.
    private val base32 = Base32()

    @Test
    fun `RFC 4648 known-answer vectors`() {
        val cases = mapOf(
            "" to "",
            "f" to "MY",
            "fo" to "MZXQ",
            "foo" to "MZXW6",
            "foob" to "MZXW6YQ",
            "fooba" to "MZXW6YTB",
            "foobar" to "MZXW6YTBOI",
        )
        for ((input, expected) in cases) {
            assertEquals("encode(\"$input\")", expected, base32.encode(input.toByteArray(Charsets.US_ASCII)))
        }
    }
}

class CryptomatorFileNameCryptorTest {

    private val random = SecureRandom()
    private fun newCryptor() = CryptomatorFileNameCryptor(CryptomatorMasterkey.generate(random))

    @Test
    fun `encryptFilename and decryptFilename round trip with no associated data`() {
        val cryptor = newCryptor()
        val encrypted = cryptor.encryptFilename("some file.txt")
        assertEquals("some file.txt", cryptor.decryptFilename(encrypted))
    }

    @Test
    fun `encryptFilename and decryptFilename round trip with associated data (dirId)`() {
        val cryptor = newCryptor()
        val dirId = "11112222-3333-4444-5555-666677778888".toByteArray(Charsets.UTF_8)
        val encrypted = cryptor.encryptFilename("report (final).pdf", dirId)
        assertEquals("report (final).pdf", cryptor.decryptFilename(encrypted, dirId))
    }

    @Test
    fun `decryptFilename fails authentication when associated data does not match what was used to encrypt`() {
        val cryptor = newCryptor()
        val dirId = "dir-a".toByteArray(Charsets.UTF_8)
        val otherDirId = "dir-b".toByteArray(Charsets.UTF_8)
        val encrypted = cryptor.encryptFilename("secret.txt", dirId)

        // SIV mode authenticates the associated data as part of the tag,
        // so decrypting under the wrong dirId must fail closed rather than
        // silently returning a name for the wrong directory's tweak.
        assertThrows(CryptomatorAuthenticationException::class.java) {
            cryptor.decryptFilename(encrypted, otherDirId)
        }
    }

    @Test
    fun `decryptFilename fails authentication under a different masterkey`() {
        val cryptor = newCryptor()
        val encrypted = cryptor.encryptFilename("secret.txt")
        val otherCryptor = CryptomatorFileNameCryptor(CryptomatorMasterkey.generate(random))

        assertThrows(CryptomatorAuthenticationException::class.java) {
            otherCryptor.decryptFilename(encrypted)
        }
    }

    @Test
    fun `decryptFilename rejects malformed base64`() {
        val cryptor = newCryptor()
        assertThrows(CryptomatorAuthenticationException::class.java) {
            cryptor.decryptFilename("not valid base64url!!!")
        }
    }

    @Test
    fun `hashDirectoryId is deterministic for the same key and dirId`() {
        val cryptor = newCryptor()
        val h1 = cryptor.hashDirectoryId("some-dir-id")
        val h2 = cryptor.hashDirectoryId("some-dir-id")
        assertEquals(h1, h2)
    }

    @Test
    fun `hashDirectoryId differs for different dirIds under the same key`() {
        val cryptor = newCryptor()
        assertNotEquals(cryptor.hashDirectoryId("dir-a"), cryptor.hashDirectoryId("dir-b"))
    }

    @Test
    fun `hashDirectoryId differs for the same dirId under different keys`() {
        val cryptorA = newCryptor()
        val cryptorB = newCryptor()
        assertNotEquals(cryptorA.hashDirectoryId("same-dir-id"), cryptorB.hashDirectoryId("same-dir-id"))
    }

    @Test
    fun `round trip holds for empty and multi-byte-boundary filenames`() {
        val cryptor = newCryptor()
        for (name in listOf("", "a", "a longer file name with spaces and punctuation!.tar.gz", "🎉emoji-name.txt")) {
            val encrypted = cryptor.encryptFilename(name)
            assertEquals(name, cryptor.decryptFilename(encrypted))
        }
    }
}
