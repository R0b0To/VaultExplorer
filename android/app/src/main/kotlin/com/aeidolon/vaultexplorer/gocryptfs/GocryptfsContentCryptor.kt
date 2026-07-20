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
 * Mirrors CryptomatorContentCryptor.Gcm: header + per-chunk AES-GCM with
 * blockNo/fileID as associated data. Values below come straight from
 * contentenc/content.go + file_header.go's constants (HeaderLen=18,
 * DefaultBS=4096, GCMIV128 => 16-byte nonce, 16-byte tag).
 */
class GocryptfsContentCryptor(private val contentKey: ByteArray) {
    companion object {
        const val HEADER_LEN = 2 + 16 // version(2) + fileID(16)
        const val CLEARTEXT_CHUNK_SIZE = 4096
        private const val NONCE_LEN = 16
        private const val TAG_LEN = 16
        const val CIPHERTEXT_CHUNK_SIZE = NONCE_LEN + CLEARTEXT_CHUNK_SIZE + TAG_LEN // 4128
        private const val VERSION: Short = 2
    }

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
        val nonce = ByteArray(NONCE_LEN).also { random.nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(contentKey, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
        cipher.updateAAD(concatAd(chunkNumber, header.fileId))
        return nonce + cipher.doFinal(cleartext)
    }

    @Throws(GocryptfsContentAuthException::class)
    fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        if (ciphertext.size < NONCE_LEN + TAG_LEN) throw GocryptfsContentAuthException("Truncated chunk")
        // All-zero chunk => sparse-file hole => all-zero cleartext (content.go's fast path).
        if (ciphertext.all { it == 0.toByte() }) return ByteArray(CLEARTEXT_CHUNK_SIZE)

        val nonce = ciphertext.copyOfRange(0, NONCE_LEN)
        if (nonce.all { it == 0.toByte() }) throw GocryptfsContentAuthException("all-zero nonce")
        val payloadAndTag = ciphertext.copyOfRange(NONCE_LEN, ciphertext.size)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(contentKey, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
            cipher.updateAAD(concatAd(chunkNumber, header.fileId))
            return cipher.doFinal(payloadAndTag)
        } catch (e: AEADBadTagException) {
            throw GocryptfsContentAuthException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
        }
    }

    fun cleartextSize(ciphertextSize: Long): Long {
        if (ciphertextSize <= HEADER_LEN) return 0L
        val body = ciphertextSize - HEADER_LEN 
        val fullChunks = body / CIPHERTEXT_CHUNK_SIZE
        val remainder = body % CIPHERTEXT_CHUNK_SIZE
        var size = fullChunks * CLEARTEXT_CHUNK_SIZE
        if (remainder > 0) size += remainder - (NONCE_LEN + TAG_LEN)
        return size
    }

    private fun concatAd(chunkNumber: Long, fileId: ByteArray): ByteArray =
        ByteBuffer.allocate(8 + 16).order(ByteOrder.BIG_ENDIAN)
            .putLong(chunkNumber).put(fileId).array()
}