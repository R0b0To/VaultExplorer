package com.aeidolon.vaultexplorer.util

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure JVM (java.security only). The known-answer vectors are the same ones
 * crypto/test/user_entropy_test.cpp checks against the native mixer, generated
 * independently with Python's hashlib -- that shared set is what keeps the two
 * implementations interchangeable.
 */
class UserEntropyTest {

    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }

    private val abc = "abc".toByteArray(Charsets.US_ASCII)
    private val seq = ByteArray(256) { it.toByte() }

    private val abcBlock0 =
        "4d82b192197f6acf18b25fb7a614234cccba32f491980a5b5e557c754c070f00" +
            "55b7ea618fa08a4522dfa3eb8cb475ea7cbaea174958d99734218f46b1c5751e"
    private val abcBlock1Prefix16 = "3db069c51204be1e6422515dd2e7e32b"

    @Test
    fun `seed and keystream blocks match the shared known answers`() {
        val seedAbc = UserEntropy.deriveSeed(abc)
        assertEquals(
            "7c00470b61007d223a813096dc10d2de10072461f61bc31ea5d52636c02f47d3" +
                "c956ee84b68d7ed20996d2f1444520b80e7fd8880674f782df3bcf7ea0eb5fcf",
            hex(seedAbc),
        )
        assertEquals(abcBlock0, hex(UserEntropy.keystreamBlock(seedAbc, 0)))
        assertEquals(
            "3db069c51204be1e6422515dd2e7e32b39c05ca232de6486a18a3d2f732fd784" +
                "58cf3a26b06df3909e0f32deff55a69bdb7e65a9ed0b45f31df5fa87d208509d",
            hex(UserEntropy.keystreamBlock(seedAbc, 1)),
        )

        val seedSeq = UserEntropy.deriveSeed(seq)
        assertEquals(
            "e99bd0d71f96e5fbf1b9cfdd3b56d52fb375e9644f2877f56f45d0fc247d6377" +
                "9733403eccc7ca1960b2ef0df07493e638ca31d5980a8818bc29b9bf4fac2cf8",
            hex(seedSeq),
        )
        assertEquals(
            "f829110957796a853df92a16f2a4230c86b2bacf8749487654f4fbf263eeff04" +
                "e9d47b03044dfbe1b1b37b2f4b81a229115f43618b071426614fa1a06c42ee56",
            hex(UserEntropy.keystreamBlock(seedSeq, 0)),
        )
    }

    @Test
    fun `applyKeystream xors exactly the documented stream across a block boundary`() {
        val mixed = MixedSecureRandom(abc)
        val out = ByteArray(80)
        mixed.applyKeystream(out)
        assertEquals(abcBlock0, hex(out.copyOfRange(0, 64)))
        assertEquals(abcBlock1Prefix16, hex(out.copyOfRange(64, 80)))
    }

    @Test
    fun `the stream is consumed sequentially across calls and never reused`() {
        val a = MixedSecureRandom(abc)
        val first = ByteArray(48).also { a.applyKeystream(it) }
        val second = ByteArray(48).also { a.applyKeystream(it) }
        assertFalse(first.contentEquals(second))

        // The same bytes in one go match the two calls back to back.
        val whole = ByteArray(96).also { MixedSecureRandom(abc).applyKeystream(it) }
        assertArrayEquals(first, whole.copyOfRange(0, 48))
        assertArrayEquals(second, whole.copyOfRange(48, 96))
    }

    @Test
    fun `different inputs give different streams`() {
        val x = ByteArray(64).also { MixedSecureRandom("abc".toByteArray()).applyKeystream(it) }
        val y = ByteArray(64).also { MixedSecureRandom("abd".toByteArray()).applyKeystream(it) }
        assertFalse(x.contentEquals(y))
    }

    @Test
    fun `secureRandomFor returns a plain generator when there is no user entropy`() {
        assertFalse(UserEntropy.secureRandomFor(null) is MixedSecureRandom)
        assertFalse(UserEntropy.secureRandomFor(ByteArray(0)) is MixedSecureRandom)
        assertTrue(UserEntropy.secureRandomFor(abc) is MixedSecureRandom)
    }

    @Test
    fun `mixed generator still produces independent random output`() {
        val r1 = UserEntropy.secureRandomFor(abc)
        val r2 = UserEntropy.secureRandomFor(abc)
        val a = ByteArray(64).also { r1.nextBytes(it) }
        val b = ByteArray(64).also { r2.nextBytes(it) }
        // Same user entropy, but the system generator underneath differs.
        assertFalse(a.contentEquals(b))

        // next*() helpers of SecureRandom route through nextBytes().
        val ints = (0 until 8).map { r1.nextInt() }.toSet()
        assertTrue(ints.size > 1)
        assertNotEquals(0, ByteArray(32).also { r1.nextBytes(it) }.sumOf { it.toInt() and 0xFF })
    }
}
