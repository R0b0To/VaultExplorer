package com.aeidolon.vaultexplorer.gocryptfs

import java.security.MessageDigest
import java.util.Base64

class GocryptfsNameException(message: String) : Exception(message)

class GocryptfsFileNameCryptor(
    nameKey: ByteArray,
    private val longNameMax: Int,
    private val plaintextNames: Boolean = false
) {
    private val eme = if (plaintextNames) null else GocryptfsEme(nameKey)
    private val b64 = Base64.getUrlEncoder().withoutPadding()
    private val b64Decoder = Base64.getUrlDecoder()

    companion object {
        const val LONGNAME_PREFIX = "gocryptfs.longname."
        const val LONGNAME_SUFFIX = ".name"
        const val DIRIV_FILENAME = "gocryptfs.diriv"
        private const val DEFAULT_LONGNAME_MAX = 255
    }

    val effectiveLongNameMax: Int get() = if (longNameMax > 0) longNameMax else DEFAULT_LONGNAME_MAX

    fun encryptName(plainName: String, dirIv: ByteArray): String {
        if (plaintextNames) return plainName
        val padded = pad16(plainName.toByteArray(Charsets.UTF_8))
        return b64.encodeToString(eme!!.encrypt(dirIv, padded))
    }

    fun decryptName(cipherName: String, dirIv: ByteArray): String {
        if (plaintextNames) return cipherName
        val raw = try {
            b64Decoder.decode(cipherName)
        } catch (e: IllegalArgumentException) {
            throw GocryptfsNameException("Malformed base64 filename: $cipherName")
        }
        if (raw.isEmpty() || raw.size % 16 != 0) {
            throw GocryptfsNameException("Malformed ciphertext filename: $cipherName")
        }
        val padded = eme!!.decrypt(dirIv, raw)
        val unpadded = unpad16(padded)
        val cleartext = String(unpadded, Charsets.UTF_8)

        // Strict validation: if decryption used the wrong diriv or ciphertext was corrupt,
        // it produces pseudo-random bytes that happen to pass PKCS#7.
        // A valid cleartext filename in gocryptfs MUST:
        // 1. Not contain null characters or replacement character \uFFFD (invalid UTF-8)
        // 2. Not contain path separators ('/') or control characters (\n, \r)
        // 3. Re-encode to the exact same bytes (ensures valid UTF-8 round-trip)
        if ((unpadded.isNotEmpty() && cleartext.isEmpty()) ||
            cleartext.contains('\uFFFD') ||
            cleartext.contains('/') ||
            cleartext.contains('\u0000') ||
            cleartext.contains('\n') ||
            cleartext.contains('\r') ||
            !cleartext.toByteArray(Charsets.UTF_8).contentEquals(unpadded)) {
            throw GocryptfsNameException("Invalid decrypted filename (corrupted ciphertext or wrong diriv): $cipherName")
        }
        return cleartext
    }

    fun hashLongName(cipherName: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(cipherName.toByteArray(Charsets.UTF_8))
        return LONGNAME_PREFIX + b64.encodeToString(digest)
    }

    fun isOverLongNameLimit(cipherName: String): Boolean {
        if (plaintextNames) return false
        return cipherName.length > effectiveLongNameMax
    }

    private fun pad16(data: ByteArray): ByteArray {
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
        if (padLen == 0 || padLen > 16 || padLen > padded.size) {
            throw GocryptfsNameException("invalid PKCS7 padding")
        }
        for (i in padded.size - padLen until padded.size) {
            if ((padded[i].toInt() and 0xFF) != padLen) throw GocryptfsNameException("invalid PKCS7 padding")
        }
        return padded.copyOf(padded.size - padLen)
    }
}