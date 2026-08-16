package com.aeidolon.vaultexplorer.gocryptfs

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom

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

    private val tlsAad = object : ThreadLocal<ByteArray>() {
        override fun initialValue() = ByteArray(24)
    }

    private fun getAad(chunkNumber: Long, fileId: ByteArray): ByteArray {
        val aad = tlsAad.get()!!
        aad[0] = (chunkNumber ushr 56).toByte()
        aad[1] = (chunkNumber ushr 48).toByte()
        aad[2] = (chunkNumber ushr 40).toByte()
        aad[3] = (chunkNumber ushr 32).toByte()
        aad[4] = (chunkNumber ushr 24).toByte()
        aad[5] = (chunkNumber ushr 16).toByte()
        aad[6] = (chunkNumber ushr 8).toByte()
        aad[7] = chunkNumber.toByte()
        System.arraycopy(fileId, 0, aad, 8, 16)
        return aad
    }

    fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        val aad = getAad(chunkNumber, header.fileId)
        return when (cipher) {
            GocryptfsCipher.AES_256_GCM ->
                com.aeidolon.vaultexplorer.NativeEngine.aesGcmEncryptFastNative(contentKey, nonceLen, aad, cleartext)
                    ?: throw GocryptfsContentAuthException("AES-GCM encryption failed")
            GocryptfsCipher.XCHACHA20_POLY1305 -> {
                val nonce = ByteArray(nonceLen).also { random.nextBytes(it) }
                val ciphertextAndTag = com.aeidolon.vaultexplorer.NativeEngine.xchacha20Poly1305SealNative(contentKey, nonce, aad, cleartext)
                    ?: throw GocryptfsContentAuthException("XChaCha20-Poly1305 encryption failed")
                nonce + ciphertextAndTag
            }
        }
    }

    @Throws(GocryptfsContentAuthException::class)
    fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        if (ciphertext.size < nonceLen + TAG_LEN) throw GocryptfsContentAuthException("Truncated chunk")
        // Sparse-file hole shortcut (contentenc.go: bytes.Equal(ciphertext,
        // be.allZeroBlock)): the reference only takes this path for a
        // *full-size* block. A short final chunk that happens to be all
        // zero still needs a length check here too, or it would spuriously
        // match a differently-sized comparison than upstream ever makes.
        if (ciphertext.size == ciphertextChunkSize && ciphertext.all { it == 0.toByte() }) {
            return ByteArray(CLEARTEXT_CHUNK_SIZE)
        }
        val aad = getAad(chunkNumber, header.fileId)
        return when (cipher) {
            GocryptfsCipher.AES_256_GCM ->
                com.aeidolon.vaultexplorer.NativeEngine.aesGcmDecryptFastNative(contentKey, nonceLen, aad, ciphertext)
                    ?: throw GocryptfsContentAuthException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
            GocryptfsCipher.XCHACHA20_POLY1305 -> {
                val nonce = ciphertext.copyOfRange(0, nonceLen)
                val payloadAndTag = ciphertext.copyOfRange(nonceLen, ciphertext.size)
                com.aeidolon.vaultexplorer.NativeEngine.xchacha20Poly1305OpenNative(contentKey, nonce, aad, payloadAndTag)
                    ?: throw GocryptfsContentAuthException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
            }
        }
    }

    // Both XChaCha20 and AES-GCM now route natively through the BoringSSL stream bridge.
    // The C++ layer automatically switches between AES-GCM and XChaCha20 based on the nonceLen!
    fun encryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        return com.aeidolon.vaultexplorer.NativeEngine.aesGcmEncryptStreamNative(
            contentKey, nonceLen, CLEARTEXT_CHUNK_SIZE, header.fileId, startChunkNumber, inputBuffer
        ) ?: throw GocryptfsContentAuthException("Bulk stream encryption failed")
    }

    fun decryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        return com.aeidolon.vaultexplorer.NativeEngine.aesGcmDecryptStreamNative(
            contentKey, nonceLen, CLEARTEXT_CHUNK_SIZE, header.fileId, startChunkNumber, inputBuffer
        ) ?: throw GocryptfsContentAuthException("Bulk stream decryption failed")
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
}