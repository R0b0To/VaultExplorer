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
}
