package com.aeidolon.vaultexplorer.internalvault

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.BasicFileAttributes

/**
 * The rules for the directory that holds vaults inside the app's private
 * storage ("App storage" in the UI): what a vault may be called, which paths
 * count as being inside it, how a half-written vault is kept out of sight, and
 * how one is deleted.
 *
 * Deliberately free of `android.*` types so the path-safety rules, which
 * decide what [deleteTree] is allowed to remove, run in a plain JVM unit test.
 * [InternalVaultStorage] binds it to `Context.filesDir`.
 *
 * Layout under [root]:
 *  - `<name>.hc`, `<name>/` -- a registered vault (a container file or a
 *    folder vault's directory), named by the user.
 *  - `.part-<random>` -- a vault that is still being created or copied in.
 *    Only ever renamed to its final name once complete, so a crash can never
 *    leave a truncated vault under a real name. Swept by [sweepStaging].
 */
class AppVaultStore(val root: File) {

    companion object {
        /** Directory name under `filesDir`. */
        const val DIR_NAME = "vaults"

        /** Prefix of in-progress entries; hidden from [list] and removed by [sweepStaging]. */
        const val STAGING_PREFIX = ".part-"

        /** ext4/f2fs limit a name to 255 bytes; stay well below it to leave room for " (n)" and an extension. */
        private const val MAX_NAME_BYTES = 120
        private const val MAX_EXTENSION_CHARS = 8
        private const val FILE_SCHEME = "file://"

        /** Characters Windows/Android shells and Storage Access Framework providers commonly reject. */
        private val FORBIDDEN = setOf('/', '\\', ':', '*', '?', '"', '<', '>', '|')

        /**
         * A name that is safe as a single path segment: no separators or
         * control characters, no leading dots (so it can never be hidden or
         * mistaken for staging), not empty, and within [MAX_NAME_BYTES] bytes of UTF-8.
         */
        fun sanitizeName(raw: String?, fallback: String = "vault"): String {
            val cleaned = StringBuilder()
            for (ch in (raw ?: "")) {
                cleaned.append(if (ch.code < 0x20 || ch.code == 0x7f || ch in FORBIDDEN) '_' else ch)
            }
            var s = cleaned.toString().trim().trimStart('.').trimEnd('.', ' ')
            if (s.toByteArray(StandardCharsets.UTF_8).size > MAX_NAME_BYTES) {
                val out = StringBuilder()
                var bytes = 0
                var i = 0
                while (i < s.length) {
                    val cp = s.codePointAt(i)
                    val n = Character.charCount(cp)
                    val b = String(Character.toChars(cp)).toByteArray(StandardCharsets.UTF_8).size
                    if (bytes + b > MAX_NAME_BYTES) break
                    out.appendCodePoint(cp)
                    bytes += b
                    i += n
                }
                s = out.toString().trimEnd('.', ' ')
            }
            return if (s.isEmpty()) fallback else s
        }

        /** Splits `vault.hc` into (`vault`, `.hc`); a "extension" that is long or not alphanumeric stays part of the base. */
        fun splitExtension(name: String): Pair<String, String> {
            val dot = name.lastIndexOf('.')
            if (dot <= 0 || dot == name.length - 1) return name to ""
            val ext = name.substring(dot)
            val body = ext.substring(1)
            if (body.length > MAX_EXTENSION_CHARS || !body.all { it.isLetterOrDigit() }) return name to ""
            return name.substring(0, dot) to ext
        }

        /**
         * `file:///abs/path` with every character outside the RFC 3986
         * unreserved set (and `/`) percent-encoded as UTF-8. Matches what
         * `android.net.Uri.fromFile` produces for the paths this class makes,
         * and is what `Uri.parse(...).path` decodes back.
         */
        fun fileUriString(file: File): String {
            val path = file.absolutePath
            val out = StringBuilder(FILE_SCHEME)
            for (b in path.toByteArray(StandardCharsets.UTF_8)) {
                val c = b.toInt() and 0xff
                val unreserved = (c in 'A'.code..'Z'.code) || (c in 'a'.code..'z'.code) ||
                    (c in '0'.code..'9'.code) || c == '-'.code || c == '.'.code || c == '_'.code ||
                    c == '~'.code || c == '/'.code
                if (unreserved) out.append(c.toChar()) else out.append('%').append("%02X".format(c))
            }
            return out.toString()
        }

        /** The absolute path of a `file://` URI, percent-decoded as UTF-8; null for any other string. */
        fun pathFromFileUri(uri: String): String? {
            if (!uri.startsWith(FILE_SCHEME)) return null
            var rest = uri.substring(FILE_SCHEME.length)
            val cut = rest.indexOfFirst { it == '?' || it == '#' }
            if (cut >= 0) rest = rest.substring(0, cut)
            if (!rest.startsWith("/")) return null   // an authority other than empty: not a local path
            return percentDecode(rest)
        }

        /** Decodes valid `%XX` sequences as UTF-8 bytes; anything else (including a stray `%`) is kept as is. */
        private fun percentDecode(s: String): String {
            val buf = ByteArrayOutputStream(s.length)
            var i = 0
            while (i < s.length) {
                val ch = s[i]
                if (ch == '%' && i + 2 < s.length) {
                    val hi = Character.digit(s[i + 1], 16)
                    val lo = Character.digit(s[i + 2], 16)
                    if (hi >= 0 && lo >= 0) {
                        buf.write((hi shl 4) or lo)
                        i += 3
                        continue
                    }
                }
                val cp = s.codePointAt(i)
                buf.write(String(Character.toChars(cp)).toByteArray(StandardCharsets.UTF_8))
                i += Character.charCount(cp)
            }
            return String(buf.toByteArray(), StandardCharsets.UTF_8)
        }
    }

    /** One registered vault found by [list]. */
    data class Entry(val file: File, val isDirectory: Boolean, val sizeBytes: Long)

    fun ensureRoot(): File {
        if (!root.isDirectory && !root.mkdirs() && !root.isDirectory) {
            throw IOException("Could not create the app storage folder")
        }
        return root
    }

    /**
     * True when [file] is strictly inside [root] once symlinks and `..` are
     * resolved. The root itself does not count: nothing may delete or hand out
     * the whole vault directory.
     */
    fun isInside(file: File): Boolean = try {
        val c = file.canonicalFile
        val r = root.canonicalFile
        c != r && c.path.startsWith(r.path + File.separator)
    } catch (_: IOException) {
        false
    }

    /** The file a `file://` [uriString] names, or null unless it points inside [root]. */
    fun resolveUri(uriString: String): File? {
        val path = pathFromFileUri(uriString) ?: return null
        val f = File(path)
        return if (isInside(f)) f else null
    }

    /**
     * Claims a fresh, empty container file named after [displayName] (made
     * unique with " (1)", " (2)", ...). The name is reserved atomically with
     * `createNewFile`, so two concurrent creations can never pick the same one.
     */
    fun reserveContainerFile(displayName: String): File {
        ensureRoot()
        val (base, ext) = splitExtension(sanitizeName(displayName))
        var n = 0
        while (true) {
            val name = if (n == 0) base + ext else "$base ($n)$ext"
            val candidate = File(root, name)
            if (candidate.createNewFile()) return candidate
            if (++n > 10_000) throw IOException("Could not find a free name for the vault")
        }
    }

    /** Claims a fresh, empty directory named after [displayName] for a folder vault. */
    fun reserveFolderVaultDir(displayName: String): File {
        ensureRoot()
        val base = sanitizeName(displayName)
        var n = 0
        while (true) {
            val name = if (n == 0) base else "$base ($n)"
            val candidate = File(root, name)
            if (candidate.mkdir()) return candidate
            if (++n > 10_000) throw IOException("Could not find a free name for the vault")
        }
    }

    /** A not-yet-existing hidden path for building a vault before it is given its real name. */
    fun newStagingPath(): File {
        ensureRoot()
        return File(root, STAGING_PREFIX + java.util.UUID.randomUUID().toString().replace("-", ""))
    }

    /**
     * Moves a finished staging entry onto [reserved] (the empty file or
     * directory claimed earlier), so the vault appears under its real name all
     * at once. Falls back to a non-atomic replace where the filesystem refuses
     * an atomic move.
     */
    fun publish(staging: File, reserved: File) {
        require(isInside(staging) && isInside(reserved)) { "Both paths must be inside app storage" }
        try {
            Files.move(staging.toPath(), reserved.toPath(), StandardCopyOption.ATOMIC_MOVE)
        } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
            Files.move(staging.toPath(), reserved.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    /**
     * Deletes every leftover in-progress entry. Only call when no create or
     * copy is running, or it would delete one that is still being written.
     */
    fun sweepStaging(): Int {
        val children = root.listFiles() ?: return 0
        var removed = 0
        for (child in children) {
            if (child.name.startsWith(STAGING_PREFIX) && deleteTree(child)) removed++
        }
        return removed
    }

    /**
     * Deletes names that were reserved but never filled: zero-byte files and
     * empty directories directly under [root]. A registered vault is never
     * either (a container has a header, a folder vault has its config file),
     * so these can only be what a crash left between claiming a name and
     * publishing into it. Only call when no create or copy is running.
     */
    fun sweepReservations(): Int {
        val children = root.listFiles() ?: return 0
        var removed = 0
        for (child in children) {
            if (child.name.startsWith(".")) continue
            if (Files.isSymbolicLink(child.toPath())) continue
            val abandoned = if (child.isDirectory) child.list()?.isEmpty() == true else child.isFile && child.length() == 0L
            if (abandoned && deleteTree(child)) removed++
        }
        return removed
    }

    /**
     * Deletes [target] and everything under it, without following symlinks.
     * Refuses (returns false) for anything that is not strictly inside [root];
     * this is the only place the app deletes vault data on a path that came
     * from outside the native layer, so the containment check is the guard.
     */
    fun deleteTree(target: File): Boolean {
        if (!isInside(target)) return false
        val start: Path = target.toPath()
        if (!Files.exists(start, java.nio.file.LinkOption.NOFOLLOW_LINKS)) return true
        return try {
            Files.walkFileTree(start, object : SimpleFileVisitor<Path>() {
                override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                    Files.delete(file)
                    return FileVisitResult.CONTINUE
                }

                override fun postVisitDirectory(dir: Path, exc: IOException?): FileVisitResult {
                    if (exc != null) throw exc
                    Files.delete(dir)
                    return FileVisitResult.CONTINUE
                }
            })
            true
        } catch (_: IOException) {
            false
        }
    }

    /** Free bytes on the volume holding [root]. */
    fun availableBytes(): Long = ensureRoot().usableSpace

    /** Total size in bytes of the files under [dir]. */
    fun treeSize(dir: File): Long {
        var total = 0L
        val stack = ArrayDeque<File>()
        stack.add(dir)
        while (stack.isNotEmpty()) {
            val cur = stack.removeLast()
            val kids = cur.listFiles() ?: continue
            for (k in kids) {
                if (Files.isSymbolicLink(k.toPath())) continue
                if (k.isDirectory) stack.add(k) else total += k.length()
            }
        }
        return total
    }

    /** Registered vaults (staging entries are hidden), sorted by name. */
    fun list(): List<Entry> {
        val children = root.listFiles() ?: return emptyList()
        return children
            .filter { !it.name.startsWith(".") }
            .sortedBy { it.name.lowercase() }
            .map { f -> if (f.isDirectory) Entry(f, true, treeSize(f)) else Entry(f, false, f.length()) }
    }
}
