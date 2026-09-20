package com.aeidolon.vaultexplorer.camera

import com.aeidolon.vaultexplorer.VeLog
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.CipherOutputStream
import javax.crypto.SecretKey
import javax.crypto.spec.IvParameterSpec

private const val TAG = "ScratchpadChunkWriter"

// AES-CTR uses a 16-byte IV and true streaming without buffering
internal const val SCRATCHPAD_IV_BYTES = 16
internal const val SCRATCHPAD_TRANSFORMATION = "AES/CTR/NoPadding"

class ScratchpadChunkWriter(
    file: File,
    key: SecretKey,
) : ChunkSink {
    private val fileOut = BufferedOutputStream(FileOutputStream(file), 64 * 1024)
    private val cipherOut: CipherOutputStream
    private var closed = false

    init {
        val iv = ByteArray(SCRATCHPAD_IV_BYTES).also { SecureRandom().nextBytes(it) }
        fileOut.write(iv)
        val cipher = Cipher.getInstance(SCRATCHPAD_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key, IvParameterSpec(iv))
        cipherOut = CipherOutputStream(fileOut, cipher)
    }

    override fun write(data: ByteArray): Boolean {
        if (closed) return false
        return try {
            cipherOut.write(data)
            true
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "write failed" }
            false
        }
    }

    override fun finish(): Boolean {
        if (closed) return true
        closed = true
        return try {
            cipherOut.close()
            true
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "finish failed" }
            false
        }
    }
}