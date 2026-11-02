package com.aeidolon.vaultexplorer.gocryptfs

import org.json.JSONObject
import java.util.Base64

class GocryptfsConfigException(message: String) : Exception(message)

/**
 * The three gocryptfs content ciphers. The per-cipher constants live here, in
 * one place, so the unlock / create / folder-check paths can't drift apart
 * (e.g. derive a 32-byte key for a cipher that needs 64).
 *
 * @property hkdfInfo HKDF-SHA256 "info" string the content key is derived with
 *   (gocryptfs internal/cryptocore/hkdf.go).
 * @property contentKeyLen Length of the derived content key in bytes. AES-SIV
 *   needs 64 because RFC 5297 splits the key in half (S2V key | CTR key); the
 *   other two ciphers use a single 32-byte key.
 * @property nonceLen Per-block nonce length stored in front of each ciphertext
 *   block. AES-SIV uses a 16-byte nonce too (it is fed to SIV as the last
 *   associated-data element, not as an IV), so its block layout is
 *   `nonce(16) | siv-tag(16) | ciphertext` -- the same 4128-byte full block as
 *   AES-GCM, but NOT the same bytes.
 */
enum class GocryptfsCipher(
    val hkdfInfo: String,
    val contentKeyLen: Int,
    val nonceLen: Int,
) {
    AES_256_GCM("AES-GCM file content encryption", 32, 16),
    XCHACHA20_POLY1305("XChaCha20-Poly1305 file content encryption", 32, 24),
    AES_SIV("AES-SIV file content encryption", 64, 16),
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
            // than being an alternative to it, XChaCha20Poly1305 *conflicts*
            // with GCMIV128, and XChaCha20Poly1305 and AESSIV can't be
            // combined. (`gocryptfs -init -aessiv` and `-reverse` both write
            // GCMIV128 + AESSIV.)
            when {
                hasXChaCha && hasAessiv -> problems += "XChaCha20Poly1305 conflicts with AESSIV"
                hasXChaCha && hasGcmIv128 -> problems += "XChaCha20Poly1305 conflicts with GCMIV128"
                hasAessiv && !hasGcmIv128 -> problems += "AESSIV requires GCMIV128"
                !hasXChaCha && !hasGcmIv128 -> problems += "missing a content cipher feature flag"
            }

            if (problems.isNotEmpty()) {
                throw GocryptfsConfigException(
                    "Unsupported gocryptfs feature flags: ${problems.joinToString("; ")}. " +
                        "This app supports standard vaults created with AES-256-GCM, XChaCha20-Poly1305 or AES-SIV."
                )
            }

            // Three outcomes reach here: hasXChaCha (with neither GCMIV128 nor
            // AESSIV, enforced above), hasAessiv (always with GCMIV128, so it
            // must be tested before the plain-GCM fallthrough), or plain
            // GCMIV128 -- every other combination already threw.
            val cipher = when {
                hasXChaCha -> GocryptfsCipher.XCHACHA20_POLY1305
                hasAessiv -> GocryptfsCipher.AES_SIV
                else -> GocryptfsCipher.AES_256_GCM
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
                cipher = cipher,
                plaintextNames = hasPlaintextNames,
            )
        }
    }
}