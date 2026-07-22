package com.aeidolon.vaultexplorer.cryptomator

import com.aeidolon.vaultexplorer.VeraCryptEngine
import java.nio.charset.StandardCharsets

object Scrypt {

    private const val DEFAULT_P = 1

    fun scrypt(passphrase: CharArray, salt: ByteArray, costParam: Int, blockSize: Int, keyLengthBytes: Int): ByteArray {
        val pw = StandardCharsets.UTF_8.encode(java.nio.CharBuffer.wrap(passphrase))
        val pwBytes = ByteArray(pw.remaining())
        pw.get(pwBytes)
        try {
            return scrypt(pwBytes, salt, costParam, blockSize, keyLengthBytes, DEFAULT_P)
        } finally {
            pwBytes.fill(0)
        }
    }

    fun scrypt(passphrase: ByteArray, salt: ByteArray, costParam: Int, blockSize: Int, keyLengthBytes: Int, p: Int = DEFAULT_P): ByteArray {
        val nativeBytes = VeraCryptEngine.scryptNative(passphrase, salt, costParam, blockSize, p, keyLengthBytes)
        if (nativeBytes != null) {
            return nativeBytes
        }
        throw OutOfMemoryError("Native scrypt allocation/derivation failed for N=$costParam, r=$blockSize, p=$p")
    }
}