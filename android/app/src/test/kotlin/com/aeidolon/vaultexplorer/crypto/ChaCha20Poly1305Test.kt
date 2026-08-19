package com.aeidolon.vaultexplorer.crypto

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every test here checks against an official published test vector (RFC
 * 8439 "ChaCha20 and Poly1305 for IETF Protocols", or
 * draft-irtf-cfrg-xchacha for HChaCha20), transcribed directly from the
 * RFC/draft text -- not derived from this app's own implementation. A
 * couple of the very long vectors (RFC 8439 Appendix A.2 Test Vector #2
 * and Appendix A.5) are deliberately skipped: several hundred bytes of
 * hand-transcribed hex is exactly the kind of thing that could introduce
 * a silent copy error, and the vectors kept here already exercise every
 * code path (short and multi-block messages, AAD, tag verification
 * failure, the Poly1305 modular-reduction edge cases).
 */
class ChaCha20Poly1305Test {

    private fun hex(s: String): ByteArray {
        val clean = s.replace(Regex("[^0-9a-fA-F]"), "")
        require(clean.length % 2 == 0)
        return ByteArray(clean.length / 2) { i -> clean.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }

    // ---- RFC 8439 §2.3.2: ChaCha20 Block Function ----

    @Test
    fun `chacha20Block matches RFC 8439 section 2_3_2`() {
        val key = hex("00:01:02:03:04:05:06:07:08:09:0a:0b:0c:0d:0e:0f:10:11:12:13:14:15:16:17:18:19:1a:1b:1c:1d:1e:1f")
        val nonce = hex("00:00:00:09:00:00:00:4a:00:00:00:00")
        val expected = hex(
            "10 f1 e7 e4 d1 3b 59 15 50 0f dd 1f a3 20 71 c4" +
                "c7 d1 f4 c7 33 c0 68 03 04 22 aa 9a c3 d4 6c 4e" +
                "d2 82 64 46 07 9f aa 09 14 c2 d7 05 d9 8b 02 a2" +
                "b5 12 9c d1 de 16 4e b9 cb d0 83 e8 a2 50 3c 4e"
        )
        assertArrayEquals(expected, ChaCha20Poly1305.chacha20Block(key, 1, nonce))
    }

    @Test
    fun `chacha20Block matches RFC 8439 Appendix A_1 Test Vector 1 (all zero)`() {
        val key = ByteArray(32)
        val nonce = ByteArray(12)
        val expected = hex(
            "76 b8 e0 ad a0 f1 3d 90 40 5d 6a e5 53 86 bd 28" +
                "bd d2 19 b8 a0 8d ed 1a a8 36 ef cc 8b 77 0d c7" +
                "da 41 59 7c 51 57 48 8d 77 24 e0 3f b8 d8 4a 37" +
                "6a 43 b8 f4 15 18 a1 1c c3 87 b6 69 b2 ee 65 86"
        )
        assertArrayEquals(expected, ChaCha20Poly1305.chacha20Block(key, 0, nonce))
    }

    // ---- RFC 8439 §2.4.2: ChaCha20 Encryption ("Sunscreen") ----

    @Test
    fun `chacha20Xor matches RFC 8439 section 2_4_2 sunscreen vector`() {
        val key = hex("00:01:02:03:04:05:06:07:08:09:0a:0b:0c:0d:0e:0f:10:11:12:13:14:15:16:17:18:19:1a:1b:1c:1d:1e:1f")
        val nonce = hex("00:00:00:00:00:00:00:4a:00:00:00:00")
        val plaintext = ("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for " +
            "the future, sunscreen would be it.").toByteArray(Charsets.US_ASCII)
        val expectedCiphertext = hex(
            "6e 2e 35 9a 25 68 f9 80 41 ba 07 28 dd 0d 69 81" +
                "e9 7e 7a ec 1d 43 60 c2 0a 27 af cc fd 9f ae 0b" +
                "f9 1b 65 c5 52 47 33 ab 8f 59 3d ab cd 62 b3 57" +
                "16 39 d6 24 e6 51 52 ab 8f 53 0c 35 9f 08 61 d8" +
                "07 ca 0d bf 50 0d 6a 61 56 a3 8e 08 8a 22 b6 5e" +
                "52 bc 51 4d 16 cc f8 06 81 8c e9 1a b7 79 37 36" +
                "5a f9 0b bf 74 a3 5b e6 b4 0b 8e ed f2 78 5e 42" +
                "87 4d"
        )
        val actual = ChaCha20Poly1305.chacha20Xor(key, 1, nonce, plaintext)
        assertArrayEquals(expectedCiphertext, actual)
        // And decryption (same operation, XOR is its own inverse) recovers the plaintext.
        assertArrayEquals(plaintext, ChaCha20Poly1305.chacha20Xor(key, 1, nonce, actual))
    }

    // ---- RFC 8439 §2.5.2: Poly1305 Example ----

    @Test
    fun `poly1305Mac matches RFC 8439 section 2_5_2 example`() {
        val key = hex(
            "85:d6:be:78:57:55:6d:33:7f:44:52:fe:42:d5:06:a8:" +
                "01:03:80:8a:fb:0d:b2:fd:4a:bf:f6:af:41:49:f5:1b"
        )
        val message = "Cryptographic Forum Research Group".toByteArray(Charsets.US_ASCII)
        val expectedTag = hex("a8:06:1d:c1:30:51:36:c6:c2:2b:8b:af:0c:01:27:a9")
        assertArrayEquals(expectedTag, ChaCha20Poly1305.poly1305Mac(key, message))
    }

    // ---- RFC 8439 Appendix A.3: Poly1305 edge cases ----

    @Test
    fun `poly1305Mac matches RFC 8439 Appendix A_3 Test Vector 1 (all zero)`() {
        val key = ByteArray(32)
        val message = ByteArray(64)
        assertArrayEquals(ByteArray(16), ChaCha20Poly1305.poly1305Mac(key, message))
    }

    @Test
    fun `poly1305Mac matches RFC 8439 Appendix A_3 Test Vector 5 (131-bit final result)`() {
        val r = hex("02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val s = hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val data = hex("FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF")
        val expectedTag = hex("03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        assertArrayEquals(expectedTag, ChaCha20Poly1305.poly1305Mac(r + s, data))
    }

    @Test
    fun `poly1305Mac matches RFC 8439 Appendix A_3 Test Vector 6 (s addition overflow)`() {
        val r = hex("02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val s = hex("FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF")
        val data = hex("02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val expectedTag = hex("03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        assertArrayEquals(expectedTag, ChaCha20Poly1305.poly1305Mac(r + s, data))
    }

    @Test
    fun `poly1305Mac matches RFC 8439 Appendix A_3 Test Vector 7 (carry from lower limb)`() {
        val r = hex("01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val s = hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val data = hex(
            "FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF" +
                "F0 FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF" +
                "11 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
        )
        val expectedTag = hex("05 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        assertArrayEquals(expectedTag, ChaCha20Poly1305.poly1305Mac(r + s, data))
    }

    @Test
    fun `poly1305Mac matches RFC 8439 Appendix A_3 Test Vector 8 (result exactly 2^130-5)`() {
        val r = hex("01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val s = hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val data = hex(
            "FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF" +
                "FB FE FE FE FE FE FE FE FE FE FE FE FE FE FE FE" +
                "01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01"
        )
        assertArrayEquals(ByteArray(16), ChaCha20Poly1305.poly1305Mac(r + s, data))
    }

    @Test
    fun `poly1305Mac matches RFC 8439 Appendix A_3 Test Vector 9 (result exactly 2^130-6)`() {
        val r = hex("02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val s = hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val data = hex("FD FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF")
        val expectedTag = hex("FA FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF")
        assertArrayEquals(expectedTag, ChaCha20Poly1305.poly1305Mac(r + s, data))
    }

    @Test
    fun `poly1305Mac matches RFC 8439 Appendix A_3 Test Vector 10 (131-bit intermediate)`() {
        val r = hex("01 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00")
        val s = hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val data = hex(
            "E3 35 94 D7 50 5E 43 B9 00 00 00 00 00 00 00 00" +
                "33 94 D7 50 5E 43 79 CD 01 00 00 00 00 00 00 00" +
                "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" +
                "01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
        )
        val expectedTag = hex("14 00 00 00 00 00 00 00 55 00 00 00 00 00 00 00")
        assertArrayEquals(expectedTag, ChaCha20Poly1305.poly1305Mac(r + s, data))
    }

    @Test
    fun `poly1305Mac matches RFC 8439 Appendix A_3 Test Vector 11 (131-bit final)`() {
        val r = hex("01 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00")
        val s = hex("00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        val data = hex(
            "E3 35 94 D7 50 5E 43 B9 00 00 00 00 00 00 00 00" +
                "33 94 D7 50 5E 43 79 CD 01 00 00 00 00 00 00 00" +
                "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
        )
        val expectedTag = hex("13 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        assertArrayEquals(expectedTag, ChaCha20Poly1305.poly1305Mac(r + s, data))
    }

    // ---- RFC 8439 §2.6.2: Poly1305 Key Generation ----

    @Test
    fun `poly1305KeyGen matches RFC 8439 section 2_6_2`() {
        val key = hex(
            "80 81 82 83 84 85 86 87 88 89 8a 8b 8c 8d 8e 8f" +
                "90 91 92 93 94 95 96 97 98 99 9a 9b 9c 9d 9e 9f"
        )
        val nonce = hex("00 00 00 00 00 01 02 03 04 05 06 07")
        val expected = hex(
            "8a d5 a0 8b 90 5f 81 cc 81 50 40 27 4a b2 94 71" +
                "a8 33 b6 37 e3 fd 0d a5 08 db b8 e2 fd d1 a6 46"
        )
        assertArrayEquals(expected, ChaCha20Poly1305.poly1305KeyGen(key, nonce))
    }

    // ---- RFC 8439 §2.8.2: full AEAD_CHACHA20_POLY1305 ----

    @Test
    fun `chacha20Poly1305Seal matches RFC 8439 section 2_8_2`() {
        val plaintext = ("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for " +
            "the future, sunscreen would be it.").toByteArray(Charsets.US_ASCII)
        val aad = hex("50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7")
        val key = hex(
            "80 81 82 83 84 85 86 87 88 89 8a 8b 8c 8d 8e 8f" +
                "90 91 92 93 94 95 96 97 98 99 9a 9b 9c 9d 9e 9f"
        )
        // nonce = 32-bit fixed-common part (07 00 00 00) || IV (40 41 42 43 44 45 46 47)
        val nonce = hex("07 00 00 00 40 41 42 43 44 45 46 47")
        val expectedCiphertext = hex(
            "d3 1a 8d 34 64 8e 60 db 7b 86 af bc 53 ef 7e c2" +
                "a4 ad ed 51 29 6e 08 fe a9 e2 b5 a7 36 ee 62 d6" +
                "3d be a4 5e 8c a9 67 12 82 fa fb 69 da 92 72 8b" +
                "1a 71 de 0a 9e 06 0b 29 05 d6 a5 b6 7e cd 3b 36" +
                "92 dd bd 7f 2d 77 8b 8c 98 03 ae e3 28 09 1b 58" +
                "fa b3 24 e4 fa d6 75 94 55 85 80 8b 48 31 d7 bc" +
                "3f f4 de f0 8e 4b 7a 9d e5 76 d2 65 86 ce c6 4b" +
                "61 16"
        )
        val expectedTag = hex("1a:e1:0b:59:4f:09:e2:6a:7e:90:2e:cb:d0:60:06:91")

        val sealed = ChaCha20Poly1305.chacha20Poly1305Seal(key, nonce, aad, plaintext)
        assertArrayEquals(expectedCiphertext + expectedTag, sealed)

        val opened = ChaCha20Poly1305.chacha20Poly1305Open(key, nonce, aad, sealed)
        assertArrayEquals(plaintext, opened)
    }

    @Test
    fun `chacha20Poly1305Open rejects a tampered ciphertext`() {
        val plaintext = "some cryfs block plaintext".toByteArray(Charsets.US_ASCII)
        val key = ByteArray(32) { it.toByte() }
        val nonce = ByteArray(12) { (it + 1).toByte() }
        val sealed = ChaCha20Poly1305.chacha20Poly1305Seal(key, nonce, ByteArray(0), plaintext)

        val tampered = sealed.copyOf()
        tampered[0] = (tampered[0] + 1).toByte()
        assertNull(ChaCha20Poly1305.chacha20Poly1305Open(key, nonce, ByteArray(0), tampered))

        val tamperedTag = sealed.copyOf()
        tamperedTag[tamperedTag.size - 1] = (tamperedTag[tamperedTag.size - 1] + 1).toByte()
        assertNull(ChaCha20Poly1305.chacha20Poly1305Open(key, nonce, ByteArray(0), tamperedTag))

        // Sanity: the untampered ciphertext still opens correctly.
        assertArrayEquals(plaintext, ChaCha20Poly1305.chacha20Poly1305Open(key, nonce, ByteArray(0), sealed))
    }

    // ---- draft-irtf-cfrg-xchacha-01 §2.2.1: HChaCha20 ----

    @Test
    fun `hChaCha20 matches draft-irtf-cfrg-xchacha test vector`() {
        val key = hex("00:01:02:03:04:05:06:07:08:09:0a:0b:0c:0d:0e:0f:10:11:12:13:14:15:16:17:18:19:1a:1b:1c:1d:1e:1f")
        val nonce16 = hex("00:00:00:09:00:00:00:4a:00:00:00:00:31:41:59:27")
        val expectedSubkey = hex(
            "82413b42 27b27bfe d30e4250 8a877d73" +
                "a0f9e4d5 8a74a853 c12ec413 26d3ecdc"
        )
        assertArrayEquals(expectedSubkey, ChaCha20Poly1305.hChaCha20(key, nonce16))
    }

    // ---- XChaCha20-Poly1305 composition: no official short test vector was
    // available to transcribe reliably, so this checks the composed
    // construction round-trips and authenticates correctly. Every
    // sub-algorithm it's built from (HChaCha20, ChaCha20-Poly1305) is
    // independently verified against official vectors above; the
    // composition itself (splitting the 24-byte nonce, deriving the
    // subkey) is a direct port of this app's own C++ reference
    // (xchacha20poly1305.cpp), reviewed line-by-line against it. ----

    @Test
    fun `xchacha20Poly1305 round-trips and authenticates with a 24-byte nonce`() {
        val key = ByteArray(32) { (it * 7 + 1).toByte() }
        val nonce24 = ByteArray(24) { (it * 3 + 2).toByte() }
        val plaintext = "a cryfs block's worth of plaintext, long enough to span more than one 64-byte chacha block".toByteArray(Charsets.US_ASCII)

        val sealed = ChaCha20Poly1305.xchacha20Poly1305Seal(key, nonce24, ByteArray(0), plaintext)
        assertTrue(sealed.size == plaintext.size + 16)

        val opened = ChaCha20Poly1305.xchacha20Poly1305Open(key, nonce24, ByteArray(0), sealed)
        assertArrayEquals(plaintext, opened)

        // A different nonce must not decrypt it.
        val wrongNonce = nonce24.copyOf().also { it[0] = (it[0] + 1).toByte() }
        assertNull(ChaCha20Poly1305.xchacha20Poly1305Open(key, wrongNonce, ByteArray(0), sealed))

        // Tampering with the ciphertext must be caught.
        val tampered = sealed.copyOf().also { it[5] = (it[5] + 1).toByte() }
        assertNull(ChaCha20Poly1305.xchacha20Poly1305Open(key, nonce24, ByteArray(0), tampered))
    }

    @Test
    fun `xchacha20Poly1305 handles empty plaintext`() {
        val key = ByteArray(32) { it.toByte() }
        val nonce24 = ByteArray(24) { it.toByte() }
        val sealed = ChaCha20Poly1305.xchacha20Poly1305Seal(key, nonce24, ByteArray(0), ByteArray(0))
        assertTrue(sealed.size == 16) // just the tag
        val opened = ChaCha20Poly1305.xchacha20Poly1305Open(key, nonce24, ByteArray(0), sealed)
        assertNotNull(opened)
        assertTrue(opened!!.isEmpty())
    }
}
