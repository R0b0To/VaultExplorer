package com.aeidolon.vaultexplorer.gocryptfs

import org.json.JSONObject
import java.util.Base64

class GocryptfsConfigException(message: String) : Exception(message)

enum class GocryptfsCipher { AES_256_GCM, XCHACHA20_POLY1305 }

/**
 * The `FIDO2` object of a gocryptfs.conf for a vault protected with a FIDO2
 * security key (`gocryptfs -init -fido2`). Upstream derives the vault's
 * "password" as the 32-byte hmac-secret output for [hmacSalt] using
 * [credentialId], relying party id [RP_ID]; [assertOptions] are the
 * `fido2-assert -t` options in effect (e.g. `pin=true`).
 */
class GocryptfsFido2Params(
    val credentialId: ByteArray,
    val hmacSalt: ByteArray,
    val assertOptions: List<String>,
) {
    companion object {
        const val RP_ID = "gocryptfs"
    }
}

data class GocryptfsConfig(
    val encryptedKey: ByteArray,
    val scryptSalt: ByteArray,
    val scryptN: Int,
    val scryptR: Int,
    val scryptP: Int,
    val scryptKeyLen: Int,
    val version: Int,
    val featureFlags: Set<String>,
    val longNameMax: Int,
    val cipher: GocryptfsCipher,
    val plaintextNames: Boolean,
    val fido2: GocryptfsFido2Params? = null,
) {
    val hasDirIV: Boolean get() = "DirIV" in featureFlags

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

            val hasGcmIv128 = "GCMIV128" in flags
            val hasXChaCha = "XChaCha20Poly1305" in flags
            val hasAessiv = "AESSIV" in flags
            val hasPlaintextNames = "PlaintextNames" in flags

            val problems = mutableListOf<String>()
            if (!flags.contains("HKDF")) problems += "missing HKDF"
            if (!hasPlaintextNames) {
                if (!flags.contains("EMENames")) problems += "missing EMENames"
                if (!flags.contains("Raw64")) problems += "missing Raw64"
            }

            val unsupported = flags - setOf("GCMIV128", "XChaCha20Poly1305", "AESSIV", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF", "PlaintextNames", "FIDO2")

            if (unsupported.isNotEmpty()) problems += "unsupported feature flags $unsupported"

            // Real gocryptfs content-cipher semantics (internal/configfile/
            // validate.go): AESSIV *requires* GCMIV128 to also be set rather
            // than being an alternative to it, and XChaCha20Poly1305
            // *conflicts* with GCMIV128.
            when {
                hasXChaCha && hasGcmIv128 -> problems += "XChaCha20Poly1305 conflicts with GCMIV128"
                hasAessiv && !hasGcmIv128 -> problems += "AESSIV requires GCMIV128"
                hasAessiv -> problems += "AES-SIV content encryption is not yet supported in VaultExplorer"
                !hasXChaCha && !hasGcmIv128 -> problems += "missing a content cipher feature flag"
            }

            if (problems.isNotEmpty()) {
                throw GocryptfsConfigException(
                    "Unsupported gocryptfs feature flags: ${problems.joinToString("; ")}. " +
                        "This app supports standard vaults created with AES-256-GCM or XChaCha20-Poly1305."
                )
            }

            // Only two outcomes reach here: hasXChaCha (with !hasGcmIv128,
            // enforced above), or plain GCMIV128 with neither AESSIV nor
            // XChaCha -- every other combination already threw.
            val cipher = when {
                hasXChaCha -> GocryptfsCipher.XCHACHA20_POLY1305
                else -> GocryptfsCipher.AES_256_GCM
            }

            val fido2 = parseFido2(json, "FIDO2" in flags)

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
                cipher = cipher,
                plaintextNames = hasPlaintextNames,
                fido2 = fido2,
            )
        }

        /**
         * The FIDO2 feature flag and the `FIDO2` object must agree: a
         * missing object under the flag would make every unlock attempt
         * fail with a confusing "wrong password", so reject it up front.
         */
        private fun parseFido2(json: JSONObject, flagSet: Boolean): GocryptfsFido2Params? {
            if (!flagSet) return null
            val obj = json.optJSONObject("FIDO2")
            if (obj == null) {
                throw GocryptfsConfigException("gocryptfs.conf has the FIDO2 flag but no FIDO2 section")
            }
            return try {
                val options = mutableListOf<String>()
                obj.optJSONArray("AssertOptions")?.let { arr ->
                    for (i in 0 until arr.length()) options.add(arr.getString(i))
                }
                GocryptfsFido2Params(
                    credentialId = Base64.getDecoder().decode(obj.getString("CredentialID")),
                    hmacSalt = Base64.getDecoder().decode(obj.getString("HMACSalt")),
                    assertOptions = options,
                )
            } catch (e: Exception) {
                throw GocryptfsConfigException("gocryptfs.conf has a malformed FIDO2 section: ${e.message}")
            }
        }
    }
}