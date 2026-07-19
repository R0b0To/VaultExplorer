package com.aeidolon.vaultexplorer.cryptomator

import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.InvalidKeyException
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * A vault's unwrapped 64-byte masterkey: 32-byte encKey || 32-byte macKey.
 * Mirrors org.cryptomator.cryptolib.api.Masterkey's key layout exactly.
 */
class CryptomatorMasterkey(private val raw: ByteArray) {
    init {
        require(raw.size == 64) { "Masterkey must be 64 bytes (encKey||macKey), was ${raw.size}" }
    }

    val encKey: SecretKeySpec get() = SecretKeySpec(raw, 0, 32, "AES")
    val macKey: SecretKeySpec get() = SecretKeySpec(raw, 32, 32, "AES") // used as a raw 256-bit key for CMAC/S2V and HmacSHA256

    /** Raw 64 bytes, for JWT (vault.cryptomator) HMAC verification, which signs with the whole masterkey. */
    fun rawKeyBytes(): ByteArray = raw.copyOf()

    fun destroy() {
        raw.fill(0)
    }

    companion object {
        fun generate(random: SecureRandom): CryptomatorMasterkey {
            val key = ByteArray(64)
            random.nextBytes(key)
            return CryptomatorMasterkey(key)
        }

        fun fromParts(encKey: ByteArray, macKey: ByteArray): CryptomatorMasterkey {
            require(encKey.size == 32 && macKey.size == 32)
            val combined = ByteArray(64)
            System.arraycopy(encKey, 0, combined, 0, 32)
            System.arraycopy(macKey, 0, combined, 32, 32)
            return CryptomatorMasterkey(combined)
        }
    }
}

class InvalidPassphraseException : Exception("Wrong password for this vault.")
class MasterkeyFileFormatException(message: String) : Exception(message)

/**
 * Parses/persists masterkey.cryptomator (scrypt-KDF-protected JSON) and
 * unwraps/wraps the two AES-key-wrapped (RFC 3394) 256-bit subkeys inside it.
 *
 * File schema (unchanged since vault format 3, still current in format 8):
 * {
 *   "version": 999,                 // legacy field, ignored for format 8 (see MASTERKEY_FILE_VERSION note)
 *   "scryptSalt": "<base64, 8 bytes>",
 *   "scryptCostParam": 32768,       // N = 2^15
 *   "scryptBlockSize": 8,           // r
 *   "primaryMasterKey": "<base64, AES-key-wrapped 32-byte encKey>",
 *   "hmacMasterKey": "<base64, AES-key-wrapped 32-byte macKey>",
 *   "versionMac": "<base64, HMAC-SHA256(macKey, bigEndian(version))>"
 * }
 */
object CryptomatorMasterkeyFile {

    private const val DEFAULT_SCRYPT_COST_PARAM = 1 shl 15 // 2^15
    private const val DEFAULT_SCRYPT_BLOCK_SIZE = 8
    private const val DEFAULT_SCRYPT_SALT_LEN = 8
    private const val DEFAULT_MASTERKEY_FILE_VERSION = 999
    private val PEPPER = ByteArray(0) // non-Hub vaults use no pepper

    data class ParsedFile(
        val version: Int,
        val scryptSalt: ByteArray,
        val scryptCostParam: Int,
        val scryptBlockSize: Int,
        val encMasterKeyWrapped: ByteArray,
        val macMasterKeyWrapped: ByteArray,
        val versionMac: ByteArray,
    )

    fun parse(jsonBytes: ByteArray): ParsedFile {
        val json = try {
            JSONObject(String(jsonBytes, StandardCharsets.UTF_8))
        } catch (e: Exception) {
            throw MasterkeyFileFormatException("masterkey.cryptomator is not valid JSON: ${e.message}")
        }
        fun b64(key: String): ByteArray = Base64.getDecoder().decode(json.getString(key))
        val version = json.optInt("version", DEFAULT_MASTERKEY_FILE_VERSION)
        val parsed = ParsedFile(
            version = version,
            scryptSalt = b64("scryptSalt"),
            scryptCostParam = json.getInt("scryptCostParam"),
            scryptBlockSize = json.getInt("scryptBlockSize"),
            encMasterKeyWrapped = b64("primaryMasterKey"),
            macMasterKeyWrapped = b64("hmacMasterKey"),
            versionMac = b64("versionMac"),
        )
        if (parsed.scryptCostParam <= 1 || parsed.scryptBlockSize <= 0) {
            throw MasterkeyFileFormatException("Invalid scrypt parameters in masterkey.cryptomator")
        }
        return parsed
    }

    /** Unwraps the masterkey given the user's passphrase. Throws [InvalidPassphraseException] on wrong password. */
    @Throws(InvalidPassphraseException::class)
    fun unlock(parsed: ParsedFile, passphrase: CharArray): CryptomatorMasterkey {
        val kekBytes = Scrypt.scrypt(passphrase, saltAndPepper(parsed.scryptSalt), parsed.scryptCostParam, parsed.scryptBlockSize, 32)
        try {
            val kek = SecretKeySpec(kekBytes, "AES")
            val encKey = aesKeyUnwrap(kek, parsed.encMasterKeyWrapped)
            val macKey = aesKeyUnwrap(kek, parsed.macMasterKeyWrapped)
            return CryptomatorMasterkey.fromParts(encKey, macKey)
        } catch (e: InvalidKeyException) {
            throw InvalidPassphraseException()
        } finally {
            kekBytes.fill(0)
        }
    }

    /** Serializes a freshly generated masterkey into masterkey.cryptomator's JSON format. */
    fun lock(masterkey: CryptomatorMasterkey, passphrase: CharArray, random: SecureRandom, vaultVersion: Int = DEFAULT_MASTERKEY_FILE_VERSION): ByteArray {
        val salt = ByteArray(DEFAULT_SCRYPT_SALT_LEN)
        random.nextBytes(salt)
        val kekBytes = Scrypt.scrypt(passphrase, saltAndPepper(salt), DEFAULT_SCRYPT_COST_PARAM, DEFAULT_SCRYPT_BLOCK_SIZE, 32)
        try {
            val kek = SecretKeySpec(kekBytes, "AES")
            val encWrapped = aesKeyWrap(kek, masterkey.encKey.encoded)
            val macWrapped = aesKeyWrap(kek, masterkey.macKey.encoded)

            val mac = Mac.getInstance("HmacSHA256")
            mac.init(masterkey.macKey)
            val versionBytes = java.nio.ByteBuffer.allocate(4).putInt(vaultVersion).array()
            val versionMac = mac.doFinal(versionBytes)

            val json = JSONObject()
            json.put("version", vaultVersion)
            json.put("scryptSalt", Base64.getEncoder().encodeToString(salt))
            json.put("scryptCostParam", DEFAULT_SCRYPT_COST_PARAM)
            json.put("scryptBlockSize", DEFAULT_SCRYPT_BLOCK_SIZE)
            json.put("primaryMasterKey", Base64.getEncoder().encodeToString(encWrapped))
            json.put("hmacMasterKey", Base64.getEncoder().encodeToString(macWrapped))
            json.put("versionMac", Base64.getEncoder().encodeToString(versionMac))
            return json.toString(2).toByteArray(StandardCharsets.UTF_8)
        } finally {
            kekBytes.fill(0)
        }
    }

    private fun saltAndPepper(salt: ByteArray): ByteArray {
        if (PEPPER.isEmpty()) return salt
        return salt + PEPPER
    }

    // NOTE: Conscrypt (Android's default JCA provider, "AndroidOpenSSL") does
    // NOT implement the "AESWrap" transformation -- its supported Cipher list
    // is a fixed, deliberately small set (see
    // https://android.googlesource.com/platform/external/conscrypt/+/HEAD/CAPABILITIES.md)
    // and RFC 3394 key wrap isn't in it. Rather than depend on Bouncy Castle
    // (unavailable as a Cipher provider from API 28+ per Android P's
    // provider-deprecation change) purely for this, RFC 3394 is implemented
    // directly here using only "AES/ECB/NoPadding", which Conscrypt does
    // provide. Verified against the official RFC 3394 section 4.1 test vector.
    private val RFC3394_IV = byteArrayOf(
        0xA6.toByte(), 0xA6.toByte(), 0xA6.toByte(), 0xA6.toByte(),
        0xA6.toByte(), 0xA6.toByte(), 0xA6.toByte(), 0xA6.toByte(),
    )

    private fun aesKeyWrap(kek: SecretKeySpec, keyToWrap: ByteArray): ByteArray {
        require(keyToWrap.size % 8 == 0 && keyToWrap.size >= 16) { "Key to wrap must be a multiple of 8 bytes, >= 16" }
        val n = keyToWrap.size / 8
        val cipher = Cipher.getInstance("AES/ECB/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, kek)

        var a = RFC3394_IV.copyOf()
        val r = Array(n) { i -> keyToWrap.copyOfRange(i * 8, (i + 1) * 8) }

        for (j in 0 until 6) {
            for (i in 1..n) {
                val b = cipher.doFinal(a + r[i - 1])
                val t = (n * j + i).toLong()
                a = xorCounter(b.copyOfRange(0, 8), t)
                r[i - 1] = b.copyOfRange(8, 16)
            }
        }
        return a + r.reduce { acc, bytes -> acc + bytes }
    }

    @Throws(InvalidKeyException::class)
    private fun aesKeyUnwrap(kek: SecretKeySpec, wrapped: ByteArray): ByteArray {
        require(wrapped.size % 8 == 0 && wrapped.size >= 24) { "Wrapped key must be a multiple of 8 bytes, >= 24" }
        val n = wrapped.size / 8 - 1
        val cipher = Cipher.getInstance("AES/ECB/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, kek)

        var a = wrapped.copyOfRange(0, 8)
        val r = Array(n) { i -> wrapped.copyOfRange(8 + i * 8, 8 + (i + 1) * 8) }

        for (j in 5 downTo 0) {
            for (i in n downTo 1) {
                val t = (n * j + i).toLong()
                val aXorT = xorCounter(a, t)
                val b = cipher.doFinal(aXorT + r[i - 1])
                a = b.copyOfRange(0, 8)
                r[i - 1] = b.copyOfRange(8, 16)
            }
        }
        if (!MessageDigest.isEqual(a, RFC3394_IV)) {
            throw InvalidKeyException("AES key unwrap integrity check failed (wrong KEK or corrupted data).")
        }
        return r.reduce { acc, bytes -> acc + bytes }
    }

    /** XORs the low 8 bytes of an 8-byte block with a 64-bit big-endian counter (RFC 3394's "MSB(64,A) XOR t"). */
    private fun xorCounter(block: ByteArray, t: Long): ByteArray {
        val result = block.copyOf()
        for (k in 0 until 8) {
            val shift = 8 * (7 - k)
            val tByte = ((t ushr shift) and 0xFF).toInt().toByte()
            result[k] = (result[k].toInt() xor tByte.toInt()).toByte()
        }
        return result
    }
}

/** Which key-loading strategy a vault.cryptomator's JWT `kid` claim selects. Only MASTERKEY is supported (no Hub/OAuth). */
enum class VaultKeyLoadingStrategy {
    MASTERKEY, HUB, UNSUPPORTED;

    companion object {
        fun fromKeyId(keyId: String): VaultKeyLoadingStrategy = when {
            keyId.startsWith("masterkeyfile:") -> MASTERKEY
            keyId.startsWith("hub+http") -> HUB
            else -> UNSUPPORTED
        }
    }
}

class VaultConfigException(message: String) : Exception(message)

data class CryptomatorVaultConfig(
    val vaultFormat: Int,
    val cipherCombo: String, // "SIV_GCM" (format 8) or "SIV_CTRMAC" (format 7)
    val shorteningThreshold: Int,
)

/**
 * Minimal JWT decode/verify for vault.cryptomator — supports only the
 * "masterkeyfile:masterkey.cryptomator" key-loading strategy (no Hub/OAuth,
 * matching this app's fully-offline model). Deliberately avoids a full JWT
 * library dependency (auth0/java-jwt) since only HMAC-SHA256/384/512
 * verification of a fixed claim set is needed.
 */
object CryptomatorVaultConfigParser {

    @Throws(VaultConfigException::class)
    fun decodeUnverified(jwt: String): Pair<String, Int> {
        val parts = jwt.split(".")
        if (parts.size != 3) throw VaultConfigException("Malformed vault.cryptomator (not a JWT)")
        val header = jsonOf(parts[0])
        val payload = jsonOf(parts[1])
        val keyId = header.optString("kid", "")
        if (keyId.isEmpty()) throw VaultConfigException("Missing 'kid' in vault.cryptomator header")
        val vaultFormat = payload.optInt("format", -1)
        if (vaultFormat < 0) throw VaultConfigException("Missing 'format' claim in vault.cryptomator")
        return Pair(keyId, vaultFormat)
    }

    /** Verifies the HMAC signature using the full 64-byte raw masterkey, then returns the trusted config. */
    @Throws(VaultConfigException::class)
    fun verify(jwt: String, masterkey: CryptomatorMasterkey): CryptomatorVaultConfig {
        val parts = jwt.split(".")
        if (parts.size != 3) throw VaultConfigException("Malformed vault.cryptomator (not a JWT)")
        val header = jsonOf(parts[0])
        val payload = jsonOf(parts[1])
        val alg = header.optString("alg", "")
        val macAlgorithm = when (alg) {
            "HS256" -> "HmacSHA256"
            "HS384" -> "HmacSHA384"
            "HS512" -> "HmacSHA512"
            else -> throw VaultConfigException("Unsupported vault.cryptomator signature algorithm: $alg")
        }

        val signingInput = "${parts[0]}.${parts[1]}"
        val mac = Mac.getInstance(macAlgorithm)
        mac.init(SecretKeySpec(masterkey.rawKeyBytes(), macAlgorithm))
        val expectedSig = mac.doFinal(signingInput.toByteArray(StandardCharsets.UTF_8))
        val actualSig = Base64.getUrlDecoder().decode(padBase64Url(parts[2]))
        if (!MessageDigest.isEqual(expectedSig, actualSig)) {
            throw VaultConfigException("vault.cryptomator signature verification failed — wrong password or corrupted vault config.")
        }

        val cipherCombo = payload.optString("cipherCombo", "")
        val vaultFormat = payload.optInt("format", -1)
        val shorteningThreshold = payload.optInt("shorteningThreshold", 220)
        if (cipherCombo != "SIV_GCM" && cipherCombo != "SIV_CTRMAC") {
            throw VaultConfigException("Unsupported cipherCombo: $cipherCombo")
        }
        return CryptomatorVaultConfig(vaultFormat, cipherCombo, shorteningThreshold)
    }

    fun create(vaultFormat: Int, cipherCombo: String, shorteningThreshold: Int, masterkey: CryptomatorMasterkey, vaultId: String): String {
        val header = JSONObject().apply {
            put("alg", "HS256")
            put("typ", "JWT")
            put("kid", "masterkeyfile:masterkey.cryptomator")
        }
        val payload = JSONObject().apply {
            put("jti", vaultId)
            put("format", vaultFormat)
            put("cipherCombo", cipherCombo)
            put("shorteningThreshold", shorteningThreshold)
        }
        val encodedHeader = base64UrlNoPad(header.toString().toByteArray(StandardCharsets.UTF_8))
        val encodedPayload = base64UrlNoPad(payload.toString().toByteArray(StandardCharsets.UTF_8))
        val signingInput = "$encodedHeader.$encodedPayload"
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(masterkey.rawKeyBytes(), "HmacSHA256"))
        val sig = mac.doFinal(signingInput.toByteArray(StandardCharsets.UTF_8))
        return "$signingInput.${base64UrlNoPad(sig)}"
    }

    private fun jsonOf(base64UrlSegment: String): JSONObject {
        val bytes = Base64.getUrlDecoder().decode(padBase64Url(base64UrlSegment))
        return JSONObject(String(bytes, StandardCharsets.UTF_8))
    }

    private fun padBase64Url(s: String): String {
        val rem = s.length % 4
        return if (rem == 0) s else s + "=".repeat(4 - rem)
    }

    private fun base64UrlNoPad(bytes: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
}