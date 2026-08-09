package com.aeidolon.vaultexplorer.gocryptfs

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class GocryptfsContentAuthException(message: String) : Exception(message)

class GocryptfsFileHeader(val fileId: ByteArray) {
    init { require(fileId.size == 16) }
}

/**
 * Mirrors CryptomatorContentCryptor.Gcm: header + per-chunk AEAD with
 * blockNo/fileID as associated data. Values below come straight from
 * contentenc/content.go + file_header.go's constants (HeaderLen=18,
 * DefaultBS=4096). Nonce/tag are both 16 bytes for GCMIV128 (AES-256-GCM);
 * XChaCha20Poly1305 keeps the 16-byte tag but uses a 24-byte nonce instead
 * (its wider 192-bit nonce is the whole point of the cipher — safe to pick
 * randomly per chunk without gocryptfs's GCM-specific nonce-reuse mitigations).
 * The two are mutually exclusive per vault (GocryptfsConfig.cipher), so this
 * class is constructed with one fixed cipher for the vault's lifetime.
 */
class GocryptfsContentCryptor(
    private val contentKey: ByteArray,
    private val cipher: GocryptfsCipher = GocryptfsCipher.AES_256_GCM,
) {
    companion object {
        const val HEADER_LEN = 2 + 16 // version(2) + fileID(16)
        const val CLEARTEXT_CHUNK_SIZE = 4096
        private const val TAG_LEN = 16
        private const val VERSION: Short = 2
        // Retained for the AES-256-GCM default (16-byte nonce) -- most call
        // sites now go through the cipher-aware instance property
        // [ciphertextChunkSize] below, since XChaCha20Poly1305 uses a
        // 24-byte nonce and can't be expressed as a single constant.
        const val CIPHERTEXT_CHUNK_SIZE = 16 + CLEARTEXT_CHUNK_SIZE + TAG_LEN // 4128
    }

    private val nonceLen: Int = when (cipher) {
        GocryptfsCipher.AES_256_GCM -> 16
        GocryptfsCipher.XCHACHA20_POLY1305 -> 24
    }

    /** Cipher-dependent ciphertext chunk size — use this (not the
     *  AES-GCM-only companion constant) wherever a specific vault's chunk
     *  layout matters, e.g. GocryptfsSession's chunkCryptor. */
    val ciphertextChunkSize: Int get() = nonceLen + CLEARTEXT_CHUNK_SIZE + TAG_LEN

    private val random = SecureRandom()

    fun createHeader(): GocryptfsFileHeader {
        val fileId = ByteArray(16).also { random.nextBytes(it) }
        return GocryptfsFileHeader(fileId)
    }

    fun encodeHeader(header: GocryptfsFileHeader): ByteArray =
        ByteBuffer.allocate(HEADER_LEN).order(ByteOrder.BIG_ENDIAN)
            .putShort(VERSION).put(header.fileId).array()

    @Throws(GocryptfsContentAuthException::class)
    fun decodeHeader(bytes: ByteArray): GocryptfsFileHeader {
        if (bytes.size < HEADER_LEN) throw GocryptfsContentAuthException("Truncated file header")
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        val version = buf.short
        if (version != VERSION) throw GocryptfsContentAuthException("Unsupported file format version $version")
        val fileId = ByteArray(16).also { buf.get(it) }
        return GocryptfsFileHeader(fileId)
    }

    fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        val nonce = ByteArray(nonceLen).also { random.nextBytes(it) }
        val aad = concatAd(chunkNumber, header.fileId)
        val ciphertextAndTag = when (cipher) {
            GocryptfsCipher.AES_256_GCM -> {
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(contentKey, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
                c.updateAAD(aad)
                c.doFinal(cleartext)
            }
            GocryptfsCipher.XCHACHA20_POLY1305 ->
                com.aeidolon.vaultexplorer.NativeEngine.xchacha20Poly1305SealNative(contentKey, nonce, aad, cleartext)
                    ?: throw GocryptfsContentAuthException("XChaCha20-Poly1305 encryption failed")
        }
        return nonce + ciphertextAndTag
    }

    @Throws(GocryptfsContentAuthException::class)
    fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        if (ciphertext.size < nonceLen + TAG_LEN) throw GocryptfsContentAuthException("Truncated chunk")
        // All-zero chunk => sparse-file hole => all-zero cleartext (content.go's fast path).
        if (ciphertext.all { it == 0.toByte() }) return ByteArray(CLEARTEXT_CHUNK_SIZE)

        val nonce = ciphertext.copyOfRange(0, nonceLen)
        if (nonce.all { it == 0.toByte() }) throw GocryptfsContentAuthException("all-zero nonce")
        val payloadAndTag = ciphertext.copyOfRange(nonceLen, ciphertext.size)
        val aad = concatAd(chunkNumber, header.fileId)
        return when (cipher) {
            GocryptfsCipher.AES_256_GCM -> try {
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.DECRYPT_MODE, SecretKeySpec(contentKey, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
                c.updateAAD(aad)
                c.doFinal(payloadAndTag)
            } catch (e: AEADBadTagException) {
                throw GocryptfsContentAuthException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
            }
            GocryptfsCipher.XCHACHA20_POLY1305 ->
                com.aeidolon.vaultexplorer.NativeEngine.xchacha20Poly1305OpenNative(contentKey, nonce, aad, payloadAndTag)
                    ?: throw GocryptfsContentAuthException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
        }
    }

    fun cleartextSize(ciphertextSize: Long): Long {
        if (ciphertextSize <= HEADER_LEN) return 0L
        val body = ciphertextSize - HEADER_LEN
        val fullChunks = body / ciphertextChunkSize
        val remainder = body % ciphertextChunkSize
        var size = fullChunks * CLEARTEXT_CHUNK_SIZE
        if (remainder > 0) size += remainder - (nonceLen + TAG_LEN)
        return size
    }

    private fun concatAd(chunkNumber: Long, fileId: ByteArray): ByteArray =
        ByteBuffer.allocate(8 + 16).order(ByteOrder.BIG_ENDIAN)
            .putLong(chunkNumber).put(fileId).array()
}