package com.aeidolon.vaultexplorer.cryptomator

import java.security.MessageDigest
import java.util.Base64
import javax.crypto.spec.SecretKeySpec

/**
 * Encrypts/decrypts individual path segment names and hashes directory IDs,
 * using AES-SIV (see [SivMode]) with the vault's masterkey — identical
 * across vault formats 7 and 8 (the filename scheme didn't change between
 * them, only the file *content* scheme did).
 */
class CryptomatorFileNameCryptor(private val masterkey: CryptomatorMasterkey) {

    private val siv = SivMode()
    private val base64Url: Base64.Encoder = Base64.getUrlEncoder().withoutPadding()
    private val base64UrlDecoder: Base64.Decoder = Base64.getUrlDecoder()
    private val base32: Base32 = Base32()

    /**
     * SHA-1(SIV-encrypt(dirId)) base32-encoded — the physical two-level
     * directory name (`d/<hash[0:2]>/<hash[2:]>`) a virtual directory's
     * contents are actually stored under.
     */
    fun hashDirectoryId(cleartextDirectoryId: String): String {
        val cleartextBytes = cleartextDirectoryId.toByteArray(Charsets.UTF_8)
        val encKeySpec = SecretKeySpec(masterkey.encKey.encoded, "AES")
        val macKeySpec = SecretKeySpec(masterkey.macKey.encoded, "AES")
        val encrypted = siv.encrypt(encKeySpec, macKeySpec, cleartextBytes)
        val digest = MessageDigest.getInstance("SHA-1").digest(encrypted)
        return base32.encode(digest)
    }

    /** Encrypts a single cleartext path segment (not a full path) for storage as a `.c9r` file/folder name. */
    fun encryptFilename(cleartextName: String, vararg associatedData: ByteArray): String {
        val cleartextBytes = cleartextName.toByteArray(Charsets.UTF_8)
        val encKeySpec = SecretKeySpec(masterkey.encKey.encoded, "AES")
        val macKeySpec = SecretKeySpec(masterkey.macKey.encoded, "AES")
        val encrypted = siv.encrypt(encKeySpec, macKeySpec, cleartextBytes, *associatedData)
        return base64Url.encodeToString(encrypted)
    }

    /** Decrypts a `.c9r`-stripped ciphertext name back to its cleartext segment. */
    @Throws(CryptomatorAuthenticationException::class)
    fun decryptFilename(ciphertextName: String, vararg associatedData: ByteArray): String {
        return try {
            val encrypted = base64UrlDecoder.decode(padBase64(ciphertextName))
            val encKeySpec = SecretKeySpec(masterkey.encKey.encoded, "AES")
            val macKeySpec = SecretKeySpec(masterkey.macKey.encoded, "AES")
            val decrypted = siv.decrypt(encKeySpec, macKeySpec, encrypted, *associatedData)
            String(decrypted, Charsets.UTF_8)
        } catch (e: UnauthenticCiphertextException) {
            throw CryptomatorAuthenticationException("Filename decryption failed for '$ciphertextName' — wrong key or the vault's directory structure doesn't match this dirId (moved/corrupted?).")
        } catch (e: IllegalArgumentException) {
            throw CryptomatorAuthenticationException("Malformed ciphertext filename: '$ciphertextName'")
        }
    }

    private fun padBase64(s: String): String {
        val rem = s.length % 4
        return if (rem == 0) s else s + "=".repeat(4 - rem)
    }
}

/** RFC 4648 base32 (no padding), matching Guava's BaseEncoding.base32() used by cryptolib for dirId hashes. */
class Base32 {
    private val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    fun encode(data: ByteArray): String {
        if (data.isEmpty()) return ""
        val sb = StringBuilder((data.size * 8 + 4) / 5)
        var buffer = 0L
        var bitsLeft = 0
        for (b in data) {
            buffer = (buffer shl 8) or (b.toLong() and 0xFF)
            bitsLeft += 8
            while (bitsLeft >= 5) {
                bitsLeft -= 5
                val index = ((buffer shr bitsLeft) and 0x1F).toInt()
                sb.append(alphabet[index])
            }
        }
        if (bitsLeft > 0) {
            val index = ((buffer shl (5 - bitsLeft)) and 0x1F).toInt()
            sb.append(alphabet[index])
        }
        return sb.toString()
    }
}
