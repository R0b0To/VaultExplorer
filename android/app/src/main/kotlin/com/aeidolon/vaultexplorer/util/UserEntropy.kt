package com.aeidolon.vaultexplorer.util

import java.security.MessageDigest
import java.security.SecureRandom

/**
 * JVM counterpart of the native `userentropy` mixer (crypto/user_entropy.h) for
 * the vault formats that generate their keys in Kotlin rather than in C++:
 * Cryptomator, gocryptfs and CryFS.
 *
 * The creation wizards collect entropy from the user's touch movement (a
 * `ByteArray`, null/empty when the user skipped the step). [secureRandomFor]
 * turns it into a [SecureRandom] whose output is
 *
 *     system SecureRandom bytes  XOR  keystream(user entropy)
 *
 * The keystream depends only on the user input and the system bytes are
 * independent of it, so the result is exactly as uniform as the system
 * generator alone: the user's contribution can protect against a weak OS RNG
 * (the point of VeraCrypt's pool) but can never reduce the entropy, even if the
 * input is low quality or attacker-controlled. There is no fallback to user
 * entropy alone.
 *
 * Construction -- byte-for-byte the same as the native mixer, and covered by
 * the same known-answer vectors in UserEntropyTest / user_entropy_test.cpp:
 *
 *     seed    = SHA-512( "VaultExplorer/user-entropy/v1" || u32be(len) || input )
 *     block_i = SHA-512( seed || u64be(i) )           i = 0, 1, 2, ...
 *     stream  = block_0 || block_1 || ...             consumed sequentially,
 *                                                     never reused or rewound
 */
object UserEntropy {
    private const val DOMAIN = "VaultExplorer/user-entropy/v1"
    internal const val SEED_SIZE = 64
    internal const val BLOCK_SIZE = 64

    /**
     * Returns a plain [SecureRandom] when [userEntropy] is null or empty,
     * otherwise one that mixes it into everything it produces. The caller keeps
     * ownership of [userEntropy] (and should wipe it); only a 64-byte seed
     * derived from it is retained.
     */
    @JvmStatic
    fun secureRandomFor(userEntropy: ByteArray?): SecureRandom =
        if (userEntropy == null || userEntropy.isEmpty()) SecureRandom() else MixedSecureRandom(userEntropy)

    internal fun deriveSeed(input: ByteArray): ByteArray {
        val md = MessageDigest.getInstance("SHA-512")
        md.update(DOMAIN.toByteArray(Charsets.US_ASCII))
        val n = input.size
        md.update(
            byteArrayOf(
                (n ushr 24).toByte(), (n ushr 16).toByte(), (n ushr 8).toByte(), n.toByte(),
            )
        )
        md.update(input)
        return md.digest()
    }

    internal fun keystreamBlock(seed: ByteArray, counter: Long): ByteArray {
        val md = MessageDigest.getInstance("SHA-512")
        md.update(seed)
        val ctr = ByteArray(8)
        for (i in 0 until 8) ctr[i] = (counter ushr (56 - 8 * i)).toByte()
        md.update(ctr)
        return md.digest()
    }
}

/** See [UserEntropy]. Overriding [nextBytes] is enough: every other `next*` of [SecureRandom] routes through it. */
internal class MixedSecureRandom(userEntropy: ByteArray) : SecureRandom() {
    private val seed: ByteArray = UserEntropy.deriveSeed(userEntropy)
    private var counter: Long = 0L
    private var block: ByteArray = ByteArray(UserEntropy.BLOCK_SIZE)
    private var blockPos: Int = UserEntropy.BLOCK_SIZE  // forces block 0 on first use

    @Synchronized
    override fun nextBytes(bytes: ByteArray) {
        super.nextBytes(bytes)
        applyKeystream(bytes)
    }

    /** XORs the next `bytes.size` keystream bytes into [bytes]. Exposed for the known-answer tests. */
    @Synchronized
    internal fun applyKeystream(bytes: ByteArray) {
        for (i in bytes.indices) {
            if (blockPos == UserEntropy.BLOCK_SIZE) {
                block = UserEntropy.keystreamBlock(seed, counter)
                counter++
                blockPos = 0
            }
            bytes[i] = (bytes[i].toInt() xor block[blockPos].toInt()).toByte()
            blockPos++
        }
    }
}
