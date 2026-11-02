package com.aeidolon.vaultexplorer.gocryptfs

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import com.aeidolon.vaultexplorer.crypto.ChaCha20Poly1305
import com.aeidolon.vaultexplorer.cryptomator.SivMode
import com.aeidolon.vaultexplorer.cryptomator.UnauthenticCiphertextException

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

    private val nonceLen: Int = cipher.nonceLen

    init {
        // AES-SIV needs 64 bytes (two AES-256 keys); handing it the 32 bytes
        // the other ciphers use would otherwise only surface as a confusing
        // key-size error deep inside the first chunk operation.
        require(contentKey.size == cipher.contentKeyLen) {
            "$cipher content key must be ${cipher.contentKeyLen} bytes, was ${contentKey.size}"
        }
    }

    val ciphertextChunkSize: Int get() = nonceLen + CLEARTEXT_CHUNK_SIZE + TAG_LEN

    // ---- AES-SIV (RFC 5297) ------------------------------------------------
    //
    // gocryptfs's siv_aead wraps a 64-byte SIV key as a cipher.AEAD:
    //   * key split (RFC 5297 section 2.2): the LEFT 32 bytes are K1 (the S2V /
    //     AES-CMAC key), the RIGHT 32 bytes are K2 (the AES-CTR key). SivMode
    //     takes them as (encKey = CTR, macKey = S2V), hence the swap below.
    //   * associated data = [ 24-byte block AAD (blockNo | fileId), 16-byte
    //     nonce ], in that order -- RFC 5297 section 3's nonce-based AEAD use.
    //   * Seal output = SIV tag (16) | ciphertext, and the on-disk block is
    //     nonce | that, i.e. nonce(16) | tag(16) | ciphertext.
    // Reusing SivMode (rather than a second SIV) keeps the native
    // sivEncryptNative/sivDecryptNative fast path and the JCE-only fallback
    // that Cryptomator already relies on.
    private class SivKeys(val mac: SecretKeySpec, val enc: SecretKeySpec)

    private val sivMode: SivMode? = if (cipher == GocryptfsCipher.AES_SIV) SivMode() else null
    private val sivKeys: SivKeys? = if (cipher == GocryptfsCipher.AES_SIV) {
        val half = contentKey.size / 2
        SivKeys(
            mac = SecretKeySpec(contentKey, 0, half, "AES"),
            enc = SecretKeySpec(contentKey, half, half, "AES"),
        )
    } else null

    /** Marks the AEAD `when` branches that the early AES-SIV dispatch makes unreachable. */
    private fun sivHandledSeparately(): Nothing =
        throw IllegalStateException("AES-SIV chunks are handled by the SIV path, not the AEAD path")

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
        if (cipher == GocryptfsCipher.AES_SIV) return sivEncryptChunk(cleartext, aad)
        if (com.aeidolon.vaultexplorer.NativeEngine.isLoaded) {
            val nativeResult = when (cipher) {
                GocryptfsCipher.AES_256_GCM ->
                    com.aeidolon.vaultexplorer.NativeEngine.aesGcmEncryptFastNative(contentKey, nonceLen, aad, cleartext)
                GocryptfsCipher.XCHACHA20_POLY1305 -> {
                    val nonce = ByteArray(nonceLen).also { random.nextBytes(it) }
                    val ciphertextAndTag = com.aeidolon.vaultexplorer.NativeEngine.xchacha20Poly1305SealNative(contentKey, nonce, aad, cleartext)
                    ciphertextAndTag?.let { nonce + it }
                }
                GocryptfsCipher.AES_SIV -> sivHandledSeparately()
            }
            if (nativeResult != null) return nativeResult
        }
        val nonce = ByteArray(nonceLen).also { random.nextBytes(it) }
        return when (cipher) {
            GocryptfsCipher.AES_256_GCM -> {
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(contentKey, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
                c.updateAAD(aad)
                nonce + c.doFinal(cleartext)
            }
            GocryptfsCipher.XCHACHA20_POLY1305 -> {
                val ciphertextAndTag = ChaCha20Poly1305.xchacha20Poly1305Seal(contentKey, nonce, aad, cleartext)
                nonce + ciphertextAndTag
            }
            GocryptfsCipher.AES_SIV -> sivHandledSeparately()
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
        val nonce = ciphertext.copyOfRange(0, nonceLen)
        if (nonce.all { it == 0.toByte() }) throw GocryptfsContentAuthException("all-zero nonce")

        val aad = getAad(chunkNumber, header.fileId)
        if (cipher == GocryptfsCipher.AES_SIV) return sivDecryptChunk(ciphertext, nonce, aad, chunkNumber)
        if (com.aeidolon.vaultexplorer.NativeEngine.isLoaded) {
            val nativeResult = when (cipher) {
                GocryptfsCipher.AES_256_GCM ->
                    com.aeidolon.vaultexplorer.NativeEngine.aesGcmDecryptFastNative(contentKey, nonceLen, aad, ciphertext)
                GocryptfsCipher.XCHACHA20_POLY1305 -> {
                    val payloadAndTag = ciphertext.copyOfRange(nonceLen, ciphertext.size)
                    com.aeidolon.vaultexplorer.NativeEngine.xchacha20Poly1305OpenNative(contentKey, nonce, aad, payloadAndTag)
                }
                GocryptfsCipher.AES_SIV -> sivHandledSeparately()
            }
            if (nativeResult != null) return nativeResult
            throw GocryptfsContentAuthException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
        }

        val payloadAndTag = ciphertext.copyOfRange(nonceLen, ciphertext.size)
        return when (cipher) {
            GocryptfsCipher.AES_256_GCM -> try {
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.DECRYPT_MODE, SecretKeySpec(contentKey, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
                c.updateAAD(aad)
                c.doFinal(payloadAndTag)
            } catch (e: Exception) {
                throw GocryptfsContentAuthException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
            }
            GocryptfsCipher.XCHACHA20_POLY1305 -> {
                ChaCha20Poly1305.xchacha20Poly1305Open(contentKey, nonce, aad, payloadAndTag)
                    ?: throw GocryptfsContentAuthException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
            }
            GocryptfsCipher.AES_SIV -> sivHandledSeparately()
        }
    }

    private fun sivEncryptChunk(cleartext: ByteArray, aad: ByteArray): ByteArray {
        val keys = sivKeys!!
        val nonce = ByteArray(nonceLen).also { random.nextBytes(it) }
        // AD order matters: [blockNo|fileId, nonce] -- see the AES-SIV notes above.
        return nonce + sivMode!!.encrypt(keys.enc, keys.mac, cleartext, aad, nonce)
    }

    private fun sivDecryptChunk(ciphertext: ByteArray, nonce: ByteArray, aad: ByteArray, chunkNumber: Long): ByteArray {
        val keys = sivKeys!!
        val sivAndPayload = ciphertext.copyOfRange(nonceLen, ciphertext.size)
        return try {
            sivMode!!.decrypt(keys.enc, keys.mac, sivAndPayload, aad, nonce)
        } catch (e: UnauthenticCiphertextException) {
            throw GocryptfsContentAuthException("Chunk $chunkNumber authentication failed — wrong key or corrupted/tampered file.")
        }
    }

    // Both XChaCha20 and AES-GCM now route natively through the BoringSSL stream bridge.
    // The C++ layer automatically switches between AES-GCM and XChaCha20 based on the nonceLen!
    //
    // AES-SIV must NOT go through that bridge: its nonce is also 16 bytes, so the
    // native side would silently pick AES-GCM -- writing GCM blocks into an SIV
    // vault (unreadable by gocryptfs) or failing every read. SIV has no native
    // stream path, so it runs the per-chunk SIV path below, which also keeps the
    // sparse-hole shortcut in decryptChunk for reads.
    fun encryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        if (cipher == GocryptfsCipher.AES_SIV) return sivEncryptStream(inputBuffer, startChunkNumber, header)
        return com.aeidolon.vaultexplorer.NativeEngine.aesGcmEncryptStreamNative(
            contentKey, nonceLen, CLEARTEXT_CHUNK_SIZE, header.fileId, startChunkNumber, inputBuffer
        ) ?: throw GocryptfsContentAuthException("Bulk stream encryption failed")
    }

    fun decryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        if (cipher == GocryptfsCipher.AES_SIV) return sivDecryptStream(inputBuffer, startChunkNumber, header)
        return com.aeidolon.vaultexplorer.NativeEngine.aesGcmDecryptStreamNative(
            contentKey, nonceLen, CLEARTEXT_CHUNK_SIZE, header.fileId, startChunkNumber, inputBuffer
        ) ?: throw GocryptfsContentAuthException("Bulk stream decryption failed")
    }

    private fun sivEncryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        val fullChunks = inputBuffer.size / CLEARTEXT_CHUNK_SIZE
        val partialLen = inputBuffer.size % CLEARTEXT_CHUNK_SIZE
        val out = ByteArray(fullChunks * ciphertextChunkSize + if (partialLen > 0) nonceLen + partialLen + TAG_LEN else 0)
        var inOffset = 0
        var outOffset = 0
        var chunkNumber = startChunkNumber
        while (inOffset < inputBuffer.size) {
            val len = minOf(CLEARTEXT_CHUNK_SIZE, inputBuffer.size - inOffset)
            val sealed = encryptChunk(inputBuffer.copyOfRange(inOffset, inOffset + len), chunkNumber, header)
            System.arraycopy(sealed, 0, out, outOffset, sealed.size)
            inOffset += len
            outOffset += sealed.size
            chunkNumber++
        }
        return out
    }

    private fun sivDecryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: GocryptfsFileHeader): ByteArray {
        val fullChunks = inputBuffer.size / ciphertextChunkSize
        val partialCtLen = inputBuffer.size % ciphertextChunkSize
        // A trailing fragment shorter than nonce+tag can't hold even an empty chunk.
        if (partialCtLen in 1 until nonceLen + TAG_LEN) throw GocryptfsContentAuthException("Truncated chunk")
        val out = ByteArray(fullChunks * CLEARTEXT_CHUNK_SIZE + if (partialCtLen > 0) partialCtLen - (nonceLen + TAG_LEN) else 0)
        var inOffset = 0
        var outOffset = 0
        var chunkNumber = startChunkNumber
        while (inOffset < inputBuffer.size) {
            val len = minOf(ciphertextChunkSize, inputBuffer.size - inOffset)
            val opened = decryptChunk(inputBuffer.copyOfRange(inOffset, inOffset + len), chunkNumber, header)
            System.arraycopy(opened, 0, out, outOffset, opened.size)
            inOffset += len
            outOffset += opened.size
            chunkNumber++
        }
        return out
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