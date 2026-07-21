package com.aeidolon.vaultexplorer.crypto

/**
 * Doubles a 128-bit block in GF(2^128) under the standard AES/XTS/EME/SIV
 * reduction polynomial x^128 + x^7 + x^2 + x + 1 (0x87).
 *
 * Extracted from [com.aeidolon.vaultexplorer.cryptomator.SivMode]'s private
 * `dbl()`. Note that while SIV and EME both perform GF(2^128) doubling
 * with the same 0x87 polynomial, they use opposite byte-endianness:
 * SIV treats blocks as big-endian (this function), while EME treats them
 * as little-endian (see [com.aeidolon.vaultexplorer.gocryptfs.GocryptfsEme.multByTwo]).
 * Thus, they cannot share a single doubling implementation.
 */
fun gf128Double(block: ByteArray): ByteArray {
    require(block.size == 16)
    val result = ByteArray(16)
    var carry = 0
    for (i in 15 downTo 0) {
        val b = block[i].toInt() and 0xFF
        result[i] = ((b shl 1) or carry).toByte()
        carry = (b shr 7) and 1
    }
    if ((block[0].toInt() and 0x80) != 0) {
        result[15] = (result[15].toInt() xor 0x87).toByte()
    }
    return result
}