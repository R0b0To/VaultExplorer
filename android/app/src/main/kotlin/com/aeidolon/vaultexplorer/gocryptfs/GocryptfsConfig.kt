package com.aeidolon.vaultexplorer.gocryptfs

import org.json.JSONObject
import java.util.Base64

class GocryptfsConfigException(message: String) : Exception(message)

enum class GocryptfsCipher { AES_256_GCM, AES_256_GCM_IV96, XCHACHA20_POLY1305 }

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
            val hasGcmIv96 = "GCMIV96" in flags
            val hasXChaCha = "XChaCha20Poly1305" in flags
            val hasAessiv = "AESSIV" in flags
            val hasPlaintextNames = "PlaintextNames" in flags

            val cipherCount = listOf(hasGcmIv128, hasGcmIv96, hasXChaCha, hasAessiv).count { it }

            val problems = mutableListOf<String>()
            if (!flags.contains("HKDF")) problems += "missing HKDF"
            if (!hasPlaintextNames) {
                if (!flags.contains("EMENames")) problems += "missing EMENames"
                if (!flags.contains("Raw64")) problems += "missing Raw64"
            }

            val unsupported = flags - setOf("GCMIV128", "GCMIV96", "XChaCha20Poly1305", "AESSIV", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF", "PlaintextNames", "FIDO2")
            
            if (unsupported.isNotEmpty()) problems += "unsupported feature flags $unsupported"
            if (cipherCount > 1) problems += "multiple mutually exclusive cipher flags set"
            if (cipherCount == 0) problems += "missing a content cipher flag"
            if (hasAessiv) problems += "AES-SIV content encryption is not yet supported in VaultExplorer"

            if (problems.isNotEmpty()) {
                throw GocryptfsConfigException(
                    "Unsupported gocryptfs feature flags: ${problems.joinToString("; ")}. " +
                        "This app supports standard vaults created with AES-256-GCM or XChaCha20-Poly1305."
                )
            }

            val cipher = when {
                hasXChaCha -> GocryptfsCipher.XCHACHA20_POLY1305
                hasGcmIv96 -> GocryptfsCipher.AES_256_GCM_IV96
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