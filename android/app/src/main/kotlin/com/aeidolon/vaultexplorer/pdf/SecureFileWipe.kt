package com.aeidolon.vaultexplorer

import android.util.Log
import java.io.File
import java.io.RandomAccessFile

/**
 * Overwrites a file with zeros before deleting it, so a leftover plaintext
 * temp file isn't just unlinked (which on most Android filesystems leaves
 * the content readable until the blocks are reused).
 *
 * Mirrors the pattern already used by
 * [com.aeidolon.vaultexplorer.camera.VaultVideoRecorder]'s private
 * `secureDeleteFile` for recording temp files -- pulled out here so the
 * PDF edit-session temp copy (see [com.aeidolon.vaultexplorer.pdf.VaultPdfEditSessionRegistry])
 * can reuse the same guarantee instead of duplicating it.
 */
object SecureFileWipe {
    private const val TAG = "SecureFileWipe"

    fun wipe(file: File): Boolean {
        return try {
            if (file.exists()) {
                val len = file.length()
                if (len > 0) {
                    RandomAccessFile(file, "rws").use { raf ->
                        val zeros = ByteArray(64 * 1024)
                        var remaining = len
                        while (remaining > 0) {
                            val writeLen = minOf(remaining, zeros.size.toLong()).toInt()
                            raf.write(zeros, 0, writeLen)
                            remaining -= writeLen
                        }
                    }
                }
                file.delete()
            } else {
                true
            }
        } catch (e: Exception) {
            Log.w(TAG, "wipe: failed for ${file.name}", e)
            try { file.delete() } catch (_: Exception) {}
            false
        }
    }
}
