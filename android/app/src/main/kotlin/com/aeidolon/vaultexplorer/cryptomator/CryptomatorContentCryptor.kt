package com.aeidolon.vaultexplorer.cryptomator

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

class CryptomatorAuthenticationException(message: String) : Exception(message)

/**
 * A decrypted file header: a random per-file nonce plus a random per-file
 * content key. Every chunk of the file is encrypted with this content key,
 * bound to this header's nonce via AAD/MAC — so headers can't be swapped
 * between files without detection.
 */
class CryptomatorFileHeader(val nonce: ByteArray, val contentKey: ByteArray, var reserved: Long = -1L)

/**
 * Per-vault-format file content encryption. Two implementations:
 *  - [Gcm] for vault format 8 (cipherCombo "SIV_GCM")
 *  - [CtrHmac] for vault format 7 (cipherCombo "SIV_CTRMAC")
 *
 * Chunking: cleartext is split into 32 KiB chunks; each chunk is
 * independently encrypted/authenticated so random access (seek + read) never
 * requires decrypting the whole file — essential for readFileChunk()'s
 * offset/length contract.
 *
 * `masterkey` is threaded through every call (rather than cached on the
 * cryptor instance) because both [Gcm] and [CtrHmac] are stateless
 * singletons shared across every concurrently-open file/session — caching a
 * key on the instance would be a cross-vault data race.
 */
sealed interface CryptomatorContentCryptor {
    val headerSize: Int
    val cleartextChunkSize: Int
    val ciphertextChunkSize: Int

    fun createHeader(random: SecureRandom): CryptomatorFileHeader
    fun encryptHeader(header: CryptomatorFileHeader, masterkey: CryptomatorMasterkey, random: SecureRandom): ByteArray
    @Throws(CryptomatorAuthenticationException::class)
    fun decryptHeader(ciphertext: ByteArray, masterkey: CryptomatorMasterkey): CryptomatorFileHeader

    fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: CryptomatorFileHeader, masterkey: CryptomatorMasterkey, random: SecureRandom): ByteArray
    @Throws(CryptomatorAuthenticationException::class)
    fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: CryptomatorFileHeader, masterkey: CryptomatorMasterkey): ByteArray

    /** cleartext size -> ciphertext size (header + all full/partial chunks), matching ciphertextSize() in cryptolib. */
    fun ciphertextSize(cleartextSize: Long): Long {
        if (cleartextSize == 0L) return 0L
        val fullChunks = cleartextSize / cleartextChunkSize
        val remainder = cleartextSize % cleartextChunkSize
        var size = fullChunks * ciphertextChunkSize
        if (remainder > 0) size += remainder + (ciphertextChunkSize - cleartextChunkSize)
        return size
    }

    fun cleartextSize(ciphertextSize: Long): Long {
        if (ciphertextSize == 0L) return 0L
        val overheadPerChunk = ciphertextChunkSize - cleartextChunkSize
        val fullChunks = ciphertextSize / ciphertextChunkSize
        val remainder = ciphertextSize % ciphertextChunkSize
        var size = fullChunks * cleartextChunkSize
        if (remainder > 0) size += remainder - overheadPerChunk
        return size
    }

    companion object {
        fun forCipherCombo(cipherCombo: String): CryptomatorContentCryptor = when (cipherCombo) {
            "SIV_GCM" -> Gcm
            "SIV_CTRMAC" -> CtrHmac
            else -> throw VaultConfigException("Unsupported cipherCombo: $cipherCombo")
        }
    }

    /** Vault format 8: 12B nonce header, AES-GCM chunks (nonce||ciphertext||16B tag), AAD = chunk# || header nonce. */
    object Gcm : CryptomatorContentCryptor {
        private const val NONCE_LEN = 12
        private const val TAG_LEN = 16
        private const val CONTENT_KEY_LEN = 32
        private const val HEADER_RESERVED_LEN = 8
        override val headerSize = NONCE_LEN + (HEADER_RESERVED_LEN + CONTENT_KEY_LEN) + TAG_LEN // 12 + 40 + 16 = 68
        override val cleartextChunkSize = 32 * 1024
        override val ciphertextChunkSize = NONCE_LEN + cleartextChunkSize + TAG_LEN // 32780

        override fun createHeader(random: SecureRandom): CryptomatorFileHeader {
            val nonce = ByteArray(NONCE_LEN).also { random.nextBytes(it) }
            val contentKey = ByteArray(CONTENT_KEY_LEN).also { random.nextBytes(it) }
            return CryptomatorFileHeader(nonce, contentKey)
        }

        override fun encryptHeader(header: CryptomatorFileHeader, masterkey: CryptomatorMasterkey, random: SecureRandom): ByteArray {
            val payload = ByteBuffer.allocate(HEADER_RESERVED_LEN + CONTENT_KEY_LEN)
                .order(ByteOrder.BIG_ENDIAN)
                .putLong(header.reserved)
                .put(header.contentKey)
                .array()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, masterkey.encKey, GCMParameterSpec(TAG_LEN * 8, header.nonce))
            val encrypted = cipher.doFinal(payload)
            return header.nonce + encrypted
        }

        override fun decryptHeader(ciphertext: ByteArray, masterkey: CryptomatorMasterkey): CryptomatorFileHeader {
            if (ciphertext.size < headerSize) throw CryptomatorAuthenticationException("Truncated file header")
            val nonce = ciphertext.copyOfRange(0, NONCE_LEN)
            val payloadAndTag = ciphertext.copyOfRange(NONCE_LEN, headerSize)
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, masterkey.encKey, GCMParameterSpec(TAG_LEN * 8, nonce))
                val payload = cipher.doFinal(payloadAndTag)
                val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
                val reserved = buf.long
                val contentKey = ByteArray(CONTENT_KEY_LEN).also { buf.get(it) }
                return CryptomatorFileHeader(nonce, contentKey, reserved)
            } catch (e: AEADBadTagException) {
                throw CryptomatorAuthenticationException("File header tag mismatch — wrong key or corrupted file.")
            }
        }

        override fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: CryptomatorFileHeader, masterkey: CryptomatorMasterkey, random: SecureRandom): ByteArray {
            val nonce = ByteArray(NONCE_LEN).also { random.nextBytes(it) }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val key = SecretKeySpec(header.contentKey, "AES")
            cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_LEN * 8, nonce))
            cipher.updateAAD(bigEndianLong(chunkNumber))
            cipher.updateAAD(header.nonce)
            val encrypted = cipher.doFinal(cleartext)
            return nonce + encrypted
        }

        override fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: CryptomatorFileHeader, masterkey: CryptomatorMasterkey): ByteArray {
            if (ciphertext.size < NONCE_LEN + TAG_LEN) throw CryptomatorAuthenticationException("Truncated chunk")
            val nonce = ciphertext.copyOfRange(0, NONCE_LEN)
            val payloadAndTag = ciphertext.copyOfRange(NONCE_LEN, ciphertext.size)
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                val key = SecretKeySpec(header.contentKey, "AES")
                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_LEN * 8, nonce))
                cipher.updateAAD(bigEndianLong(chunkNumber))
                cipher.updateAAD(header.nonce)
                return cipher.doFinal(payloadAndTag)
            } catch (e: AEADBadTagException) {
                throw CryptomatorAuthenticationException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
            }
        }
    }

    /** Vault format 7: 16B nonce header, AES-CTR chunks + detached HMAC-SHA256 (nonce||ciphertext||32B mac), MAC keyed with the *vault's* macKey (not the per-file content key). */
    object CtrHmac : CryptomatorContentCryptor {
        private const val NONCE_LEN = 16
        private const val MAC_LEN = 32
        private const val CONTENT_KEY_LEN = 32
        private const val HEADER_RESERVED_LEN = 8
        override val headerSize = NONCE_LEN + (HEADER_RESERVED_LEN + CONTENT_KEY_LEN) + MAC_LEN // 16 + 40 + 32 = 88
        override val cleartextChunkSize = 32 * 1024
        override val ciphertextChunkSize = NONCE_LEN + cleartextChunkSize + MAC_LEN // 32848

        override fun createHeader(random: SecureRandom): CryptomatorFileHeader {
            val nonce = ByteArray(NONCE_LEN).also { random.nextBytes(it) }
            val contentKey = ByteArray(CONTENT_KEY_LEN).also { random.nextBytes(it) }
            return CryptomatorFileHeader(nonce, contentKey)
        }

        override fun encryptHeader(header: CryptomatorFileHeader, masterkey: CryptomatorMasterkey, random: SecureRandom): ByteArray {
            val payload = ByteBuffer.allocate(HEADER_RESERVED_LEN + CONTENT_KEY_LEN)
                .order(ByteOrder.BIG_ENDIAN)
                .putLong(header.reserved)
                .put(header.contentKey)
                .array()
            val cipher = Cipher.getInstance("AES/CTR/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, masterkey.encKey, IvParameterSpec(header.nonce))
            val encryptedPayload = cipher.doFinal(payload)

            val nonceAndCiphertext = header.nonce + encryptedPayload
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(masterkey.macKey)
            val tag = mac.doFinal(nonceAndCiphertext)
            return nonceAndCiphertext + tag
        }

        override fun decryptHeader(ciphertext: ByteArray, masterkey: CryptomatorMasterkey): CryptomatorFileHeader {
            if (ciphertext.size < headerSize) throw CryptomatorAuthenticationException("Truncated file header")
            val nonce = ciphertext.copyOfRange(0, NONCE_LEN)
            val encryptedPayload = ciphertext.copyOfRange(NONCE_LEN, NONCE_LEN + HEADER_RESERVED_LEN + CONTENT_KEY_LEN)
            val expectedMac = ciphertext.copyOfRange(NONCE_LEN + HEADER_RESERVED_LEN + CONTENT_KEY_LEN, headerSize)

            val mac = Mac.getInstance("HmacSHA256")
            mac.init(masterkey.macKey)
            val actualMac = mac.doFinal(nonce + encryptedPayload)
            if (!MessageDigest.isEqual(expectedMac, actualMac)) {
                throw CryptomatorAuthenticationException("File header MAC mismatch — wrong key or corrupted file.")
            }

            val cipher = Cipher.getInstance("AES/CTR/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, masterkey.encKey, IvParameterSpec(nonce))
            val payload = cipher.doFinal(encryptedPayload)
            val buf = ByteBuffer.wrap(payload).order(ByteOrder.BIG_ENDIAN)
            val reserved = buf.long
            val contentKey = ByteArray(CONTENT_KEY_LEN).also { buf.get(it) }
            return CryptomatorFileHeader(nonce, contentKey, reserved)
        }

        override fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: CryptomatorFileHeader, masterkey: CryptomatorMasterkey, random: SecureRandom): ByteArray {
            val nonce = ByteArray(NONCE_LEN).also { random.nextBytes(it) }
            val cipher = Cipher.getInstance("AES/CTR/NoPadding")
            val key = SecretKeySpec(header.contentKey, "AES")
            cipher.init(Cipher.ENCRYPT_MODE, key, IvParameterSpec(nonce))
            val ciphertext = cipher.doFinal(cleartext)
            val nonceAndCiphertext = nonce + ciphertext
            val tag = calcChunkMac(masterkey.macKey.encoded, header.nonce, chunkNumber, nonceAndCiphertext)
            return nonceAndCiphertext + tag
        }

        override fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: CryptomatorFileHeader, masterkey: CryptomatorMasterkey): ByteArray {
            if (ciphertext.size < NONCE_LEN + MAC_LEN) throw CryptomatorAuthenticationException("Truncated chunk")
            val nonce = ciphertext.copyOfRange(0, NONCE_LEN)
            val nonceAndCiphertext = ciphertext.copyOfRange(0, ciphertext.size - MAC_LEN)
            val expectedMac = ciphertext.copyOfRange(ciphertext.size - MAC_LEN, ciphertext.size)
            val actualMac = calcChunkMac(masterkey.macKey.encoded, header.nonce, chunkNumber, nonceAndCiphertext)
            if (!MessageDigest.isEqual(expectedMac, actualMac)) {
                throw CryptomatorAuthenticationException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
            }
            val encPayload = nonceAndCiphertext.copyOfRange(NONCE_LEN, nonceAndCiphertext.size)
            val cipher = Cipher.getInstance("AES/CTR/NoPadding")
            val key = SecretKeySpec(header.contentKey, "AES")
            cipher.init(Cipher.DECRYPT_MODE, key, IvParameterSpec(nonce))
            return cipher.doFinal(encPayload)
        }

        private fun calcChunkMac(macKeyBytes: ByteArray, headerNonce: ByteArray, chunkNumber: Long, nonceAndCiphertext: ByteArray): ByteArray {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(macKeyBytes, "HmacSHA256"))
            mac.update(headerNonce)
            mac.update(bigEndianLong(chunkNumber))
            mac.update(nonceAndCiphertext)
            return mac.doFinal()
        }
    }
}

private fun bigEndianLong(n: Long): ByteArray =
    ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(n).array()