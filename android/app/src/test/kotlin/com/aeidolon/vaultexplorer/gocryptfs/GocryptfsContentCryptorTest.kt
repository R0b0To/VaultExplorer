package com.aeidolon.vaultexplorer.gocryptfs

import java.security.SecureRandom
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class GocryptfsContentCryptorTest {
    private val random = SecureRandom()
    
    private fun newCryptor(cipher: GocryptfsCipher = GocryptfsCipher.AES_256_GCM) =
        GocryptfsContentCryptor(ByteArray(32).also { random.nextBytes(it) }, cipher)

    // Helper to determine if we are running in an environment where NativeEngine JNI calls work
    // (i.e., a real device/emulator rather than a bare host JVM where `System.loadLibrary` fails).
    private fun isNativeAvailable(): Boolean {
        return try {
            com.aeidolon.vaultexplorer.NativeEngine.getCascadeIdCount()
            true
        } catch (e: UnsatisfiedLinkError) {
            false
        } catch (e: NoClassDefFoundError) {
            false
        } catch (e: ExceptionInInitializerError) {
            false
        }
    }

    private fun ciphersToTest(): List<GocryptfsCipher> {
        return if (isNativeAvailable()) {
            GocryptfsCipher.values().toList()
        } else {
            // JVM-only fallback: only test standard AES ciphers backed by java.crypto.Cipher
            listOf(GocryptfsCipher.AES_256_GCM, GocryptfsCipher.AES_256_GCM_IV96)
        }
    }

    @Test
    fun `header round trip preserves fileId`() {
        for (cipher in ciphersToTest()) {
            val cryptor = newCryptor(cipher)
            val header = cryptor.createHeader()
            val encoded = cryptor.encodeHeader(header)
            assertEquals(GocryptfsContentCryptor.HEADER_LEN, encoded.size)
            val decoded = cryptor.decodeHeader(encoded)
            assertArrayEquals(header.fileId, decoded.fileId)
        }
    }

    @Test
    fun `decodeHeader rejects an unsupported version`() {
        val cryptor = newCryptor()
        val encoded = cryptor.encodeHeader(cryptor.createHeader())
        encoded[1] = 9
        assertThrows(GocryptfsContentAuthException::class.java) {
            cryptor.decodeHeader(encoded)
        }
    }

    @Test
    fun `chunk round trip for empty, partial, and full-size chunks`() {
        for (cipher in ciphersToTest()) {
            val cryptor = newCryptor(cipher)
            val header = cryptor.createHeader()
            for (cleartext in listOf(
                ByteArray(0),
                ByteArray(17) { it.toByte() },
                ByteArray(GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE) { (it % 256).toByte() },
            )) {
                val ciphertext = cryptor.encryptChunk(cleartext, chunkNumber = 5, header)
                val decrypted = cryptor.decryptChunk(ciphertext, chunkNumber = 5, header)
                assertArrayEquals(cleartext, decrypted)
            }
        }
    }

    @Test
    fun `decryptChunk fails auth when ciphertext is tampered`() {
        for (cipher in ciphersToTest()) {
            val cryptor = newCryptor(cipher)
            val header = cryptor.createHeader()
            val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, 0, header)
            val tampered = ciphertext.copyOf().also { it[it.size - 1] = it[it.size - 1].inc() }
            assertThrows(GocryptfsContentAuthException::class.java) {
                cryptor.decryptChunk(tampered, 0, header)
            }
        }
    }

    @Test
    fun `decryptChunk fails auth when chunkNumber does not match the AAD used to encrypt`() {
        for (cipher in ciphersToTest()) {
            val cryptor = newCryptor(cipher)
            val header = cryptor.createHeader()
            val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, chunkNumber = 3, header)
            assertThrows(GocryptfsContentAuthException::class.java) {
                cryptor.decryptChunk(ciphertext, chunkNumber = 4, header)
            }
        }
    }

    @Test
    fun `decryptChunk fails auth under a different content key`() {
        for (cipher in ciphersToTest()) {
            val cryptor = newCryptor(cipher)
            val header = cryptor.createHeader()
            val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, 0, header)
            val otherCryptor = newCryptor(cipher)
            assertThrows(GocryptfsContentAuthException::class.java) {
                otherCryptor.decryptChunk(ciphertext, 0, header)
            }
        }
    }

    @Test
    fun `an all-zero ciphertext chunk decodes as an all-zero cleartext chunk (sparse-file hole fast path)`() {
        for (cipher in ciphersToTest()) {
            val cryptor = newCryptor(cipher)
            val header = cryptor.createHeader()
            val allZeroCiphertext = ByteArray(cryptor.ciphertextChunkSize)
            val decrypted = cryptor.decryptChunk(allZeroCiphertext, chunkNumber = 0, header)
            assertArrayEquals(ByteArray(GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE), decrypted)
        }
    }

    @Test
    fun `a non-zero ciphertext with an all-zero nonce is rejected rather than silently mishandled`() {
        for (cipher in ciphersToTest()) {
            val cryptor = newCryptor(cipher)
            val header = cryptor.createHeader()
            val malformed = ByteArray(cryptor.ciphertextChunkSize)
            malformed[cryptor.ciphertextChunkSize - 1] = 1
            assertThrows(GocryptfsContentAuthException::class.java) {
                cryptor.decryptChunk(malformed, chunkNumber = 0, header)
            }
        }
    }

    @Test
    fun `cleartextSize is the inverse of the chunking math across chunk boundaries`() {
        for (cipher in ciphersToTest()) {
            val cryptor = newCryptor(cipher)
            val headerLen = GocryptfsContentCryptor.HEADER_LEN.toLong()
            val cleartextChunk = GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE.toLong()
            val ciphertextChunk = cryptor.ciphertextChunkSize.toLong()
            val nonceAndTagLen = (cryptor.ciphertextChunkSize - GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE).toLong()
            for (fullChunks in listOf(0L, 1L, 3L)) {
                val ciphertextSize = headerLen + fullChunks * ciphertextChunk
                val expectedCleartext = fullChunks * cleartextChunk
                assertEquals(expectedCleartext, cryptor.cleartextSize(ciphertextSize))
            }
            val partialCiphertext = headerLen + ciphertextChunk + (100L + nonceAndTagLen)
            assertEquals(cleartextChunk + 100L, cryptor.cleartextSize(partialCiphertext))
        }
    }
}