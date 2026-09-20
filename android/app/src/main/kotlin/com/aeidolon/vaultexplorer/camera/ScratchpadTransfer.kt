package com.aeidolon.vaultexplorer.camera

import com.aeidolon.vaultexplorer.VeLog
import java.io.File
import java.io.FileInputStream
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private const val TAG = "ScratchpadTransfer"
internal const val SCRATCHPAD_FILE_PREFIX = "quickcapture_"
internal const val SCRATCHPAD_FILE_SUFFIX = ".enc"

/**
 * One-shot operations on a finished scratchpad file: decrypt it into a
 * chosen vault, or wipe it unread. Neither talks to the camera or to
 * Camera2 -- by the time either runs, capture has already stopped and
 * the scratchpad file is a complete, closed ciphertext (see
 * [ScratchpadChunkWriter.finish]).
 */
object ScratchpadTransfer {

    fun scratchpadFile(cacheDir: File, token: String): File =
        File(cacheDir, "$SCRATCHPAD_FILE_PREFIX$token$SCRATCHPAD_FILE_SUFFIX")

    /**
     * Decrypts [file] with [key] and streams the plaintext into the
     * already-mounted vault identified by [volId]/[virtualPath], 64KB at
     * a time, via the same [VaultChunkWriter] the in-vault camera path
     * uses -- so the target container's own on-disk encryption
     * (Cryptomator/gocryptfs/CryFS/dislocker, whichever [volId] happens
     * to be) is applied exactly as it would be for a direct in-vault
     * capture, with no format-specific code needed here.
     *
     * Wipes [file] afterward either way. The caller still needs to call
     * the existing finishWrite/finalizeVaultWrite commit step on the
     * Dart side once this returns true -- this only performs the write,
     * it doesn't commit it (see CameraVaultService.finalizeVaultWrite).
     */
    fun finalizeIntoVault(file: File, key: SecretKey, volId: Int, virtualPath: String): Boolean {
        val ok = try {
            decryptAndDrain(file, key, VaultChunkWriter(volId, virtualPath))
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "finalizeIntoVault failed" }
            false
        }
        VaultVideoRecorder.secureDeleteFile(file)
        return ok
    }

    private fun decryptAndDrain(file: File, key: SecretKey, sink: ChunkSink): Boolean {
        if (!file.exists() || file.length() <= SCRATCHPAD_GCM_NONCE_BYTES) {
            VeLog.e(TAG) { "decryptAndDrain: scratchpad missing or too short" }
            return false
        }
        FileInputStream(file).use { fis ->
            val nonce = ByteArray(SCRATCHPAD_GCM_NONCE_BYTES)
            if (fis.read(nonce) != nonce.size) return false
            val cipher = Cipher.getInstance(SCRATCHPAD_TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(SCRATCHPAD_GCM_TAG_BITS, nonce))
            CipherInputStream(fis, cipher).use { cis ->
                val buffer = ByteArray(64 * 1024)
                var n: Int
                while (cis.read(buffer).also { n = it } != -1) {
                    if (n > 0) {
                        val chunk = if (n == buffer.size) buffer else buffer.copyOf(n)
                        if (!sink.write(chunk)) return false
                    }
                }
            }
            // GCM's auth tag is verified as the final block is read inside
            // the `.use{}` above -- a truncated or tampered scratchpad
            // throws there rather than silently handing back garbage.
        }
        return sink.finish()
    }

    /** Wipes [file] without decrypting it -- used for an explicit discard
     *  and, with no matching key at all, for orphan cleanup. */
    fun discard(file: File) {
        VaultVideoRecorder.secureDeleteFile(file)
    }

    /**
     * Sweeps [cacheDir] for scratchpad files left behind by a previous
     * process death -- same rationale as
     * [VaultVideoRecorder.sweepOrphanedTempFiles], and safe for the same
     * reason: [ScratchpadKeyStore] is an in-memory singleton, so a fresh
     * process never holds the key for a file created by a previous one,
     * making any leftover scratchpad permanently undecryptable garbage
     * regardless of how it got left behind. Call once at startup, before
     * any capture could plausibly create a new one (see
     * MainActivity.onCreate).
     */
    fun sweepOrphaned(cacheDir: File?): Int {
        val dir = cacheDir ?: return 0
        val orphans = dir.listFiles { f ->
            f.isFile && f.name.startsWith(SCRATCHPAD_FILE_PREFIX) && f.name.endsWith(SCRATCHPAD_FILE_SUFFIX)
        } ?: return 0
        var wiped = 0
        for (file in orphans) {
            if (VaultVideoRecorder.secureDeleteFile(file)) wiped++
        }
        if (wiped > 0) {
            VeLog.i(TAG) { "sweepOrphaned: wiped $wiped orphaned scratchpad file(s)" }
        }
        return wiped
    }
}
