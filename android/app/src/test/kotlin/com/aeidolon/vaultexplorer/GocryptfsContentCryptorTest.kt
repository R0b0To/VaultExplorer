package com.aeidolon.vaultexplorer.gocryptfs

import java.security.SecureRandom
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Pure-JVM (javax.crypto only, no NativeEngine/JNI dependency) -- unlike
 * GocryptfsFileNameCryptor/GocryptfsEme, which route through
 * NativeEngine.gocryptfsEmeNative() and aren't safely testable here (see
 * CryptomatorContentCryptorTest's class doc for why).
 */
class GocryptfsContentCryptorTest {

    private val random = SecureRandom()
    private fun newCryptor() = GocryptfsContentCryptor(ByteArray(32).also { random.nextBytes(it) })

    @Test
    fun `header round trip preserves fileId`() {
        val cryptor = newCryptor()
        val header = cryptor.createHeader()
        val encoded = cryptor.encodeHeader(header)
        assertEquals(GocryptfsContentCryptor.HEADER_LEN, encoded.size)

        val decoded = cryptor.decodeHeader(encoded)
        assertArrayEquals(header.fileId, decoded.fileId)
    }

    @Test
    fun `decodeHeader rejects an unsupported version`() {
        val cryptor = newCryptor()
        val encoded = cryptor.encodeHeader(cryptor.createHeader())
        // Byte 0-1 is the big-endian version (currently 2); corrupt it.
        encoded[1] = 9

        assertThrows(GocryptfsContentAuthException::class.java) {
            cryptor.decodeHeader(encoded)
        }
    }

    @Test
    fun `chunk round trip for empty, partial, and full-size chunks`() {
        val cryptor = newCryptor()
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

    @Test
    fun `decryptChunk fails auth when ciphertext is tampered`() {
        val cryptor = newCryptor()
        val header = cryptor.createHeader()
        val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, 0, header)
        val tampered = ciphertext.copyOf().also { it[it.size - 1] = it[it.size - 1].inc() }

        assertThrows(GocryptfsContentAuthException::class.java) {
            cryptor.decryptChunk(tampered, 0, header)
        }
    }

    @Test
    fun `decryptChunk fails auth when chunkNumber does not match the AAD used to encrypt`() {
        val cryptor = newCryptor()
        val header = cryptor.createHeader()
        val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, chunkNumber = 3, header)

        assertThrows(GocryptfsContentAuthException::class.java) {
            cryptor.decryptChunk(ciphertext, chunkNumber = 4, header)
        }
    }

    @Test
    fun `decryptChunk fails auth under a different content key`() {
        val cryptor = newCryptor()
        val header = cryptor.createHeader()
        val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, 0, header)
        val otherCryptor = newCryptor()

        assertThrows(GocryptfsContentAuthException::class.java) {
            otherCryptor.decryptChunk(ciphertext, 0, header)
        }
    }

    @Test
    fun `an all-zero ciphertext chunk decodes as an all-zero cleartext chunk (sparse-file hole fast path)`() {
        // Matches gocryptfs's own content.go fast path for sparse-file
        // holes: an all-zero physical chunk never went through encryption
        // at all, so it must decode without touching AES-GCM or the key,
        // rather than being treated as (and failing) a real ciphertext.
        val cryptor = newCryptor()
        val header = cryptor.createHeader()
        val allZeroCiphertext = ByteArray(GocryptfsContentCryptor.CIPHERTEXT_CHUNK_SIZE)

        val decrypted = cryptor.decryptChunk(allZeroCiphertext, chunkNumber = 0, header)

        assertArrayEquals(ByteArray(GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE), decrypted)
    }

    @Test
    fun `a non-zero ciphertext with an all-zero nonce is rejected rather than silently mishandled`() {
        // Only a *fully* all-zero chunk (nonce AND payload) is the sparse
        // hole fast path. A chunk with a genuine all-zero nonce but
        // non-zero payload should never occur from real encryption (nonces
        // are random) and must be rejected explicitly, not decrypted with
        // an all-zero IV.
        val cryptor = newCryptor()
        val header = cryptor.createHeader()
        val malformed = ByteArray(GocryptfsContentCryptor.CIPHERTEXT_CHUNK_SIZE)
        malformed[GocryptfsContentCryptor.CIPHERTEXT_CHUNK_SIZE - 1] = 1 // non-zero payload/tag byte, zero nonce

        assertThrows(GocryptfsContentAuthException::class.java) {
            cryptor.decryptChunk(malformed, chunkNumber = 0, header)
        }
    }

    @Test
    fun `cleartextSize is the inverse of the chunking math across chunk boundaries`() {
        val headerLen = GocryptfsContentCryptor.HEADER_LEN.toLong()
        val cleartextChunk = GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE.toLong()
        val ciphertextChunk = GocryptfsContentCryptor.CIPHERTEXT_CHUNK_SIZE.toLong()
        val overhead = ciphertextChunk - cleartextChunk

        // No encryptWhole()/ciphertextSize() helper exists on this class (unlike
        // Cryptomator's), so we compute expected ciphertext size the same way the
        // real chunker would: header + N full chunks' worth of ciphertext.
        for (fullChunks in listOf(0L, 1L, 3L)) {
            val ciphertextSize = headerLen + fullChunks * ciphertextChunk
            val expectedCleartext = fullChunks * cleartextChunk
            assertEquals(expectedCleartext, GocryptfsContentCryptor(ByteArray(32)).cleartextSize(ciphertextSize))
        }

        // Partial trailing chunk: header + one full chunk + a partial chunk of 100 cleartext bytes.
        val partialCiphertext = headerLen + ciphertextChunk + (100L + overhead)
        assertEquals(cleartextChunk + 100L, GocryptfsContentCryptor(ByteArray(32)).cleartextSize(partialCiphertext))
    }
}
