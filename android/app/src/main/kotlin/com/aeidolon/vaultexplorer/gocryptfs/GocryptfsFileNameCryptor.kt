package com.aeidolon.vaultexplorer.gocryptfs

import java.security.MessageDigest
import java.util.Base64

class GocryptfsNameException(message: String) : Exception(message)

class GocryptfsFileNameCryptor(
    nameKey: ByteArray,
    private val longNameMax: Int,
    private val plaintextNames: Boolean = false,
    // Raw64: unpadded base64. Vaults from gocryptfs <= 1.6 use padded base64 for names *and* long-name hashes.
    raw64: Boolean = true,
) {
    private val eme = if (plaintextNames) null else GocryptfsEme(nameKey)
    private val b64 = if (raw64) Base64.getUrlEncoder().withoutPadding() else Base64.getUrlEncoder()
    private val b64Decoder = Base64.getUrlDecoder()

    companion object {
        const val LONGNAME_PREFIX = "gocryptfs.longname."
        const val LONGNAME_SUFFIX = ".name"
        const val DIRIV_FILENAME = "gocryptfs.diriv"
        private const val DEFAULT_LONGNAME_MAX = 255
        private const val NAME_MAX = 255

        /**
         * nametransform.IsValidName: non-empty, at most 255 bytes, no NUL or '/', not "." or "..". (gocryptfs
         * allows newlines and U+FFFD in names; so do we.)
         */
        fun isValidName(name: ByteArray): Boolean {
            if (name.isEmpty() || name.size > NAME_MAX) return false
            if (name.any { it == 0.toByte() || it == '/'.code.toByte() }) return false
            if (name.size == 1 && name[0] == '.'.code.toByte()) return false
            if (name.size == 2 && name[0] == '.'.code.toByte() && name[1] == '.'.code.toByte()) return false
            return true
        }
    }

    val effectiveLongNameMax: Int get() = if (longNameMax > 0) longNameMax else DEFAULT_LONGNAME_MAX

    fun encryptName(plainName: String, dirIv: ByteArray): String {
        if (plaintextNames) return plainName
        val bytes = plainName.toByteArray(Charsets.UTF_8)
        if (!isValidName(bytes)) throw GocryptfsNameException("Invalid file name")
        val padded = pad16(bytes)
        return b64.encodeToString(eme!!.encrypt(dirIv, padded))
    }

    fun decryptName(cipherName: String, dirIv: ByteArray): String {
        if (plaintextNames) return cipherName
        val raw = try {
            b64Decoder.decode(cipherName)
        } catch (e: IllegalArgumentException) {
            throw GocryptfsNameException("Malformed base64 filename: $cipherName")
        }
        // gocryptfs decodes with base64.Strict(): a spelling that merely decodes to the same bytes (stray trailing
        // bits, padding where Raw64 has none, ...) is not one of its names.
        if (b64.encodeToString(raw) != cipherName) {
            throw GocryptfsNameException("Malformed base64 filename: $cipherName")
        }
        if (raw.isEmpty() || raw.size % 16 != 0) {
            throw GocryptfsNameException("Malformed ciphertext filename: $cipherName")
        }
        val padded = eme!!.decrypt(dirIv, raw)
        val unpadded = unpad16(padded)
        val cleartext = String(unpadded, Charsets.UTF_8)

        // If decryption used the wrong diriv or the ciphertext was corrupt, the result is pseudo-random bytes that
        // happen to pass PKCS#7. gocryptfs then relies on IsValidName; on top of that a Java String can only hold
        // well-formed UTF-8, so the bytes must survive a round trip (this is also what tells a literal U+FFFD,
        // which gocryptfs allows, from a replaced invalid sequence).
        if (!isValidName(unpadded) ||
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
        // The padding may not be the whole block: names are never empty (unPad16).
        if (padLen == 0 || padLen > 16 || padLen >= padded.size) {
            throw GocryptfsNameException("invalid PKCS7 padding")
        }
        for (i in padded.size - padLen until padded.size) {
            if ((padded[i].toInt() and 0xFF) != padLen) throw GocryptfsNameException("invalid PKCS7 padding")
        }
        return padded.copyOf(padded.size - padLen)
    }
}