package com.aeidolon.vaultexplorer.securitykey

import org.json.JSONObject
import java.io.InputStream
import java.util.Base64

/**
 * The `systemd-fido2` LUKS2 token written by `systemd-cryptenroll --fido2-device=`.
 *
 * The LUKS passphrase for the keyslot this token belongs to is the standard
 * base64 text (with padding) of the 32-byte hmac-secret output obtained with
 * [credentialId] and [salt] for relying party [rpId] -- see [passphraseFor].
 */
class Luks2Fido2Token(
    val credentialId: ByteArray,
    val salt: ByteArray,
    val rpId: String,
    val policy: AssertPolicy,
) {
    companion object {
        /** What systemd-cryptenroll uses when the token has no `fido2-rp` field. */
        const val DEFAULT_RP_ID = "io.systemd.cryptsetup"

        /** The LUKS passphrase systemd derives from an hmac-secret [secret]. */
        fun passphraseFor(secret: ByteArray): String = Base64.getEncoder().encodeToString(secret)
    }
}

/**
 * Finds a `systemd-fido2` token in a LUKS2 header.
 *
 * LUKS2 layout: a 4096-byte binary header (magic "LUKS\xBA\xBE", big-endian
 * u16 version at offset 6, big-endian u64 total header size at offset 8),
 * followed by a JSON area filling the rest of the header size. Tokens live
 * in the JSON's "tokens" object. Read-only and tolerant: anything that isn't
 * a well-formed LUKS2 header with a systemd-fido2 token yields null.
 */
object Luks2Fido2TokenReader {
    private const val BINARY_HEADER_SIZE = 4096
    private const val MAX_HEADER_SIZE = 4L * 1024 * 1024
    private const val TOKEN_TYPE = "systemd-fido2"
    private val MAGIC_PRIMARY = byteArrayOf('L'.code.toByte(), 'U'.code.toByte(), 'K'.code.toByte(), 'S'.code.toByte(), 0xBA.toByte(), 0xBE.toByte())
    private val MAGIC_SECONDARY = byteArrayOf('S'.code.toByte(), 'K'.code.toByte(), 'U'.code.toByte(), 'L'.code.toByte(), 0xBA.toByte(), 0xBE.toByte())

    /** Reads from the start of a container. The stream is not closed. */
    fun read(stream: InputStream): Luks2Fido2Token? {
        val head = ByteArray(BINARY_HEADER_SIZE)
        if (!readFully(stream, head)) return null
        val magic = head.copyOfRange(0, 6)
        if (!magic.contentEquals(MAGIC_PRIMARY) && !magic.contentEquals(MAGIC_SECONDARY)) return null
        val version = ((head[6].toInt() and 0xFF) shl 8) or (head[7].toInt() and 0xFF)
        if (version != 2) return null
        var headerSize = 0L
        for (i in 8 until 16) headerSize = (headerSize shl 8) or (head[i].toLong() and 0xFF)
        if (headerSize <= BINARY_HEADER_SIZE || headerSize > MAX_HEADER_SIZE) return null
        val json = ByteArray((headerSize - BINARY_HEADER_SIZE).toInt())
        if (!readFully(stream, json)) return null
        return parseJsonArea(json)
    }

    /** [jsonArea]: the JSON area bytes, NUL-padded as stored on disk. */
    internal fun parseJsonArea(jsonArea: ByteArray): Luks2Fido2Token? {
        var end = jsonArea.indexOf(0.toByte())
        if (end < 0) end = jsonArea.size
        val root = try {
            JSONObject(String(jsonArea, 0, end, Charsets.UTF_8))
        } catch (_: Exception) {
            return null
        }
        val tokens = root.optJSONObject("tokens") ?: return null
        val keys = tokens.keys().asSequence().sortedBy { it.toIntOrNull() ?: Int.MAX_VALUE }
        for (key in keys) {
            val token = tokens.optJSONObject(key) ?: continue
            if (token.optString("type") != TOKEN_TYPE) continue
            return try {
                val credential = Base64.getDecoder().decode(token.getString("fido2-credential"))
                val salt = Base64.getDecoder().decode(token.getString("fido2-salt"))
                if (credential.isEmpty() || salt.isEmpty()) continue
                Luks2Fido2Token(
                    credentialId = credential,
                    salt = salt,
                    rpId = token.optString("fido2-rp", "").ifEmpty { Luks2Fido2Token.DEFAULT_RP_ID },
                    policy = AssertPolicy(
                        pin = token.optBoolean("fido2-clientPin-required", false),
                        up = if (token.has("fido2-up-required")) token.optBoolean("fido2-up-required") else null,
                        uv = if (token.has("fido2-uv-required")) token.optBoolean("fido2-uv-required") else null,
                    ),
                )
            } catch (_: Exception) {
                continue
            }
        }
        return null
    }

    private fun readFully(stream: InputStream, into: ByteArray): Boolean {
        var off = 0
        while (off < into.size) {
            val n = stream.read(into, off, into.size - off)
            if (n < 0) return false
            off += n
        }
        return true
    }
}
