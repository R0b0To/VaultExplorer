package com.aeidolon.vaultexplorer.cryptomator

import java.security.GeneralSecurityException
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-SIV (RFC 5297) — deterministic authenticated encryption used by
 * Cryptomator to encrypt file/directory names.
 *
 * Ported from the reference algorithm in RFC 5297 §2.6/§2.7. Cryptomator's
 * own SivMode (org.cryptomator:siv-mode) is the reference implementation;
 * this is an independent port using only javax.crypto/java.security
 * primitives already available on Android, to avoid adding a Maven
 * dependency for one algorithm.
 *
 * Key layout matches Cryptomator's convention: a 256-bit "mac key" (S2V/CMAC
 * key) and a 256-bit "enc key" (CTR key) — the OPPOSITE order from the raw
 * RFC 5297 "SIV = K1 || K2" convention, matching FileNameCryptorImpl's
 * `siv.encrypt(ek, mk, ...)` call, i.e. encryption key first, MAC key second.
 */
class SivMode {

    /**
     * Encrypts [plaintext] deterministically. [associatedData] (zero or more
     * byte strings, e.g. the parent directory id) is authenticated but not
     * encrypted, matching S2V's vector construction.
     */
    fun encrypt(encKey: SecretKeySpec, macKey: SecretKeySpec, plaintext: ByteArray, vararg associatedData: ByteArray): ByteArray {
        val siv = s2v(macKey, associatedData.toList() + listOf(plaintext))
        val ciphertext = ctr(encKey, siv, plaintext)
        return siv + ciphertext
    }

    /**
     * Decrypts and authenticates [ciphertext] (siv || ctrCiphertext).
     * Throws [UnauthenticCiphertextException] if the recomputed SIV doesn't
     * match the one embedded in the ciphertext.
     */
    @Throws(UnauthenticCiphertextException::class)
    fun decrypt(encKey: SecretKeySpec, macKey: SecretKeySpec, ciphertext: ByteArray, vararg associatedData: ByteArray): ByteArray {
        if (ciphertext.size < 16) {
            throw IllegalArgumentException("Ciphertext must be at least 16 bytes (SIV).")
        }
        val siv = ciphertext.copyOfRange(0, 16)
        val actualCiphertext = ciphertext.copyOfRange(16, ciphertext.size)
        val plaintext = ctr(encKey, siv, actualCiphertext)
        val expectedSiv = s2v(macKey, associatedData.toList() + listOf(plaintext))
        if (!MessageDigest.isEqual(siv, expectedSiv)) {
            throw UnauthenticCiphertextException("SIV mismatch — wrong key or tampered/corrupt ciphertext.")
        }
        return plaintext
    }

    // ---- S2V (RFC 5297 §2.4) ------------------------------------------------

    private fun s2v(macKey: SecretKeySpec, elements: List<ByteArray>): ByteArray {
        require(elements.isNotEmpty()) { "S2V requires at least one element (the plaintext)." }

        // D = AES-CMAC(K, <zero>)
        var d = aesCmac(macKey, ByteArray(16))

        // For every associated-data element except the last (which is the
        // actual plaintext), D = dbl(D) xor AES-CMAC(K, element).
        for (i in 0 until elements.size - 1) {
            d = xor(dbl(d), aesCmac(macKey, elements[i]))
        }

        val last = elements.last()
        return if (last.size >= 16) {
            // T = last xorend D  (xor D into the final 16 bytes of `last`)
            val t = last.copyOf()
            val offset = t.size - 16
            for (i in 0 until 16) t[offset + i] = (t[offset + i].toInt() xor d[i].toInt()).toByte()
            aesCmac(macKey, t)
        } else {
            val padded = pad(last)
            aesCmac(macKey, xor(dbl(d), padded))
        }
    }

    private fun pad(data: ByteArray): ByteArray {
        val result = ByteArray(16)
        System.arraycopy(data, 0, result, 0, data.size)
        result[data.size] = 0x80.toByte()
        return result
    }

    /** Doubling in GF(2^128) with the standard reduction polynomial (RFC 5297 §2.3). */
    private fun dbl(block: ByteArray): ByteArray {
        require(block.size == 16)
        val result = ByteArray(16)
        var carry = 0
        for (i in 15 downTo 0) {
            val b = block[i].toInt() and 0xFF
            result[i] = ((b shl 1) or carry).toByte()
            carry = (b shr 7) and 1
        }
        if ((block[0].toInt() and 0x80) != 0) {
            result[15] = (result[15].toInt() xor 0x87).toByte()
        }
        return result
    }

    private fun xor(a: ByteArray, b: ByteArray): ByteArray {
        require(a.size == b.size)
        return ByteArray(a.size) { i -> (a[i].toInt() xor b[i].toInt()).toByte() }
    }

    /** AES-CMAC (RFC 4493) over the whole input, using javax.crypto's raw AES block cipher. */
    private fun aesCmac(key: SecretKeySpec, message: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/ECB/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)

        val zero = ByteArray(16)
        val l = cipher.doFinal(zero)
        val k1 = dbl(l)
        val k2 = dbl(k1)

        val n = if (message.isEmpty()) 1 else (message.size + 15) / 16
        val lastBlockComplete = message.isNotEmpty() && message.size % 16 == 0

        val mLast: ByteArray
        if (lastBlockComplete) {
            val lastStart = (n - 1) * 16
            val last = message.copyOfRange(lastStart, message.size)
            mLast = xor(last, k1)
        } else {
            val lastStart = (n - 1) * 16
            val lastLen = message.size - lastStart
            val last = ByteArray(16)
            if (lastLen > 0) System.arraycopy(message, lastStart, last, 0, lastLen)
            val padded = pad10(last, lastLen)
            mLast = xor(padded, k2)
        }

        var x = ByteArray(16)
        for (i in 0 until n - 1) {
            val block = message.copyOfRange(i * 16, (i + 1) * 16)
            x = cipher.doFinal(xor(x, block))
        }
        return cipher.doFinal(xor(x, mLast))
    }

    private fun pad10(block: ByteArray, dataLen: Int): ByteArray {
        val result = block.copyOf(16)
        if (dataLen < 16) {
            result[dataLen] = 0x80.toByte()
            for (i in dataLen + 1 until 16) result[i] = 0
        }
        return result
    }

    // ---- CTR (RFC 5297 §2.6, SIV with top two bits of the two 32-bit halves cleared) --------

    private fun ctr(encKey: SecretKeySpec, siv: ByteArray, data: ByteArray): ByteArray {
        if (data.isEmpty()) return ByteArray(0)
        // Clear the 32nd and 64th bits (top bit of each 32-bit half, 0-indexed
        // from the start) of the SIV before using it as the CTR IV — RFC 5297 §2.6 "Q".
        val q = siv.copyOf()
        q[8] = (q[8].toInt() and 0x7F).toByte()
        q[12] = (q[12].toInt() and 0x7F).toByte()

        val cipher = Cipher.getInstance("AES/CTR/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, encKey, IvParameterSpec(q))
        return cipher.doFinal(data)
    }
}

class UnauthenticCiphertextException(message: String) : GeneralSecurityException(message)