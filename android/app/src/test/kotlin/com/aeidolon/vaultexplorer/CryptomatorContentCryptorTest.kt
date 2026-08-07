package com.aeidolon.vaultexplorer.cryptomator

import java.security.SecureRandom
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Pure-JVM (javax.crypto only, no NativeEngine/JNI dependency) so this runs
 * under a plain `./gradlew testDebugUnitTest` without needing a device,
 * emulator, or Robolectric. This is deliberately the boundary this suite
 * covers -- CryptomatorFileNameCryptor/SivMode were NOT given tests here
 * because they route through NativeEngine.sivEncryptNative(), whose
 * un-guarded `System.loadLibrary("vaultexplorer")` init block throws
 * UnsatisfiedLinkError the moment it's referenced outside a real Android
 * process, crashing the whole test rather than exercising the Kotlin
 * fallback path. That's a separate, real gap (see conversation notes) --
 * fixing it means either guarding the loadLibrary call or injecting the
 * native call behind a seam, which is a bigger change than this pass.
 */
class CryptomatorContentCryptorTest {

    private val random = SecureRandom()
    private val masterkey = CryptomatorMasterkey.generate(random)

    private fun roundTripHeader(cryptor: CryptomatorContentCryptor) {
        val header = cryptor.createHeader(random).also { it.reserved = 42L }
        val encrypted = cryptor.encryptHeader(header, masterkey, random)
        assertEquals(cryptor.headerSize, encrypted.size)

        val decrypted = cryptor.decryptHeader(encrypted, masterkey)
        assertArrayEquals(header.nonce, decrypted.nonce)
        assertArrayEquals(header.contentKey, decrypted.contentKey)
        assertEquals(header.reserved, decrypted.reserved)
    }

    private fun roundTripChunk(cryptor: CryptomatorContentCryptor, cleartext: ByteArray, chunkNumber: Long) {
        val header = cryptor.createHeader(random)
        val ciphertext = cryptor.encryptChunk(cleartext, chunkNumber, header, masterkey, random)
        val decrypted = cryptor.decryptChunk(ciphertext, chunkNumber, header, masterkey)
        assertArrayEquals(cleartext, decrypted)
    }

    // ---- Gcm (vault format 8) ----------------------------------------

    @Test
    fun `Gcm header round trip preserves nonce, contentKey, and reserved field`() {
        roundTripHeader(CryptomatorContentCryptor.Gcm)
    }

    @Test
    fun `Gcm chunk round trip for empty, partial, and full-size chunks`() {
        val cryptor = CryptomatorContentCryptor.Gcm
        roundTripChunk(cryptor, ByteArray(0), chunkNumber = 0)
        roundTripChunk(cryptor, ByteArray(37) { it.toByte() }, chunkNumber = 0)
        roundTripChunk(cryptor, ByteArray(cryptor.cleartextChunkSize) { (it % 256).toByte() }, chunkNumber = 5)
    }

    @Test
    fun `Gcm decryptChunk fails auth when ciphertext is tampered`() {
        val cryptor = CryptomatorContentCryptor.Gcm
        val header = cryptor.createHeader(random)
        val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, 0, header, masterkey, random)
        val tampered = ciphertext.copyOf().also { it[it.size - 1] = it[it.size - 1].inc() }

        assertThrows(CryptomatorAuthenticationException::class.java) {
            cryptor.decryptChunk(tampered, 0, header, masterkey)
        }
    }

    @Test
    fun `Gcm decryptChunk fails auth when chunkNumber does not match the AAD used to encrypt`() {
        val cryptor = CryptomatorContentCryptor.Gcm
        val header = cryptor.createHeader(random)
        val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, 3, header, masterkey, random)

        assertThrows(CryptomatorAuthenticationException::class.java) {
            cryptor.decryptChunk(ciphertext, 4, header, masterkey) // wrong chunk number as AAD
        }
    }

    @Test
    fun `Gcm decryptHeader fails auth under a different masterkey`() {
        val cryptor = CryptomatorContentCryptor.Gcm
        val header = cryptor.createHeader(random)
        val encrypted = cryptor.encryptHeader(header, masterkey, random)
        val otherKey = CryptomatorMasterkey.generate(random)

        assertThrows(CryptomatorAuthenticationException::class.java) {
            cryptor.decryptHeader(encrypted, otherKey)
        }
    }

    // ---- CtrHmac (vault format 7) -------------------------------------

    @Test
    fun `CtrHmac header round trip preserves nonce, contentKey, and reserved field`() {
        roundTripHeader(CryptomatorContentCryptor.CtrHmac)
    }

    @Test
    fun `CtrHmac chunk round trip for empty, partial, and full-size chunks`() {
        val cryptor = CryptomatorContentCryptor.CtrHmac
        roundTripChunk(cryptor, ByteArray(0), chunkNumber = 0)
        roundTripChunk(cryptor, ByteArray(37) { it.toByte() }, chunkNumber = 0)
        roundTripChunk(cryptor, ByteArray(cryptor.cleartextChunkSize) { (it % 256).toByte() }, chunkNumber = 5)
    }

    @Test
    fun `CtrHmac decryptChunk fails auth when ciphertext is tampered`() {
        val cryptor = CryptomatorContentCryptor.CtrHmac
        val header = cryptor.createHeader(random)
        val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, 0, header, masterkey, random)
        val tampered = ciphertext.copyOf().also { it[0] = it[0].inc() }

        assertThrows(CryptomatorAuthenticationException::class.java) {
            cryptor.decryptChunk(tampered, 0, header, masterkey)
        }
    }

    @Test
    fun `CtrHmac decryptChunk fails auth when chunkNumber does not match the MAC computed at encryption`() {
        val cryptor = CryptomatorContentCryptor.CtrHmac
        val header = cryptor.createHeader(random)
        val ciphertext = cryptor.encryptChunk(ByteArray(64) { 1 }, 3, header, masterkey, random)

        assertThrows(CryptomatorAuthenticationException::class.java) {
            cryptor.decryptChunk(ciphertext, 4, header, masterkey)
        }
    }

    // ---- ciphertextSize()/cleartextSize() round trip -------------------

    @Test
    fun `ciphertextSize and cleartextSize are inverses across chunk boundaries (Gcm)`() {
        val cryptor = CryptomatorContentCryptor.Gcm
        for (cleartextSize in listOf(0L, 1L, 37L, cryptor.cleartextChunkSize.toLong(),
                                      cryptor.cleartextChunkSize.toLong() + 1, cryptor.cleartextChunkSize.toLong() * 3)) {
            val ciphertextSize = cryptor.ciphertextSize(cleartextSize)
            assertEquals(
                "cleartextSize(ciphertextSize($cleartextSize)) should round-trip",
                cleartextSize, cryptor.cleartextSize(ciphertextSize)
            )
        }
    }

    @Test
    fun `ciphertextSize and cleartextSize are inverses across chunk boundaries (CtrHmac)`() {
        val cryptor = CryptomatorContentCryptor.CtrHmac
        for (cleartextSize in listOf(0L, 1L, 37L, cryptor.cleartextChunkSize.toLong(),
                                      cryptor.cleartextChunkSize.toLong() + 1, cryptor.cleartextChunkSize.toLong() * 3)) {
            val ciphertextSize = cryptor.ciphertextSize(cleartextSize)
            assertEquals(
                "cleartextSize(ciphertextSize($cleartextSize)) should round-trip",
                cleartextSize, cryptor.cleartextSize(ciphertextSize)
            )
        }
    }
}
