package com.aeidolon.vaultexplorer.crypto

import com.aeidolon.vaultexplorer.NativeEngine

/**
 * JNI surface of the platform-neutral crypto primitives (cpp/crypto/prims, bridged by
 * cpp/jni/prims_bridge.cpp): the code a desktop front-end calls directly, here used for the
 * `hmac` and `aesCbcDecrypt` platform-channel methods in place of JCA.
 *
 * Every function returns null when the native library is unavailable *or* the primitive
 * refuses the input; callers then run their JCA code, which is unchanged and is what reports
 * errors (a bad padding becomes the exception Dart already knows how to handle). The primitive
 * never has the last word on a failure, only on a success.
 */
internal object NativePrims {
    val isAvailable: Boolean = NativeEngine.isLoaded && try {
        nativeInit()
        true
    } catch (_: UnsatisfiedLinkError) {
        false
    }

    /** HMAC; [hash] is "sha1" | "sha256" | "sha512". */
    fun hmac(hash: String, key: ByteArray, data: ByteArray): ByteArray? {
        if (!isAvailable) return null
        return try {
            nativeHmac(hash, key, data)
        } catch (_: UnsatisfiedLinkError) {
            null
        }
    }

    /** AES-CBC with PKCS#7 padding. */
    fun aesCbcDecrypt(key: ByteArray, iv: ByteArray, ciphertext: ByteArray): ByteArray? {
        if (!isAvailable) return null
        return try {
            nativeAesCbcDecrypt(key, iv, ciphertext)
        } catch (_: UnsatisfiedLinkError) {
            null
        }
    }

    @JvmStatic external fun nativeInit()
    @JvmStatic external fun nativeHmac(hash: String, key: ByteArray, data: ByteArray): ByteArray?
    @JvmStatic external fun nativeAesCbcDecrypt(key: ByteArray, iv: ByteArray, ciphertext: ByteArray): ByteArray?
}
