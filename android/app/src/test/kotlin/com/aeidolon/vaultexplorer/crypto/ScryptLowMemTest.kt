package com.aeidolon.vaultexplorer.crypto

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * The low-memory scrypt entry point (used for CryFS, whose official settings can need 512 MiB-1 GiB) must give the
 * regular result, and must refuse -- rather than exhaust the Android heap -- when only the pure-JVM fallback exists
 * and the parameters are large. (The native 1 GiB case is covered by the native test suite, against OpenSSL.)
 */
class ScryptLowMemTest {

    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }

    @Test
    fun `low-memory scrypt equals the regular result and the OpenSSL reference value`() {
        val pw = "pw".toByteArray()
        val salt = "salt".toByteArray()
        val regular = Scrypt.scrypt(pw, salt, 1024, 8, 32, 2)
        val lowMem = Scrypt.scryptLowMem(pw, salt, 1024, 8, 32, 2)
        assertEquals(hex(regular), hex(lowMem))
        // Reference value computed with OpenSSL's scrypt (Python hashlib.scrypt), independent of this code base.
        assertEquals("4f2c2a6104b12e0c6e8c68f18654c503092d880124c2c3430a48c183e0b52abc", hex(lowMem))
    }

    @Test
    fun `huge parameters are refused when no native library is available`() {
        // N=2^20, r=8 needs a 1 GiB array: fine natively (time-memory trade-off), fatal on the JVM heap.
        assertThrows(UnsupportedOperationException::class.java) {
            Scrypt.scryptLowMem("pw".toByteArray(), "salt".toByteArray(), 1 shl 20, 8, 32, 1)
        }
    }
}
