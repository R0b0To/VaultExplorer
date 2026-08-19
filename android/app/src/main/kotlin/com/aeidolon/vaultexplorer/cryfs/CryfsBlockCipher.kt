package com.aeidolon.vaultexplorer.cryfs

import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.crypto.ChaCha20Poly1305
import java.security.GeneralSecurityException
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

class CryfsUnsupportedCipherException(cipherName: String) :
    Exception("Vault uses cipher \"$cipherName\", which this app does not support.")

/**
 * Cipher IDs, matching CryfsCipherId in crypto/cryfs_block_cipher.h exactly
 * (kUnknown there is 255; NativeEngine's JNI layer already translates that
 * to -1 for this Kotlin-side "unsupported" contract, so the fallback below
 * does the same).
 */
private const val AES_256_GCM = 0
private const val AES_256_CFB = 1
private const val AES_128_GCM = 2
private const val AES_128_CFB = 3
private const val XCHACHA20_POLY1305 = 4
private const val UNSUPPORTED = -1

object CryfsBlockCipher {

    /**
     * The C++ reference this whole object mirrors: crypto/cryfs_block_cipher.cpp.
     * Byte layouts (must match exactly, since either side may write a block
     * the other reads back):
     *  - AES-*-GCM:          16-byte random IV | ciphertext | 16-byte GCM tag  (no AAD)
     *  - AES-*-CFB:          16-byte random IV | ciphertext                    (no tag -- unauthenticated)
     *  - xchacha20-poly1305: 24-byte random nonce | ciphertext | 16-byte Poly1305 tag  (no AAD)
     */
    private const val IV_SIZE = 16
    private const val GCM_TAG_BITS = 128
    private const val GCM_TAG_SIZE = 16
    private const val XCHACHA_NONCE_SIZE = 24
    private const val XCHACHA_TAG_SIZE = 16

    private val secureRandom = SecureRandom()

    /**
     * Why every native call here goes through a try/catch instead of a
     * plain call: on a plain JVM (this module's src/test/kotlin unit
     * tests, no Android runtime, no .so on the classpath), a bare
     * NativeEngine.cryfs*Native(...) call throws UnsatisfiedLinkError
     * (first touch) or NoClassDefFoundError (every touch after that)
     * instead of ever reaching this function's body -- the try/catch has
     * to live at the call site, in an already-initialized class, for it
     * to actually catch that. Mirrors SivMode.kt / GocryptfsEme.kt.
     */
    private inline fun nativeCipherIdOrNull(call: () -> Int): Int? = try {
        call()
    } catch (e: UnsatisfiedLinkError) {
        null
    } catch (e: NoClassDefFoundError) {
        null
    }

    private inline fun nativeBytesOrNull(call: () -> ByteArray?): ByteArray? = try {
        call()
    } catch (e: UnsatisfiedLinkError) {
        null
    } catch (e: NoClassDefFoundError) {
        null
    }

    /** @throws CryfsUnsupportedCipherException if [cipherName] isn't one this app implements. */
    fun cipherIdFor(cipherName: String): Int {
        val id = nativeCipherIdOrNull { NativeEngine.cryfsCipherIdNative(cipherName) }
            ?: cipherIdForFallback(cipherName)
        if (id < 0) throw CryfsUnsupportedCipherException(cipherName)
        return id
    }

    private fun cipherIdForFallback(cipherName: String): Int = when (cipherName) {
        "aes-256-gcm" -> AES_256_GCM
        "aes-256-cfb" -> AES_256_CFB
        "aes-128-gcm" -> AES_128_GCM
        "aes-128-cfb" -> AES_128_CFB
        "xchacha20-poly1305" -> XCHACHA20_POLY1305
        else -> UNSUPPORTED
    }

    /** @return IV || ciphertext || tag. */
    fun encrypt(cipherId: Int, key: ByteArray, plaintext: ByteArray): ByteArray {
        return nativeBytesOrNull { NativeEngine.cryfsEncryptBlockNative(cipherId, key, plaintext) }
            ?: encryptFallback(cipherId, key, plaintext)
            ?: throw IllegalStateException("CryFS block encryption failed")
    }

    /** @return the decrypted, authenticity-checked plaintext, or null if the tag/key is wrong. */
    fun decrypt(cipherId: Int, key: ByteArray, ciphertext: ByteArray): ByteArray? {
        val native = nativeBytesOrNull { NativeEngine.cryfsDecryptBlockNative(cipherId, key, ciphertext) }
        if (native != null) return native
        // NativeEngine unavailable specifically (not "native ran and
        // rejected the ciphertext") is the only case where falling
        // through to the Kotlin implementation is correct; a genuine
        // auth failure from a *loaded* native lib must stay null, not
        // silently retry against a second implementation. nativeBytesOrNull
        // already collapses "unavailable" and "loaded but rejected" to the
        // same null, which is fine here: encrypt() flowed through the same
        // implementation, so a loaded-native auth failure would only ever
        // happen against a genuinely bad ciphertext -- something the
        // Kotlin fallback should also (and will also) reject.
        return decryptFallback(cipherId, key, ciphertext)
    }

    private fun keyBitsFor(cipherId: Int): Int = when (cipherId) {
        AES_256_GCM, AES_256_CFB, XCHACHA20_POLY1305 -> 256
        AES_128_GCM, AES_128_CFB -> 128
        else -> 0
    }

    private fun encryptFallback(cipherId: Int, key: ByteArray, plaintext: ByteArray): ByteArray? {
        val keyBits = keyBitsFor(cipherId)
        if (keyBits == 0 || key.size * 8 != keyBits) return null

        return try {
            when (cipherId) {
                AES_256_GCM, AES_128_GCM -> {
                    val iv = ByteArray(IV_SIZE).also { secureRandom.nextBytes(it) }
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(GCM_TAG_BITS, iv))
                    // JCE appends the tag to the end of doFinal()'s output,
                    // which already matches the target ciphertext||tag layout.
                    iv + cipher.doFinal(plaintext)
                }
                AES_256_CFB, AES_128_CFB -> {
                    val iv = ByteArray(IV_SIZE).also { secureRandom.nextBytes(it) }
                    val cipher = Cipher.getInstance("AES/CFB/NoPadding") // SunJCE/Conscrypt: no explicit width = full-block (128-bit) feedback, matching mbedtls_aes_crypt_cfb128
                    cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
                    iv + cipher.doFinal(plaintext)
                }
                XCHACHA20_POLY1305 -> {
                    val nonce = ByteArray(XCHACHA_NONCE_SIZE).also { secureRandom.nextBytes(it) }
                    nonce + ChaCha20Poly1305.xchacha20Poly1305Seal(key, nonce, ByteArray(0), plaintext)
                }
                else -> null
            }
        } catch (e: GeneralSecurityException) {
            null
        }
    }

    private fun decryptFallback(cipherId: Int, key: ByteArray, ciphertext: ByteArray): ByteArray? {
        val keyBits = keyBitsFor(cipherId)
        if (keyBits == 0 || key.size * 8 != keyBits) return null

        return try {
            when (cipherId) {
                AES_256_GCM, AES_128_GCM -> {
                    if (ciphertext.size < IV_SIZE + GCM_TAG_SIZE) return null
                    val iv = ciphertext.copyOfRange(0, IV_SIZE)
                    val body = ciphertext.copyOfRange(IV_SIZE, ciphertext.size) // ciphertext || tag, as JCE expects
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(GCM_TAG_BITS, iv))
                    cipher.doFinal(body)
                }
                AES_256_CFB, AES_128_CFB -> {
                    if (ciphertext.size < IV_SIZE) return null
                    val iv = ciphertext.copyOfRange(0, IV_SIZE)
                    val body = ciphertext.copyOfRange(IV_SIZE, ciphertext.size)
                    val cipher = Cipher.getInstance("AES/CFB/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
                    cipher.doFinal(body) // unauthenticated -- a wrong key/IV just yields garbage, never throws
                }
                XCHACHA20_POLY1305 -> {
                    if (ciphertext.size < XCHACHA_NONCE_SIZE + XCHACHA_TAG_SIZE) return null
                    val nonce = ciphertext.copyOfRange(0, XCHACHA_NONCE_SIZE)
                    val body = ciphertext.copyOfRange(XCHACHA_NONCE_SIZE, ciphertext.size)
                    ChaCha20Poly1305.xchacha20Poly1305Open(key, nonce, ByteArray(0), body)
                }
                else -> null
            }
        } catch (e: AEADBadTagException) {
            null // wrong key or tampered/corrupt ciphertext -- expected, not exceptional
        } catch (e: GeneralSecurityException) {
            null
        }
    }
}