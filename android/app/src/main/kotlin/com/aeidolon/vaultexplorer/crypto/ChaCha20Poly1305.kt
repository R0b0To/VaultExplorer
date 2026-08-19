package com.aeidolon.vaultexplorer.crypto

import java.math.BigInteger
import java.security.MessageDigest

/**
 * Pure-Kotlin ChaCha20, Poly1305, HChaCha20, and XChaCha20-Poly1305 AEAD,
 * per RFC 8439 ("ChaCha20 and Poly1305 for IETF Protocols") and
 * draft-irtf-cfrg-xchacha ("XChaCha: eXtended-nonce ChaCha and
 * AEAD_XChaCha20_Poly1305").
 *
 * This exists because CryFS 1.0+ defaults to "xchacha20-poly1305" for new
 * vaults (see CryfsCipherId in crypto/cryfs_block_cipher.h), and unlike
 * AES-GCM/AES-CFB, XChaCha20-Poly1305 has no standard javax.crypto
 * provider on the JVM/Android -- there's nothing to fall back to except a
 * real implementation. Ported line-for-line from this app's own C++
 * reference (crypto/xchacha20poly1305.cpp's hchacha20(), which is not
 * mbedtls -- it's hand-written specifically for the same reason this file
 * is) and from mbedtls_chachapoly's standard RFC 8439 construction for the
 * inner AEAD, which xchacha20poly1305.cpp delegates to.
 *
 * Poly1305's 130-bit modular arithmetic uses java.math.BigInteger rather
 * than hand-rolled limb arithmetic. This is NOT constant-time (RFC 8439
 * §3 flags BigInteger-style arithmetic specifically as a timing-side-
 * channel risk for online/network protocols) -- deliberately accepted
 * here because this path only runs when the native library isn't loaded,
 * i.e. plain-JVM unit tests, never on a real device with real user data.
 * The native implementation (mbedtls_chachapoly, used for every real
 * on-device encrypt/decrypt) is constant-time. Do not repurpose this file
 * as a production crypto path without addressing that.
 *
 * Verified against every relevant RFC 8439 / draft-irtf-cfrg-xchacha test
 * vector in ChaCha20Poly1305Test.kt: the ChaCha20 block function, ChaCha20
 * encryption, Poly1305 MAC (including the tricky modular-reduction edge
 * cases in RFC 8439 Appendix A.3 #5-11), Poly1305 key generation, the full
 * ChaCha20-Poly1305 AEAD construction (encrypt and decrypt), and HChaCha20.
 */
object ChaCha20Poly1305 {

    private val P1305: BigInteger = BigInteger.ONE.shiftLeft(130).subtract(BigInteger.valueOf(5))
    private val MASK128: BigInteger = BigInteger.ONE.shiftLeft(128)

    private val SIGMA = intArrayOf(0x61707865, 0x3320646e, 0x79622d32, 0x6b206574)

    // ---- little-endian 32-bit word helpers, reusing LittleEndian (which
    // returns Long, since it's meant for on-disk sizes that must never
    // silently truncate) rather than adding a second/competing LE helper.
    // Here we genuinely want Int: ChaCha20 state words are 32-bit values
    // manipulated with wraparound (mod 2^32) arithmetic, which is exactly
    // Kotlin's native Int overflow behavior. ----

    private fun readU32LE(b: ByteArray, off: Int): Int = LittleEndian.readU32(b, off).toInt()

    private fun writeU32LE(b: ByteArray, off: Int, v: Int) {
        LittleEndian.writeU32(b, off, v.toLong() and 0xFFFFFFFFL)
    }

    private fun rotl(x: Int, n: Int): Int = (x shl n) or (x ushr (32 - n))

    // RFC 8439 §2.1: the ChaCha quarter round.
    private fun quarterRound(s: IntArray, a: Int, b: Int, c: Int, d: Int) {
        s[a] += s[b]; s[d] = rotl(s[d] xor s[a], 16)
        s[c] += s[d]; s[b] = rotl(s[b] xor s[c], 12)
        s[a] += s[b]; s[d] = rotl(s[d] xor s[a], 8)
        s[c] += s[d]; s[b] = rotl(s[b] xor s[c], 7)
    }

    private fun tenDoubleRounds(s: IntArray) {
        repeat(10) {
            quarterRound(s, 0, 4, 8, 12)
            quarterRound(s, 1, 5, 9, 13)
            quarterRound(s, 2, 6, 10, 14)
            quarterRound(s, 3, 7, 11, 15)
            quarterRound(s, 0, 5, 10, 15)
            quarterRound(s, 1, 6, 11, 12)
            quarterRound(s, 2, 7, 8, 13)
            quarterRound(s, 3, 4, 9, 14)
        }
    }

    private fun initialState(key: ByteArray, nonce12: ByteArray, counter: Int): IntArray {
        require(key.size == 32) { "ChaCha20 key must be 32 bytes" }
        require(nonce12.size == 12) { "ChaCha20 nonce must be 12 bytes" }
        val state = IntArray(16)
        state[0] = SIGMA[0]; state[1] = SIGMA[1]; state[2] = SIGMA[2]; state[3] = SIGMA[3]
        for (i in 0 until 8) state[4 + i] = readU32LE(key, i * 4)
        state[12] = counter
        for (i in 0 until 3) state[13 + i] = readU32LE(nonce12, i * 4)
        return state
    }

    /** RFC 8439 §2.3: (key, counter, 12-byte nonce) -> 64 keystream bytes. */
    fun chacha20Block(key: ByteArray, counter: Int, nonce12: ByteArray): ByteArray {
        val initial = initialState(key, nonce12, counter)
        val working = initial.copyOf()
        tenDoubleRounds(working)
        for (i in 0 until 16) working[i] += initial[i]

        val out = ByteArray(64)
        for (i in 0 until 16) writeU32LE(out, i * 4, working[i])
        return out
    }

    /** RFC 8439 §2.4: XORs successive keystream blocks (starting at [counter]) with [data]. */
    fun chacha20Xor(key: ByteArray, counter: Int, nonce12: ByteArray, data: ByteArray): ByteArray {
        val out = ByteArray(data.size)
        var offset = 0
        var block = counter
        while (offset < data.size) {
            val keystream = chacha20Block(key, block, nonce12)
            val n = minOf(64, data.size - offset)
            for (i in 0 until n) out[offset + i] = (data[offset + i].toInt() xor keystream[i].toInt()).toByte()
            offset += n
            block += 1
        }
        return out
    }

    /**
     * draft-irtf-cfrg-xchacha §2.2: HChaCha20 subkey derivation. Same core
     * as [chacha20Block], but takes a 16-byte nonce in place of a 32-bit
     * counter + 12-byte nonce, skips the final "add the original input
     * words" step, and only outputs words 0-3 and 12-15.
     */
    fun hChaCha20(key: ByteArray, nonce16: ByteArray): ByteArray {
        require(key.size == 32) { "HChaCha20 key must be 32 bytes" }
        require(nonce16.size == 16) { "HChaCha20 nonce must be 16 bytes" }
        val state = IntArray(16)
        state[0] = SIGMA[0]; state[1] = SIGMA[1]; state[2] = SIGMA[2]; state[3] = SIGMA[3]
        for (i in 0 until 8) state[4 + i] = readU32LE(key, i * 4)
        for (i in 0 until 4) state[12 + i] = readU32LE(nonce16, i * 4)

        tenDoubleRounds(state)

        val out = ByteArray(32)
        for (i in 0 until 4) writeU32LE(out, i * 4, state[i])
        for (i in 0 until 4) writeU32LE(out, 16 + i * 4, state[12 + i])
        return out
    }

    // ---- Poly1305 (RFC 8439 §2.5) ----

    /** Interprets [b] as an unsigned little-endian integer. */
    private fun leBytesToBigInt(b: ByteArray): BigInteger {
        val bigEndianUnsigned = ByteArray(b.size + 1) // leading 0 byte forces a positive BigInteger
        for (i in b.indices) bigEndianUnsigned[i + 1] = b[b.size - 1 - i]
        return BigInteger(bigEndianUnsigned)
    }

    /** RFC 8439 §2.5.1: a 32-byte one-time key + arbitrary-length message -> 16-byte tag. */
    fun poly1305Mac(key: ByteArray, message: ByteArray): ByteArray {
        require(key.size == 32) { "Poly1305 key must be 32 bytes" }

        // clamp(r): r &= 0x0ffffffc0ffffffc0ffffffc0fffffff (r treated as
        // a 16-byte little-endian number -- see poly1305aes_test_clamp in
        // RFC 8439 §2.5 for the byte-level equivalent this matches).
        val r = key.copyOfRange(0, 16)
        r[3] = (r[3].toInt() and 0x0F).toByte()
        r[7] = (r[7].toInt() and 0x0F).toByte()
        r[11] = (r[11].toInt() and 0x0F).toByte()
        r[15] = (r[15].toInt() and 0x0F).toByte()
        r[4] = (r[4].toInt() and 0xFC).toByte()
        r[8] = (r[8].toInt() and 0xFC).toByte()
        r[12] = (r[12].toInt() and 0xFC).toByte()

        val rNum = leBytesToBigInt(r)
        val sNum = leBytesToBigInt(key.copyOfRange(16, 32))

        var acc = BigInteger.ZERO
        var offset = 0
        while (offset < message.size) {
            val blockLen = minOf(16, message.size - offset)
            // "Add one bit beyond the number of octets" == append a 0x01 byte.
            val block = ByteArray(blockLen + 1)
            System.arraycopy(message, offset, block, 0, blockLen)
            block[blockLen] = 0x01
            val n = leBytesToBigInt(block)
            acc = (acc + n) * rNum % P1305
            offset += blockLen
        }
        acc += sNum // NOT reduced mod P1305 -- only the low 128 bits are kept, next.

        val low128 = acc.mod(MASK128)
        val bigEndian = low128.toByteArray() // variable length, possibly with a leading 0 sign byte
        val tag = ByteArray(16)
        for (i in 0 until 16) {
            val srcIdx = bigEndian.size - 1 - i
            tag[i] = if (srcIdx >= 0) bigEndian[srcIdx] else 0
        }
        return tag
    }

    /** RFC 8439 §2.6.1: derives the one-time Poly1305 key from (key, nonce) via ChaCha20 block 0. */
    fun poly1305KeyGen(key: ByteArray, nonce12: ByteArray): ByteArray =
        chacha20Block(key, 0, nonce12).copyOfRange(0, 32)

    private fun pad16Length(len: Int): Int = if (len % 16 == 0) 0 else 16 - (len % 16)

    private fun aeadMacData(aad: ByteArray, ciphertext: ByteArray): ByteArray {
        val out = ByteArray(aad.size + pad16Length(aad.size) + ciphertext.size + pad16Length(ciphertext.size) + 8 + 8)
        var off = 0
        System.arraycopy(aad, 0, out, off, aad.size)
        off += aad.size + pad16Length(aad.size)
        System.arraycopy(ciphertext, 0, out, off, ciphertext.size)
        off += ciphertext.size + pad16Length(ciphertext.size)
        LittleEndian.writeU64(out, off, aad.size.toLong())
        off += 8
        LittleEndian.writeU64(out, off, ciphertext.size.toLong())
        return out
    }

    /** RFC 8439 §2.8: AEAD_CHACHA20_POLY1305 with a 12-byte nonce. Returns ciphertext || 16-byte tag. */
    fun chacha20Poly1305Seal(key: ByteArray, nonce12: ByteArray, aad: ByteArray, plaintext: ByteArray): ByteArray {
        val otk = poly1305KeyGen(key, nonce12)
        val ciphertext = chacha20Xor(key, 1, nonce12, plaintext)
        val tag = poly1305Mac(otk, aeadMacData(aad, ciphertext))
        return ciphertext + tag
    }

    /** Inverse of [chacha20Poly1305Seal]. Returns null (rather than throwing) if the tag doesn't verify. */
    fun chacha20Poly1305Open(key: ByteArray, nonce12: ByteArray, aad: ByteArray, ciphertextAndTag: ByteArray): ByteArray? {
        if (ciphertextAndTag.size < 16) return null
        val ciphertext = ciphertextAndTag.copyOfRange(0, ciphertextAndTag.size - 16)
        val receivedTag = ciphertextAndTag.copyOfRange(ciphertextAndTag.size - 16, ciphertextAndTag.size)

        val otk = poly1305KeyGen(key, nonce12)
        val expectedTag = poly1305Mac(otk, aeadMacData(aad, ciphertext))
        if (!MessageDigest.isEqual(expectedTag, receivedTag)) return null // constant-time compare
        return chacha20Xor(key, 1, nonce12, ciphertext)
    }

    // ---- XChaCha20-Poly1305 (draft-irtf-cfrg-xchacha) ----

    private fun xchachaSubkeyAndInnerNonce(key: ByteArray, nonce24: ByteArray): Pair<ByteArray, ByteArray> {
        require(key.size == 32) { "XChaCha20 key must be 32 bytes" }
        require(nonce24.size == 24) { "XChaCha20 nonce must be 24 bytes" }
        val subkey = hChaCha20(key, nonce24.copyOfRange(0, 16))
        // Inner 12-byte nonce: 4 zero bytes followed by the last 8 bytes of the 24-byte nonce.
        val nonce12 = ByteArray(12)
        System.arraycopy(nonce24, 16, nonce12, 4, 8)
        return subkey to nonce12
    }

    /** Seals with a 24-byte extended nonce. Returns ciphertext || 16-byte tag. */
    fun xchacha20Poly1305Seal(key: ByteArray, nonce24: ByteArray, aad: ByteArray, plaintext: ByteArray): ByteArray {
        val (subkey, nonce12) = xchachaSubkeyAndInnerNonce(key, nonce24)
        return chacha20Poly1305Seal(subkey, nonce12, aad, plaintext)
    }

    /** Inverse of [xchacha20Poly1305Seal]. Returns null if the tag doesn't verify. */
    fun xchacha20Poly1305Open(key: ByteArray, nonce24: ByteArray, aad: ByteArray, ciphertextAndTag: ByteArray): ByteArray? {
        val (subkey, nonce12) = xchachaSubkeyAndInnerNonce(key, nonce24)
        return chacha20Poly1305Open(subkey, nonce12, aad, ciphertextAndTag)
    }
}
