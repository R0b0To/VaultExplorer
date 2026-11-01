package com.aeidolon.vaultexplorer.gocryptfs

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assume
import org.junit.Before
import org.junit.Test
import java.util.Base64

class GocryptfsConfigFido2Test {
    @Before
    fun requireJson() {
        val ok = try {
            JSONObject().put("x", 1)
            true
        } catch (e: RuntimeException) {
            false
        } catch (e: NoClassDefFoundError) {
            false
        }
        Assume.assumeTrue("Skipping: Android JSON framework not available on this host JVM", ok)
    }

    private val credential = ByteArray(96) { it.toByte() }
    private val hmacSalt = ByteArray(32) { (it + 100).toByte() }
    private fun b64(b: ByteArray) = Base64.getEncoder().encodeToString(b)

    private fun config(flags: List<String>, fido2: JSONObject? = null): ByteArray {
        val o = JSONObject()
        o.put("Creator", "gocryptfs 2.x")
        o.put("EncryptedKey", b64(ByteArray(48)))
        o.put(
            "ScryptObject",
            JSONObject().put("Salt", b64(ByteArray(32))).put("N", 65536).put("R", 8).put("P", 1).put("KeyLen", 32),
        )
        o.put("Version", 2)
        o.put("FeatureFlags", JSONArray(flags))
        if (fido2 != null) o.put("FIDO2", fido2)
        return o.toString().toByteArray()
    }

    private val base = listOf("GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF")

    @Test
    fun parsesTheFido2SectionAndAssertOptions() {
        val section = JSONObject()
            .put("CredentialID", b64(credential))
            .put("HMACSalt", b64(hmacSalt))
            .put("AssertOptions", JSONArray(listOf("pin=true")))
        val cfg = GocryptfsConfig.parse(config(base + "FIDO2", section))
        val f = cfg.fido2
        assertNotNull(f)
        assertArrayEquals(credential, f!!.credentialId)
        assertArrayEquals(hmacSalt, f.hmacSalt)
        assertEquals(listOf("pin=true"), f.assertOptions)
    }

    @Test
    fun assertOptionsMayBeAbsentOrNull() {
        val noOptions = JSONObject().put("CredentialID", b64(credential)).put("HMACSalt", b64(hmacSalt))
        assertEquals(emptyList<String>(), GocryptfsConfig.parse(config(base + "FIDO2", noOptions)).fido2!!.assertOptions)
        // Go marshals a nil slice as null
        val nullOptions = JSONObject().put("CredentialID", b64(credential)).put("HMACSalt", b64(hmacSalt)).put("AssertOptions", JSONObject.NULL)
        assertEquals(emptyList<String>(), GocryptfsConfig.parse(config(base + "FIDO2", nullOptions)).fido2!!.assertOptions)
    }

    @Test
    fun ordinaryVaultHasNoFido2Params() {
        assertNull(GocryptfsConfig.parse(config(base)).fido2)
    }

    @Test
    fun flagWithoutSectionIsRejectedUpFront() {
        assertThrows(GocryptfsConfigException::class.java) { GocryptfsConfig.parse(config(base + "FIDO2")) }
    }

    @Test
    fun malformedSectionIsRejected() {
        val bad = JSONObject().put("CredentialID", "***not base64***").put("HMACSalt", b64(hmacSalt))
        assertThrows(GocryptfsConfigException::class.java) { GocryptfsConfig.parse(config(base + "FIDO2", bad)) }
    }

    @Test
    fun writtenConfigRoundTripsThroughTheParser() {
        // The creator and the parser must agree on field names and encodings.
        // The creator uses android.util.Base64, which a bare host JVM stubs out.
        Assume.assumeTrue(
            "Skipping: android.util.Base64 not available on this host JVM",
            try {
                android.util.Base64.encodeToString(byteArrayOf(1), android.util.Base64.NO_WRAP)
                true
            } catch (e: RuntimeException) {
                false
            },
        )
        val params = GocryptfsFido2Params(credential, hmacSalt, listOf("pin=true"))
        val json = GocryptfsVault.buildConfigJson(
            encryptedKey = ByteArray(48),
            scryptSalt = ByteArray(32),
            scryptN = 65536,
            scryptR = 8,
            scryptP = 1,
            longNameMax = 255,
            featureFlags = base + "FIDO2",
            fido2 = params,
        )
        val cfg = GocryptfsConfig.parse(json.toByteArray())
        assertArrayEquals(credential, cfg.fido2!!.credentialId)
        assertArrayEquals(hmacSalt, cfg.fido2!!.hmacSalt)
        assertEquals(listOf("pin=true"), cfg.fido2!!.assertOptions)
    }
}
