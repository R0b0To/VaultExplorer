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
    private const val TAG_LEN = 16

    // The key wrap is AES-GCM with block number 0. With HKDF the scrypt output is expanded first and the nonce is
    // 128 bit; vaults without it (gocryptfs <= 1.2) use the scrypt output directly and a 96-bit nonce.
    private fun nonceLen(hkdf: Boolean) = if (hkdf) 16 else 12

    /**
     * The (name key, content key) pair for [masterkey], derived as gocryptfs' cryptocore.New does: HKDF with a
     * per-purpose info string -- or, for vaults without the HKDF flag, the master key itself (AES-SIV: its SHA-512,
     * since it needs 64 bytes). The name key is empty for plaintext names.
     */
    fun deriveKeys(config: GocryptfsConfig, masterkey: ByteArray): Pair<ByteArray, ByteArray> {
        if (config.hasHkdf) {
            val nameKey = if (config.plaintextNames) ByteArray(0) else Hkdf.deriveSha256(masterkey, "EME filename encryption", 32)
            val contentKey = Hkdf.deriveSha256(masterkey, config.cipher.hkdfInfo, config.cipher.contentKeyLen)
            return nameKey to contentKey
        }
        val nameKey = if (config.plaintextNames) ByteArray(0) else masterkey.copyOf()
        val contentKey = if (config.cipher == GocryptfsCipher.AES_SIV) {
            MessageDigest.getInstance("SHA-512").digest(masterkey)
        } else {
            masterkey.copyOf()
        }
        return nameKey to contentKey
    }

    @Throws(GocryptfsWrongPasswordException::class, GocryptfsConfigException::class)
    fun unlock(config: GocryptfsConfig, password: CharArray): ByteArray {
        if (config.fido2) {
            throw GocryptfsConfigException(
                "This vault is protected by a FIDO2 security key (gocryptfs -fido2). " +
                    "Unlocking with a hardware token is not supported by this app."
            )
        }
        val scryptHash = Scrypt.scrypt(
            passphrase = password,
            salt = config.scryptSalt,
            costParam = config.scryptN,
            blockSize = config.scryptR,
            keyLengthBytes = config.scryptKeyLen,
        )
        try {
            // The master key is ALWAYS wrapped using AES-GCM, even for XChaCha20 vaults
            val gcmKey = if (config.hasHkdf) Hkdf.deriveSha256(scryptHash, "AES-GCM file content encryption", 32) else scryptHash.copyOf()
            val masterkey = try {
                decryptBlock(gcmKey, config.encryptedKey, nonceLen(config.hasHkdf))
            } finally {
                gcmKey.fill(0)
            }
            // gocryptfs only ever uses 32-byte master keys (cryptocore.KeyLen) and panics on anything else.
            if (masterkey.size != 32) {
                masterkey.fill(0)
                throw GocryptfsConfigException("gocryptfs.conf: the master key is not 32 bytes long")
            }
            return masterkey
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
        hkdf: Boolean = true,
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
            val gcmKey = if (hkdf) Hkdf.deriveSha256(scryptHash, "AES-GCM file content encryption", 32) else scryptHash.copyOf()
            try {
                return encryptBlock(gcmKey, masterkey, random, nonceLen(hkdf))
            } finally {
                gcmKey.fill(0)
            }
        } finally {
            scryptHash.fill(0)
        }
    }

    private fun decryptBlock(key: ByteArray, blob: ByteArray, nonceLen: Int): ByteArray {
        require(blob.size > nonceLen + TAG_LEN) { "EncryptedKey blob too short" }

        val nonce = blob.copyOfRange(0, nonceLen)
        if (MessageDigest.isEqual(nonce, ByteArray(nonceLen))) {
            throw GocryptfsWrongPasswordException()
        }
        val payloadAndTag = blob.copyOfRange(nonceLen, blob.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
        cipher.updateAAD(ByteArray(8)) // 8 bytes of zeroes (Block #0)
        return cipher.doFinal(payloadAndTag)
    }

    private fun encryptBlock(key: ByteArray, plaintext: ByteArray, random: SecureRandom, nonceLen: Int): ByteArray {
        val nonce = ByteArray(nonceLen).also { random.nextBytes(it) }
        val aad = ByteArray(8) // Block #0
        
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
        cipher.updateAAD(aad)
        val ciphertextAndTag = cipher.doFinal(plaintext)
        
        return nonce + ciphertextAndTag
    }
}