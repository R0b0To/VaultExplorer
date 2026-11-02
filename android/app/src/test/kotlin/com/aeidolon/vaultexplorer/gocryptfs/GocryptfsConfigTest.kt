package com.aeidolon.vaultexplorer.gocryptfs

import java.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Before
import org.junit.Test

/**
 * Feature-flag handling in [GocryptfsConfig.parse], with the AES-SIV cases pinned to
 * gocryptfs's own validation rules (internal/configfile/validate.go) and to configs
 * written by the real binary. (The wider config/unlock tests in GocryptfsMasterkeyTest
 * are skipped without the native library; none of these need it.)
 */
class GocryptfsConfigTest {

    @Before
    fun setUp() {
        val isJsonAvailable = try {
            JSONObject().put("test", 1)
            true
        } catch (e: RuntimeException) {
            false
        } catch (e: NoClassDefFoundError) {
            false
        }
        Assume.assumeTrue("Skipping test: Android JSON framework not available on this host JVM", isJsonAvailable)
    }

    private fun configJson(flags: List<String>): ByteArray = JSONObject().apply {
        put("EncryptedKey", Base64.getEncoder().encodeToString(ByteArray(48)))
        put("ScryptObject", JSONObject().apply {
            put("Salt", Base64.getEncoder().encodeToString(ByteArray(16)))
            put("N", 16); put("R", 8); put("P", 1); put("KeyLen", 32)
        })
        put("Version", 2)
        put("FeatureFlags", JSONArray(flags))
    }.toString().toByteArray(Charsets.UTF_8)

    private fun parseError(flags: List<String>): String =
        assertThrows(GocryptfsConfigException::class.java) { GocryptfsConfig.parse(configJson(flags)) }.message!!

    // ---- accepted

    @Test
    fun `AESSIV together with GCMIV128 selects the AES-SIV cipher`() {
        val parsed = GocryptfsConfig.parse(
            configJson(listOf("GCMIV128", "HKDF", "DirIV", "EMENames", "LongNames", "Raw64", "AESSIV"))
        )
        assertEquals(GocryptfsCipher.AES_SIV, parsed.cipher)
        assertTrue("AESSIV" in parsed.featureFlags)
        assertTrue(parsed.hasDirIV)
        assertFalse(parsed.plaintextNames)
    }

    @Test
    fun `AESSIV with PlaintextNames is accepted (reverse mode with -plaintextnames)`() {
        val parsed = GocryptfsConfig.parse(configJson(listOf("GCMIV128", "HKDF", "PlaintextNames", "AESSIV")))
        assertEquals(GocryptfsCipher.AES_SIV, parsed.cipher)
        assertTrue(parsed.plaintextNames)
    }

    @Test
    fun `AESSIV without DirIV is accepted (deterministic names)`() {
        val parsed = GocryptfsConfig.parse(configJson(listOf("GCMIV128", "HKDF", "EMENames", "LongNames", "Raw64", "AESSIV")))
        assertEquals(GocryptfsCipher.AES_SIV, parsed.cipher)
        assertFalse(parsed.hasDirIV)
    }

    @Test
    fun `existing ciphers still resolve the same way`() {
        assertEquals(
            GocryptfsCipher.AES_256_GCM,
            GocryptfsConfig.parse(configJson(listOf("GCMIV128", "HKDF", "DirIV", "EMENames", "LongNames", "Raw64"))).cipher,
        )
        assertEquals(
            GocryptfsCipher.XCHACHA20_POLY1305,
            GocryptfsConfig.parse(configJson(listOf("XChaCha20Poly1305", "HKDF", "DirIV", "EMENames", "LongNames", "Raw64"))).cipher,
        )
    }

    // ---- rejected (same rules as gocryptfs validate.go)

    @Test
    fun `AESSIV without GCMIV128 is rejected`() {
        val message = parseError(listOf("HKDF", "DirIV", "EMENames", "LongNames", "Raw64", "AESSIV"))
        assertTrue(message, message.contains("AESSIV requires GCMIV128"))
    }

    @Test
    fun `AESSIV with XChaCha20Poly1305 is rejected as a conflict`() {
        val message = parseError(listOf("XChaCha20Poly1305", "AESSIV", "HKDF", "DirIV", "EMENames", "LongNames", "Raw64"))
        assertTrue(message, message.contains("XChaCha20Poly1305 conflicts with AESSIV"))
    }

    @Test
    fun `AESSIV is no longer reported as unsupported`() {
        val message = parseError(listOf("GCMIV128", "AESSIV", "DirIV", "EMENames", "LongNames", "Raw64")) // no HKDF
        assertFalse(message, message.contains("not yet supported"))
        assertTrue(message, message.contains("missing HKDF"))
    }

    // ---- real configs written by gocryptfs (tests/example_filesystems in the gocryptfs repo)

    // v1.3-reverse/.gocryptfs.reverse.conf: what `gocryptfs -reverse -init` writes. Password "test".
    private val realReverseConfig = """
        {"Creator": "gocryptfs v1.3",
         "EncryptedKey": "o6yhOpoaToWqs7iZMgx2J+dmrRcL8TOjqd7ntlqy4Y/g/ygNRADJXGITtEIDukf7FbGyn2JNZtWs/4ZOgLNmYw==",
         "ScryptObject": {"Salt": "8a64zpm0vXFg9uretHuwbxijzQmx2QF4hKOYM0yK/S8=", "N": 65536, "R": 8, "P": 1, "KeyLen": 32},
         "Version": 2,
         "FeatureFlags": ["GCMIV128", "HKDF", "DirIV", "EMENames", "LongNames", "Raw64", "AESSIV"]}
    """.trimIndent()

    @Test
    fun `a real gocryptfs reverse-mode config parses as AES-SIV and unlocks to the known masterkey`() {
        val parsed = GocryptfsConfig.parse(realReverseConfig.toByteArray(Charsets.UTF_8))
        assertEquals(GocryptfsCipher.AES_SIV, parsed.cipher)

        // The master key is always wrapped with AES-GCM + HKDF regardless of the content cipher,
        // so this exercises the unchanged unlock path against a genuine AESSIV config. Expected value:
        // upstream's own `-masterkey 2290a7f4-3e1908fb-b006f7d9-261bdaf1-4b72bc38-3b24956c-db7d8a8d-d996076a`.
        val expected = "2290a7f43e1908fbb006f7d9261bdaf14b72bc383b24956cdb7d8a8dd996076a"
            .chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val masterkey = GocryptfsMasterkey.unlock(parsed, "test".toCharArray())
        assertArrayEquals(expected, masterkey)

        // ...and the content key derives to the 64 bytes AES-SIV needs.
        val contentKey = Hkdf.deriveSha256(masterkey, parsed.cipher.hkdfInfo, parsed.cipher.contentKeyLen)
        assertEquals(64, contentKey.size)
        GocryptfsContentCryptor(contentKey, parsed.cipher) // accepted: key length matches the cipher
    }

    @Test
    fun `a real legacy v1_1 AES-SIV config without HKDF is still rejected by the existing HKDF rule`() {
        // v1.1-aessiv/gocryptfs.conf: written before HKDF/Raw64 existed. The app has never accepted
        // pre-HKDF vaults for any cipher; enabling AES-SIV does not change that.
        val legacy = """
            {"Creator": "gocryptfs v1.1-beta1-33-gf054353-dirty",
             "EncryptedKey": "y2ldEXg3Ui0jwic99bqvvrvGRPRDB7gYzvOBwZxcmWqRgcp3BLMShhIXwx3Pewmst5TivqSrK2r9wUIL",
             "ScryptObject": {"Salt": "oEt1In6W5UD1Pe9CFSz21x5ptTRluU43mmshUtmSwAk=", "N": 1024, "R": 8, "P": 1, "KeyLen": 32},
             "Version": 2,
             "FeatureFlags": ["GCMIV128", "DirIV", "EMENames", "LongNames", "AESSIV"]}
        """.trimIndent()
        val e = assertThrows(GocryptfsConfigException::class.java) { GocryptfsConfig.parse(legacy.toByteArray(Charsets.UTF_8)) }
        assertTrue(e.message!!, e.message!!.contains("missing HKDF"))
    }
}
