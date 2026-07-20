package com.aeidolon.vaultexplorer.gocryptfs

import org.json.JSONObject
import java.util.Base64

class GocryptfsConfigException(message: String) : Exception(message)

/** The feature-flag set this integration supports unlocking. Anything else
 *  (PlaintextNames, AESSIV-only reverse vaults, XChaCha20Poly1305, FIDO2,
 *  no-HKDF legacy filesystems) is rejected explicitly rather than guessed
 *  at — mirrors CryptomatorVault.open's vaultFormat 7..8 gate. */
private val SUPPORTED_FLAGS = setOf(
    "GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF"
)
private val REQUIRED_FLAGS = SUPPORTED_FLAGS // all six must be present

data class GocryptfsConfig(
    val encryptedKey: ByteArray,
    val scryptSalt: ByteArray,
    val scryptN: Int,
    val scryptR: Int,
    val scryptP: Int,
    val scryptKeyLen: Int,
    val version: Int,
    val featureFlags: Set<String>,
    val longNameMax: Int, // 0 = default (255), matches gocryptfs's own convention
) {
    companion object {
        @Throws(GocryptfsConfigException::class)
        fun parse(jsonBytes: ByteArray): GocryptfsConfig {
            val json = try {
                JSONObject(String(jsonBytes, Charsets.UTF_8))
            } catch (e: Exception) {
                throw GocryptfsConfigException("gocryptfs.conf is not valid JSON: ${e.message}")
            }
            fun b64(key: String): ByteArray = Base64.getDecoder().decode(json.getString(key))

            val version = json.optInt("Version", -1)
            if (version != 2) {
                throw GocryptfsConfigException("Unsupported on-disk format version $version (only 2 is supported)")
            }

            val scrypt = json.getJSONObject("ScryptObject")
            val flags = mutableSetOf<String>()
            json.optJSONArray("FeatureFlags")?.let { arr ->
                for (i in 0 until arr.length()) flags.add(arr.getString(i))
            }
            val missing = REQUIRED_FLAGS - flags
            val unsupported = flags - SUPPORTED_FLAGS
            if (missing.isNotEmpty() || unsupported.isNotEmpty()) {
                throw GocryptfsConfigException(
                    "Unsupported gocryptfs feature flags (missing=$missing, unsupported=$unsupported). " +
                        "This app only supports vaults created with gocryptfs's modern defaults " +
                        "(-init with no extra flags)."
                )
            }

            return GocryptfsConfig(
                encryptedKey = b64("EncryptedKey"),
                scryptSalt = Base64.getDecoder().decode(scrypt.getString("Salt")),
                scryptN = scrypt.getInt("N"),
                scryptR = scrypt.getInt("R"),
                scryptP = scrypt.getInt("P"),
                scryptKeyLen = scrypt.getInt("KeyLen"),
                version = version,
                featureFlags = flags,
                longNameMax = json.optInt("LongNameMax", 0),
            )
        }
    }
}