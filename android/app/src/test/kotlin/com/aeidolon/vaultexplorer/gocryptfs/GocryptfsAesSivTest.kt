package com.aeidolon.vaultexplorer.gocryptfs

import com.aeidolon.vaultexplorer.cryptomator.SivMode
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * AES-SIV (RFC 5297) content encryption, checked against data that did NOT come
 * from this code: a file written by the real gocryptfs binary, and blocks built
 * with an independent RFC 5297 + RFC 5869 implementation (Python `cryptography`),
 * laid out as gocryptfs's `internal/siv_aead` + `contentenc` define them.
 *
 * Everything here runs on a bare JVM: with no native library SivMode takes its
 * JCE-only fallback, which is the path under test. (Native SIV is the same
 * sivEncryptNative/sivDecryptNative Cryptomator already uses.)
 */
class GocryptfsAesSivTest {

    private fun hex(s: String): ByteArray =
        ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun blockAad(chunkNumber: Long, fileId: ByteArray): ByteArray =
        ByteBuffer.allocate(8 + fileId.size).order(ByteOrder.BIG_ENDIAN).putLong(chunkNumber).put(fileId).array()

    private val fileId = hex("a0a1a2a3a4a5a6a7a8a9aaabacadaeaf")
    private val header = GocryptfsFileHeader(fileId)

    // HKDF-SHA256(masterkey = 00 01 02 .. 1f, salt = none,
    //             info = "AES-SIV file content encryption", L = 64) -- from Python's
    // cryptography.hazmat HKDF, i.e. NOT from our Hkdf.kt.
    private val masterkey = ByteArray(32) { it.toByte() }
    private val hkdfKey64 = hex(
        "90be6449231c24d9d308f1772b47953b6acf97f9e7876a16172e019977f3b7e0" +
            "2419aaf86d684593cf2b43008422ad6726b83aaf0897186fb8a8cbd04854bd3c"
    )

    private fun sivCryptor(key: ByteArray = hkdfKey64) = GocryptfsContentCryptor(key, GocryptfsCipher.AES_SIV)

    // ---------------------------------------------------------------- real gocryptfs data

    @Test
    fun `decrypts a file written by the real gocryptfs binary`() {
        // tests/example_filesystems/v1.1-aessiv/MA0FDdmnXpmPJtS_AcAbqQ== from the gocryptfs
        // repository: 2-byte version | 16-byte file ID | nonce | SIV tag | 10 payload bytes.
        // That example filesystem predates HKDF, so its content key is SHA-512(masterkey)
        // (upstream mounts it with -hkdf=false -aessiv -masterkey eaf371c3-f9a55336-...).
        // The cryptor takes the 64-byte key as given, so the legacy key derivation is fine here.
        val realFile = hex(
            "00023f89cdb79bc403237dd2746cd190a13031f364ec28e95b06525210fec440" +
                "757776acd1badf1716e8f93b4e0fbbd720fba790313d8c5cee5f0444"
        )
        val masterkeyOfExample = hex("eaf371c3f9a553368819f22b7bccd7c2a738cf617261c65814c28a039428992b")
        val key64 = MessageDigest.getInstance("SHA-512").digest(masterkeyOfExample)
        val cryptor = sivCryptor(key64)

        assertEquals(60, realFile.size)
        assertEquals(10L, cryptor.cleartextSize(realFile.size.toLong()))
        val fileHeader = cryptor.decodeHeader(realFile.copyOfRange(0, GocryptfsContentCryptor.HEADER_LEN))
        val cleartext = cryptor.decryptChunk(realFile.copyOfRange(GocryptfsContentCryptor.HEADER_LEN, realFile.size), 0, fileHeader)

        assertEquals("It works!\n", String(cleartext, Charsets.UTF_8))
    }

    @Test
    fun `real gocryptfs file is rejected when read as the wrong chunk or with the wrong key`() {
        val realFile = hex(
            "00023f89cdb79bc403237dd2746cd190a13031f364ec28e95b06525210fec440" +
                "757776acd1badf1716e8f93b4e0fbbd720fba790313d8c5cee5f0444"
        )
        val key64 = MessageDigest.getInstance("SHA-512")
            .digest(hex("eaf371c3f9a553368819f22b7bccd7c2a738cf617261c65814c28a039428992b"))
        val cryptor = sivCryptor(key64)
        val fileHeader = cryptor.decodeHeader(realFile.copyOfRange(0, GocryptfsContentCryptor.HEADER_LEN))
        val block = realFile.copyOfRange(GocryptfsContentCryptor.HEADER_LEN, realFile.size)

        assertThrows(GocryptfsContentAuthException::class.java) { cryptor.decryptChunk(block, 1, fileHeader) }
        assertThrows(GocryptfsContentAuthException::class.java) { sivCryptor(hkdfKey64).decryptChunk(block, 0, fileHeader) }
    }

    // ---------------------------------------------------------------- HKDF key derivation

    @Test
    fun `HKDF derives the 64-byte content key under the AES-SIV info string`() {
        assertEquals("AES-SIV file content encryption", GocryptfsCipher.AES_SIV.hkdfInfo)
        assertEquals(64, GocryptfsCipher.AES_SIV.contentKeyLen)
        // 64 bytes is two HKDF-Expand blocks -- the first time Hkdf.kt is asked for more than one.
        val derived = Hkdf.deriveSha256(masterkey, GocryptfsCipher.AES_SIV.hkdfInfo, GocryptfsCipher.AES_SIV.contentKeyLen)
        assertArrayEquals(hkdfKey64, derived)
    }

    @Test
    fun `per-cipher constants match what gocryptfs derives for the existing ciphers`() {
        assertEquals("AES-GCM file content encryption", GocryptfsCipher.AES_256_GCM.hkdfInfo)
        assertEquals(32, GocryptfsCipher.AES_256_GCM.contentKeyLen)
        assertEquals(16, GocryptfsCipher.AES_256_GCM.nonceLen)
        assertEquals("XChaCha20-Poly1305 file content encryption", GocryptfsCipher.XCHACHA20_POLY1305.hkdfInfo)
        assertEquals(32, GocryptfsCipher.XCHACHA20_POLY1305.contentKeyLen)
        assertEquals(24, GocryptfsCipher.XCHACHA20_POLY1305.nonceLen)
        assertEquals(16, GocryptfsCipher.AES_SIV.nonceLen)
    }

    // ---------------------------------------------------------------- read side: independent vectors

    @Test
    fun `decrypts independently built reference blocks`() {
        val cryptor = sivCryptor()
        // (chunk number, plaintext, block) -- chunk 0x0102030405060708 pins the 8-byte
        // big-endian chunk-number encoding in the AAD; the empty block is nonce | tag only.
        val vectors = listOf(
            Triple(
                5L,
                hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"),
                hex(
                    "11111111111111111111111111111111dbc81b2c0c9491ce92341c158168086c" +
                        "78c65e3a3495aa0bc1b072d959b0ccc8bfdb5a973f701c6b5918cd335daafc0e" +
                        "63a3e1b058677ef9d2b232a40b83507807ac8fc163aca9f3bfae370e1b946e44"
                ),
            ),
            Triple(
                0x0102030405060708L,
                hex("010e1b2835424f5c697683909daab7c4d1"),
                hex(
                    "22222222222222222222222222222222be4ba578ab5ce086938869410a7a67a5" +
                        "5b43340d3d9ce5ce8a4dbc1834f60cb2e2"
                ),
            ),
            Triple(0L, ByteArray(0), hex("333333333333333333333333333333334245e2721ac92e53b4133f433cc8a125")),
        )
        for ((chunkNumber, plaintext, block) in vectors) {
            assertArrayEquals("chunk $chunkNumber", plaintext, cryptor.decryptChunk(block, chunkNumber, header))
        }
    }

    // ---------------------------------------------------------------- write side: layout + AD order

    @Test
    fun `encryptChunk writes nonce | SIV tag | ciphertext sealed with AD blockNo-fileId then nonce`() {
        val cryptor = sivCryptor()
        val plaintext = ByteArray(300) { (it * 7).toByte() }
        val block = cryptor.encryptChunk(plaintext, 9, header)

        assertEquals(16 + 16 + plaintext.size, block.size)
        val nonce = block.copyOfRange(0, 16)
        // Open it by hand with RFC 5297's key split: LEFT 32 bytes = S2V key, RIGHT 32 = CTR key.
        val macKey = SecretKeySpec(hkdfKey64, 0, 32, "AES")
        val encKey = SecretKeySpec(hkdfKey64, 32, 32, "AES")
        val opened = SivMode().decrypt(encKey, macKey, block.copyOfRange(16, block.size), blockAad(9, fileId), nonce)
        assertArrayEquals(plaintext, opened)
    }

    @Test
    fun `a block sealed with the associated data in the other order is rejected`() {
        val cryptor = sivCryptor()
        val plaintext = ByteArray(64) { it.toByte() }
        val nonce = ByteArray(16) { 0x55 }
        val macKey = SecretKeySpec(hkdfKey64, 0, 32, "AES")
        val encKey = SecretKeySpec(hkdfKey64, 32, 32, "AES")
        // gocryptfs seals with [blockAad, nonce]; [nonce, blockAad] is a different SIV.
        val swapped = nonce + SivMode().encrypt(encKey, macKey, plaintext, nonce, blockAad(2, fileId))
        assertThrows(GocryptfsContentAuthException::class.java) { cryptor.decryptChunk(swapped, 2, header) }
    }

    @Test
    fun `a block sealed with the key halves swapped is rejected`() {
        val cryptor = sivCryptor()
        val plaintext = ByteArray(64) { it.toByte() }
        val nonce = ByteArray(16) { 0x66 }
        val left = SecretKeySpec(hkdfKey64, 0, 32, "AES")
        val right = SecretKeySpec(hkdfKey64, 32, 32, "AES")
        val swapped = nonce + SivMode().encrypt(left, right, plaintext, blockAad(2, fileId), nonce)
        assertThrows(GocryptfsContentAuthException::class.java) { cryptor.decryptChunk(swapped, 2, header) }
    }

    @Test
    fun `SIV blocks use a fresh random nonce each time`() {
        val cryptor = sivCryptor()
        val plaintext = ByteArray(64) { 1 }
        val a = cryptor.encryptChunk(plaintext, 0, header)
        val b = cryptor.encryptChunk(plaintext, 0, header)
        assertFalse(a.contentEquals(b))
        assertFalse(a.copyOfRange(0, 16).contentEquals(b.copyOfRange(0, 16)))
    }

    @Test
    fun `the nonce is authenticated -- flipping a nonce bit fails the read`() {
        val cryptor = sivCryptor()
        val block = cryptor.encryptChunk(ByteArray(64) { 1 }, 0, header)
        block[0] = (block[0].toInt() xor 1).toByte()
        assertThrows(GocryptfsContentAuthException::class.java) { cryptor.decryptChunk(block, 0, header) }
    }

    @Test
    fun `a block does not open under a different file ID`() {
        val cryptor = sivCryptor()
        val block = cryptor.encryptChunk(ByteArray(64) { 1 }, 0, header)
        val otherFile = GocryptfsFileHeader(ByteArray(16) { 9 })
        assertThrows(GocryptfsContentAuthException::class.java) { cryptor.decryptChunk(block, 0, otherFile) }
    }

    // ---------------------------------------------------------------- sizes

    @Test
    fun `AES-SIV blocks have the same 4128-byte layout size as AES-GCM`() {
        val cryptor = sivCryptor()
        assertEquals(16 + 4096 + 16, cryptor.ciphertextChunkSize)
        val full = cryptor.encryptChunk(ByteArray(GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE) { 3 }, 0, header)
        assertEquals(4128, full.size)
        assertEquals(4096L + 100L, cryptor.cleartextSize(GocryptfsContentCryptor.HEADER_LEN + 4128L + (16 + 16 + 100)))
    }

    // ---------------------------------------------------------------- key length guard

    @Test
    fun `a 32-byte key is rejected for AES-SIV instead of failing later inside SIV`() {
        assertThrows(IllegalArgumentException::class.java) {
            GocryptfsContentCryptor(ByteArray(32), GocryptfsCipher.AES_SIV)
        }
    }

    @Test
    fun `a 64-byte key is rejected for AES-GCM`() {
        assertThrows(IllegalArgumentException::class.java) {
            GocryptfsContentCryptor(ByteArray(64), GocryptfsCipher.AES_256_GCM)
        }
    }

    // ---------------------------------------------------------------- bulk stream path

    @Test
    fun `stream round trip over several chunks plus a partial tail`() {
        val cryptor = sivCryptor()
        val plaintext = ByteArray(3 * 4096 + 1234) { (it * 31).toByte() }
        val encrypted = cryptor.encryptStream(plaintext, 0, header)
        assertEquals(3 * 4128 + (16 + 16 + 1234), encrypted.size)
        assertArrayEquals(plaintext, cryptor.decryptStream(encrypted, 0, header))
    }

    @Test
    fun `stream encryption is the concatenation of per-chunk SIV blocks`() {
        // Guards the silent-GCM hazard: the native stream bridge picks AES-GCM for ANY 16-byte
        // nonce, so a SIV cryptor that reached it would write GCM blocks into an SIV vault.
        // Each block of the stream output must open as a SIV block under decryptChunk.
        val cryptor = sivCryptor()
        val plaintext = ByteArray(2 * 4096 + 77) { (it % 251).toByte() }
        val encrypted = cryptor.encryptStream(plaintext, 4, header)
        var offset = 0
        var chunk = 4L
        val rebuilt = java.io.ByteArrayOutputStream()
        while (offset < encrypted.size) {
            val len = minOf(cryptor.ciphertextChunkSize, encrypted.size - offset)
            rebuilt.write(cryptor.decryptChunk(encrypted.copyOfRange(offset, offset + len), chunk, header))
            offset += len
            chunk++
        }
        assertArrayEquals(plaintext, rebuilt.toByteArray())
    }

    @Test
    fun `stream blocks written in a batch are readable chunk by chunk and vice versa`() {
        val cryptor = sivCryptor()
        val plaintext = ByteArray(2 * 4096) { (it % 199).toByte() }
        val perChunk = cryptor.encryptChunk(plaintext.copyOfRange(0, 4096), 0, header) +
            cryptor.encryptChunk(plaintext.copyOfRange(4096, 8192), 1, header)
        assertArrayEquals(plaintext, cryptor.decryptStream(perChunk, 0, header))
    }

    @Test
    fun `decryptStream honours the start chunk number`() {
        val cryptor = sivCryptor()
        val plaintext = ByteArray(4096 + 10) { 7 }
        val encrypted = cryptor.encryptStream(plaintext, 12, header)
        assertArrayEquals(plaintext, cryptor.decryptStream(encrypted, 12, header))
        assertThrows(GocryptfsContentAuthException::class.java) { cryptor.decryptStream(encrypted, 11, header) }
    }

    @Test
    fun `decryptStream names the chunk that failed authentication`() {
        val cryptor = sivCryptor()
        val encrypted = cryptor.encryptStream(ByteArray(3 * 4096) { 1 }, 0, header)
        encrypted[cryptor.ciphertextChunkSize + 100] = (encrypted[cryptor.ciphertextChunkSize + 100].toInt() xor 0x80).toByte()
        val e = assertThrows(GocryptfsContentAuthException::class.java) { cryptor.decryptStream(encrypted, 0, header) }
        assertTrue(e.message!!, e.message!!.contains("Chunk 1 "))
    }

    @Test
    fun `decryptStream rejects a trailing fragment too short to hold nonce and tag`() {
        val cryptor = sivCryptor()
        val encrypted = cryptor.encryptStream(ByteArray(4096) { 1 }, 0, header)
        val torn = encrypted + ByteArray(20)
        assertThrows(GocryptfsContentAuthException::class.java) { cryptor.decryptStream(torn, 0, header) }
    }

    @Test
    fun `decryptStream expands a sparse-file hole chunk to zeros`() {
        val cryptor = sivCryptor()
        val data = ByteArray(4096) { 5 }
        val stream = cryptor.encryptChunk(data, 0, header) + ByteArray(cryptor.ciphertextChunkSize)
        val out = cryptor.decryptStream(stream, 0, header)
        assertArrayEquals(data + ByteArray(4096), out)
    }

    @Test
    fun `empty stream buffers produce empty output`() {
        val cryptor = sivCryptor()
        assertEquals(0, cryptor.encryptStream(ByteArray(0), 0, header).size)
        assertEquals(0, cryptor.decryptStream(ByteArray(0), 0, header).size)
    }
}
