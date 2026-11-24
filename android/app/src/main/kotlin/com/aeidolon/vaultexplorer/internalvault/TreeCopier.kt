package com.aeidolon.vaultexplorer.internalvault

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.FilterOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import java.security.MessageDigest

/** The copy was stopped by the user. The partial copy is the caller's to remove. */
class RelocationCancelledException : IOException("Cancelled")

/** The copy finished but does not match the source byte for byte. */
class RelocationVerifyException(message: String) : IOException(message)

/**
 * A file or folder that can be read, whether it lives on the local filesystem
 * or behind the Storage Access Framework. Keeps [TreeCopier] free of
 * `android.*` so the copy-and-verify logic is exercised by plain JVM tests.
 */
interface VaultNode {
    val name: String
    val isDirectory: Boolean

    /** Size in bytes of a file; -1 when the provider does not say. Unused for directories. */
    val length: Long
    fun children(): List<VaultNode>
    fun openRead(): InputStream
}

/** A folder that new files and subfolders can be created in. */
interface WritableDir : VaultNode {
    fun makeDir(name: String): WritableDir

    /** Creates [name] and returns a stream to write it. Closing the stream finishes the file. */
    fun makeFile(name: String): OutputStream
}

/** Size and SHA-256 (lowercase hex) of one copied file. */
data class FileFingerprint(val size: Long, val sha256: String)

/** What a copy wrote: every directory and file, by `/`-separated path relative to the copied root. */
class CopyManifest {
    val directories = LinkedHashSet<String>()
    val files = LinkedHashMap<String, FileFingerprint>()
    val totalBytes: Long get() = files.values.sumOf { it.size }
}

/**
 * Copies a file or folder tree and proves the result is identical.
 *
 * The source is hashed as it is read for the copy, then the destination is
 * read back and hashed independently and compared, with the same entries and
 * no extras. So a verified copy means the destination really holds the bytes,
 * not just that the write calls returned. Only after that does the caller
 * switch to the copy and, optionally, delete the original.
 *
 * Progress is reported as bytes: the copy pass and the verify pass each count
 * once, so a caller sizing the bar uses `2 * bytes`.
 *
 * [isCancelled] is polled between buffers; [onBytes] receives each chunk size.
 */
class TreeCopier(
    private val isCancelled: () -> Boolean = { false },
    private val onBytes: (Long) -> Unit = {},
    private val bufferSize: Int = 256 * 1024,
) {

    /** Bytes and file count under [node] (a single file counts as 1). Unknown sizes count as 0. */
    fun measure(node: VaultNode): Pair<Long, Long> {
        if (!node.isDirectory) return maxOf(node.length, 0L) to 1L
        var bytes = 0L
        var files = 0L
        for (child in node.children()) {
            val (b, f) = measure(child)
            bytes += b
            files += f
        }
        return bytes to files
    }

    /** Copies the single file [src] into the stream [out] and returns its fingerprint. Does not close [out]. */
    fun copyFile(src: VaultNode, out: OutputStream): FileFingerprint {
        require(!src.isDirectory) { "Not a file: ${src.name}" }
        val digest = MessageDigest.getInstance("SHA-256")
        val buf = ByteArray(bufferSize)
        var size = 0L
        src.openRead().use { input ->
            while (true) {
                checkCancelled()
                val n = input.read(buf)
                if (n < 0) break
                digest.update(buf, 0, n)
                out.write(buf, 0, n)
                size += n
                onBytes(n.toLong())
            }
        }
        out.flush()
        // Matching hashes only prove the copy equals what was *read*. A provider that returns end-of-file early
        // would yield a truncated file that still verifies, so the bytes read must match the reported length.
        // A reported length of 0 (or -1) means "unknown" to many providers, so it cannot be held against the read.
        val reported = src.length
        if (reported > 0 && reported != size) {
            throw RelocationVerifyException(
                "\"${src.name}\" could only be read as $size of $reported bytes",
            )
        }
        return FileFingerprint(size, hex(digest.digest()))
    }

    /** Copies [src] (a folder) into the empty folder [dst]; both roots map to the empty relative path. */
    fun copyTree(src: VaultNode, dst: WritableDir): CopyManifest {
        require(src.isDirectory) { "Not a folder: ${src.name}" }
        val manifest = CopyManifest()
        copyChildren(src, dst, "", manifest)
        return manifest
    }

    private fun copyChildren(src: VaultNode, dst: WritableDir, prefix: String, manifest: CopyManifest) {
        for (child in src.children()) {
            checkCancelled()
            val name = requireSafeSegment(child.name)
            val rel = if (prefix.isEmpty()) name else "$prefix/$name"
            if (child.isDirectory) {
                val sub = dst.makeDir(name)
                manifest.directories.add(rel)
                copyChildren(child, sub, rel, manifest)
            } else {
                dst.makeFile(name).use { out ->
                    manifest.files[rel] = copyFile(child, out)
                }
            }
        }
    }

    /** Throws [RelocationVerifyException] unless [node] (a file) has exactly [expected]'s size and hash. */
    fun verifyFile(node: VaultNode, expected: FileFingerprint, label: String = node.name) {
        val actual = fingerprint(node)
        if (actual != expected) {
            throw RelocationVerifyException(
                "\"$label\" does not match the original (expected ${expected.size} bytes, found ${actual.size})",
            )
        }
    }

    /** Throws [RelocationVerifyException] unless the folder [dst] holds exactly the entries in [manifest], unchanged. */
    fun verifyTree(dst: VaultNode, manifest: CopyManifest) {
        val foundFiles = LinkedHashMap<String, VaultNode>()
        val foundDirs = LinkedHashSet<String>()
        walk(dst, "", foundDirs, foundFiles)
        val missingFiles = manifest.files.keys - foundFiles.keys
        if (missingFiles.isNotEmpty()) throw RelocationVerifyException("Missing in the copy: ${missingFiles.first()}")
        val extraFiles = foundFiles.keys - manifest.files.keys
        if (extraFiles.isNotEmpty()) throw RelocationVerifyException("Unexpected extra file in the copy: ${extraFiles.first()}")
        val missingDirs = manifest.directories - foundDirs
        if (missingDirs.isNotEmpty()) throw RelocationVerifyException("Missing folder in the copy: ${missingDirs.first()}")
        val extraDirs = foundDirs - manifest.directories
        if (extraDirs.isNotEmpty()) throw RelocationVerifyException("Unexpected extra folder in the copy: ${extraDirs.first()}")
        for ((rel, expected) in manifest.files) {
            checkCancelled()
            verifyFile(foundFiles.getValue(rel), expected, rel)
        }
    }

    private fun walk(node: VaultNode, prefix: String, dirs: MutableSet<String>, files: MutableMap<String, VaultNode>) {
        for (child in node.children()) {
            val rel = if (prefix.isEmpty()) child.name else "$prefix/${child.name}"
            if (child.isDirectory) {
                dirs.add(rel)
                walk(child, rel, dirs, files)
            } else {
                files[rel] = child
            }
        }
    }

    private fun fingerprint(node: VaultNode): FileFingerprint {
        val digest = MessageDigest.getInstance("SHA-256")
        val buf = ByteArray(bufferSize)
        var size = 0L
        node.openRead().use { input ->
            while (true) {
                checkCancelled()
                val n = input.read(buf)
                if (n < 0) break
                digest.update(buf, 0, n)
                size += n
                onBytes(n.toLong())
            }
        }
        return FileFingerprint(size, hex(digest.digest()))
    }

    private fun checkCancelled() {
        if (isCancelled()) throw RelocationCancelledException()
    }

    private fun hex(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) sb.append("%02x".format(b.toInt() and 0xff))
        return sb.toString()
    }

    private fun requireSafeSegment(name: String): String {
        if (name.isEmpty() || name == "." || name == ".." || name.contains('/') || name.contains('\u0000')) {
            throw IOException("Refusing to copy an entry with an unsafe name: \"$name\"")
        }
        return name
    }
}

/** A local file or folder. */
class LocalNode(val file: File) : VaultNode {
    override val name: String get() = file.name
    override val isDirectory: Boolean get() = file.isDirectory
    override val length: Long get() = file.length()

    override fun children(): List<VaultNode> {
        // Symlinks are never followed: a vault is plain files, and following a
        // link could copy something from outside the vault.
        val kids = file.listFiles() ?: return emptyList()
        return kids
            .filter { !Files.isSymbolicLink(it.toPath()) }
            .sortedBy { it.name }
            .map { LocalNode(it) }
    }

    override fun openRead(): InputStream = FileInputStream(file)
}

/** A local folder that can be written. Each finished file is flushed to disk before its stream closes. */
class LocalWritableDir(private val dir: File) : WritableDir {
    override val name: String get() = dir.name
    override val isDirectory: Boolean get() = true
    override val length: Long get() = -1L
    override fun children(): List<VaultNode> = LocalNode(dir).children()
    override fun openRead(): InputStream = throw IOException("A folder cannot be read as a stream")

    override fun makeDir(name: String): WritableDir {
        val d = File(dir, name)
        if (!d.mkdir()) throw IOException("Could not create folder \"$name\"")
        return LocalWritableDir(d)
    }

    override fun makeFile(name: String): OutputStream {
        val f = File(dir, name)
        if (!f.createNewFile()) throw IOException("Could not create file \"$name\"")
        return SyncOnCloseOutputStream(FileOutputStream(f))
    }
}

/**
 * Forces the file's data to disk before closing it. The original is deleted
 * after a copy, so a power loss between the verify and the page cache reaching
 * flash must not be able to leave a truncated vault as the only copy.
 */
class SyncOnCloseOutputStream(private val fos: FileOutputStream) : FilterOutputStream(fos) {
    override fun write(b: ByteArray, off: Int, len: Int) {
        // FilterOutputStream.write(byte[],int,int) writes one byte at a time.
        fos.write(b, off, len)
    }

    override fun close() {
        try {
            flush()
            fos.fd.sync()
        } finally {
            fos.close()
        }
    }
}
