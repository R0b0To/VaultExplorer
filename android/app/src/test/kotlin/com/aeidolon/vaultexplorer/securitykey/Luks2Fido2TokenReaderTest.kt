package com.aeidolon.vaultexplorer.securitykey

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.util.Base64

/**
 * Builds LUKS2 headers byte-for-byte as described by the LUKS2 on-disk
 * format spec (4096-byte binary header, then a NUL-padded JSON area filling
 * the rest of hdr_size) and checks the systemd-fido2 token is found.
 */
class Luks2Fido2TokenReaderTest {
    @Before
    fun requireJson() {
        val ok = try {
            JSONObject().put("x", 1)
            true
        } catch (e: RuntimeException) {
            false // "Method put in org.json.JSONObject not mocked" on a bare host JVM
        } catch (e: NoClassDefFoundError) {
            false
        }
        Assume.assumeTrue("Skipping: Android JSON framework not available on this host JVM", ok)
    }

    private val credential = ByteArray(64) { (it * 3 + 1).toByte() }
    private val salt = ByteArray(32) { (0xFF - it).toByte() }
    private fun b64(b: ByteArray) = Base64.getEncoder().encodeToString(b)

    private fun header(json: String, hdrSize: Long = 16384, magic: ByteArray = byteArrayOf(0x4C, 0x55, 0x4B, 0x53, 0xBA.toByte(), 0xBE.toByte()), version: Int = 2): ByteArray {
        val out = ByteArray(hdrSize.toInt())
        magic.copyInto(out, 0)
        out[6] = (version shr 8).toByte()
        out[7] = version.toByte()
        for (i in 0 until 8) out[8 + i] = (hdrSize shr (8 * (7 - i))).toByte()
        val j = json.toByteArray(Charsets.UTF_8)
        j.copyInto(out, 4096) // remainder stays NUL-padded, as on disk
        return out
    }

    private fun tokenJson(extra: String = "", rp: String? = null) =
        """{"keyslots":{"0":{"type":"luks2"}},"tokens":{"0":{"type":"systemd-recovery","keyslots":["1"]},""" +
            """"1":{"type":"systemd-fido2","keyslots":["0"],"fido2-credential":"${b64(credential)}","fido2-salt":"${b64(salt)}"""" +
            (if (rp != null) ""","fido2-rp":"$rp"""" else "") + extra + """}}}"""

    @Test
    fun findsSystemdFido2TokenAmongOtherTokens() {
        val token = Luks2Fido2TokenReader.read(ByteArrayInputStream(header(tokenJson(""","fido2-clientPin-required":true,"fido2-up-required":true,"fido2-uv-required":false"""))))
        assertNotNull(token)
        assertArrayEquals(credential, token!!.credentialId)
        assertArrayEquals(salt, token.salt)
        assertTrue(token.policy.pin)
        assertEquals(true, token.policy.up)
        assertEquals(false, token.policy.uv)
    }

    @Test
    fun missingRpFallsBackToSystemdDefault() {
        val token = Luks2Fido2TokenReader.read(ByteArrayInputStream(header(tokenJson())))!!
        assertEquals("io.systemd.cryptsetup", token.rpId)
        assertFalse(token.policy.pin)
        assertNull(token.policy.up)
    }

    @Test
    fun explicitRpIsKept() {
        val token = Luks2Fido2TokenReader.read(ByteArrayInputStream(header(tokenJson(rp = "example.test"))))!!
        assertEquals("example.test", token.rpId)
    }

    @Test
    fun acceptsTheSecondaryHeaderMagic() {
        val secondary = byteArrayOf(0x53, 0x4B, 0x55, 0x4C, 0xBA.toByte(), 0xBE.toByte())
        assertNotNull(Luks2Fido2TokenReader.read(ByteArrayInputStream(header(tokenJson(), magic = secondary))))
    }

    @Test
    fun containerWithoutAFidoTokenYieldsNull() {
        assertNull(Luks2Fido2TokenReader.read(ByteArrayInputStream(header("""{"keyslots":{},"tokens":{"0":{"type":"systemd-tpm2"}}}"""))))
        assertNull(Luks2Fido2TokenReader.read(ByteArrayInputStream(header("""{"keyslots":{}}"""))))
    }

    @Test
    fun nonLuks2DataYieldsNull() {
        assertNull(Luks2Fido2TokenReader.read(ByteArrayInputStream(ByteArray(20000)))) // zeros: no magic
        assertNull(Luks2Fido2TokenReader.read(ByteArrayInputStream(header(tokenJson(), version = 1)))) // LUKS1 has no tokens
        assertNull(Luks2Fido2TokenReader.read(ByteArrayInputStream(ByteArray(100)))) // truncated
    }

    @Test
    fun absurdHeaderSizeIsRejectedWithoutAllocating() {
        val h = header(tokenJson())
        val huge = 1L shl 40
        for (i in 0 until 8) h[8 + i] = (huge shr (8 * (7 - i))).toByte()
        assertNull(Luks2Fido2TokenReader.read(ByteArrayInputStream(h)))
    }

    @Test
    fun passphraseIsStandardPaddedBase64OfTheSecret() {
        val secret = ByteArray(32) { (it * 7).toByte() }
        val p = Luks2Fido2Token.passphraseFor(secret)
        assertEquals(44, p.length)
        assertTrue(p.endsWith("="))
        assertArrayEquals(secret, Base64.getDecoder().decode(p))
    }
}
