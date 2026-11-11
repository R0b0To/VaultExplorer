package com.aeidolon.vaultexplorer.gocryptfs

import java.security.SecureRandom
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

/**
 * Compatibility with the official gocryptfs (github.com/rfjakob/gocryptfs). The vault data below is copied
 * verbatim from its tests/example_filesystems (password "test"); the master keys were derived independently
 * of this code (scrypt, then AES-GCM) and are the keys gocryptfs itself finds. The rules are those of
 * internal/configfile/validate.go.
 */
class GocryptfsOfficialCompatTest {
    @Before
    fun requireJsonImplementation() {
        // org.json is a stub on the plain JVM unit-test classpath.
        val usable = try { JSONObject("{\"a\":1}").getInt("a") == 1 } catch (_: Throwable) { false }
        assumeTrue("org.json is not available in this unit-test environment", usable)
    }

    private fun hex(s: String): ByteArray = s.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    private fun config(json: String) = GocryptfsConfig.parse(json.toByteArray(Charsets.UTF_8))
    private val pw = "test".toCharArray()

    // tests/example_filesystems/v0.7: gocryptfs 0.7 -- no HKDF, no Raw64, no LongNames
    private val v07 = """{"EncryptedKey": "0crm+qEf00XPxQrc8NIMp/0rgfaLb8wzTj+3G1slSytjsLHctj/fOKkGJIFyBk7xzvnWdkhyxxvHgfMS", "ScryptObject": {"Salt": "yZn+QMjR2ENZ6MoiURpqEqr8mgnCX8WN87KJafgiXhU=", "N": 1024, "R": 8, "P": 1, "KeyLen": 32}, "Version": 2, "FeatureFlags": ["GCMIV128", "DirIV", "EMENames"]}"""
    // tests/example_filesystems/v0.9: adds LongNames (still no HKDF / Raw64)
    private val v09 = """{"EncryptedKey": "sAB/dsiDbFBbMr7ppsB3Fu81hVr6BBxlcfY1wZYRHlRvRV2uwRdYAACNM39CDxLBHZuNjk9UyWh87McP", "ScryptObject": {"Salt": "3mphl9Hmhzd6exmc8Um0jOOCgR8hAYvbzbEpTnIEMPg=", "N": 1024, "R": 8, "P": 1, "KeyLen": 32}, "Version": 2, "FeatureFlags": ["GCMIV128", "DirIV", "EMENames", "LongNames"]}"""

    @Test
    fun `v0_7 vault without HKDF and Raw64 unlocks and its padded-base64 names decrypt`() {
        val c = config(v07)
        assertFalse(c.hasHkdf)
        assertFalse(c.raw64)
        assertTrue(c.hasDirIV)
        assertEquals(GocryptfsCipher.AES_256_GCM, c.cipher)

        val masterkey = GocryptfsMasterkey.unlock(c, pw)
        assertArrayEquals(hex("ed7f6d8340cce86c0e7d79c2a9438710575221bf30a0eb602821fa8f7f3123bf"), masterkey)
        val (nameKey, contentKey) = GocryptfsMasterkey.deriveKeys(c, masterkey)
        assertArrayEquals(masterkey, nameKey)       // no HKDF: the master key is used as-is
        assertArrayEquals(masterkey, contentKey)

        val names = GocryptfsFileNameCryptor(nameKey, c.longNameMax, false, c.raw64)
        val dirIv = hex("df69c8a4b75c3f13858c3dd1ce014d63")
        val onDisk = listOf("4tRF1LdULRFLiXwfze671Q==", "RWPXmXkRFrWw1aOpq7C-NQ==", "dwPcZNei4HN4qPA6FxoG_A==")
        assertEquals(setOf("abs", "rel", "status.txt"), onDisk.map { names.decryptName(it, dirIv) }.toSet())
        for (n in onDisk) assertEquals(n, names.encryptName(names.decryptName(n, dirIv), dirIv))
    }

    @Test
    fun `v0_9 long name with padded base64 hashes to the official file name`() {
        val c = config(v09)
        val masterkey = GocryptfsMasterkey.unlock(c, pw)
        assertArrayEquals(hex("1cafe3f4bc3164662214c47cecd89bf34e078fe4f5faeea78b7cab02884f5e1c"), masterkey)
        val names = GocryptfsFileNameCryptor(GocryptfsMasterkey.deriveKeys(c, masterkey).first, c.longNameMax, false, c.raw64)
        // contents of gocryptfs.longname.<hash>.name: the full encrypted name
        val sidecar = "Py7wkyXYf1YXvFvHuizOqva6WWWYEQ-JYv1rOAvWWaARLyGdQdxuW-iBf1Vwd8orZjqkcIGgnxOfuRsarXKmn4-3L2MRIZKPhhx2QRqpPRtFylEABH1KwZ_2ZZnx5cpcO8TIoeVdL6NXnRw-WrT06zTUzVRioNPRLPa0J6c8_eb5QFb4EG5wPpn-XlJSedjAw31MUNvFxKYQku_UwJF0CvvXLCozVnNM_dDNWsgBevzB8VBySbfW7XgYMRPJRlJe3Pjeues9tyGJvAxGJVjfo4nZyWusMF2G4f9w06m3Bxjc7ladgJR6F6pyI4Z65DCIL7G6G2y__agmNcKtFwCS_Q=="
        assertEquals(344, sidecar.length)
        assertEquals("longname_255_" + "x".repeat(242), names.decryptName(sidecar, hex("11ff7e48d5e6e18717417cd481c8e3ad")))
        assertEquals("gocryptfs.longname.y4J-w3LBX165Mn_pGdDRY7Gb6EgHcTrdWjME3WGu-CQ=", names.hashLongName(sidecar))
        assertTrue(names.isOverLongNameLimit(sidecar))
    }

    private fun cfg(flags: List<String>, longNameMax: Int? = null, version: Int = 2): ByteArray {
        val o = JSONObject()
        o.put("EncryptedKey", java.util.Base64.getEncoder().encodeToString(ByteArray(64)))
        o.put("ScryptObject", JSONObject().put("Salt", java.util.Base64.getEncoder().encodeToString(ByteArray(32)))
            .put("N", 1024).put("R", 8).put("P", 1).put("KeyLen", 32))
        o.put("Version", version)
        o.put("FeatureFlags", JSONArray(flags))
        if (longNameMax != null) o.put("LongNameMax", longNameMax)
        return o.toString().toByteArray(Charsets.UTF_8)
    }

    private fun rejected(flags: List<String>, longNameMax: Int? = null): String =
        assertThrows(GocryptfsConfigException::class.java) { GocryptfsConfig.parse(cfg(flags, longNameMax)) }.message!!

    private val base = listOf("HKDF", "GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64")

    @Test
    fun `LongNameMax flag and field must agree and fit a uint8`() {
        assertEquals(100, GocryptfsConfig.parse(cfg(base + "LongNameMax", 100)).longNameMax)
        assertEquals(0, GocryptfsConfig.parse(cfg(base)).longNameMax)
        assertTrue(rejected(base, 100).contains("LongNameMax feature flag is NOT set"))
        assertTrue(rejected(base + "LongNameMax", 0).contains("feature flag IS set"))
        assertTrue(rejected(base + "LongNameMax").contains("feature flag IS set"))
        assertTrue(rejected(base + "LongNameMax", 300).contains("between 0 and 255"))
        assertTrue(rejected(base + "LongNameMax", -1).contains("between 0 and 255"))
    }

    @Test
    fun `deterministic-names vaults are just vaults without the DirIV flag`() {
        val c = GocryptfsConfig.parse(cfg(listOf("HKDF", "GCMIV128", "EMENames", "LongNames", "Raw64")))
        assertFalse(c.hasDirIV)
        assertTrue(c.deterministicNames)
        assertFalse(GocryptfsConfig.parse(cfg(base)).deterministicNames)
        assertFalse(GocryptfsConfig.parse(cfg(listOf("HKDF", "GCMIV128", "PlaintextNames"))).deterministicNames)
    }

    @Test
    fun `flag combinations are accepted and refused exactly like gocryptfs Validate`() {
        // accepted by gocryptfs
        GocryptfsConfig.parse(cfg(listOf("GCMIV128", "DirIV", "EMENames")))                    // v0.7
        GocryptfsConfig.parse(cfg(listOf("HKDF", "GCMIV128", "DirIV", "LongNames", "Raw64"))) // EMENames is never required
        GocryptfsConfig.parse(cfg(listOf("HKDF", "XChaCha20Poly1305", "DirIV", "EMENames")))
        GocryptfsConfig.parse(cfg(listOf("HKDF", "GCMIV128", "PlaintextNames")))
        // refused by gocryptfs
        assertTrue(rejected(listOf("HKDF", "DirIV", "EMENames")).contains("AES-GCM requires GCMIV128"))
        assertTrue(rejected(listOf("HKDF", "AESSIV", "DirIV")).contains("AESSIV requires GCMIV128"))
        assertTrue(rejected(listOf("HKDF", "XChaCha20Poly1305", "GCMIV128")).contains("conflicts with GCMIV128"))
        assertTrue(rejected(listOf("HKDF", "XChaCha20Poly1305", "AESSIV")).contains("conflicts with AESSIV"))
        assertTrue(rejected(listOf("XChaCha20Poly1305", "DirIV")).contains("requires HKDF"))
        assertTrue(rejected(listOf("HKDF", "GCMIV128", "Bogus")).contains("unknown feature flags"))
        for (f in listOf("EMENames", "DirIV", "LongNames", "Raw64")) {
            assertTrue(rejected(listOf("HKDF", "GCMIV128", "PlaintextNames", f)).contains("PlaintextNames conflicts with $f"))
        }
    }

    @Test
    fun `a FIDO2 vault parses but cannot be unlocked with a password`() {
        val c = GocryptfsConfig.parse(cfg(listOf("HKDF", "GCMIV128", "DirIV", "EMENames", "FIDO2")))
        assertTrue(c.fido2)
        assertTrue(assertThrows(GocryptfsConfigException::class.java) { GocryptfsMasterkey.unlock(c, pw) }.message!!.contains("FIDO2"))
    }

    @Test
    fun `wrap without HKDF writes a 96-bit nonce and unlock reads it back`() {
        val masterkey = ByteArray(32) { it.toByte() }
        val salt = ByteArray(32) { (it + 1).toByte() }
        val password = "pw".toCharArray()
        val blob = GocryptfsMasterkey.wrap(masterkey, password, salt, 16, 8, 32, SecureRandom(), hkdf = false)
        assertEquals(12 + 32 + 16, blob.size)
        val legacy = GocryptfsConfig(blob, salt, 16, 8, 1, 32, 2, setOf("GCMIV128", "DirIV", "EMENames"), 0, GocryptfsCipher.AES_256_GCM, false)
        assertArrayEquals(masterkey, GocryptfsMasterkey.unlock(legacy, password))
        // read as an HKDF vault the same blob must be refused, not decrypt to garbage
        val asHkdf = legacy.copy(featureFlags = legacy.featureFlags + "HKDF")
        assertThrows(GocryptfsWrongPasswordException::class.java) { GocryptfsMasterkey.unlock(asHkdf, password) }
        assertEquals(16 + 32 + 16, GocryptfsMasterkey.wrap(masterkey, password, salt, 16, 8, 32, SecureRandom()).size)
    }
}
