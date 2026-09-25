package com.aeidolon.vaultexplorer

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile

/**
 * Shared helper for removing plaintext content -- decrypted vault content
 * staged in cacheDir for thumbnailing, export, video recording, etc., and
 * (via [secureDeleteSafDocument]/[secureDeleteSafTree]) the on-device
 * originals a user chooses to delete after importing them into a vault --
 * so a deleted file isn't just unlinked (which on most Android filesystems
 * and removable media leaves the content readable until the underlying
 * blocks are reused) but is actually overwritten first.
 *
 * Originally lived only inside VaultVideoRecorder; pulled out so every
 * other call site that stages plaintext in cacheDir (thumbnails, exports)
 * gets the same treatment instead of a plain File.delete().
 */
object SecureFileWipe {
    private const val TAG = "SecureFileWipe"
    private const val CHUNK_SIZE = 64 * 1024

    /** Overwrites [file] with zeros before deleting it. Returns false if the
     *  file couldn't be fully wiped -- the caller falls back to at least
     *  having tried delete(). */
    fun secureDeleteFile(file: File): Boolean {
        return try {
            if (file.exists()) {
                val len = file.length()
                if (len > 0) {
                    // Plain "rw" here, NOT "rws" -- "rws" forces every single
                    // write() to synchronously flush content+metadata to the
                    // storage device, which for a large file turns this into
                    // thousands of individual disk-sync round trips (e.g. ~5400
                    // fsyncs for a 337MB file at 64KB/write -- multiple seconds
                    // of pure sync latency, dwarfing the actual write time).
                    // "rw" buffers normally through the page cache; the single
                    // explicit fd.sync() below still guarantees every zero byte
                    // is physically committed before delete() unlinks the file,
                    // which is the actual security property we need -- it just
                    // costs one flush instead of one per chunk.
                    RandomAccessFile(file, "rw").use { raf ->
                        writeZeros(len) { buf, writeLen -> raf.write(buf, 0, writeLen) }
                        raf.fd.sync()
                    }
                }
                file.delete()
            } else {
                true
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "secureDeleteFile failed" }
            try { file.delete() } catch (_: Exception) {}
            false
        }
    }

    /**
     * Overwrites the on-device document [doc] with zeros before deleting it.
     * Used for "delete original after import" -- unlike [secureDeleteFile],
     * [doc] may live on removable/external media (SD card, USB OTG flash
     * drive) reached only through SAF, not always as a raw path the app can
     * open a [RandomAccessFile] on.
     *
     * Tries a raw `java.io.File` first (fast path with a single fsync, same
     * as [secureDeleteFile]) via [RawFileResolver] -- this covers internal
     * storage and, with All-Files-Access granted, the primary SD card. Falls
     * back to a SAF `ParcelFileDescriptor`/`OutputStream` write for anything
     * that isn't reachable as a raw path, which is the common case for USB
     * OTG flash drives and other removable media: exactly the scenario a
     * "delete original" after importing from external storage needs to
     * cover. Returns false if the content couldn't be fully overwritten --
     * the caller falls back to at least having tried delete().
     */
    fun secureDeleteSafDocument(context: Context, doc: DocumentFile): Boolean {
        if (!doc.exists()) return true
        if (doc.isDirectory) return secureDeleteSafTree(context, doc)

        val uri = doc.uri

        // Fast path: Only use raw java.io.File if the kernel grants POSIX write permission.
        // On USB OTG storage, canWrite() is false; routing through File fails with EACCES.
        val rawFile = try {
            RawFileResolver.getRawFileFromUri(context, uri)
        } catch (_: Exception) {
            null
        }
        if (rawFile != null && rawFile.exists() && rawFile.canWrite()) {
            val ok = secureDeleteFile(rawFile)
            if (ok) {
                try { doc.delete() } catch (_: Exception) {}
                return true
            }
        }

        // SAF Path (Required for USB OTG drives and removable media)
        return try {
            var len = doc.length()
            var zeroWiped = false

            // Try "rw" (in-place overwrite without truncate) so the existing
            // clusters on the USB drive are written over rather than deallocated.
            val pfd = try {
                context.contentResolver.openFileDescriptor(uri, "rw")
            } catch (_: Exception) {
                try {
                    context.contentResolver.openFileDescriptor(uri, "rwt")
                } catch (_: Exception) {
                    null
                }
            }

            if (pfd != null) {
                pfd.use { fd ->
                    val statSize = fd.statSize
                    val targetLen = if (statSize > 0) statSize else len
                    if (targetLen > 0) {
                        FileOutputStream(fd.fileDescriptor).channel.use { channel ->
                            channel.position(0)
                            val zeros = ByteArray(CHUNK_SIZE)
                            var remaining = targetLen
                            while (remaining > 0) {
                                val writeLen = minOf(remaining, zeros.size.toLong()).toInt()
                                val buf = java.nio.ByteBuffer.wrap(zeros, 0, writeLen)
                                while (buf.hasRemaining()) {
                                    channel.write(buf)
                                }
                                remaining -= writeLen
                            }
                            channel.force(true)
                        }
                        zeroWiped = true
                    }
                }
            }

            if (!zeroWiped && len > 0) {
                // Secondary fallback: openOutputStream with "wt" if provider denies openFileDescriptor
                context.contentResolver.openOutputStream(uri, "wt")?.use { out ->
                    writeZeros(len) { buf, writeLen -> out.write(buf, 0, writeLen) }
                    out.flush()
                    if (out is FileOutputStream) {
                        out.fd.sync()
                    }
                    zeroWiped = true
                }
            }

            if (!zeroWiped && len > 0) {
                VeLog.w(TAG) { "secureDeleteSafDocument: could not zero-wipe $uri before deleting" }
            }

            doc.delete()
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "secureDeleteSafDocument failed for $uri" }
            try { doc.delete() } catch (_: Exception) {}
            false
        }
    }

    /**
     * Recursively overwrites every file under [doc] with zeros before
     * deleting it, then removes the now-empty directories bottom-up.
     */
    fun secureDeleteSafTree(context: Context, doc: DocumentFile): Boolean {
        if (!doc.exists()) return true
        if (!doc.isDirectory) return secureDeleteSafDocument(context, doc)

        // Only use raw directory walk if the directory has direct POSIX write permission.
        val rawDir = try {
            RawFileResolver.getRawFileFromUri(context, doc.uri)
        } catch (_: Exception) {
            null
        }
        if (rawDir != null && rawDir.exists() && rawDir.isDirectory && rawDir.canWrite()) {
            val ok = secureDeleteRawTree(rawDir)
            if (ok) {
                try { doc.delete() } catch (_: Exception) {}
                return true
            }
        }

        // SAF tree walk fallback (for USB OTG drives)
        return try {
            var allOk = true
            for (child in doc.listFiles()) {
                if (!secureDeleteSafTree(context, child)) allOk = false
            }
            doc.delete() && allOk
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "secureDeleteSafTree failed on ${doc.uri}" }
            try { doc.delete() } catch (_: Exception) {}
            false
        }
    }

    private fun secureDeleteRawTree(dir: File): Boolean {
        var allOk = true
        val children = dir.listFiles() ?: emptyArray()
        for (child in children) {
            val ok = if (child.isDirectory) secureDeleteRawTree(child) else secureDeleteFile(child)
            if (!ok) allOk = false
        }
        return dir.delete() && allOk
    }

    /** Streams [len] zero bytes out through [write] in [CHUNK_SIZE] pieces. */
    private inline fun writeZeros(len: Long, write: (ByteArray, Int) -> Unit) {
        val zeros = ByteArray(CHUNK_SIZE)
        var remaining = len
        while (remaining > 0) {
            val writeLen = minOf(remaining, zeros.size.toLong()).toInt()
            write(zeros, writeLen)
            remaining -= writeLen
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
            VeLog.i(TAG) { "sweepOrphanedFiles: wiped $wiped orphaned plaintext temp file(s)" }
        }
        return wiped
    }
}