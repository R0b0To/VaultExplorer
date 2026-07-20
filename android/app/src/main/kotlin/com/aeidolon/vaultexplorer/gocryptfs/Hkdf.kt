package com.aeidolon.vaultexplorer.gocryptfs

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * RFC 5869 HKDF-SHA256 (Extract-then-Expand), matching Go stdlib's
 * `crypto/hkdf.Key(sha256.New, secret, salt, info, length)` as used by
 * gocryptfs's `cryptocore/hkdf.go` (`hkdfDerive`). gocryptfs always calls it
 * with `salt = nil`, which per RFC 5869 §2.2 means "use a salt of HashLen
 * zero bytes" — implemented explicitly below rather than relying on any
 * library default.
 */
object Hkdf {
    private const val HASH_LEN = 32 // SHA-256 digest size

    fun deriveSha256(secret: ByteArray, info: String, outLen: Int): ByteArray {
        val zeroSalt = ByteArray(HASH_LEN)
        val prk = hmacSha256(zeroSalt, secret) // Extract

        // Expand
        val infoBytes = info.toByteArray(Charsets.UTF_8)
        val n = (outLen + HASH_LEN - 1) / HASH_LEN
        require(n <= 255) { "HKDF output too long" }

        var t = ByteArray(0)
        val okm = ByteArray(n * HASH_LEN)
        for (i in 1..n) {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(prk, "HmacSHA256"))
            mac.update(t)
            mac.update(infoBytes)
            mac.update(i.toByte())
            t = mac.doFinal()
            System.arraycopy(t, 0, okm, (i - 1) * HASH_LEN, HASH_LEN)
        }
        return okm.copyOf(outLen)
    }

    private fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data)
    }
}