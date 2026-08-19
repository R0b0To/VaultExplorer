package com.aeidolon.vaultexplorer.cryfs

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Runs entirely against [CryfsBlockCipher]'s JVM fallback: this module's
 * src/test/kotlin unit tests run on the plain JVM with no native .so on
 * the classpath (see app/build.gradle -- testImplementation is JUnit
 * only), so every NativeEngine.cryfs*Native call here throws
 * UnsatisfiedLinkError and falls through to the Kotlin implementation.
 * That's the whole point: this is the test that couldn't exist before
 * CryfsBlockCipher.kt had a fallback at all (see the tech-debt note this
 * addresses -- SivMode.kt and GocryptfsEme.kt already had this; this
 * class didn't).
 */
class CryfsBlockCipherTest {

    private fun hex(s: String): ByteArray {
        val clean = s.replace(Regex("[^0-9a-fA-F]"), "")
        return ByteArray(clean.length / 2) { i -> clean.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }

    // ---- cipherIdFor ----

    @Test
    fun `cipherIdFor maps every known cipher name to a distinct id`() {
        val ids = listOf("aes-256-gcm", "aes-256-cfb", "aes-128-gcm", "aes-128-cfb", "xchacha20-poly1305")
            .map { CryfsBlockCipher.cipherIdFor(it) }
        assertEquals(5, ids.toSet().size) // all distinct
        assertTrue(ids.all { it >= 0 })
    }

    @Test
    fun `cipherIdFor rejects an unknown cipher name`() {
        assertThrows(CryfsUnsupportedCipherException::class.java) {
            CryfsBlockCipher.cipherIdFor("aes-512-turbo")
        }
    }

    // ---- round-trips for every cipher CryFS supports ----

    private fun roundTripCase(cipherName: String, keySize: Int) {
        val cipherId = CryfsBlockCipher.cipherIdFor(cipherName)
        val key = ByteArray(keySize) { (it * 11 + 3).toByte() }
        val plaintext = "a cryfs block's worth of plaintext data, long enough to span multiple cipher blocks of any of these algorithms".toByteArray(Charsets.US_ASCII)

        val ciphertext = CryfsBlockCipher.encrypt(cipherId, key, plaintext)
        val decrypted = CryfsBlockCipher.decrypt(cipherId, key, ciphertext)
        assertArrayEquals("round-trip failed for $cipherName", plaintext, decrypted)
    }

    @Test fun `aes-256-gcm round-trips`() = roundTripCase("aes-256-gcm", 32)
    @Test fun `aes-128-gcm round-trips`() = roundTripCase("aes-128-gcm", 16)
    @Test fun `aes-256-cfb round-trips`() = roundTripCase("aes-256-cfb", 32)
    @Test fun `aes-128-cfb round-trips`() = roundTripCase("aes-128-cfb", 16)
    @Test fun `xchacha20-poly1305 round-trips`() = roundTripCase("xchacha20-poly1305", 32)

    @Test
    fun `round-trip also holds for empty plaintext, on every cipher`() {
        for (name in listOf("aes-256-gcm", "aes-128-gcm", "aes-256-cfb", "aes-128-cfb", "xchacha20-poly1305")) {
            val cipherId = CryfsBlockCipher.cipherIdFor(name)
            val keySize = if (name.startsWith("aes-128")) 16 else 32
            val key = ByteArray(keySize)
            val ciphertext = CryfsBlockCipher.encrypt(cipherId, key, ByteArray(0))
            val decrypted = CryfsBlockCipher.decrypt(cipherId, key, ciphertext)
            assertArrayEquals("empty round-trip failed for $name", ByteArray(0), decrypted)
        }
    }

    // ---- byte layout: IV/nonce and tag sizes must match the C++ side exactly ----

    @Test
    fun `gcm ciphertext layout is 16-byte IV, then body, then 16-byte tag`() {
        val cipherId = CryfsBlockCipher.cipherIdFor("aes-256-gcm")
        val key = ByteArray(32)
        val plaintext = ByteArray(37) { it.toByte() }
        val ciphertext = CryfsBlockCipher.encrypt(cipherId, key, plaintext)
        assertEquals(16 + plaintext.size + 16, ciphertext.size)
    }

    @Test
    fun `cfb ciphertext layout is 16-byte IV then body, no tag`() {
        val cipherId = CryfsBlockCipher.cipherIdFor("aes-256-cfb")
        val key = ByteArray(32)
        val plaintext = ByteArray(37) { it.toByte() }
        val ciphertext = CryfsBlockCipher.encrypt(cipherId, key, plaintext)
        assertEquals(16 + plaintext.size, ciphertext.size)
    }

    @Test
    fun `xchacha20-poly1305 ciphertext layout is 24-byte nonce, then body, then 16-byte tag`() {
        val cipherId = CryfsBlockCipher.cipherIdFor("xchacha20-poly1305")
        val key = ByteArray(32)
        val plaintext = ByteArray(37) { it.toByte() }
        val ciphertext = CryfsBlockCipher.encrypt(cipherId, key, plaintext)
        assertEquals(24 + plaintext.size + 16, ciphertext.size)
    }

    // ---- NIST SP 800-38A Appendix F.3.13 / F.3.17: CFB128-AES128 / CFB128-AES256 ----
    // Exercised through the public decrypt() API by feeding it the NIST
    // IV||ciphertext blob directly: CryfsBlockCipher.encrypt() always
    // generates its own random IV internally, so a fixed-IV *encrypt*
    // check isn't reachable through the public API -- but decrypt() takes
    // the full blob as input, which is enough to validate the same
    // AES/CFB/NoPadding transformation end to end against an official
    // vector, and encrypt() shares that exact Cipher setup (just
    // ENCRYPT_MODE instead of DECRYPT_MODE).

    @Test
    fun `aes-128-cfb decrypt matches NIST SP 800-38A CFB128-AES128 vector`() {
        val cipherId = CryfsBlockCipher.cipherIdFor("aes-128-cfb")
        val key = hex("2b7e151628aed2a6abf7158809cf4f3c")
        val iv = hex("000102030405060708090a0b0c0d0e0f")
        val ciphertext = hex(
            "3b3fd92eb72dad20333449f8e83cfb4a" +
                "c8a64537a0b3a93fcde3cdad9f1ce58b" +
                "26751f67a3cbb140b1808cf187a4f4df" +
                "c04b05357c5d1c0eeac4c66f9ff7f2e6"
        )
        val expectedPlaintext = hex(
            "6bc1bee22e409f96e93d7e117393172a" +
                "ae2d8a571e03ac9c9eb76fac45af8e51" +
                "30c81c46a35ce411e5fbc1191a0a52ef" +
                "f69f2445df4f9b17ad2b417be66c3710"
        )
        val decrypted = CryfsBlockCipher.decrypt(cipherId, key, iv + ciphertext)
        assertArrayEquals(expectedPlaintext, decrypted)
    }

    @Test
    fun `aes-256-cfb decrypt matches NIST SP 800-38A CFB128-AES256 vector`() {
        val cipherId = CryfsBlockCipher.cipherIdFor("aes-256-cfb")
        val key = hex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
        val iv = hex("000102030405060708090a0b0c0d0e0f")
        val ciphertext = hex(
            "dc7e84bfda79164b7ecd8486985d3860" +
                "39ffed143b28b1c832113c6331e5407b" +
                "df10132415e54b92a13ed0a8267ae2f9" +
                "75a385741ab9cef82031623d55b1e471"
        )
        val expectedPlaintext = hex(
            "6bc1bee22e409f96e93d7e117393172a" +
                "ae2d8a571e03ac9c9eb76fac45af8e51" +
                "30c81c46a35ce411e5fbc1191a0a52ef" +
                "f69f2445df4f9b17ad2b417be66c3710"
        )
        val decrypted = CryfsBlockCipher.decrypt(cipherId, key, iv + ciphertext)
        assertArrayEquals(expectedPlaintext, decrypted)
    }

    // ---- authentication: GCM and XChaCha20-Poly1305 must reject tampering; CFB can't (by design) ----

    @Test
    fun `gcm and xchacha20-poly1305 reject a tampered ciphertext byte`() {
        for (name in listOf("aes-256-gcm", "xchacha20-poly1305")) {
            val cipherId = CryfsBlockCipher.cipherIdFor(name)
            val key = ByteArray(32)
            val ciphertext = CryfsBlockCipher.encrypt(cipherId, key, "some plaintext".toByteArray())
            val tampered = ciphertext.copyOf()
            tampered[tampered.size - 1] = (tampered[tampered.size - 1] + 1).toByte() // flip a tag byte
            assertNull("$name should reject a tampered ciphertext", CryfsBlockCipher.decrypt(cipherId, key, tampered))
        }
    }

    @Test
    fun `gcm and xchacha20-poly1305 reject the wrong key`() {
        for (name in listOf("aes-256-gcm", "xchacha20-poly1305")) {
            val cipherId = CryfsBlockCipher.cipherIdFor(name)
            val key = ByteArray(32) { 1 }
            val wrongKey = ByteArray(32) { 2 }
            val ciphertext = CryfsBlockCipher.encrypt(cipherId, key, "some plaintext".toByteArray())
            assertNull("$name should reject the wrong key", CryfsBlockCipher.decrypt(cipherId, wrongKey, ciphertext))
        }
    }

    @Test
    fun `decrypt returns null rather than throwing on truncated ciphertext, for every cipher`() {
        for (name in listOf("aes-256-gcm", "aes-128-gcm", "aes-256-cfb", "aes-128-cfb", "xchacha20-poly1305")) {
            val cipherId = CryfsBlockCipher.cipherIdFor(name)
            val keySize = if (name.startsWith("aes-128")) 16 else 32
            val key = ByteArray(keySize)
            assertNull("$name should reject a too-short ciphertext", CryfsBlockCipher.decrypt(cipherId, key, ByteArray(4)))
        }
    }

    @Test
    fun `encrypt uses a fresh random IV or nonce every call`() {
        // Not a cryptographic randomness test -- just confirms the IV/nonce
        // prefix isn't accidentally hardcoded or reused, which would be a
        // catastrophic (nonce-reuse) bug for GCM and XChaCha20-Poly1305.
        val cipherId = CryfsBlockCipher.cipherIdFor("aes-256-gcm")
        val key = ByteArray(32)
        val a = CryfsBlockCipher.encrypt(cipherId, key, "same plaintext".toByteArray())
        val b = CryfsBlockCipher.encrypt(cipherId, key, "same plaintext".toByteArray())
        assertTrue(!a.copyOfRange(0, 16).contentEquals(b.copyOfRange(0, 16)))
    }
}
