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

    /** Without HKDF (gocryptfs <= 1.2) the master key is used as-is and the config's own key wrap has a 96-bit nonce. */
    val hasHkdf: Boolean get() = "HKDF" in featureFlags

    /** Without Raw64 (gocryptfs <= 1.6) names and long-name hashes are padded base64. */
    val raw64: Boolean get() = "Raw64" in featureFlags

    /** `-fido2`: the scrypt input comes from a hardware token instead of a password. */
    val fido2: Boolean get() = "FIDO2" in featureFlags

    /** `-deterministic-names`: no DirIV flag, hence no gocryptfs.diriv files and an all-zero IV everywhere. */
    val deterministicNames: Boolean get() = !plaintextNames && !hasDirIV

    companion object {
        // Every flag gocryptfs knows (internal/configfile/feature_flags.go); anything else it refuses.
        private val KNOWN_FLAGS = setOf(
            "PlaintextNames", "DirIV", "EMENames", "GCMIV128", "LongNames", "LongNameMax",
            "AESSIV", "Raw64", "HKDF", "FIDO2", "XChaCha20Poly1305",
        )

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

            val longNameMax = if (json.has("LongNameMax")) json.optInt("LongNameMax", -1) else 0
            if (longNameMax < 0 || longNameMax > 255) {
                throw GocryptfsConfigException("gocryptfs.conf: LongNameMax must be a number between 0 and 255")
            }

            // gocryptfs does not require HKDF (except for XChaCha20), EMENames or Raw64: vaults from before those
            // existed (v0.7 .. v1.2) are still mounted by it, and so are they here.
            val problems = mutableListOf<String>()
            val unsupported = flags - KNOWN_FLAGS
            if (unsupported.isNotEmpty()) problems += "unknown feature flags $unsupported"

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
                !hasXChaCha && !hasGcmIv128 -> problems += "AES-GCM requires GCMIV128 feature flag"
            }
            if (hasXChaCha && !hasAessiv && !hasGcmIv128 && "HKDF" !in flags) problems += "XChaCha20Poly1305 requires HKDF feature flag"

            if (hasPlaintextNames) {
                for (f in listOf("EMENames", "DirIV", "LongNames", "Raw64", "LongNameMax")) {
                    if (f in flags) problems += "PlaintextNames conflicts with $f feature flag"
                }
            }
            if (longNameMax != 0 && "LongNameMax" !in flags) {
                problems += "LongNameMax=$longNameMax but the LongNameMax feature flag is NOT set"
            }
            if (longNameMax == 0 && "LongNameMax" in flags) {
                problems += "LongNameMax=0 but the LongNameMax feature flag IS set"
            }

            if (problems.isNotEmpty()) {
                throw GocryptfsConfigException(
                    "Unsupported gocryptfs feature flags: ${problems.joinToString("; ")}. " +
                        "This app supports gocryptfs vaults (on-disk format 2) with AES-256-GCM, XChaCha20-Poly1305 or AES-SIV."
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
                longNameMax = longNameMax,
                cipher = cipher,
                plaintextNames = hasPlaintextNames,
            )
        }
    }
}