package com.aeidolon.vaultexplorer.engine

/**
 * Common adapter interface for vault content cryptors (e.g. CryptomatorContentCryptor
 * and GocryptfsContentCryptor). This allows [ChunkedFileEngine] to handle
 * the read/write buffering and temp-file streaming agnostically.
 */
interface VaultChunkCryptor<H> {
    val headerSize: Int
    val cleartextChunkSize: Int
    val ciphertextChunkSize: Int
    fun createHeader(): H
    fun encodeHeader(header: H): ByteArray
    fun decodeHeader(bytes: ByteArray): H
    fun encryptChunk(cleartext: ByteArray, chunkNumber: Long, header: H): ByteArray
    fun decryptChunk(ciphertext: ByteArray, chunkNumber: Long, header: H): ByteArray

    // Fast multi-chunk stream encryption (default fallback loop if not overridden)
    fun encryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: H): ByteArray {
        val chunkSize = cleartextChunkSize
        val baos = java.io.ByteArrayOutputStream(inputBuffer.size)
        var offset = 0
        var cNum = startChunkNumber
        while (offset < inputBuffer.size) {
            val len = minOf(chunkSize, inputBuffer.size - offset)
            val chunk = inputBuffer.copyOfRange(offset, offset + len)
            baos.write(encryptChunk(chunk, cNum, header))
            cNum += 1
            offset += len
        }
        return baos.toByteArray()
    }

    // Fast multi-chunk stream decryption (default fallback loop if not overridden)
    fun decryptStream(inputBuffer: ByteArray, startChunkNumber: Long, header: H): ByteArray {
        val ctChunkSize = ciphertextChunkSize
        val baos = java.io.ByteArrayOutputStream(inputBuffer.size)
        var offset = 0
        var cNum = startChunkNumber
        while (offset < inputBuffer.size) {
            val len = minOf(ctChunkSize, inputBuffer.size - offset)
            val chunk = inputBuffer.copyOfRange(offset, offset + len)
            baos.write(decryptChunk(chunk, cNum, header))
            cNum += 1
            offset += len
        }
        return baos.toByteArray()
    }
}