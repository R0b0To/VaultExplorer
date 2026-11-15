package com.aeidolon.vaultexplorer.cryfs

import com.aeidolon.vaultexplorer.crypto.LittleEndian
import com.aeidolon.vaultexplorer.crypto.Scrypt
import org.json.JSONObject
import java.security.SecureRandom
import com.aeidolon.vaultexplorer.handlers.DerivedKeyHandlers

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

    /**
     * Key sizes in bytes of the ciphers official C++ CryFS 1.x offers besides AES and XChaCha20-Poly1305. They are
     * implemented natively (crypto/cryfs_legacy_ciphers.cpp) and verified against Crypto++, the library CryFS used.
     * Every "-gcm" one has a 16-byte IV and a 16-byte tag; every "-cfb" one a 16-byte IV and no tag.
     */
    val LEGACY_CIPHER_KEY_BYTES: Map<String, Int> = mapOf(
        "twofish-256-gcm" to 32, "twofish-256-cfb" to 32, "twofish-128-gcm" to 16, "twofish-128-cfb" to 16,
        "serpent-256-gcm" to 32, "serpent-256-cfb" to 32, "serpent-128-gcm" to 16, "serpent-128-cfb" to 16,
        "cast-256-gcm" to 32, "cast-256-cfb" to 32,
        "mars-256-gcm" to 32, "mars-256-cfb" to 32, "mars-448-gcm" to 56, "mars-448-cfb" to 56,
        "mars-128-gcm" to 16, "mars-128-cfb" to 16,
    )

    private fun cipherKeySizeBytes(cipherName: String): Int = when (cipherName) {
        "aes-256-gcm", "aes-256-cfb", "xchacha20-poly1305" -> 32
        "aes-128-gcm", "aes-128-cfb" -> 16
        else -> LEGACY_CIPHER_KEY_BYTES[cipherName] ?: throw CryfsUnsupportedCipherException(cipherName)
    }

    /** Numeric dotted-version comparison ("0.10" == "0.10.0", "0.9" < "0.10"), like upstream's version parsing. */
    private fun compareDottedVersions(a: String, b: String): Int {
        fun parts(s: String): IntArray {
            val p = s.split('.')
            if (p.size > 3 || p.any { it.isEmpty() || it.length > 9 || !it.all { c -> c in '0'..'9' } }) {
                throw CryfsConfigException("cryfs.config has an unparsable version string: \"$s\".")
            }
            return IntArray(3) { i -> p.getOrNull(i)?.toInt() ?: 0 }
        }
        val x = parts(a)
        val y = parts(b)
        for (i in 0..2) if (x[i] != y[i]) return if (x[i] < y[i]) -1 else 1
        return 0
    }

    /** scrypt via the low-memory path; large official parameters must neither OOM nor be misreported as a wrong password. */
    private fun deriveScrypt(passwordBytes: ByteArray, kdf: KdfHeader): ByteArray = try {
        Scrypt.scryptLowMem(passwordBytes, kdf.salt, kdf.scryptN, kdf.scryptR, COMBINED_KEY_SIZE, kdf.scryptP)
    } catch (e: UnsupportedOperationException) {
        throw CryfsConfigException(e.message ?: "This vault's scrypt settings are not supported on this device.")
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
        val kdfParamsLen = LittleEndian.readU64(raw, pos)
        pos += 8
        if (kdfParamsLen < 16 || pos + kdfParamsLen > raw.size) {
            throw CryfsConfigException("Malformed cryfs.config (bad KDF parameter length: $kdfParamsLen).")
        }
        val kdfParamsBytes = raw.copyOfRange(pos, pos + kdfParamsLen.toInt())
        pos += kdfParamsLen.toInt()

        val encryptedInnerConfig = raw.copyOfRange(pos, raw.size)

        val scryptN = LittleEndian.readU64(kdfParamsBytes, 0)
        val scryptR = LittleEndian.readU32(kdfParamsBytes, 8)
        val scryptP = LittleEndian.readU32(kdfParamsBytes, 12)
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
            deriveScrypt(passwordBytes, kdf)
        } finally {
            passwordBytes.fill(0)
        }
    }

    @Throws(CryfsConfigException::class, CryfsWrongPasswordException::class)
    fun parse(raw: ByteArray, password: CharArray): CryfsConfig {
        val kdf = readKdfHeader(raw)
        val passwordBytes = passwordToUtf8Bytes(password)
        val combinedKey = try {
            deriveScrypt(passwordBytes, kdf)
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

        // Format gate, mirroring upstream's loader: a missing "version" means a pre-0.10 vault.
        val formatVersion = if (json.has("version")) json.optString("version", "") else "0.8"
        val versionCmp = compareDottedVersions(formatVersion, FORMAT_VERSION)
        if (versionCmp < 0) {
            throw CryfsConfigException(
                "This vault uses CryFS filesystem format $formatVersion, which is older than the supported $FORMAT_VERSION. " +
                    "Open it once with CryFS 0.10 or newer (for example on a computer) so it gets migrated, then try again."
            )
        }
        if (versionCmp > 0) {
            throw CryfsConfigException(
                "This vault uses CryFS filesystem format $formatVersion, which is newer than the $FORMAT_VERSION this app supports. " +
                    "Please update the app."
            )
        }

        val migrations = json.optJSONObject("migrations")
            ?: throw CryfsConfigException(
                "cryfs.config has no \"migrations\" section: this vault has not been migrated to the current CryFS format. " +
                    "Open it once with CryFS 0.10 or newer to migrate it, then try again."
            )
        val hasVersionNumbers = migrations.optString("hasVersionNumbers") == "true" || migrations.optBoolean("hasVersionNumbers", false)
        val hasParentPointers = migrations.optString("hasParentPointers") == "true" || migrations.optBoolean("hasParentPointers", false)
        if (!hasVersionNumbers || !hasParentPointers) {
            throw CryfsConfigException(
                "cryfs.config says this vault has not been fully migrated (\"migrations\" flags are not set). " +
                    "Open it once with CryFS 0.10 or newer to migrate it, then try again."
            )
        }

        fun required(key: String): String {
            val v = if (json.has(key) && !json.isNull(key)) json.optString(key, "") else ""
            if (v.isEmpty()) throw CryfsConfigException("cryfs.config is missing the required field \"$key\".")
            return v
        }
        val createdWithVersion = required("createdWithVersion")
        val lastOpenedWithVersion = required("lastOpenedWithVersion")

        val blocksizeBytes = parseFlexibleLong(json, "blocksizeBytes")
            ?: throw CryfsConfigException("cryfs.config is missing the required field \"blocksizeBytes\".")
        if (blocksizeBytes <= 0L || blocksizeBytes > (1L shl 30) ||
            CryfsBlockStore.calculateVirtualBlockSize(blocksizeBytes.toInt(), cipher) < 8 + 2 * 16
        ) {
            throw CryfsConfigException("cryfs.config has an invalid block size: $blocksizeBytes.")
        }

        val exclusiveClientId = parseFlexibleLong(json, "exclusiveClientId")
        if (exclusiveClientId != null && (exclusiveClientId <= 0L || exclusiveClientId > 0xFFFFFFFFL)) {
            throw CryfsConfigException("cryfs.config has an invalid exclusiveClientId.")
        }

        val rootBlobStr = required("rootblob")
        val keyStr = required("key")
        val fsIdStr = required("filesystemId")
        val key = LittleEndian.hexToBytes(keyStr)
        if (key.size != cipherKeySizeBytes(cipher)) {
            throw CryfsConfigException("cryfs.config encryption key has the wrong length for cipher \"$cipher\".")
        }
        val filesystemId = LittleEndian.hexToBytes(fsIdStr)
        if (filesystemId.size != 16) {
            throw CryfsConfigException("cryfs.config filesystem ID is not 16 bytes.")
        }

        return CryfsConfig(
            blockCipherName = cipher,
            encryptionKey = key,
            blocksizeBytes = blocksizeBytes.toInt(),
            rootBlobId = CryfsBlockId.fromHex(rootBlobStr),
            filesystemId = filesystemId,
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
                put("key", LittleEndian.bytesToHex(config.encryptionKey))
                put("cipher", config.blockCipherName)
                put("version", config.formatVersion)
                put("createdWithVersion", config.createdWithVersion)
                put("lastOpenedWithVersion", config.lastOpenedWithVersion)
                put("blocksizeBytes", config.blocksizeBytes.toString())
                put("filesystemId", LittleEndian.bytesToHex(config.filesystemId))
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

            val kdfParamsBytes = LittleEndian.u64Bytes(DEFAULT_SCRYPT_N.toLong()) +
                LittleEndian.u32Bytes(DEFAULT_SCRYPT_R.toLong()) +
                LittleEndian.u32Bytes(DEFAULT_SCRYPT_P.toLong()) +
                salt

            return writeNullTerminatedString(OUTER_HEADER) +
                LittleEndian.u64Bytes(kdfParamsBytes.size.toLong()) +
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
        val dataLen = LittleEndian.readU32(data, 0)
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
        System.arraycopy(LittleEndian.u32Bytes(data.size.toLong()), 0, out, 0, 4)
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
}