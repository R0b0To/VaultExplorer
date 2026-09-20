package com.aeidolon.vaultexplorer.camera

import com.aeidolon.vaultexplorer.VeLog
import java.io.File
import java.io.FileOutputStream
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.CipherOutputStream
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private const val TAG = "ScratchpadChunkWriter"

/** 96-bit nonce -- the size GCM is defined and optimized for; using a
 *  different length forces an extra internal hash step for no benefit
 *  here. */
internal const val SCRATCHPAD_GCM_NONCE_BYTES = 12
internal const val SCRATCHPAD_GCM_TAG_BITS = 128
internal const val SCRATCHPAD_TRANSFORMATION = "AES/GCM/NoPadding"

/**
 * Encrypts everything written to it with AES-256-GCM under an ephemeral,
 * caller-supplied [key] (see [ScratchpadKeyStore]) and appends the
 * ciphertext to [file]. A fresh random 12-byte nonce is generated per
 * writer instance and written in the clear as the first 12 bytes of
 * [file] -- it does not need to stay secret, only be unique for this
 * key, which a fresh [SecureRandom] draw guarantees for any realistic
 * capture (one nonce per capture session; the key itself is never
 * reused across sessions -- see [ScratchpadKeyStore.createSession]).
 *
 * [finish] MUST be called exactly once after the last [write] to flush
 * the GCM authentication tag; until then the file on disk is not a
 * complete, decryptable ciphertext. [ScratchpadTransfer.decryptAndDrain]
 * relies on that tag to detect a truncated or tampered scratchpad file
 * rather than silently handing back garbage plaintext.
 */
class ScratchpadChunkWriter(
    file: File,
    key: SecretKey,
) : ChunkSink {
    private val fileOut = FileOutputStream(file)
    private val cipherOut: CipherOutputStream
    private var closed = false

    init {
        val nonce = ByteArray(SCRATCHPAD_GCM_NONCE_BYTES).also { SecureRandom().nextBytes(it) }
        fileOut.write(nonce)
        val cipher = Cipher.getInstance(SCRATCHPAD_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(SCRATCHPAD_GCM_TAG_BITS, nonce))
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
