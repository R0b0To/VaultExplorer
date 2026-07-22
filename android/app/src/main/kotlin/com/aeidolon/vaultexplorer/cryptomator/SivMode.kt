package com.aeidolon.vaultexplorer.cryptomator

import com.aeidolon.vaultexplorer.VeraCryptEngine
import com.aeidolon.vaultexplorer.crypto.gf128Double
import java.security.GeneralSecurityException
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

class SivMode {

    fun encrypt(encKey: SecretKeySpec, macKey: SecretKeySpec, plaintext: ByteArray, vararg associatedData: ByteArray): ByteArray {
        val adList = if (associatedData.isNotEmpty()) associatedData.toList().toTypedArray() else null
        val nativeBytes = VeraCryptEngine.sivEncryptNative(encKey.encoded, macKey.encoded, plaintext, adList)
        if (nativeBytes != null) return nativeBytes

        val siv = s2v(macKey, associatedData.toList() + listOf(plaintext))
        val ciphertext = ctr(encKey, siv, plaintext)
        return siv + ciphertext
    }

    fun decrypt(encKey: SecretKeySpec, macKey: SecretKeySpec, ciphertext: ByteArray, vararg associatedData: ByteArray): ByteArray {
        if (ciphertext.size < 16) {
            throw IllegalArgumentException("Ciphertext must be at least 16 bytes (SIV).")
        }
        val adList = if (associatedData.isNotEmpty()) associatedData.toList().toTypedArray() else null
        val nativeBytes = VeraCryptEngine.sivDecryptNative(encKey.encoded, macKey.encoded, ciphertext, adList)
        if (nativeBytes != null) return nativeBytes

        val siv = ciphertext.copyOfRange(0, 16)
        val actualCiphertext = ciphertext.copyOfRange(16, ciphertext.size)
        val plaintext = ctr(encKey, siv, actualCiphertext)
        val expectedSiv = s2v(macKey, associatedData.toList() + listOf(plaintext))
        if (!MessageDigest.isEqual(siv, expectedSiv)) {
            throw UnauthenticCiphertextException("SIV mismatch — wrong key or tampered/corrupt ciphertext.")
        }
        return plaintext
    }

    // ---- Kotlin Fallback Implementation ------------------------------------

    private fun s2v(macKey: SecretKeySpec, elements: List<ByteArray>): ByteArray {
        require(elements.isNotEmpty()) { "S2V requires at least one element (the plaintext)." }

        var d = aesCmac(macKey, ByteArray(16))

        for (i in 0 until elements.size - 1) {
            d = xor(dbl(d), aesCmac(macKey, elements[i]))
        }

        val last = elements.last()
        return if (last.size >= 16) {
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

    private fun dbl(block: ByteArray): ByteArray = gf128Double(block)

    private fun xor(a: ByteArray, b: ByteArray): ByteArray {
        require(a.size == b.size)
        return ByteArray(a.size) { i -> (a[i].toInt() xor b[i].toInt()).toByte() }
    }

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

    private fun ctr(encKey: SecretKeySpec, siv: ByteArray, data: ByteArray): ByteArray {
        if (data.isEmpty()) return ByteArray(0)
        val q = siv.copyOf()
        q[8] = (q[8].toInt() and 0x7F).toByte()
        q[12] = (q[12].toInt() and 0x7F).toByte()

        val cipher = Cipher.getInstance("AES/CTR/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, encKey, IvParameterSpec(q))
        return cipher.doFinal(data)
    }
}

class UnauthenticCiphertextException(message: String) : GeneralSecurityException(message)