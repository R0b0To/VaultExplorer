package com.aeidolon.vaultexplorer

import android.util.Log
import java.io.File
import java.io.RandomAccessFile

/**
 * Shared helper for removing plaintext scratch files -- decrypted vault
 * content staged in cacheDir for thumbnailing, export, video recording,
 * etc. -- so a deleted file isn't just unlinked (which on most Android
 * filesystems leaves the content readable until the underlying blocks are
 * reused) but is actually overwritten first.
 *
 * Originally lived only inside VaultVideoRecorder; pulled out so every
 * other call site that stages plaintext in cacheDir (thumbnails, exports)
 * gets the same treatment instead of a plain File.delete().
 */
object SecureFileWipe {
    private const val TAG = "SecureFileWipe"

    /** Overwrites [file] with zeros before deleting it. Returns false if the
     *  file couldn't be fully wiped -- the caller falls back to at least
     *  having tried delete(). */
    fun secureDeleteFile(file: File): Boolean {
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
            Log.w(TAG, "secureDeleteFile failed", e)
            try { file.delete() } catch (_: Exception) {}
            false
        }
    }

    /**
     * Sweeps [cacheDir] for stray files whose name starts with any of
     * [prefixes], secure-deleting each. Intended to run once at app
     * startup, off the main thread, to recover plaintext temp files left
     * behind by a process death (crash, force-stop, OOM kill) that skipped
     * the normal cleanup path. Returns how many files were wiped.
     */
    fun sweepOrphanedFiles(cacheDir: File?, prefixes: List<String>): Int {
        val dir = cacheDir ?: return 0
        val orphans = dir.listFiles { f ->
            f.isFile && prefixes.any { prefix -> f.name.startsWith(prefix) }
        } ?: return 0
        var wiped = 0
        for (file in orphans) {
            if (secureDeleteFile(file)) wiped++
        }
        if (wiped > 0) {
            Log.i(TAG, "sweepOrphanedFiles: wiped $wiped orphaned plaintext temp file(s)")
        }
        return wiped
    }
}
