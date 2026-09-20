package com.aeidolon.vaultexplorer.camera

import com.aeidolon.vaultexplorer.VeLog
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.SecretKey
import javax.crypto.spec.IvParameterSpec

private const val TAG = "ScratchpadTransfer"
internal const val SCRATCHPAD_FILE_PREFIX = "quickcapture_"
internal const val SCRATCHPAD_FILE_SUFFIX = ".enc"

object ScratchpadTransfer {

    fun scratchpadFile(cacheDir: File, token: String): File =
        File(cacheDir, "$SCRATCHPAD_FILE_PREFIX$token$SCRATCHPAD_FILE_SUFFIX")

    fun finalizeIntoVault(file: File, key: SecretKey, volId: Int, virtualPath: String): Boolean {
        val totalStart = System.currentTimeMillis()
        VeLog.i(TAG) { "[PERF] finalizeIntoVault START: file=${file.length()} bytes, volId=$volId, path=$virtualPath" }

        val drainStart = System.currentTimeMillis()
        val ok = try {
            decryptAndDrain(file, key, VaultChunkWriter(volId, virtualPath))
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "[PERF] finalizeIntoVault failed" }
            false
        }
        val drainDuration = System.currentTimeMillis() - drainStart
        VeLog.i(TAG) { "[PERF] decryptAndDrain completed in ${drainDuration}ms (ok=$ok)" }

        val wipeStart = System.currentTimeMillis()
        VaultVideoRecorder.secureDeleteFile(file)
        val wipeDuration = System.currentTimeMillis() - wipeStart
        VeLog.i(TAG) { "[PERF] secureDeleteFile completed in ${wipeDuration}ms" }

        val totalDuration = System.currentTimeMillis() - totalStart
        VeLog.i(TAG) { "[PERF] finalizeIntoVault TOTAL: ${totalDuration}ms" }
        return ok
    }

    private fun decryptAndDrain(file: File, key: SecretKey, sink: ChunkSink): Boolean {
        if (!file.exists() || file.length() <= SCRATCHPAD_IV_BYTES) {
            VeLog.e(TAG) { "decryptAndDrain: scratchpad missing or too short" }
            return false
        }

        var chunkCount = 0
        var totalSinkWriteTime = 0L
        var maxSinkWriteTime = 0L

        BufferedInputStream(FileInputStream(file), 64 * 1024).use { bis ->
            val iv = ByteArray(SCRATCHPAD_IV_BYTES)
            if (bis.read(iv) != iv.size) return false

            val cipher = Cipher.getInstance(SCRATCHPAD_TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, IvParameterSpec(iv))

            // 64KB buffers. By decrypting directly, we bypass CipherInputStream's
            // hardcoded 512-byte fragmentation and write true 64KB chunks to the vault.
            val inBuffer = ByteArray(64 * 1024)
            val outBuffer = ByteArray(64 * 1024)
            var bytesRead: Int

            while (bis.read(inBuffer).also { bytesRead = it } != -1) {
                if (bytesRead > 0) {
                    val outLen = cipher.update(inBuffer, 0, bytesRead, outBuffer, 0)
                    if (outLen > 0) {
                        chunkCount++
                        val chunk = if (outLen == outBuffer.size) outBuffer else outBuffer.copyOf(outLen)
                        val writeStart = System.currentTimeMillis()
                        val wrote = sink.write(chunk)
                        val writeElapsed = System.currentTimeMillis() - writeStart
                        totalSinkWriteTime += writeElapsed
                        if (writeElapsed > maxSinkWriteTime) maxSinkWriteTime = writeElapsed
                        if (!wrote) {
                            VeLog.e(TAG) { "[PERF] sink.write failed on chunk #$chunkCount" }
                            return false
                        }
                    }
                }
            }

            val finalBytes = cipher.doFinal()
            if (finalBytes != null && finalBytes.isNotEmpty()) {
                chunkCount++
                if (!sink.write(finalBytes)) {
                    return false
                }
            }
        }

        val finishStart = System.currentTimeMillis()
        val finished = sink.finish()
        val finishElapsed = System.currentTimeMillis() - finishStart

        VeLog.i(TAG) {
            "[PERF] decryptAndDrain stats: $chunkCount chunks, total vault write time=${totalSinkWriteTime}ms " +
            "(avg=${if (chunkCount > 0) totalSinkWriteTime / chunkCount else 0}ms/chunk, max=${maxSinkWriteTime}ms), " +
            "sink.finish()=${finishElapsed}ms"
        }
        return finished
    }

    fun discard(file: File) {
        VaultVideoRecorder.secureDeleteFile(file)
    }

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