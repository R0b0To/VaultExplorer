package com.aeidolon.vaultexplorer.container

import com.aeidolon.vaultexplorer.DirEntryWire
import java.io.IOException
import java.io.OutputStream
import java.util.zip.Deflater
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Streams one vault folder (and everything under it) out as a single ZIP
 * archive, entirely in memory -- the engine behind sharing a *folder* from
 * an unlocked vault (see [ContainerShareProvider]).
 *
 * Android's share sheet has no notion of a folder: `ACTION_SEND` carries
 * streams, not directories. Rather than flatten the tree into a pile of
 * loose files (losing the structure and colliding on same-named files in
 * different subfolders), the folder is shared as one `<name>.zip` whose
 * top-level entry is the folder itself.
 *
 * Deliberately knows nothing about JNI, sessions or Android: the vault is
 * reached only through [Source], which keeps this class unit-testable on a
 * plain JVM (see FolderZipWriterTest) and keeps the "no decrypted bytes on
 * disk" rule trivially checkable here -- the only sink is the
 * [OutputStream] the caller passes in.
 *
 * Failure semantics matter more than usual here, because the receiving app
 * can't tell "the archive ended" from "the archive was cut short" unless
 * the stream itself says so. Anything that goes wrong -- a listing that hit
 * the native "too many children" cap, a read error, the vault starting to
 * lock, a nesting depth that looks like a cycle -- therefore throws, and
 * the archive is *not* finalized: no central directory is ever written for
 * a partial archive, so an unzipper rejects it as corrupt rather than
 * quietly extracting a subset of the folder. The caller is expected to
 * signal the failure on the underlying stream too (the share provider
 * closes its pipe with an error).
 *
 * @param skipExtensions lower-case extensions (no dot) of files to leave
 *   out. The share action uses this to keep Item Vault pseudo-files
 *   (passwords, cards, secure notes, ...) out of a shared folder, the same
 *   way multi-select share already drops them.
 * @param shouldAbort polled between chunks; return true to stop promptly
 *   (the vault is locking and must not wait for a long share to finish).
 */
class FolderZipWriter(
    private val source: Source,
    private val skipExtensions: Set<String> = emptySet(),
    private val shouldAbort: () -> Boolean = { false },
) {

    /** Read access to the vault tree being archived. */
    interface Source {
        /** Raw directory-listing wire entries for [dirPath], or null if it can't be listed. */
        fun list(dirPath: String): Array<String>?

        /** Opens [path] for sequential-ish reading. Must throw if it can't be opened. */
        fun openFile(path: String): FileReader
    }

    interface FileReader : AutoCloseable {
        /** Total length in bytes. */
        val size: Long

        /**
         * Reads up to [length] bytes starting at [offset] into [buffer].
         * Returns the number of bytes read; negative means an I/O error.
         */
        fun read(offset: Long, buffer: ByteArray, length: Int): Int
    }

    /** Thrown when [shouldAbort] fires; distinct so callers can log it as expected, not as a bug. */
    class AbortedException(message: String) : IOException(message)

    companion object {
        private const val TRUNCATED_SENTINEL = "System:TRUNCATED"
        private const val CHUNK_BYTES = 256 * 1024

        // Far deeper than any real folder tree; exists only so a corrupt
        // vault whose directory graph loops can't recurse forever. Hitting
        // it fails the share loudly instead of silently dropping the rest.
        private const val MAX_DEPTH = 128

        // Formats that are already compressed: deflating them burns CPU for
        // ~0% gain, so they are written with NO_COMPRESSION (still a valid
        // deflate stream, just stored blocks).
        private val ALREADY_COMPRESSED = setOf(
            "jpg", "jpeg", "png", "webp", "heic", "heif", "avif", "gif",
            "mp4", "m4v", "mov", "mkv", "webm", "avi", "3gp",
            "mp3", "m4a", "aac", "ogg", "oga", "opus", "flac",
            "zip", "7z", "rar", "gz", "xz", "bz2", "zst",
            "pdf", "docx", "xlsx", "pptx", "odt", "ods", "odp", "apk", "jar",
        )
    }

    /**
     * Writes the archive for the folder at [rootPath] to [out]. The folder's
     * own name is the archive's single top-level entry. [rootPath] must name
     * a real folder, not the vault root (which has no name to archive under).
     *
     * On success the archive is finalized and flushed but [out] is left
     * open -- closing it is the caller's call, since the caller also owns
     * the "close with error" alternative. On any exception nothing further
     * is written to [out] (see class docs) and the exception propagates.
     */
    @Throws(IOException::class)
    fun write(rootPath: String, out: OutputStream) {
        val rootName = rootPath.trimEnd('/').substringAfterLast('/')
        if (rootName.isEmpty()) throw IOException("Cannot archive the vault root")

        val sink = DiscardableOutput(out)
        val zos = ZipOutputStream(sink)
        try {
            writeDirectory(zos, rootPath.trimEnd('/'), "$rootName/", depth = 0, mtimeSecs = 0L, buffer = ByteArray(CHUNK_BYTES))
            zos.finish()
            zos.flush()
        } catch (e: Throwable) {
            // Stop anything -- including the central directory that
            // ZipOutputStream.close() would otherwise emit -- from reaching
            // the receiver, while still letting close() release the Deflater.
            sink.discard()
            try { zos.close() } catch (_: Exception) {}
            throw e
        }
        // Success: close() releases the Deflater; DiscardableOutput.close()
        // is a no-op, so the caller's stream stays open.
        zos.close()
    }

    private fun writeDirectory(
        zos: ZipOutputStream,
        dirPath: String,
        zipPrefix: String,
        depth: Int,
        mtimeSecs: Long,
        buffer: ByteArray,
    ) {
        if (depth > MAX_DEPTH) throw IOException("Folder nesting is too deep to share")
        checkAbort()

        // Directory entry first, so empty folders survive the round trip.
        val dirEntry = ZipEntry(zipPrefix)
        if (mtimeSecs > 0) dirEntry.time = mtimeSecs * 1000L
        zos.putNextEntry(dirEntry)
        zos.closeEntry()

        val raw = source.list(dirPath) ?: throw IOException("Could not list a folder to share")
        val children = ArrayList<DirEntryWire.Entry>(raw.size)
        for (line in raw) {
            if (line == TRUNCATED_SENTINEL) {
                // Existing export paths flag this and carry on; for a share
                // there's no side channel to flag it on, so an incomplete
                // archive would just look complete. Refuse instead.
                throw IOException("Folder is too large to list completely; refusing to share a partial archive")
            }
            if (line.startsWith("System:")) continue
            val entry = DirEntryWire.parse(line) ?: continue
            if (entry.name == "." || entry.name == "..") continue
            // A '/' or NUL can't be a real name and would let a crafted
            // entry escape its folder when the receiver extracts the zip.
            if (entry.name.isEmpty() || entry.name.contains('/') || entry.name.contains('\u0000')) {
                throw IOException("Folder contains an entry name that can't be archived safely")
            }
            children.add(entry)
        }

        for (child in children) {
            val childPath = "$dirPath/${child.name}"
            if (child.isDir) {
                writeDirectory(zos, childPath, "$zipPrefix${child.name}/", depth + 1, child.mtimeUnixSecs, buffer)
            } else {
                val ext = child.name.substringAfterLast('.', "").lowercase()
                if (ext in skipExtensions) continue
                writeFile(zos, childPath, "$zipPrefix${child.name}", ext, child.mtimeUnixSecs, buffer)
            }
        }
    }

    private fun writeFile(
        zos: ZipOutputStream,
        path: String,
        zipName: String,
        ext: String,
        mtimeSecs: Long,
        buffer: ByteArray,
    ) {
        checkAbort()
        source.openFile(path).use { reader ->
            val size = reader.size
            if (size < 0) throw IOException("Could not determine a file's size")

            zos.setLevel(if (ext in ALREADY_COMPRESSED) Deflater.NO_COMPRESSION else Deflater.BEST_SPEED)
            val entry = ZipEntry(zipName)
            if (mtimeSecs > 0) entry.time = mtimeSecs * 1000L
            zos.putNextEntry(entry)

            var offset = 0L
            while (offset < size) {
                checkAbort()
                val want = minOf(buffer.size.toLong(), size - offset).toInt()
                val n = reader.read(offset, buffer, want)
                if (n < 0) throw IOException("Read error while archiving a file")
                // The file shrank underneath us; ending the entry early
                // would silently produce a truncated file inside the zip.
                if (n == 0) throw IOException("Unexpected end of file while archiving")
                zos.write(buffer, 0, n)
                offset += n
            }
            zos.closeEntry()
        }
    }

    private fun checkAbort() {
        if (shouldAbort()) throw AbortedException("Folder share aborted")
    }

    /**
     * Sits between [ZipOutputStream] and the caller's stream so a failed
     * write can cut the zip off cleanly: once [discard]ed, every write is
     * swallowed (notably the central directory that [ZipOutputStream.close]
     * emits unconditionally). Never closes the underlying stream -- that
     * stays the caller's job.
     */
    private class DiscardableOutput(private val target: OutputStream) : OutputStream() {
        private var discarding = false

        fun discard() { discarding = true }

        override fun write(b: Int) { if (!discarding) target.write(b) }
        override fun write(b: ByteArray, off: Int, len: Int) { if (!discarding) target.write(b, off, len) }
        override fun flush() { if (!discarding) target.flush() }
        override fun close() { /* caller owns target */ }
    }
}
