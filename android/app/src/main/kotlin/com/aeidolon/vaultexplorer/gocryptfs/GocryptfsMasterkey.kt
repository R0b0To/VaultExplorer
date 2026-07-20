package com.aeidolon.vaultexplorer.gocryptfs

import com.aeidolon.vaultexplorer.cryptomator.Scrypt // reused verbatim — see §3
import java.security.MessageDigest
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class GocryptfsWrongPasswordException : Exception("Wrong password for this vault.")

/**
 * Unwraps a gocryptfs masterkey from a parsed [GocryptfsConfig], mirroring
 * CryptomatorMasterkeyFile.unlock()'s role. Where Cryptomator's masterkey
 * file wraps two 32-byte subkeys with AES-KeyWrap (RFC 3394), gocryptfs wraps
 * a single 32-byte masterkey the *same way it encrypts file content*: one
 * AES-GCM block, IV length depends on the GCMIV128 flag (we only support
 * that flag being set, so IV is always 16 bytes), key = scrypt(password),
 * AAD = 8 zero bytes (blockNo=0, no file ID) per contentenc's concatAD().
 */
object GocryptfsMasterkey {

    private const val NONCE_LEN = 16 // GCMIV128
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
            // HKDF is always required by SUPPORTED_FLAGS, so this branch is
            // unconditional here (kept explicit for readability / future
            // legacy-flag support).
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

    private fun decryptBlock(key: ByteArray, blob: ByteArray): ByteArray {
        require(blob.size > NONCE_LEN + TAG_LEN) { "EncryptedKey blob too short" }
        val nonce = blob.copyOfRange(0, NONCE_LEN)
        // Reject the same all-zero-nonce corruption case content.go guards against.
        if (MessageDigest.isEqual(nonce, ByteArray(NONCE_LEN))) {
            throw GocryptfsWrongPasswordException()
        }
        val payloadAndTag = blob.copyOfRange(NONCE_LEN, blob.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
        cipher.updateAAD(ByteArray(8)) // blockNo=0 BE, no fileID -> 8 zero bytes
        return cipher.doFinal(payloadAndTag)
    }
}