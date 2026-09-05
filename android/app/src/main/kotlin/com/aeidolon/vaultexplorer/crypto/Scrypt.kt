package com.aeidolon.vaultexplorer.crypto

import com.aeidolon.vaultexplorer.NativeEngine
import java.nio.charset.StandardCharsets
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec


object Scrypt {

    private const val DEFAULT_P = 1

    fun scrypt(passphrase: CharArray, salt: ByteArray, costParam: Int, blockSize: Int, keyLengthBytes: Int): ByteArray {
        val pw = StandardCharsets.UTF_8.encode(java.nio.CharBuffer.wrap(passphrase))
        val pwBytes = ByteArray(pw.remaining())
        pw.get(pwBytes)
        try {
            return scrypt(pwBytes, salt, costParam, blockSize, keyLengthBytes, DEFAULT_P)
        } finally {
            pwBytes.fill(0)
        }
    }

    fun scrypt(passphrase: ByteArray, salt: ByteArray, costParam: Int, blockSize: Int, keyLengthBytes: Int, p: Int = DEFAULT_P): ByteArray {
        if (NativeEngine.isLoaded) {
            val nativeBytes = NativeEngine.scryptNative(passphrase, salt, costParam, blockSize, p, keyLengthBytes)
            if (nativeBytes != null) {
                return nativeBytes
            }
        }
        // Pure-JVM fallback (RFC 7914)
        return pureScrypt(passphrase, salt, costParam, blockSize, p, keyLengthBytes)
    }

    // -----------------------------------------------------------------------
    //  Pure-JVM scrypt implementation (RFC 7914)
    // -----------------------------------------------------------------------

    private fun pureScrypt(
        passphrase: ByteArray, salt: ByteArray,
        N: Int, r: Int, p: Int, dkLen: Int
    ): ByteArray {
        require(N > 1 && (N and (N - 1)) == 0) { "N must be a power of 2 greater than 1" }
        require(r > 0 && p > 0) { "r and p must be positive" }

        val blockLen = 128 * r           // bytes per SMix block
        val bLen = blockLen * p

        // Step 1: B = PBKDF2-HMAC-SHA256(passphrase, salt, 1, p * 128 * r)
        val B = pbkdf2HmacSha256(passphrase, salt, 1, bLen)

        // Step 2: SMix each p-sized block
        for (i in 0 until p) {
            smix(B, i * blockLen, r, N)
        }

        // Step 3: output = PBKDF2-HMAC-SHA256(passphrase, B, 1, dkLen)
        return pbkdf2HmacSha256(passphrase, B, 1, dkLen)
    }

    // ---- PBKDF2-HMAC-SHA256 (iterations is always 1 in scrypt) ----

    private fun pbkdf2HmacSha256(
        password: ByteArray, salt: ByteArray, iterations: Int, dkLen: Int
    ): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(password, "HmacSHA256"))
        val hLen = 32  // SHA-256 output length
        val numBlocks = (dkLen + hLen - 1) / hLen
        val dk = ByteArray(dkLen)
        val intBuf = ByteArray(4)

        for (blockIndex in 1..numBlocks) {
            // INT(i) = big-endian 32-bit encoding of blockIndex
            intBuf[0] = (blockIndex ushr 24).toByte()
            intBuf[1] = (blockIndex ushr 16).toByte()
            intBuf[2] = (blockIndex ushr 8).toByte()
            intBuf[3] = blockIndex.toByte()

            // U_1 = HMAC(password, salt || INT(i))
            mac.reset()
            mac.update(salt)
            var u = mac.doFinal(intBuf)
            val t = u.copyOf()

            // U_2 .. U_c  (for scrypt c=1, so this loop body never runs)
            for (j in 2..iterations) {
                mac.reset()
                u = mac.doFinal(u)
                for (k in t.indices) t[k] = (t[k].toInt() xor u[k].toInt()).toByte()
            }

            val offset = (blockIndex - 1) * hLen
            val len = minOf(hLen, dkLen - offset)
            System.arraycopy(t, 0, dk, offset, len)
        }
        return dk
    }

    // ---- SMix (RFC 7914 §3) ----

    private fun smix(B: ByteArray, offset: Int, r: Int, N: Int) {
        val blockLen = 128 * r
        val X = ByteArray(blockLen)
        System.arraycopy(B, offset, X, 0, blockLen)

        // Scratch space for blockmixSalsa8: Y needs 2*r * 64 = blockLen bytes
        val Y = ByteArray(blockLen)

        // V[0..N-1], each blockLen bytes
        val V = Array(N) { ByteArray(blockLen) }
        for (i in 0 until N) {
            System.arraycopy(X, 0, V[i], 0, blockLen)
            blockmixSalsa8(X, Y, r)
        }

        for (i in 0 until N) {
            val j = integerify(X, r) and (N - 1)
            blockxor(V[j], 0, X, 0, blockLen)
            blockmixSalsa8(X, Y, r)
        }

        System.arraycopy(X, 0, B, offset, blockLen)
    }

    /** Integerify: first 4 bytes of the last 64-byte block, little-endian. */
    private fun integerify(X: ByteArray, r: Int): Int {
        val off = (2 * r - 1) * 64
        return (X[off].toInt() and 0xFF) or
                ((X[off + 1].toInt() and 0xFF) shl 8) or
                ((X[off + 2].toInt() and 0xFF) shl 16) or
                ((X[off + 3].toInt() and 0xFF) shl 24)
    }

    // ---- BlockMix-Salsa8 (RFC 7914 §2) ----

    /**
     * In-place BlockMix: reads from [B], writes result back into [B].
     * Uses [Y] as scratch space (same size as B = 128*r bytes).
     */
    private fun blockmixSalsa8(B: ByteArray, Y: ByteArray, r: Int) {
        val salsa = ByteArray(64)
        // X = B[2r-1]  (last 64-byte block)
        System.arraycopy(B, (2 * r - 1) * 64, salsa, 0, 64)

        for (i in 0 until 2 * r) {
            // X = X xor B[i]
            blockxor(B, i * 64, salsa, 0, 64)
            salsa20_8(salsa)
            System.arraycopy(salsa, 0, Y, i * 64, 64)
        }

        // Rearrange: even blocks first, then odd blocks
        for (i in 0 until r) {
            System.arraycopy(Y, (i * 2) * 64, B, i * 64, 64)
        }
        for (i in 0 until r) {
            System.arraycopy(Y, (i * 2 + 1) * 64, B, (i + r) * 64, 64)
        }
    }

    // ---- Salsa20/8 core (RFC 7914 §3 / Bernstein spec) ----

    private fun salsa20_8(block: ByteArray) {
        val b32 = IntArray(16)
        val x = IntArray(16)

        // Load 16 little-endian 32-bit words
        for (i in 0 until 16) {
            val off = i * 4
            b32[i] = (block[off].toInt() and 0xFF) or
                    ((block[off + 1].toInt() and 0xFF) shl 8) or
                    ((block[off + 2].toInt() and 0xFF) shl 16) or
                    ((block[off + 3].toInt() and 0xFF) shl 24)
            x[i] = b32[i]
        }

        // 8 rounds (4 double-rounds)
        var i = 8
        while (i > 0) {
            // Column round
            x[ 4] = x[ 4] xor ((x[ 0] + x[12]).rotateLeft( 7))
            x[ 8] = x[ 8] xor ((x[ 4] + x[ 0]).rotateLeft( 9))
            x[12] = x[12] xor ((x[ 8] + x[ 4]).rotateLeft(13))
            x[ 0] = x[ 0] xor ((x[12] + x[ 8]).rotateLeft(18))

            x[ 9] = x[ 9] xor ((x[ 5] + x[ 1]).rotateLeft( 7))
            x[13] = x[13] xor ((x[ 9] + x[ 5]).rotateLeft( 9))
            x[ 1] = x[ 1] xor ((x[13] + x[ 9]).rotateLeft(13))
            x[ 5] = x[ 5] xor ((x[ 1] + x[13]).rotateLeft(18))

            x[14] = x[14] xor ((x[10] + x[ 6]).rotateLeft( 7))
            x[ 2] = x[ 2] xor ((x[14] + x[10]).rotateLeft( 9))
            x[ 6] = x[ 6] xor ((x[ 2] + x[14]).rotateLeft(13))
            x[10] = x[10] xor ((x[ 6] + x[ 2]).rotateLeft(18))

            x[ 3] = x[ 3] xor ((x[15] + x[11]).rotateLeft( 7))
            x[ 7] = x[ 7] xor ((x[ 3] + x[15]).rotateLeft( 9))
            x[11] = x[11] xor ((x[ 7] + x[ 3]).rotateLeft(13))
            x[15] = x[15] xor ((x[11] + x[ 7]).rotateLeft(18))

            // Row round
            x[ 1] = x[ 1] xor ((x[ 0] + x[ 3]).rotateLeft( 7))
            x[ 2] = x[ 2] xor ((x[ 1] + x[ 0]).rotateLeft( 9))
            x[ 3] = x[ 3] xor ((x[ 2] + x[ 1]).rotateLeft(13))
            x[ 0] = x[ 0] xor ((x[ 3] + x[ 2]).rotateLeft(18))

            x[ 6] = x[ 6] xor ((x[ 5] + x[ 4]).rotateLeft( 7))
            x[ 7] = x[ 7] xor ((x[ 6] + x[ 5]).rotateLeft( 9))
            x[ 4] = x[ 4] xor ((x[ 7] + x[ 6]).rotateLeft(13))
            x[ 5] = x[ 5] xor ((x[ 4] + x[ 7]).rotateLeft(18))

            x[11] = x[11] xor ((x[10] + x[ 9]).rotateLeft( 7))
            x[ 8] = x[ 8] xor ((x[11] + x[10]).rotateLeft( 9))
            x[ 9] = x[ 9] xor ((x[ 8] + x[11]).rotateLeft(13))
            x[10] = x[10] xor ((x[ 9] + x[ 8]).rotateLeft(18))

            x[12] = x[12] xor ((x[15] + x[14]).rotateLeft( 7))
            x[13] = x[13] xor ((x[12] + x[15]).rotateLeft( 9))
            x[14] = x[14] xor ((x[13] + x[12]).rotateLeft(13))
            x[15] = x[15] xor ((x[14] + x[13]).rotateLeft(18))

            i -= 2
        }

        // Output: B32[i] += x[i], then store little-endian
        for (j in 0 until 16) {
            b32[j] += x[j]
            val off = j * 4
            block[off]     = (b32[j]         and 0xFF).toByte()
            block[off + 1] = ((b32[j] ushr  8) and 0xFF).toByte()
            block[off + 2] = ((b32[j] ushr 16) and 0xFF).toByte()
            block[off + 3] = ((b32[j] ushr 24) and 0xFF).toByte()
        }
    }

    /** XOR [len] bytes: dst[di..] ^= src[si..] */
    private fun blockxor(src: ByteArray, si: Int, dst: ByteArray, di: Int, len: Int) {
        for (i in 0 until len) {
            dst[di + i] = (dst[di + i].toInt() xor src[si + i].toInt()).toByte()
        }
    }
}
