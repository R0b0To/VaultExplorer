package com.aeidolon.vaultexplorer.gocryptfs

import org.json.JSONObject
import java.util.Base64

class GocryptfsConfigException(message: String) : Exception(message)

/** Which AEAD gocryptfs uses for file content, derived from FeatureFlags.
 *  Mutually exclusive on disk: GCMIV128 XOR XChaCha20Poly1305 (validated in
 *  [GocryptfsConfig.parse]). */
enum class GocryptfsCipher { AES_256_GCM, XCHACHA20_POLY1305 }

/** Flags this integration always requires, regardless of cipher — names are
 *  always EME + Raw64 + LongNames, and the masterkey is always HKDF-derived.
 *  Anything else unrecognized (PlaintextNames, AESSIV-only reverse vaults,
 *  FIDO2, no-HKDF legacy filesystems) is rejected explicitly rather than
 *  guessed at — mirrors CryptomatorVault.open's vaultFormat 7..8 gate. */
private val BASE_REQUIRED_FLAGS = setOf("EMENames", "LongNames", "Raw64", "HKDF")

/** DirIV is optional (added as an opt-out in gocryptfs v2.2): when present,
 *  each directory's name-encryption tweak is a random 16-byte IV read from
 *  its own gocryptfs.diriv; when absent, "deterministic names" mode applies
 *  and the tweak is a fixed all-zero 16-byte IV instead — see
 *  GocryptfsVaultTree.dirivFor. GCMIV128 and XChaCha20Poly1305 are the two
 *  recognized content ciphers and are mutually exclusive (XChaCha uses a
 *  192-bit nonce instead of GCM's 128-bit one, so the flag that picks the
 *  nonce size differs per cipher). */
private val KNOWN_FLAGS = BASE_REQUIRED_FLAGS + setOf("GCMIV128", "DirIV", "XChaCha20Poly1305")

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
    /** false => deterministic (all-zero) per-directory name tweak, no
     *  gocryptfs.diriv file involved. */
    val hasDirIV: Boolean get() = "DirIV" in featureFlags
    val cipher: GocryptfsCipher get() =
        if ("XChaCha20Poly1305" in featureFlags) GocryptfsCipher.XCHACHA20_POLY1305 else GocryptfsCipher.AES_256_GCM

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

            // Mirrors gocryptfs's own validate.go/feature_flags.go rules (as of
            // v2.6.1), not an arbitrary exact-match set: DirIV is optional,
            // GCMIV128 is required unless XChaCha20Poly1305 is set (in which
            // case it's forbidden — the two use different nonce sizes), and
            // XChaCha20Poly1305 always requires HKDF.
            val missing = BASE_REQUIRED_FLAGS - flags
            val unsupported = flags - KNOWN_FLAGS
            val hasGcmIv128 = "GCMIV128" in flags
            val hasXChaCha = "XChaCha20Poly1305" in flags
            val problems = mutableListOf<String>()
            if (missing.isNotEmpty()) problems += "missing required flags $missing"
            if (unsupported.isNotEmpty()) problems += "unsupported feature flags $unsupported"
            if (hasGcmIv128 && hasXChaCha) problems += "GCMIV128 and XChaCha20Poly1305 are mutually exclusive"
            if (!hasGcmIv128 && !hasXChaCha) problems += "missing GCMIV128 (required unless XChaCha20Poly1305 is set)"
            if (problems.isNotEmpty()) {
                throw GocryptfsConfigException(
                    "Unsupported gocryptfs feature flags: ${problems.joinToString("; ")}. " +
                        "This app supports vaults created with gocryptfs's modern defaults " +
                        "(AES-256-GCM or XChaCha20-Poly1305 content encryption, with or without DirIV)."
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