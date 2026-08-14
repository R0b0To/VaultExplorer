package com.aeidolon.vaultexplorer.cryfs

import com.aeidolon.vaultexplorer.crypto.Scrypt
import org.json.JSONObject
import java.security.SecureRandom

class CryfsWrongPasswordException : Exception("Wrong password for this vault.")
class CryfsConfigException(message: String) : Exception(message)

/**
 * The logical, decrypted contents of a vault's cryfs.config: everything
 * needed to read/write its blocks once the password has checked out.
 */
data class CryfsConfig(
    val blockCipherName: String,     // "cryfs"."cipher"
    val encryptionKey: ByteArray,    // "cryfs"."key"
    val blocksizeBytes: Int,         // "cryfs"."blocksizeBytes"
    val rootBlobId: CryfsBlockId,    // "cryfs"."rootblob"
    val filesystemId: ByteArray,     // 16 bytes, "cryfs"."filesystemId"
    val exclusiveClientId: Long?,    // "cryfs"."exclusiveClientId" (null = multi-client cloud mode)
    val formatVersion: String,       // "cryfs"."version"
    val createdWithVersion: String,  // "cryfs"."createdWithVersion"
    val lastOpenedWithVersion: String, // "cryfs"."lastOpenedWithVersion"
)

object CryfsConfigFile {

    private const val OUTER_HEADER = "cryfs.config;1;scrypt"
    private const val INNER_HEADER = "cryfs.config.inner;0"
    private val OUTER_CIPHER_ID = CryfsBlockCipher.cipherIdFor("aes-256-gcm")

    private const val OUTER_CONFIG_SIZE = 1024
    private const val INNER_CONFIG_SIZE = 900

    private const val OUTER_KEY_SIZE = 32
    private const val MAX_KEY_SIZE = 56
    private const val COMBINED_KEY_SIZE = OUTER_KEY_SIZE + MAX_KEY_SIZE // 88

    const val DEFAULT_SCRYPT_N = 1 shl 15 // 32768
    const val DEFAULT_SCRYPT_R = 8
    const val DEFAULT_SCRYPT_P = 1
    private const val SCRYPT_SALT_LEN = 32

    // Not private: exposed so callers (CryfsVault.create(), the create-vault platform
    // channel handler) can use it as the default/fallback for a user-chosen block size,
    // mirroring CryFS CLI's `--blocksize` option (which also defaults to 32768).
    const val DEFAULT_BLOCKSIZE = 32 * 1024
    // CryFS 1.0.0/0.11.x default to XChaCha20-Poly1305 for new filesystems (still readable by
    // old clients only if they were configured to use it too; AES-256-GCM remains supported).
    // Not private: exposed as the default for CryfsVault.create()'s cipher parameter.
    const val DEFAULT_BLOCK_CIPHER = "xchacha20-poly1305"

    // On-disk storage format version. This has NOT changed since CryFS 0.10 -- filesystems
    // created by CryFS 0.10.x, 0.11.x and 1.0.x all share this same storage format and are
    // mutually readable without migration, so this must stay "0.10" even though the software
    // release version below has moved on.
    const val FORMAT_VERSION = "0.10"

    // The actual CryFS software release version this app identifies itself as, written into
    // the "createdWithVersion" / "lastOpenedWithVersion" config fields. Distinct from
    // FORMAT_VERSION above.
    const val SOFTWARE_VERSION = "1.0.3"

    private fun passwordToUtf8Bytes(password: CharArray): ByteArray {
        val encoded = Charsets.UTF_8.encode(java.nio.CharBuffer.wrap(password))
        val bytes = ByteArray(encoded.remaining())
        encoded.get(bytes)
        return bytes
    }

    private fun cipherKeySizeBytes(cipherName: String): Int = when (cipherName) {
        "aes-256-gcm", "aes-256-cfb", "xchacha20-poly1305" -> 32
        "aes-128-gcm", "aes-128-cfb" -> 16
        else -> throw CryfsUnsupportedCipherException(cipherName)
    }

    /** Size in bytes of the scrypt output ([parse]'s `combinedKey`); the shape
     *  that a cached "derived key" must have to be replayed via
     *  [parseWithCombinedKey]. */
    const val COMBINED_KEY_LENGTH = COMBINED_KEY_SIZE

    private class KdfHeader(
        val salt: ByteArray,
        val scryptN: Int,
        val scryptR: Int,
        val scryptP: Int,
        val encryptedInnerConfig: ByteArray,
    )

    private fun readKdfHeader(raw: ByteArray): KdfHeader {
        var pos = 0

        val (header, afterHeader) = readNullTerminatedString(raw, pos)
            ?: throw CryfsConfigException("Not a cryfs.config file (missing/unterminated header).")
        if (header != OUTER_HEADER) {
            throw CryfsConfigException(
                "Not a cryfs.config file (expected header \"$OUTER_HEADER\", found \"$header\")."
            )
        }
        pos = afterHeader

        if (pos + 8 > raw.size) {
            throw CryfsConfigException("Truncated cryfs.config (missing KDF parameter length).")
        }
        val kdfParamsLen = readU64LE(raw, pos)
        pos += 8
        if (kdfParamsLen < 16 || pos + kdfParamsLen > raw.size) {
            throw CryfsConfigException("Malformed cryfs.config (bad KDF parameter length: $kdfParamsLen).")
        }
        val kdfParamsBytes = raw.copyOfRange(pos, pos + kdfParamsLen.toInt())
        pos += kdfParamsLen.toInt()

        val encryptedInnerConfig = raw.copyOfRange(pos, raw.size)

        val scryptN = readU64LE(kdfParamsBytes, 0)
        val scryptR = readU32LE(kdfParamsBytes, 8)
        val scryptP = readU32LE(kdfParamsBytes, 12)
        val salt = kdfParamsBytes.copyOfRange(16, kdfParamsBytes.size)
        if (scryptN <= 0 || scryptN > Int.MAX_VALUE.toLong()) {
            throw CryfsConfigException("Unsupported scrypt N parameter: $scryptN")
        }

        return KdfHeader(salt, scryptN.toInt(), scryptR.toInt(), scryptP.toInt(), encryptedInnerConfig)
    }

    /**
     * Validates cryfs.config's outer envelope -- header string, KDF
     * parameter block bounds -- without touching a password at all (the
     * envelope's scrypt salt/N/R/P are stored in the clear; only the inner
     * payload past it is encrypted). Returns a human-readable problem
     * description, or null if the envelope looks structurally sound.
     * Used by FolderVaultChecker.kt's no-password CryFS scan.
     */
    fun checkStructure(raw: ByteArray): String? = try {
        readKdfHeader(raw)
        null
    } catch (e: CryfsConfigException) {
        e.message ?: "Malformed cryfs.config"
    }

    /**
     * Runs scrypt over [raw]'s KDF parameters with [password] and returns the
     * raw 88-byte combined key — the expensive part of [parse]. Callers that
     * want a "remember this vault" fast-unlock cache should stash this (e.g.
     * via the same Keystore-backed store [DerivedKeyHandlers] uses for file
     * containers) and later skip straight to [parseWithCombinedKey].
     */
    @Throws(CryfsConfigException::class)
    fun deriveCombinedKey(raw: ByteArray, password: CharArray): ByteArray {
        val kdf = readKdfHeader(raw)
        val passwordBytes = passwordToUtf8Bytes(password)
        return try {
            Scrypt.scrypt(
                passwordBytes, kdf.salt, kdf.scryptN, kdf.scryptR, COMBINED_KEY_SIZE, kdf.scryptP
            )
        } finally {
            passwordBytes.fill(0)
        }
    }

    @Throws(CryfsConfigException::class, CryfsWrongPasswordException::class)
    fun parse(raw: ByteArray, password: CharArray): CryfsConfig {
        val kdf = readKdfHeader(raw)
        val passwordBytes = passwordToUtf8Bytes(password)
        val combinedKey = try {
            Scrypt.scrypt(
                passwordBytes, kdf.salt, kdf.scryptN, kdf.scryptR, COMBINED_KEY_SIZE, kdf.scryptP
            )
        } finally {
            passwordBytes.fill(0)
        }
        return try {
            decryptConfig(combinedKey, kdf.encryptedInnerConfig)
        } finally {
            combinedKey.fill(0)
        }
    }

    /**
     * Fast-path counterpart of [parse]: decrypts cryfs.config using an
     * already-derived [combinedKey] (as previously returned by
     * [deriveCombinedKey]/[parse]) instead of running scrypt again. A wrong
     * cached key surfaces the same [CryfsWrongPasswordException] as a wrong
     * password, so callers can fall back to a full password prompt.
     */
    @Throws(CryfsConfigException::class, CryfsWrongPasswordException::class)
    fun parseWithCombinedKey(raw: ByteArray, combinedKey: ByteArray): CryfsConfig {
        if (combinedKey.size != COMBINED_KEY_SIZE) {
            throw CryfsWrongPasswordException()
        }
        val kdf = readKdfHeader(raw)
        return decryptConfig(combinedKey, kdf.encryptedInnerConfig)
    }

    @Throws(CryfsConfigException::class, CryfsWrongPasswordException::class)
    private fun decryptConfig(combinedKey: ByteArray, encryptedInnerConfig: ByteArray): CryfsConfig {
        val outerKey = combinedKey.copyOfRange(0, OUTER_KEY_SIZE)
        val outerPadded = try {
            CryfsBlockCipher.decrypt(OUTER_CIPHER_ID, outerKey, encryptedInnerConfig)
                ?: throw CryfsWrongPasswordException()
        } finally {
            outerKey.fill(0)
        }
        val serializedInnerConfig = removePadding(outerPadded)

        var ipos = 0
        val (innerHeader, afterInnerHeader) = readNullTerminatedString(serializedInnerConfig, ipos)
            ?: throw CryfsConfigException("Malformed inner config (missing/unterminated header).")
        if (innerHeader != INNER_HEADER) {
            throw CryfsConfigException(
                "Malformed inner config (expected header \"$INNER_HEADER\", found \"$innerHeader\")."
            )
        }
        ipos = afterInnerHeader
        val (cipherName, afterCipherName) = readNullTerminatedString(serializedInnerConfig, ipos)
            ?: throw CryfsConfigException("Malformed inner config (missing/unterminated cipher name).")
        ipos = afterCipherName
        val encryptedConfig = serializedInnerConfig.copyOfRange(ipos, serializedInnerConfig.size)

        val innerCipherId = CryfsBlockCipher.cipherIdFor(cipherName)
        val innerKeySize = cipherKeySizeBytes(cipherName)
        val innerKey = combinedKey.copyOfRange(OUTER_KEY_SIZE, OUTER_KEY_SIZE + innerKeySize)
        val innerPadded = try {
            CryfsBlockCipher.decrypt(innerCipherId, innerKey, encryptedConfig)
                ?: throw CryfsWrongPasswordException()
        } finally {
            innerKey.fill(0)
        }
        val json = removePadding(innerPadded)

        return parsePayload(json, cipherName)
    }

    private fun parsePayload(payloadJson: ByteArray, expectedCipherName: String): CryfsConfig {
        val root = try {
            JSONObject(String(payloadJson, Charsets.UTF_8))
        } catch (e: Exception) {
            throw CryfsConfigException("cryfs.config payload is not valid JSON: ${e.message}")
        }
        val json = root.optJSONObject("cryfs")
            ?: throw CryfsConfigException("cryfs.config payload is missing the top-level \"cryfs\" object.")

        val cipher = json.optString("cipher", "")
        if (cipher != expectedCipherName) {
            throw CryfsConfigException(
                "Cipher in config JSON (\"$cipher\") doesn't match the inner-layer cipher (\"$expectedCipherName\")."
            )
        }

        val migrations = json.optJSONObject("migrations")
        if (migrations != null) {
            val hasVersionNumbers = migrations.optString("hasVersionNumbers") == "true" || migrations.optBoolean("hasVersionNumbers", false)
            val hasParentPointers = migrations.optString("hasParentPointers") == "true" || migrations.optBoolean("hasParentPointers", false)
            if (!hasVersionNumbers || !hasParentPointers) {
                throw CryfsConfigException(
                    "cryfs.config has unexpected \"migrations\" flags; this app only supports current-format vaults."
                )
            }
        }

        val formatVersion = json.optString("version", json.optString("formatVersion", "0.10"))
        val createdWithVersion = json.optString("createdWithVersion", json.optString("created_with_version", "0.10"))
        val lastOpenedWithVersion = json.optString("lastOpenedWithVersion", json.optString("last_opened_with_version", "0.10"))

        val blocksizeBytes = parseFlexibleLong(json, "blocksizeBytes") 
            ?: parseFlexibleLong(json, "blocksize")
            ?: throw CryfsConfigException("cryfs.config is missing blocksize field.")

        val exclusiveClientId = parseFlexibleLong(json, "exclusiveClientId") 
            ?: parseFlexibleLong(json, "exclusive_client_id")

        val rootBlobStr = json.optString("rootblob", json.optString("root_blob", json.optString("rootBlob", "")))
        if (rootBlobStr.isEmpty()) throw CryfsConfigException("cryfs.config is missing the required root blob ID field.")

        val keyStr = json.optString("key", json.optString("enc_key", json.optString("encKey", "")))
        if (keyStr.isEmpty()) throw CryfsConfigException("cryfs.config is missing the required encryption key field.")

        val fsIdStr = json.optString("filesystemId", json.optString("filesystem_id", ""))
        if (fsIdStr.isEmpty()) throw CryfsConfigException("cryfs.config is missing the required filesystem ID field.")

        return CryfsConfig(
            blockCipherName = cipher,
            encryptionKey = hexToBytes(keyStr),
            blocksizeBytes = blocksizeBytes.toInt(),
            rootBlobId = CryfsBlockId.fromHex(rootBlobStr),
            filesystemId = hexToBytes(fsIdStr),
            exclusiveClientId = exclusiveClientId,
            formatVersion = formatVersion,
            createdWithVersion = createdWithVersion,
            lastOpenedWithVersion = lastOpenedWithVersion,
        )
    }

    private fun parseFlexibleLong(json: JSONObject, key: String): Long? {
        if (!json.has(key) || json.isNull(key)) return null
        return when (val v = json.get(key)) {
            is String -> v.toLongOrNull()
                ?: throw CryfsConfigException("cryfs.config field \"$key\" is not a valid number: \"$v\".")
            is Number -> v.toLong()
            else -> throw CryfsConfigException("cryfs.config field \"$key\" has an unexpected JSON type.")
        }
    }

    fun build(config: CryfsConfig, password: CharArray, random: SecureRandom): ByteArray {
        val payload = JSONObject().apply {
            put("cryfs", JSONObject().apply {
                put("rootblob", config.rootBlobId.hex)
                put("key", bytesToHex(config.encryptionKey))
                put("cipher", config.blockCipherName)
                put("version", config.formatVersion)
                put("createdWithVersion", config.createdWithVersion)
                put("lastOpenedWithVersion", config.lastOpenedWithVersion)
                put("blocksizeBytes", config.blocksizeBytes.toString())
                put("filesystemId", bytesToHex(config.filesystemId))
                // Always write exclusiveClientId as null for multi-client cloud compatibility
                put("exclusiveClientId", config.exclusiveClientId?.toString() ?: JSONObject.NULL)
                put("migrations", JSONObject().apply {
                    put("hasVersionNumbers", "true")
                    put("hasParentPointers", "true")
                })
            })
        }.toString().toByteArray(Charsets.UTF_8)

        val innerCipherId = CryfsBlockCipher.cipherIdFor(config.blockCipherName)
        val innerKeySize = cipherKeySizeBytes(config.blockCipherName)

        val salt = ByteArray(SCRYPT_SALT_LEN).also { random.nextBytes(it) }
        val passwordBytes = passwordToUtf8Bytes(password)
        val combinedKey = try {
            Scrypt.scrypt(
                passwordBytes, salt, DEFAULT_SCRYPT_N, DEFAULT_SCRYPT_R, COMBINED_KEY_SIZE, DEFAULT_SCRYPT_P
            )
        } finally {
            passwordBytes.fill(0)
        }

        try {
            val paddedPayload = addPadding(payload, INNER_CONFIG_SIZE, random)
            val innerKey = combinedKey.copyOfRange(OUTER_KEY_SIZE, OUTER_KEY_SIZE + innerKeySize)
            val encryptedConfig = try {
                CryfsBlockCipher.encrypt(innerCipherId, innerKey, paddedPayload)
            } finally {
                innerKey.fill(0)
            }

            val innerLayout = writeNullTerminatedString(INNER_HEADER) +
                writeNullTerminatedString(config.blockCipherName) +
                encryptedConfig
            val paddedInnerLayout = addPadding(innerLayout, OUTER_CONFIG_SIZE, random)

            val outerKey = combinedKey.copyOfRange(0, OUTER_KEY_SIZE)
            val encryptedInnerConfig = try {
                CryfsBlockCipher.encrypt(OUTER_CIPHER_ID, outerKey, paddedInnerLayout)
            } finally {
                outerKey.fill(0)
            }

            val kdfParamsBytes = writeU64LE(DEFAULT_SCRYPT_N.toLong()) +
                writeU32LE(DEFAULT_SCRYPT_R.toLong()) +
                writeU32LE(DEFAULT_SCRYPT_P.toLong()) +
                salt

            return writeNullTerminatedString(OUTER_HEADER) +
                writeU64LE(kdfParamsBytes.size.toLong()) +
                kdfParamsBytes +
                encryptedInnerConfig
        } finally {
            combinedKey.fill(0)
        }
    }

    fun newVaultConfig(
        random: SecureRandom,
        cipher: String = DEFAULT_BLOCK_CIPHER,
        blocksizeBytes: Int = DEFAULT_BLOCKSIZE,
    ): CryfsConfig {
        val key = ByteArray(32).also { random.nextBytes(it) }
        val filesystemId = ByteArray(16).also { random.nextBytes(it) }
        val rootBlobId = CryfsBlockId.random(random)
        return CryfsConfig(
            blockCipherName = cipher,
            encryptionKey = key,
            blocksizeBytes = blocksizeBytes,
            rootBlobId = rootBlobId,
            filesystemId = filesystemId,
            exclusiveClientId = null, // Multi-client mode enabled by default
            formatVersion = FORMAT_VERSION,
            createdWithVersion = SOFTWARE_VERSION,
            lastOpenedWithVersion = SOFTWARE_VERSION,
        )
    }

    private fun removePadding(data: ByteArray): ByteArray {
        if (data.size < 4) throw CryfsConfigException("Padded config data is too short.")
        val dataLen = readU32LE(data, 0)
        if (dataLen < 0 || 4 + dataLen > data.size) {
            throw CryfsConfigException("Padded config data claims an invalid length ($dataLen).")
        }
        return data.copyOfRange(4, 4 + dataLen.toInt())
    }

    private fun addPadding(data: ByteArray, targetSize: Int, random: SecureRandom): ByteArray {
        val paddingLen = targetSize - 4 - data.size
        require(paddingLen >= 0) {
            "Config payload of ${data.size} bytes doesn't fit into a $targetSize-byte padded slot; " +
                "increase the target size."
        }
        val out = ByteArray(targetSize)
        System.arraycopy(writeU32LE(data.size.toLong()), 0, out, 0, 4)
        System.arraycopy(data, 0, out, 4, data.size)
        val paddingRegion = ByteArray(paddingLen)
        random.nextBytes(paddingRegion)
        System.arraycopy(paddingRegion, 0, out, 4 + data.size, paddingLen)
        return out
    }

    private fun readNullTerminatedString(bytes: ByteArray, start: Int): Pair<String, Int>? {
        var i = start
        while (i < bytes.size && bytes[i] != 0.toByte()) i++
        if (i >= bytes.size) return null
        val str = String(bytes, start, i - start, Charsets.UTF_8)
        return str to (i + 1)
    }

    private fun writeNullTerminatedString(s: String): ByteArray =
        s.toByteArray(Charsets.UTF_8) + byteArrayOf(0)

    private fun readU32LE(bytes: ByteArray, pos: Int): Long {
        var result = 0L
        for (i in 0 until 4) result = result or ((bytes[pos + i].toLong() and 0xFF) shl (8 * i))
        return result
    }

    private fun readU64LE(bytes: ByteArray, pos: Int): Long {
        var result = 0L
        for (i in 0 until 8) result = result or ((bytes[pos + i].toLong() and 0xFF) shl (8 * i))
        return result
    }

    private fun writeU32LE(value: Long): ByteArray {
        val out = ByteArray(4)
        for (i in 0 until 4) out[i] = ((value ushr (8 * i)) and 0xFF).toByte()
        return out
    }

    private fun writeU64LE(value: Long): ByteArray {
        val out = ByteArray(8)
        for (i in 0 until 8) out[i] = ((value ushr (8 * i)) and 0xFF).toByte()
        return out
    }

    private fun bytesToHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

    private fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "Odd-length hex string" }
        return ByteArray(hex.length / 2) { i ->
            ((Character.digit(hex[i * 2], 16) shl 4) + Character.digit(hex[i * 2 + 1], 16)).toByte()
        }
    }
}