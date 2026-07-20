package com.aeidolon.vaultexplorer.gocryptfs

import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec

/**
 * EME ("ECB-Mix-ECB"), Halevi–Rogaway, CT-RSA 2003. Used by gocryptfs for
 * filename encryption (see nametransform/names.go's EncryptName, backed by
 * github.com/rfjakob/eme upstream).
 *
 * ── PORTING NOTE ──────────────────────────────────────────────────────────
 * The body of [transform] below is a faithful, line-by-line port of
 * https://github.com/rfjakob/eme/blob/master/eme.go's `Transform()` — not a
 * reimplementation from the paper's prose.
 * ─────────────────────────────────────────────────────────────────────────
 */
class GocryptfsEme(key: ByteArray) {
    private val encCipher = Cipher.getInstance("AES/ECB/NoPadding").apply {
        init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))
    }
    private val decCipher = Cipher.getInstance("AES/ECB/NoPadding").apply {
        init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"))
    }

    fun encrypt(tweak: ByteArray, plaintext: ByteArray): ByteArray =
        transform(tweak, plaintext, encrypt = true)

    fun decrypt(tweak: ByteArray, ciphertext: ByteArray): ByteArray =
        transform(tweak, ciphertext, encrypt = false)

    // Constant-time GF multiplication as specified in EME Figure 4.1.
    private fun multByTwo(out: ByteArray, inBlock: ByteArray) {
        val tmp = ByteArray(16)
        val in15Unsigned = inBlock[15].toInt() and 0xFF
        val carry15 = in15Unsigned ushr 7
        
        tmp[0] = (((inBlock[0].toInt() and 0xFF) shl 1) xor (135 and -carry15)).toByte()
        for (j in 1 until 16) {
            val inJUnsigned = inBlock[j].toInt() and 0xFF
            val inPrevUnsigned = inBlock[j - 1].toInt() and 0xFF
            tmp[j] = (((inJUnsigned shl 1) + (inPrevUnsigned ushr 7)) and 0xFF).toByte()
        }
        System.arraycopy(tmp, 0, out, 0, 16)
    }

    private fun xor16(out: ByteArray, outOffset: Int, in1: ByteArray, in1Offset: Int, in2: ByteArray, in2Offset: Int) {
        for (i in 0 until 16) {
            out[outOffset + i] = (in1[in1Offset + i].toInt() xor in2[in2Offset + i].toInt()).toByte()
        }
    }

    private fun aesTransform(out: ByteArray, outOffset: Int, inBlock: ByteArray, inOffset: Int, encrypt: Boolean) {
        val tempIn = if (inOffset == 0 && inBlock.size == 16) inBlock else inBlock.copyOfRange(inOffset, inOffset + 16)
        val tempOut = (if (encrypt) encCipher else decCipher).doFinal(tempIn)
        System.arraycopy(tempOut, 0, out, outOffset, 16)
    }

    private fun tabulateL(m: Int): Array<ByteArray> {
        val eZero = ByteArray(16)
        // set L0 = 2*AESenc(K; 0) - EME strictly uses Block Encryption direction
        // for L tabulation regardless of whether we are encrypting or decrypting.
        val Li = encCipher.doFinal(eZero)

        val LTable = Array(m) { ByteArray(16) }
        val currentL = Li.clone()
        for (i in 0 until m) {
            multByTwo(currentL, currentL)
            System.arraycopy(currentL, 0, LTable[i], 0, 16)
        }
        return LTable
    }

    /**
     * @param tweak 16 bytes (the directory's gocryptfs.diriv)
     * @param input a whole multiple of 16 bytes, <= 128 blocks (2048 bytes) —
     *   gocryptfs filenames are always far under this limit after pad16.
     */
    private fun transform(tweak: ByteArray, input: ByteArray, encrypt: Boolean): ByteArray {
        require(tweak.size == 16)
        require(input.size % 16 == 0 && input.isNotEmpty())
        val m = input.size / 16
        require(m in 1..128)

        val C = ByteArray(input.size)
        val LTable = tabulateL(m)

        val PPj = ByteArray(16)
        for (j in 0 until m) {
            // PPj = 2**(j-1)*L xor Pj
            xor16(PPj, 0, input, j * 16, LTable[j], 0)
            // PPPj = AES(K; PPj)
            aesTransform(C, j * 16, PPj, 0, encrypt)
        }

        // MP = (xorSum PPPj) xor T
        val MP = ByteArray(16)
        xor16(MP, 0, C, 0, tweak, 0)
        for (j in 1 until m) {
            xor16(MP, 0, MP, 0, C, j * 16)
        }

        // MC = AES(K; MP)
        val MC = ByteArray(16)
        aesTransform(MC, 0, MP, 0, encrypt)

        // M = MP xor MC
        val M = ByteArray(16)
        xor16(M, 0, MP, 0, MC, 0)

        val CCCj = ByteArray(16)
        for (j in 1 until m) {
            multByTwo(M, M)
            // CCCj = 2**(j-1)*M xor PPPj
            xor16(CCCj, 0, C, j * 16, M, 0)
            System.arraycopy(CCCj, 0, C, j * 16, 16)
        }

        // CCC1 = (xorSum CCCj) xor T xor MC
        val CCC1 = ByteArray(16)
        xor16(CCC1, 0, MC, 0, tweak, 0)
        for (j in 1 until m) {
            xor16(CCC1, 0, CCC1, 0, C, j * 16)
        }
        System.arraycopy(CCC1, 0, C, 0, 16)

        for (j in 0 until m) {
            // CCj = AES(K; CCCj)
            aesTransform(C, j * 16, C, j * 16, encrypt)
            // Cj = 2**(j-1)*L xor CCj
            xor16(C, j * 16, C, j * 16, LTable[j], 0)
        }

        return C
    }
}