package com.aeidolon.vaultexplorer.gocryptfs

import com.aeidolon.vaultexplorer.crypto.Scrypt
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class GocryptfsWrongPasswordException : Exception("Wrong password for this vault.")

object GocryptfsMasterkey {
    private const val NONCE_LEN = 16
    private const val TAG_LEN = 16

    @Throws(GocryptfsWrongPasswordException::class)
    fun unlock(config: GocryptfsConfig, password: CharArray): ByteArray {
        val scryptHash = Scrypt.scrypt(
            passphrase = password,
            salt = config.scryptSalt,
            costParam = config.scryptN,
            blockSize = config.scryptR,
            keyLengthBytes = config.scryptKeyLen,
        )
        try {
            // The master key is ALWAYS wrapped using AES-GCM, even for XChaCha20 vaults
            val gcmKey = Hkdf.deriveSha256(scryptHash, "AES-GCM file content encryption", 32)
            return try {
                decryptBlock(gcmKey, config.encryptedKey)
            } finally {
                gcmKey.fill(0)
            }
        } catch (e: AEADBadTagException) {
            throw GocryptfsWrongPasswordException()
        } finally {
            scryptHash.fill(0)
        }
    }

    fun wrap(
        masterkey: ByteArray,
        password: CharArray,
        scryptSalt: ByteArray,
        scryptN: Int,
        scryptR: Int,
        scryptKeyLen: Int,
        random: SecureRandom,
    ): ByteArray {
        val scryptHash = Scrypt.scrypt(
            passphrase = password,
            salt = scryptSalt,
            costParam = scryptN,
            blockSize = scryptR,
            keyLengthBytes = scryptKeyLen,
        )
        try {
            // The master key is ALWAYS wrapped using AES-GCM, even for XChaCha20 vaults
            val gcmKey = Hkdf.deriveSha256(scryptHash, "AES-GCM file content encryption", 32)
            try {
                return encryptBlock(gcmKey, masterkey, random)
            } finally {
                gcmKey.fill(0)
            }
        } finally {
            scryptHash.fill(0)
        }
    }

    private fun decryptBlock(key: ByteArray, blob: ByteArray): ByteArray {
        require(blob.size > NONCE_LEN + TAG_LEN) { "EncryptedKey blob too short" }
        
        val nonce = blob.copyOfRange(0, NONCE_LEN)
        if (MessageDigest.isEqual(nonce, ByteArray(NONCE_LEN))) {
            throw GocryptfsWrongPasswordException()
        }
        val payloadAndTag = blob.copyOfRange(NONCE_LEN, blob.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
        cipher.updateAAD(ByteArray(8)) // 8 bytes of zeroes (Block #0)
        return cipher.doFinal(payloadAndTag)
    }

    private fun encryptBlock(key: ByteArray, plaintext: ByteArray, random: SecureRandom): ByteArray {
        val nonce = ByteArray(NONCE_LEN).also { random.nextBytes(it) }
        val aad = ByteArray(8) // Block #0
        
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
        cipher.updateAAD(aad)
        val ciphertextAndTag = cipher.doFinal(plaintext)
        
        return nonce + ciphertextAndTag
    }
}