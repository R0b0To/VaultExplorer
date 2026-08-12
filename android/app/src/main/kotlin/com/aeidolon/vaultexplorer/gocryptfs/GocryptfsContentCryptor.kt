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

class GocryptfsContentCryptor(
    private val contentKey: ByteArray,
    private val cipher: GocryptfsCipher = GocryptfsCipher.AES_256_GCM,
) {
    companion object {
        const val HEADER_LEN = 2 + 16
        const val CLEARTEXT_CHUNK_SIZE = 4096
        private const val TAG_LEN = 16
        private const val VERSION: Short = 2
    }

    private val nonceLen: Int = when (cipher) {
        GocryptfsCipher.AES_256_GCM -> 16
        GocryptfsCipher.AES_256_GCM_IV96 -> 12
        GocryptfsCipher.XCHACHA20_POLY1305 -> 24
    }

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
            GocryptfsCipher.AES_256_GCM, GocryptfsCipher.AES_256_GCM_IV96 -> {
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
        if (ciphertext.all { it == 0.toByte() }) return ByteArray(CLEARTEXT_CHUNK_SIZE)

        val nonce = ciphertext.copyOfRange(0, nonceLen)
        if (nonce.all { it == 0.toByte() }) throw GocryptfsContentAuthException("all-zero nonce")

        val payloadAndTag = ciphertext.copyOfRange(nonceLen, ciphertext.size)
        val aad = concatAd(chunkNumber, header.fileId)

        return when (cipher) {
            GocryptfsCipher.AES_256_GCM, GocryptfsCipher.AES_256_GCM_IV96 -> try {
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