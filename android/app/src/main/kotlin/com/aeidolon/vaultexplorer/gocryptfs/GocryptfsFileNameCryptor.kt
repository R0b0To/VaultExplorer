package com.aeidolon.vaultexplorer.gocryptfs

import java.security.MessageDigest
import java.util.Base64

class GocryptfsNameException(message: String) : Exception(message)

/**
 * Mirrors CryptomatorFileNameCryptor's role: encrypt/decrypt one path
 * segment at a time, keyed off the *containing directory's* tweak (dirIV
 * here, vs. Cryptomator's dirId-derived associated data).
 */
class GocryptfsFileNameCryptor(nameKey: ByteArray, private val longNameMax: Int) {
    private val eme = GocryptfsEme(nameKey)
    private val b64 = Base64.getUrlEncoder().withoutPadding() // Raw64 flag
    private val b64Decoder = Base64.getUrlDecoder()

    companion object {
        const val LONGNAME_PREFIX = "gocryptfs.longname."
        const val LONGNAME_SUFFIX = ".name"
        const val DIRIV_FILENAME = "gocryptfs.diriv"
        private const val DEFAULT_LONGNAME_MAX = 255
    }

    private val effectiveLongNameMax get() = if (longNameMax > 0) longNameMax else DEFAULT_LONGNAME_MAX

    /** Returns the raw (unshortened) ciphertext name — caller decides whether
     *  to apply long-name shortening based on [effectiveLongNameMax]. */
    fun encryptName(plainName: String, dirIv: ByteArray): String {
        val padded = pad16(plainName.toByteArray(Charsets.UTF_8))
        return b64.encodeToString(eme.encrypt(dirIv, padded))
    }

    fun decryptName(cipherName: String, dirIv: ByteArray): String {
        val raw = try {
            b64Decoder.decode(cipherName)
        } catch (e: IllegalArgumentException) {
            throw GocryptfsNameException("Malformed base64 filename: $cipherName")
        }
        if (raw.isEmpty() || raw.size % 16 != 0) {
            throw GocryptfsNameException("Malformed ciphertext filename: $cipherName")
        }
        val padded = eme.decrypt(dirIv, raw)
        return String(unpad16(padded), Charsets.UTF_8)
    }

    /** "gocryptfs.longname.<sha256(cipherName)>" — matches HashLongName(). */
    fun hashLongName(cipherName: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(cipherName.toByteArray(Charsets.UTF_8))
        return LONGNAME_PREFIX + b64.encodeToString(digest)
    }

    fun isOverLongNameLimit(cipherName: String): Boolean = cipherName.length > effectiveLongNameMax

    // PKCS#7 padding to a 16-byte boundary (nametransform/pad16.go).
    private fun pad16(data: ByteArray): ByteArray {
        val padLen = 16 - (data.size % 16).let { if (it == 0) 16 else it }.let { 16 - it }
            .let { 16 - (data.size % 16) }.let { if (it == 0) 16 else it }
        // (kept intentionally explicit/verbose to match pad16.go 1:1 rather
        // than a "clever" one-liner, since off-by-one padding bugs here are
        // exactly as unforgiving as in EME.)
        val realPadLen = 16 - (data.size % 16)
        val out = ByteArray(data.size + realPadLen)
        System.arraycopy(data, 0, out, 0, data.size)
        val padByte = realPadLen.toByte()
        for (i in data.size until out.size) out[i] = padByte
        return out
    }

    private fun unpad16(padded: ByteArray): ByteArray {
        if (padded.isEmpty() || padded.size % 16 != 0) throw GocryptfsNameException("unaligned padded size")
        val padLen = padded[padded.size - 1].toInt() and 0xFF
        if (padLen == 0 || padLen > 16 || padLen >= padded.size) {
            throw GocryptfsNameException("invalid PKCS7 padding")
        }
        for (i in padded.size - padLen until padded.size) {
            if ((padded[i].toInt() and 0xFF) != padLen) throw GocryptfsNameException("invalid PKCS7 padding")
        }
        return padded.copyOf(padded.size - padLen)
    }
}