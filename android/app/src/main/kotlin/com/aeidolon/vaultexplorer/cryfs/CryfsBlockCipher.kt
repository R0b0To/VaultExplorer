package com.aeidolon.vaultexplorer.cryfs

import com.aeidolon.vaultexplorer.VeraCryptEngine

class CryfsUnsupportedCipherException(cipherName: String) :
    Exception("Vault uses cipher \"$cipherName\", which this app does not support.")

object CryfsBlockCipher {

    /** @throws CryfsUnsupportedCipherException if [cipherName] isn't one this app implements. */
    fun cipherIdFor(cipherName: String): Int {
        val id = VeraCryptEngine.cryfsCipherIdNative(cipherName)
        if (id < 0) throw CryfsUnsupportedCipherException(cipherName)
        return id
    }

    /** @return IV || ciphertext || tag. */
    fun encrypt(cipherId: Int, key: ByteArray, plaintext: ByteArray): ByteArray {
        return VeraCryptEngine.cryfsEncryptBlockNative(cipherId, key, plaintext)
            ?: throw IllegalStateException("CryFS block encryption failed")
    }

    /** @return the decrypted, authenticity-checked plaintext, or null if the tag/key is wrong. */
    fun decrypt(cipherId: Int, key: ByteArray, ciphertext: ByteArray): ByteArray? {
        return VeraCryptEngine.cryfsDecryptBlockNative(cipherId, key, ciphertext)
    }
}