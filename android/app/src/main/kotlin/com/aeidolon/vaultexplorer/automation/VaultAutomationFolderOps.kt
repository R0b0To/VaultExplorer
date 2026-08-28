package com.aeidolon.vaultexplorer.automation

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.camera.VaultChunkWriter
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.ScopedStorageUtils
import com.aeidolon.vaultexplorer.saf.VaultPathUtils
import com.aeidolon.vaultexplorer.VeLog
import java.io.File
import java.io.InputStream
import java.io.OutputStream

private const val TAG = "VaultExplorer_AutomationIO"

/**
 * Shared source/destination resolution + copy logic for
 * [VaultAutomationReceiver]'s file- and folder-level actions (IMPORT_FILE,
 * EXPORT_FILE, IMPORT_FOLDER, EXPORT_FOLDER).
 *
 * A source or destination string is either a plain filesystem path (this
 * app already holds MANAGE_EXTERNAL_STORAGE, so these are read/written
 * directly) or a `content://` SAF Uri -- detected via
 * [ScopedStorageUtils.isSafUri], the same convention [SplitJoinHandlers]
 * and [SingleFileCryptoHandlers] already use for the same
 * raw-path-fast-path / SAF-fallback shape.
 *
 * Important limitation, not something this file can work around: a
 * `content://` Uri only works here if this app *already holds a persisted
 * permission grant* for it -- typically because the same folder was picked
 * through one of the app's own SAF pickers at some point.  Android does
 * not let a sending app confer that grant just by attaching
 * FLAG_GRANT_*_URI_PERMISSION to a broadcast *extra* string the way it
 * does for an Intent's own `data`/`clipData` -- an arbitrary content:// Uri
 * an automation profile has never handed this app permission for will
 * simply fail to resolve/read/write here, surfaced by the caller as
 * INVALID_ARGS/ERROR rather than partial or silently-empty data.
 */
object VaultAutomationFolderOps {

    private const val CHUNK_SIZE = 64 * 1024

    data class OpSummary(
        val filesOk: Int,
        val filesFailed: Int,
        val filesSkipped: Int = 0,
        val filesMatched: Int = filesOk + filesFailed,
        val truncated: Boolean = false,
    ) {
        val allFailed: Boolean get() = filesOk == 0 && filesFailed > 0
        val anyFailed: Boolean get() = filesFailed > 0
    }

    data class VaultDirEntry(val name: String, val isDir: Boolean)

    private sealed class ResolvedFolder {
        data class Raw(val file: File) : ResolvedFolder()
        data class Tree(val doc: DocumentFile) : ResolvedFolder()
    }

    // ── Single-item copy -- also used as IMPORT_FILE/EXPORT_FILE's SAF fallback ──

    /**
     * Copies one external item (raw path or `content://` document) into
     * [vaultPath], creating any missing intermediate vault directories
     * first. Always finalizes with [ContainerFileSystem.finishWrite] on
     * success, matching the writeBackFile-then-finishWrite pairing
     * ContainerToolService's crypto-to-vault path already uses -- cheap
     * and harmless for backends that don't need it, required for the ones
     * that do.
     */
    fun importOneFile(context: Context, volId: Int, sourceSpec: String, vaultPath: String): Boolean {
        ensureParentDirs(volId, vaultPath)
        if (!ScopedStorageUtils.isSafUri(sourceSpec)) {
            val src = File(sourceSpec)
            if (!src.canRead()) return false
            val ok = ContainerFileSystem.writeBackFile(volId, vaultPath, sourceSpec)
            if (ok) ContainerFileSystem.finishWrite(volId, vaultPath)
            return ok
        }
        val input = openInputStreamSafely(context, Uri.parse(sourceSpec)) ?: return false
        return streamIntoVault(volId, vaultPath, input)
    }

    /**
     * Copies the vault file at [vaultPath] out to [destSpec]. For a raw
     * path, [destSpec] is the *full destination file path* (matching
     * VaultAutomationReceiver's existing EXPORT_FILE contract). For a
     * `content://` Uri, [destSpec] must be a *tree* Uri (a folder) --
     * SAF has no way to create a new document inside a single-document
     * Uri -- and the file is created inside it named after [vaultPath]'s
     * own basename.
     */
    fun exportOneFile(context: Context, volId: Int, vaultPath: String, destSpec: String): Boolean {
        if (!ScopedStorageUtils.isSafUri(destSpec)) {
            File(destSpec).parentFile?.let { if (!it.exists()) it.mkdirs() }
            return ContainerFileSystem.extractToFile(volId, vaultPath, destSpec)
        }
        val treeDoc = try {
            DocumentFile.fromTreeUri(context, Uri.parse(destSpec))
        } catch (e: Exception) {
            null
        } ?: return false
        if (!treeDoc.isDirectory || !treeDoc.canWrite()) return false
        val name = VaultPathUtils.nameOf(VaultPathUtils.normalize(vaultPath))
        treeDoc.findFile(name)?.delete()
        val doc = treeDoc.createFile("application/octet-stream", name) ?: return false
        val out = openOutputStreamSafely(context, doc.uri) ?: return false
        return streamOutOfVault(volId, vaultPath, out)
    }

    // ── Recursive folder copy ─────────────────────────────────────────────

    /**
     * Recursively mirrors [sourceSpec] (a directory, raw or `content://`
     * tree) into [vaultDestDir]. Existing files at colliding relative
     * paths are overwritten (re-importing the same tree updates it in
     * place, the same as re-running IMPORT_FILE on one file would);
     * existing vault directories are left alone. One file failing doesn't
     * abort the rest -- best-effort sync semantics fit a nightly-backup
     * automation profile better than all-or-nothing, and the returned
     * [OpSummary] tells the caller whether anything failed.
     *
     * Optionally filters files matching [pattern].
     *
     * Returns null only when [sourceSpec] itself can't be resolved as a
     * readable directory at all (caller should treat that as INVALID_ARGS).
     */
    fun importFolder(
        context: Context,
        volId: Int,
        sourceSpec: String,
        vaultDestDir: String,
        deleteSource: Boolean,
        pattern: GlobMatcher.GlobPattern? = null,
        recursive: Boolean = true,
    ): OpSummary? {
        val root = resolveSourceFolder(context, sourceSpec) ?: return null
        var ok = 0
        var failed = 0
        var skipped = 0
        val destBase = VaultPathUtils.normalize(vaultDestDir)

        fun importLeaf(vaultPath: String, relativePath: String, rawFile: File?, docUri: Uri?) {
            if (pattern != null && !GlobMatcher.matches(pattern, relativePath)) {
                skipped++
                return
            }
            ensureParentDirs(volId, vaultPath)
            val success = if (rawFile != null) {
                ContainerFileSystem.writeBackFile(volId, vaultPath, rawFile.absolutePath).also {
                    if (it) ContainerFileSystem.finishWrite(volId, vaultPath)
                }
            } else {
                val input = docUri?.let { openInputStreamSafely(context, it) }
                if (input == null) false else streamIntoVault(volId, vaultPath, input)
            }
            if (success) {
                ok++
                if (deleteSource) {
                    if (rawFile != null) {
                        SecureFileWipe.secureDeleteFile(rawFile)
                    } else if (docUri != null) {
                        // No local bytes to zero for most SAF providers (cloud
                        // documents in particular) -- this is a normal provider
                        // delete, not a secure wipe. Documented on the
                        // EXTRA_DELETE_SOURCE constant in VaultAutomationReceiver.
                        try { DocumentFile.fromSingleUri(context, docUri)?.delete() } catch (_: Exception) {}
                    }
                }
            } else {
                failed++
                VeLog.w(TAG) { "importFolder: failed to import into $vaultPath" }
            }
        }

        when (root) {
            is ResolvedFolder.Raw -> {
                val fileSeq = if (recursive) root.file.walkTopDown() else (root.file.listFiles()?.asSequence() ?: emptySequence())
                fileSeq.filter { it.isFile }.forEach { f ->
                    val relative = f.toRelativeString(root.file).replace('\\', '/')
                    importLeaf(VaultPathUtils.joinPath(destBase, relative), relative, f, null)
                }
            }
            is ResolvedFolder.Tree -> {
                val saf = SafDocumentOps(context)
                fun walk(dir: DocumentFile, relPrefix: String) {
                    for (child in saf.listChildren(dir)) {
                        val name = child.name ?: continue
                        val childRel = if (relPrefix.isEmpty()) name else "$relPrefix/$name"
                        if (child.isDirectory) {
                            if (recursive) walk(child, childRel)
                        } else {
                            importLeaf(VaultPathUtils.joinPath(destBase, childRel), childRel, null, child.uri)
                        }
                    }
                }
                walk(root.doc, "")
            }
        }
        return OpSummary(filesOk = ok, filesFailed = failed, filesSkipped = skipped, filesMatched = ok + failed, truncated = false)
    }

    /**
     * Recursively mirrors the vault subtree at [vaultSourceDir] out to
     * [destSpec] (raw path or `content://` tree, created if missing).
     * Same overwrite-in-place / best-effort-per-file semantics as
     * [importFolder]. [OpSummary.truncated] is true if any vault
     * directory in the subtree hit the native listing's "too many
     * children" cap (the `"System:TRUNCATED"` sentinel -- see
     * RawEntry.parseAll's doc comment on the Dart side) -- the export
     * still completes for everything it *could* enumerate, but the
     * caller should know it isn't guaranteed complete.
     *
     * Optionally filters files matching [pattern].
     */
    fun exportFolder(
        context: Context,
        volId: Int,
        vaultSourceDir: String,
        destSpec: String,
        pattern: GlobMatcher.GlobPattern? = null,
        recursive: Boolean = true,
    ): OpSummary? {
        val dest = resolveDestFolder(context, destSpec) ?: return null
        var ok = 0
        var failed = 0
        var skipped = 0
        var truncated = false
        val srcBase = VaultPathUtils.normalize(vaultSourceDir)
        val saf = if (dest is ResolvedFolder.Tree) SafDocumentOps(context) else null

        fun exportLeaf(vaultPath: String, relativePath: String) {
            if (pattern != null && !GlobMatcher.matches(pattern, relativePath)) {
                skipped++
                return
            }
            val success = when (dest) {
                is ResolvedFolder.Raw -> {
                    val outFile = File(dest.file, relativePath)
                    outFile.parentFile?.let { if (!it.exists()) it.mkdirs() }
                    ContainerFileSystem.extractToFile(volId, vaultPath, outFile.absolutePath)
                }
                is ResolvedFolder.Tree -> {
                    val parentDoc = ensureSafDirs(saf!!, dest.doc, VaultPathUtils.parentOf(relativePath))
                    val name = VaultPathUtils.nameOf(relativePath)
                    if (parentDoc == null) {
                        false
                    } else {
                        parentDoc.findFile(name)?.delete()
                        val doc = saf.createFileSafe(parentDoc, "application/octet-stream", name)
                        val out = doc?.let { openOutputStreamSafely(context, it.uri) }
                        if (out == null) false else streamOutOfVault(volId, vaultPath, out)
                    }
                }
            }
            if (success) ok++ else {
                failed++
                VeLog.w(TAG) { "exportFolder: failed to export $vaultPath" }
            }
        }

        fun walk(dirPath: String, relPrefix: String) {
            val entries = ContainerFileSystem.listDirectory(volId, dirPath) ?: return
            for (raw in entries) {
                if (raw.startsWith("System:")) {
                    truncated = true
                    continue
                }
                val entry = parseDirEntry(raw) ?: continue
                val childRel = if (relPrefix.isEmpty()) entry.name else "$relPrefix/${entry.name}"
                val childVaultPath = VaultPathUtils.joinPath(dirPath, entry.name)
                if (entry.isDir) {
                    if (recursive) walk(childVaultPath, childRel)
                } else {
                    exportLeaf(childVaultPath, childRel)
                }
            }
        }
        walk(srcBase, "")
        return OpSummary(filesOk = ok, filesFailed = failed, filesSkipped = skipped, filesMatched = ok + failed, truncated = truncated)
    }

    // ── Resolution helpers ──────────────────────────────────────────────

    private fun resolveSourceFolder(context: Context, spec: String): ResolvedFolder? {
        if (ScopedStorageUtils.isSafUri(spec)) {
            val doc = try { DocumentFile.fromTreeUri(context, Uri.parse(spec)) } catch (e: Exception) { null }
            return if (doc != null && doc.isDirectory) ResolvedFolder.Tree(doc) else null
        }
        val f = File(spec)
        return if (f.isDirectory && f.canRead()) ResolvedFolder.Raw(f) else null
    }

    private fun resolveDestFolder(context: Context, spec: String): ResolvedFolder? {
        if (ScopedStorageUtils.isSafUri(spec)) {
            val doc = try { DocumentFile.fromTreeUri(context, Uri.parse(spec)) } catch (e: Exception) { null }
            return if (doc != null && doc.isDirectory && doc.canWrite()) ResolvedFolder.Tree(doc) else null
        }
        val f = File(spec)
        return if (f.exists() || f.mkdirs()) ResolvedFolder.Raw(f) else null
    }

    private fun ensureSafDirs(saf: SafDocumentOps, root: DocumentFile, relativeDirPath: String): DocumentFile? {
        if (relativeDirPath.isEmpty()) return root
        var current = root
        for (seg in relativeDirPath.split("/")) {
            if (seg.isEmpty()) continue
            val existing = saf.childOf(current, seg)
            current = if (existing != null && existing.isDirectory) {
                existing
            } else {
                saf.createDirectorySafe(current, seg) ?: return null
            }
        }
        return current
    }

    private fun ensureParentDirs(volId: Int, vaultPath: String) {
        val parent = VaultPathUtils.parentOf(VaultPathUtils.normalize(vaultPath))
        if (parent.isEmpty()) return
        var current = ""
        for (seg in parent.split("/")) {
            current = if (current.isEmpty()) seg else "$current/$seg"
            // Return value is ignored on purpose: false just as often means
            // "already exists" as "failed", and either way the write attempt
            // right after this will surface a real problem on its own.
            ContainerFileSystem.createDirectory(volId, current)
        }
    }

    /** Mirrors RawEntry.parse's wire format on the Dart side (raw_entry.dart):
     *  "F|sizeBytes|unixSecs|name" / "D|0|unixSecs|name" -- an explicit type
     *  tag, then the name as everything after the third '|' so a name that
     *  itself contains '|' still round-trips. Public: VaultAutomationReceiver
     *  also uses this for auto-generated TAKE_PHOTO/START_RECORDING names'
     *  collision check. */
    fun parseDirEntry(raw: String): VaultDirEntry? {
        val firstSep = raw.indexOf('|')
        val secondSep = if (firstSep < 0) -1 else raw.indexOf('|', firstSep + 1)
        val thirdSep = if (secondSep < 0) -1 else raw.indexOf('|', secondSep + 1)
        if (firstSep < 0 || secondSep < 0 || thirdSep < 0) return null
        val typeTag = raw.substring(0, firstSep)
        val name = raw.substring(thirdSep + 1)
        return VaultDirEntry(name = name, isDir = typeTag == "D")
    }

    // ── Streaming copy (content:// entries, and vault <-> stream in general) ──

    private fun openInputStreamSafely(context: Context, uri: Uri): InputStream? =
        try { context.contentResolver.openInputStream(uri) } catch (e: Exception) {
            VeLog.w(TAG, e) { "openInputStreamSafely failed for $uri" }
            null
        }

    private fun openOutputStreamSafely(context: Context, uri: Uri): OutputStream? =
        try { context.contentResolver.openOutputStream(uri, "wt") } catch (e: Exception) {
            VeLog.w(TAG, e) { "openOutputStreamSafely failed for $uri" }
            null
        }

    private fun streamIntoVault(volId: Int, vaultPath: String, input: InputStream): Boolean {
        val writer = VaultChunkWriter(volId, vaultPath)
        return try {
            input.use { stream ->
                val buffer = ByteArray(CHUNK_SIZE)
                var read: Int
                while (stream.read(buffer).also { read = it } != -1) {
                    if (read > 0) {
                        val chunk = if (read == buffer.size) buffer else buffer.copyOf(read)
                        if (!writer.write(chunk)) return false
                    }
                }
            }
            ContainerFileSystem.finishWrite(volId, vaultPath)
            true
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "streamIntoVault failed for $vaultPath" }
            false
        }
    }

    private fun streamOutOfVault(volId: Int, vaultPath: String, out: OutputStream): Boolean {
        return try {
            out.use { stream ->
                val size = ContainerFileSystem.getFileSize(volId, vaultPath).coerceAtLeast(0L)
                var offset = 0L
                while (offset < size) {
                    val remaining = (size - offset).coerceAtMost(CHUNK_SIZE.toLong()).toInt()
                    val chunk = ContainerFileSystem.readFileChunk(volId, vaultPath, offset, remaining) ?: break
                    if (chunk.isEmpty()) break
                    stream.write(chunk)
                    offset += chunk.size
                }
            }
            true
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "streamOutOfVault failed for $vaultPath" }
            false
        }
    }
}
