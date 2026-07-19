package com.aeidolon.vaultexplorer.cryptomator

import java.nio.charset.StandardCharsets
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * scrypt (RFC 7914) key derivation, used to unwrap the AES key-wrapped
 * subkeys stored in a vault's masterkey.cryptomator file.
 *
 * Ported from Cryptomator cryptolib's Scrypt.java, which itself derives from
 * com.lambdaworks.crypto.SCrypt (Apache License 2.0, Will Glozer). Kept as a
 * direct, from-scratch port using only javax.crypto.Mac (HMAC-SHA256,
 * available on every Android API level) rather than adding a Bouncy Castle
 * or lambdaworks dependency for a single KDF call made once per unlock.
 */
object Scrypt {

    private const val P = 1 // Cryptomator always uses parallelization=1

    fun scrypt(passphrase: CharArray, salt: ByteArray, costParam: Int, blockSize: Int, keyLengthBytes: Int): ByteArray {
        val pw = StandardCharsets.UTF_8.encode(java.nio.CharBuffer.wrap(passphrase))
        val pwBytes = ByteArray(pw.remaining())
        pw.get(pwBytes)
        try {
            return scrypt(pwBytes, salt, costParam, blockSize, keyLengthBytes)
        } finally {
            pwBytes.fill(0)
        }
    }

    fun scrypt(passphrase: ByteArray, salt: ByteArray, costParam: Int, blockSize: Int, keyLengthBytes: Int): ByteArray {
        require(costParam >= 2 && (costParam and (costParam - 1)) == 0) { "N must be a power of 2 greater than 1" }
        require(costParam <= Int.MAX_VALUE / 128 / blockSize) { "Parameter N is too large" }
        require(blockSize <= Int.MAX_VALUE / 128 / P) { "Parameter r is too large" }

        val key = SecretKeySpec(passphrase, "HmacSHA256")
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(key)

        val dk = ByteArray(keyLengthBytes)
        val b = ByteArray(128 * blockSize * P)
        val xy = ByteArray(256 * blockSize)
        val v = ByteArray(128 * blockSize * costParam)

        pbkdf2(mac, salt, 1, b, P * 128 * blockSize)

        for (i in 0 until P) {
            smix(b, i * 128 * blockSize, blockSize, costParam, v, xy)
        }

        pbkdf2(mac, b, 1, dk, keyLengthBytes)
        return dk
    }

    private fun pbkdf2(mac: Mac, s: ByteArray, c: Int, dk: ByteArray, dkLen: Int) {
        val hLen = mac.macLength
        require(dkLen.toLong() <= (Math.pow(2.0, 32.0) - 1) * hLen) { "Requested key length too long" }

        var u: ByteArray
        val t = ByteArray(hLen)
        val block1 = ByteArray(s.size + 4)

        val l = Math.ceil(dkLen.toDouble() / hLen).toInt()
        val r = dkLen - (l - 1) * hLen

        System.arraycopy(s, 0, block1, 0, s.size)

        for (i in 1..l) {
            block1[s.size + 0] = (i shr 24 and 0xff).toByte()
            block1[s.size + 1] = (i shr 16 and 0xff).toByte()
            block1[s.size + 2] = (i shr 8 and 0xff).toByte()
            block1[s.size + 3] = (i shr 0 and 0xff).toByte()

            u = mac.doFinal(block1)
            System.arraycopy(u, 0, t, 0, hLen)

            for (j in 1 until c) {
                u = mac.doFinal(u)
                for (k in 0 until hLen) {
                    t[k] = (t[k].toInt() xor u[k].toInt()).toByte()
                }
            }

            System.arraycopy(t, 0, dk, (i - 1) * hLen, if (i == l) r else hLen)
        }
    }

    private fun smix(b: ByteArray, bi: Int, r: Int, n: Int, v: ByteArray, xy: ByteArray) {
        val xi = 0
        val yi = 128 * r

        System.arraycopy(b, bi, xy, xi, 128 * r)

        for (i in 0 until n) {
            System.arraycopy(xy, xi, v, i * (128 * r), 128 * r)
            blockmixSalsa8(xy, xi, yi, r)
        }

        for (i in 0 until n) {
            val j = integerify(xy, xi, r) and (n - 1)
            blockxor(v, j * (128 * r), xy, xi, 128 * r)
            blockmixSalsa8(xy, xi, yi, r)
        }

        System.arraycopy(xy, xi, b, bi, 128 * r)
    }

    private fun blockmixSalsa8(by: ByteArray, bi: Int, yi: Int, r: Int) {
        val x = ByteArray(64)
        System.arraycopy(by, bi + (2 * r - 1) * 64, x, 0, 64)

        for (i in 0 until 2 * r) {
            blockxor(by, i * 64, x, 0, 64)
            salsa20_8(x)
            System.arraycopy(x, 0, by, yi + (i * 64), 64)
        }

        for (i in 0 until r) {
            System.arraycopy(by, yi + (i * 2) * 64, by, bi + (i * 64), 64)
        }
        for (i in 0 until r) {
            System.arraycopy(by, yi + (i * 2 + 1) * 64, by, bi + (i + r) * 64, 64)
        }
    }

    private fun rotl(a: Int, b: Int): Int = (a shl b) or (a ushr (32 - b))

    private fun salsa20_8(b: ByteArray) {
        val b32 = IntArray(16)
        val x = IntArray(16)

        for (i in 0 until 16) {
            b32[i] = (b[i * 4 + 0].toInt() and 0xff) shl 0
            b32[i] = b32[i] or ((b[i * 4 + 1].toInt() and 0xff) shl 8)
            b32[i] = b32[i] or ((b[i * 4 + 2].toInt() and 0xff) shl 16)
            b32[i] = b32[i] or ((b[i * 4 + 3].toInt() and 0xff) shl 24)
        }

        System.arraycopy(b32, 0, x, 0, 16)

        var i = 8
        while (i > 0) {
            x[4] = x[4] xor rotl(x[0] + x[12], 7)
            x[8] = x[8] xor rotl(x[4] + x[0], 9)
            x[12] = x[12] xor rotl(x[8] + x[4], 13)
            x[0] = x[0] xor rotl(x[12] + x[8], 18)
            x[9] = x[9] xor rotl(x[5] + x[1], 7)
            x[13] = x[13] xor rotl(x[9] + x[5], 9)
            x[1] = x[1] xor rotl(x[13] + x[9], 13)
            x[5] = x[5] xor rotl(x[1] + x[13], 18)
            x[14] = x[14] xor rotl(x[10] + x[6], 7)
            x[2] = x[2] xor rotl(x[14] + x[10], 9)
            x[6] = x[6] xor rotl(x[2] + x[14], 13)
            x[10] = x[10] xor rotl(x[6] + x[2], 18)
            x[3] = x[3] xor rotl(x[15] + x[11], 7)
            x[7] = x[7] xor rotl(x[3] + x[15], 9)
            x[11] = x[11] xor rotl(x[7] + x[3], 13)
            x[15] = x[15] xor rotl(x[11] + x[7], 18)
            x[1] = x[1] xor rotl(x[0] + x[3], 7)
            x[2] = x[2] xor rotl(x[1] + x[0], 9)
            x[3] = x[3] xor rotl(x[2] + x[1], 13)
            x[0] = x[0] xor rotl(x[3] + x[2], 18)
            x[6] = x[6] xor rotl(x[5] + x[4], 7)
            x[7] = x[7] xor rotl(x[6] + x[5], 9)
            x[4] = x[4] xor rotl(x[7] + x[6], 13)
            x[5] = x[5] xor rotl(x[4] + x[7], 18)
            x[11] = x[11] xor rotl(x[10] + x[9], 7)
            x[8] = x[8] xor rotl(x[11] + x[10], 9)
            x[9] = x[9] xor rotl(x[8] + x[11], 13)
            x[10] = x[10] xor rotl(x[9] + x[8], 18)
            x[12] = x[12] xor rotl(x[15] + x[14], 7)
            x[13] = x[13] xor rotl(x[12] + x[15], 9)
            x[14] = x[14] xor rotl(x[13] + x[12], 13)
            x[15] = x[15] xor rotl(x[14] + x[13], 18)
            i -= 2
        }

        for (j in 0 until 16) b32[j] += x[j]

        for (j in 0 until 16) {
            b[j * 4 + 0] = (b32[j] shr 0 and 0xff).toByte()
            b[j * 4 + 1] = (b32[j] shr 8 and 0xff).toByte()
            b[j * 4 + 2] = (b32[j] shr 16 and 0xff).toByte()
            b[j * 4 + 3] = (b32[j] shr 24 and 0xff).toByte()
        }
    }

    private fun blockxor(s: ByteArray, si: Int, d: ByteArray, di: Int, len: Int) {
        for (i in 0 until len) {
            d[di + i] = (d[di + i].toInt() xor s[si + i].toInt()).toByte()
        }
    }

    private fun integerify(b: ByteArray, bi0: Int, r: Int): Int {
        val bi = bi0 + (2 * r - 1) * 64
        var n = (b[bi + 0].toInt() and 0xff) shl 0
        n = n or ((b[bi + 1].toInt() and 0xff) shl 8)
        n = n or ((b[bi + 2].toInt() and 0xff) shl 16)
        n = n or ((b[bi + 3].toInt() and 0xff) shl 24)
        return n
    }
}
