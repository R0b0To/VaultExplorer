package com.aeidolon.vaultexplorer.handlers

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.RawFileResolver
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.bridge.ExportProgressBridge
import com.aeidolon.vaultexplorer.bridge.ImportProgressBridge
import com.aeidolon.vaultexplorer.bridge.IncomingShareBridge
import com.aeidolon.vaultexplorer.cancellation.ExportCancellation
import com.aeidolon.vaultexplorer.cancellation.ExportCancelledException
import com.aeidolon.vaultexplorer.cancellation.ImportCancellation
import com.aeidolon.vaultexplorer.cancellation.ImportCancelledException
import com.aeidolon.vaultexplorer.container.ContainerEngine
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.container.VaultBackendRegistry
import com.aeidolon.vaultexplorer.DirEntryWire
import com.aeidolon.vaultexplorer.FilesystemNameValidator
import com.aeidolon.vaultexplorer.ImportSourceRegistry
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.PendingActivityResult
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.VeLog

/**
 * Bulk import/export between SAF documents on the outside and a mounted
 * container's virtual filesystem on the inside: single/multi-file import,
 * whole-folder import, single-file export, and multi-item export-to-folder.
 * Progress for the two import flows streams to Dart via
 * [ImportProgressBridge]; [ImportCancellation] lets the Dart side cancel an
 * in-flight import by opId. The multi-item export-to-folder flow mirrors
 * this via [ExportProgressBridge]/[ExportCancellation].
 */
class ImportExportHandlers(
    private val activity: MainActivity,
    private val pendingResult: PendingActivityResult,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    companion object {
        /**
         * Fraction of a destination's reported free space held back as a
         * safety cushion in [rejectIfInsufficientSpace], to absorb real
         * per-transfer overhead -- filesystem cluster/directory-entry
         * rounding for block-device containers, or per-file header plus
         * per-block MAC/IV overhead for the directory-based vault formats
         * (Cryptomator/gocryptfs/CryFS) -- that isn't reflected in a raw
         * source byte count.
         *
         * Deliberately small: real overhead for a modest number of
         * reasonably sized files is nowhere near 5%, and reserving that
         * much rejected transfers that would genuinely have fit (an
         * 8-file/138MB import into a vault with 142MB free, for example).
         * Mirrored by `kFreeSpaceSafetyMargin` in file_size.dart on the
         * Dart side (file_operation_service.dart, vault_sync_controller.dart)
         * -- keep both in sync if this changes.
         */
        const val SPACE_SAFETY_MARGIN = 0.01

        /**
         * True if [totalBytes] fits within [available] once
         * [SPACE_SAFETY_MARGIN] is held back -- the predicate behind
         * [rejectIfInsufficientSpace]. Extracted as a pure function purely
         * so it's directly testable without a live container session
         * (which [ContainerFileSystem.getSpaceInfo], the caller supplying
         * [available], actually needs) -- same pattern as
         * [isMissingContainerUri] and [uniqueNameAgainst] above.
         */
        internal fun fitsWithinSafetyMargin(totalBytes: Long, available: Long): Boolean =
            totalBytes <= (available * (1.0 - SPACE_SAFETY_MARGIN)).toLong()

        /**
         * True if no `filePath` (containerUri) argument was supplied.
         * Extracted as a pure function purely so it's directly testable --
         * see PendingResultLeakTest, which exercises this exact predicate
         * (shared by [handlePickImportFiles], [handleExportFilesFolder], and
         * [handlePickImportFolder] -- the three handlers that launch a
         * system picker and so must stash the Flutter result) to confirm
         * each replies and returns *before* calling
         * [PendingActivityResult.stash], never after. [handleImportFile]
         * and [handleImportFolder] don't launch a picker anymore (they
         * resume an already-completed pick by token instead), so they
         * don't stash and aren't part of this invariant. Mirrors
         * VaultCreationHandlers.isMissingCredentials.
         */
        fun isMissingContainerUri(containerUri: String?): Boolean = containerUri == null

        /** Same, for [handleExportFile], which additionally requires sourcePath. */
        fun isMissingContainerOrSource(containerUri: String?, sourcePath: String?): Boolean =
            containerUri == null || sourcePath == null

        /**
         * Returns [desiredName] unchanged if its lowercased form isn't in
         * [existingLowercase], otherwise appends " (1)", " (2)", etc.
         * (preserving the file extension, if any) until it finds a free
         * name. Extracted out of [uniqueImportName] as a pure function of
         * an already-fetched name set -- same motivation as
         * [isMissingContainerUri] above -- so the naming algorithm itself
         * is testable without a live container session; the fetch itself
         * ([existingNamesLowercase]) is not tested here.
         *
         * Import previously wrote straight to the sanitized source name, so
         * a file/folder already at the destination was silently
         * overwritten. Every import target now goes through this first.
         */
        internal fun uniqueNameAgainst(existingLowercase: Set<String>, desiredName: String): String {
            if (desiredName.lowercase() !in existingLowercase) return desiredName

            val dot = desiredName.lastIndexOf('.')
            val hasExt = dot > 0 && dot < desiredName.length - 1
            val base = if (hasExt) desiredName.substring(0, dot) else desiredName
            val ext = if (hasExt) desiredName.substring(dot) else ""

            var n = 1
            while (true) {
                val candidate = "$base ($n)$ext"
                if (candidate.lowercase() !in existingLowercase) return candidate
                n++
            }
        }
    }

    private data class PendingExportMulti(
        val containerUri: String, val items: List<Map<String, Any?>>, val volId: Int, val opId: Int,
    )
    private var pendingExportMulti: PendingExportMulti? = null

    private data class PendingExportFile(val containerUri: String, val sourcePath: String, val volId: Int)
    private var pendingExportFile: PendingExportFile? = null

    // ── Two-phase import: pick + conflict-detect, then complete ────────────
    // handlePickImportFiles/handlePickImportFolder launch the system picker
    // and report back which picked top-level name(s) collide with the
    // destination directory, writing nothing yet. handleImportFile/
    // handleImportFolder then resume the same pick by [pickToken] (looked
    // up here, removed on use) once the Dart side has resolved those
    // conflicts, instead of prompting the system picker again. A pick that's
    // abandoned instead of completed (see handleCancelPickedImport) is
    // simply dropped from these maps -- nothing was written, so there's
    // nothing else to undo.

    /** One file the multi-file picker returned, before any conflict is resolved. */
    private data class PickedFileEntry(val doc: DocumentFile, val raw: File?, val name: String)

    private data class PendingPickFiles(val containerUri: String, val targetDir: String, val volId: Int)
    private var pendingPickFiles: PendingPickFiles? = null

    private data class PickedImportFiles(
        val containerUri: String, val targetDir: String, val volId: Int, val entries: List<PickedFileEntry>,
    )
    private val pickedFilesByToken = java.util.concurrent.ConcurrentHashMap<Int, PickedImportFiles>()

    private data class PendingPickFolder(val containerUri: String, val targetDir: String, val volId: Int)
    private var pendingPickFolder: PendingPickFolder? = null

    private data class PickedImportFolder(
        val containerUri: String, val targetDir: String, val volId: Int,
        val treeUri: Uri, val srcRoot: DocumentFile, val rawRoot: File?, val folderName: String,
    )
    private val pickedFolderByToken = java.util.concurrent.ConcurrentHashMap<Int, PickedImportFolder>()

    private val nextPickToken = java.util.concurrent.atomic.AtomicInteger(1)

    private fun existingNamesLowercase(volId: Int, dirPath: String): Set<String> {
        val entries = ContainerFileSystem.listDirectory(volId, dirPath) ?: return emptySet()
        return entries.mapNotNull { entry ->
            if (entry.startsWith("System:")) return@mapNotNull null
            DirEntryWire.parse(entry)?.name?.lowercase()
        }.toSet()
    }

    /**
     * Returns [desiredName] unchanged if nothing in [dirPath] already has
     * that name (case-insensitively), otherwise appends " (1)", " (2)", etc.
     * (preserving the file extension, if any) until it finds a free name.
     *
     * Import previously wrote straight to the sanitized source name, so a
     * file/folder already at the destination was silently overwritten.
     * Every import target now goes through this first.
     */
    private fun uniqueImportName(volId: Int, dirPath: String, desiredName: String): String =
        uniqueNameAgainst(existingNamesLowercase(volId, dirPath), desiredName)

    /**
     * Same idea as [existingNamesLowercase] but only the subset that are
     * folders -- lets the import conflict pre-check report whether a
     * colliding destination entry is a file or a folder (see
     * `ImportPickConflict.destIsDir` on the Dart side), so the sheet can
     * show "Overwrite folder" instead of a generic "Overwrite", exactly
     * like `ConflictEntry.destIsDir` already does for paste.
     */
    private fun existingDirsLowercase(volId: Int, dirPath: String): Set<String> {
        val entries = ContainerFileSystem.listDirectory(volId, dirPath) ?: return emptySet()
        return entries.mapNotNull { entry ->
            if (entry.startsWith("System:")) return@mapNotNull null
            val parsed = DirEntryWire.parse(entry) ?: return@mapNotNull null
            if (parsed.isDir) parsed.name.lowercase() else null
        }.toSet()
    }

    /**
     * Deletes whatever currently occupies [path] -- recursing into it
     * first when [isDir] -- so an "overwrite" resolution actually replaces
     * the destination entry instead of merging into it (for a folder) or
     * failing against it (for a file). Mirrors
     * `FileOperationService._deleteEntryRecursive` on the Dart side,
     * which does the same thing for paste's overwrite case.
     */
    private fun deleteExistingRecursive(volId: Int, path: String, isDir: Boolean): Boolean {
        if (!isDir) return ContainerFileSystem.deleteFile(volId, path)
        val children = ContainerFileSystem.listDirectory(volId, path) ?: emptyArray()
        var childrenOk = true
        for (entry in children) {
            if (entry.startsWith("System:")) continue
            val parsed = DirEntryWire.parse(entry) ?: continue
            if (!deleteExistingRecursive(volId, "$path/${parsed.name}", parsed.isDir)) {
                childrenOk = false
            }
        }
        return ContainerFileSystem.deleteFile(volId, path) && childrenOk
    }

    /**
     * Decides the final on-disk name for one top-level picked entry named
     * [pickedName] against [dirPath], honoring the conflict [plan] the
     * Dart side resolved (lowercased picked name -> "skip" / "overwrite" /
     * "keepBoth", as sent by `VaultExplorerApi.importFiles`/`importFolder`).
     * Returns `null` if this entry should be skipped entirely.
     *
     * A name absent from [plan] didn't collide with anything at pick time
     * (or the plan is empty because there was nothing to resolve) and
     * falls through to [uniqueImportName]'s ordinary behavior, which also
     * transparently covers two picked items sharing a name with *each
     * other* rather than with the destination -- see [uniqueImportName]'s
     * own doc comment.
     */
    private fun resolveImportName(
        volId: Int, dirPath: String, pickedName: String, plan: Map<String, String>,
    ): String? {
        return when (plan[pickedName.lowercase()]) {
            "skip" -> null
            "overwrite" -> {
                val key = pickedName.lowercase()
                if (existingNamesLowercase(volId, dirPath).contains(key)) {
                    val isDir = existingDirsLowercase(volId, dirPath).contains(key)
                    val existingPath = if (dirPath.isEmpty()) pickedName else "$dirPath/$pickedName"
                    deleteExistingRecursive(volId, existingPath, isDir)
                }
                pickedName
            }
            else -> uniqueImportName(volId, dirPath, pickedName)
        }
    }

    /**
     * Checks [totalBytes] against [volId]'s free space (via
     * [ContainerFileSystem.getSpaceInfo]) and, if it won't fit, replies to
     * [result] with a structured `INSUFFICIENT_SPACE` error -- same code
     * and detail shape as [VaultCreationHandlers]' create-container guard
     * -- instead of letting a multi-file/folder import run partway,
     * abort on the first native write failure, and leave whatever
     * already landed with no clear explanation of what happened. Returns
     * true if the import should stop here (a reply has already been
     * sent); callers `return@execute` immediately when this is true.
     *
     * A [SPACE_SAFETY_MARGIN] margin is reserved past the raw byte count
     * -- mirrors `FileOperationService._run`'s upfront check on the Dart
     * side (used for intra-vault copy/paste), which applies the same
     * margin for the same reason: container/filesystem overhead (FAT
     * metadata, cluster rounding, per-file headers) means a transfer sized
     * to exactly fill "available" can still legitimately come up short.
     *
     * Returns `false` (never blocks the import) when
     * [ContainerFileSystem.getSpaceInfo] can't report free space for this
     * volume -- same graceful-degradation the Dart-side check already
     * falls back to.
     */
    private fun rejectIfInsufficientSpace(
        volId: Int, totalBytes: Long, opId: Int, logTag: String, result: MethodChannel.Result,
    ): Boolean {
        val available = ContainerFileSystem.getSpaceInfo(volId)
            ?.let { if (it.size > 1) it[1] else null } ?: return false
        if (fitsWithinSafetyMargin(totalBytes, available)) return false
        VeLog.w(logTag) {
            "$logTag insufficient space opId=$opId needed=$totalBytes available=$available"
        }
        activity.runOnUiThread {
            result.error(
                "INSUFFICIENT_SPACE",
                "Not enough free space in the vault: need $totalBytes bytes, only $available available",
                mapOf("neededBytes" to totalBytes, "availableBytes" to available),
            )
        }
        return true
    }

    /**
     * @param opId 0 means "no progress/cancellation tracking" (e.g. a
     *   future caller that hasn't been wired up yet) -- every progress call
     *   below is guarded on `opId > 0` for that reason, matching how
     *   [ContainerFileSystem.extractToFile] treats an opId of 0.
     */
    /**
     * Abstracts the SAF (DocumentFile) vs raw (File) export destination.
     * The two leaf-write mechanics genuinely differ -- SAF has to extract to
     * a cache temp file and copy it through the DocumentsProvider, while a
     * raw destination lets ContainerFileSystem.extractToFile write straight
     * to the final path, no temp file or copy needed -- but the cancellation
     * check, directory walk, and recursion around that write were previously
     * duplicated wholesale across exportEntryRecursive/exportEntryRecursiveRaw.
     * This carries only that duplicated control flow; each leaf-write body
     * below is unchanged from its original function.
     */
    private sealed class ExportDestination {
        abstract fun childDirectory(name: String): ExportDestination?
        abstract fun writeLeaf(
            volId: Int, fatPath: String, name: String, opId: Int, total: Int,
            doneCounter: java.util.concurrent.atomic.AtomicInteger, totalBytes: Long,
            transferredCounter: java.util.concurrent.atomic.AtomicLong,
        ): Int

        class Saf(private val activity: Activity, private val doc: DocumentFile) : ExportDestination() {
            override fun childDirectory(name: String): ExportDestination? =
                doc.createDirectory(name)?.let { Saf(activity, it) }

            override fun writeLeaf(
                volId: Int, fatPath: String, name: String, opId: Int, total: Int,
                doneCounter: java.util.concurrent.atomic.AtomicInteger, totalBytes: Long,
                transferredCounter: java.util.concurrent.atomic.AtomicLong,
            ): Int {
                if (opId > 0) {
                    // Same fix as the raw-path import: without opId/
                    // beginFileChunks this was one silent blocking call (via
                    // extractToFile) with no progress signal until it returned.
                    ExportProgressBridge.reportProgress(opId, doneCounter.get(), total, name, transferredCounter.get(), totalBytes)
                    ExportProgressBridge.beginFileChunks(opId, transferredCounter.get())
                }
                val tempFile = File(activity.cacheDir, "export_${System.nanoTime()}")
                return try {
                    val ok = ContainerFileSystem.extractToFile(volId, fatPath, tempFile.absolutePath, opId)
                    var written = 0
                    if (ok && tempFile.exists()) {
                        val fileSize = tempFile.length()
                        doc.findFile(name)?.delete()
                        val outDoc = doc.createFile(MimeTypeHelper.getMimeType(name), name)
                        if (outDoc != null) {
                            activity.contentResolver.openOutputStream(outDoc.uri)?.use { out ->
                                tempFile.inputStream().use { it.copyTo(out) }
                            }
                            written = 1
                        }
                        if (opId > 0) {
                            val transferred = transferredCounter.addAndGet(fileSize)
                            val done = doneCounter.incrementAndGet()
                            ExportProgressBridge.reportProgress(opId, done, total, name, transferred, totalBytes)
                        }
                    }
                    written
                } catch (_: Exception) { 0 } finally {
                    SecureFileWipe.secureDeleteFile(tempFile)
                }
            }
        }

        class Raw(private val dir: File) : ExportDestination() {
            override fun childDirectory(name: String): ExportDestination? {
                val d = File(dir, name)
                return if (d.exists() || d.mkdirs()) Raw(d) else null
            }

            override fun writeLeaf(
                volId: Int, fatPath: String, name: String, opId: Int, total: Int,
                doneCounter: java.util.concurrent.atomic.AtomicInteger, totalBytes: Long,
                transferredCounter: java.util.concurrent.atomic.AtomicLong,
            ): Int {
                if (opId > 0) {
                    ExportProgressBridge.reportProgress(opId, doneCounter.get(), total, name, transferredCounter.get(), totalBytes)
                    ExportProgressBridge.beginFileChunks(opId, transferredCounter.get())
                }
                return try {
                    val target = File(dir, name)
                    if (target.exists()) target.delete()
                    val ok = ContainerFileSystem.extractToFile(volId, fatPath, target.absolutePath, opId)
                    if (ok && target.exists()) {
                        if (opId > 0) {
                            val transferred = transferredCounter.addAndGet(target.length())
                            val done = doneCounter.incrementAndGet()
                            ExportProgressBridge.reportProgress(opId, done, total, name, transferred, totalBytes)
                        }
                        1
                    } else {
                        0
                    }
                } catch (_: Exception) { 0 }
            }
        }
    }

    private fun exportEntryRecursive(
        dest: ExportDestination, fatPath: String, isDir: Boolean, volId: Int,
        opId: Int = 0, total: Int = 0, doneCounter: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(0),
        totalBytes: Long = 0L, transferredCounter: java.util.concurrent.atomic.AtomicLong = java.util.concurrent.atomic.AtomicLong(0L),
    ): Int {
        if (opId > 0 && ExportCancellation.isCancelled(opId)) {
            throw ExportCancelledException("Export cancelled")
        }
        val name = fatPath.substringAfterLast("/")
        if (!isDir) {
            return dest.writeLeaf(volId, fatPath, name, opId, total, doneCounter, totalBytes, transferredCounter)
        }
        val destDir = dest.childDirectory(name) ?: return 0
        val children = ContainerFileSystem.listDirectory(volId, fatPath) ?: return 0
        var count = 0
        for (entry in children) {
            if (entry.startsWith("System:")) continue
            val parsed = DirEntryWire.parse(entry) ?: continue
            count += exportEntryRecursive(
                destDir, "$fatPath/${parsed.name}", parsed.isDir, volId,
                opId, total, doneCounter, totalBytes, transferredCounter,
            )
        }
        return count
    }

    /** Container-side counterpart to [countEntriesRecursive]/[countEntriesRaw]
     *  (which walk an external SAF/raw source for import): counts every leaf
     *  file under [fatPath] *inside* the container, for export's total. */
    private fun countContainerEntriesRecursive(volId: Int, fatPath: String, isDir: Boolean): Int {
        if (!isDir) return 1
        val children = ContainerFileSystem.listDirectory(volId, fatPath) ?: return 0
        var count = 0
        for (entry in children) {
            if (entry.startsWith("System:")) continue
            val parsed = DirEntryWire.parse(entry) ?: continue
            count += countContainerEntriesRecursive(volId, "$fatPath/${parsed.name}", parsed.isDir)
        }
        return count
    }

    /** Container-side counterpart to [countBytesRecursive]/[countBytesRaw]. */
    private fun countContainerBytes(volId: Int, fatPath: String, isDir: Boolean): Long =
        if (isDir) ContainerFileSystem.getFolderSize(volId, fatPath) else ContainerFileSystem.getFileSize(volId, fatPath)

    /**
     * Resolves [uri] (single-document or tree) to a raw [File] when "All
     * Files Access" (MANAGE_EXTERNAL_STORAGE) is granted and the document
     * lives on local external storage. Returns null otherwise — including
     * on API < 30 legacy-storage devices where this simply isn't needed
     * because [UriToPath] itself skips the check — signaling every caller
     * to fall back to the SAF (ContentResolver) path.
     */
    private fun rawFileFor(uri: Uri): File? = RawFileResolver.getRawFileFromUri(activity, uri)
    // countEntries/countBytes below are the shared tree-walk shape behind
    // both the SAF (DocumentFile) and raw-file (File) counting variants --
    // the two representations don't share a supertype in the Android SDK,
    // so this is generic over T with three lambdas rather than an interface.
    // Each pair below (Recursive/Raw) is now a one-line adapter instead of a
    // duplicated recursive walk.
    private fun <T> countEntries(node: T, isDirectory: (T) -> Boolean, children: (T) -> List<T>): Int {
        if (!isDirectory(node)) return 1
        var count = 0
        for (child in children(node)) count += countEntries(child, isDirectory, children)
        return count
    }

    private fun <T> countBytes(node: T, isDirectory: (T) -> Boolean, children: (T) -> List<T>, length: (T) -> Long): Long {
        if (!isDirectory(node)) return length(node)
        var bytes = 0L
        for (child in children(node)) bytes += countBytes(child, isDirectory, children, length)
        return bytes
    }

    private fun countEntriesRecursive(srcDoc: DocumentFile): Int =
        countEntries(srcDoc, { it.isDirectory }, { it.listFiles().toList() })

    private fun countBytesRecursive(srcDoc: DocumentFile): Long =
        countBytes(srcDoc, { it.isDirectory }, { it.listFiles().toList() }, { it.length() })

    // ── Raw-file fast path (All Files Access) ──────────────────────────────
    // Mirrors the two functions above but walks java.io.File directly —
    // no Binder/ContentResolver round trip per node — for the common case
    // of importing from local external storage with MANAGE_EXTERNAL_STORAGE
    // granted. Falls back to the SAF versions per-item wherever it isn't.

    private fun countEntriesRaw(file: File): Int =
        countEntries(file, { it.isDirectory }, { (it.listFiles() ?: emptyArray()).toList() })

    private fun countBytesRaw(file: File): Long =
        countBytes(file, { it.isDirectory }, { (it.listFiles() ?: emptyArray()).toList() }, { it.length() })

    private class ProgressInputStream(
        private val delegate: InputStream,
        private val opId: Int,
        private val doneCounter: java.util.concurrent.atomic.AtomicInteger,
        private val totalFiles: Int,
        private val currentName: String,
        private val transferredCounter: java.util.concurrent.atomic.AtomicLong,
        private val totalBytes: Long,
    ) : InputStream() {

        override fun read(): Int {
            if (ImportCancellation.isCancelled(opId)) {
                throw ImportCancelledException("Import cancelled")
            }
            val b = delegate.read()
            if (b != -1) {
                val transferred = transferredCounter.incrementAndGet()
                ImportProgressBridge.reportProgress(
                    opId, doneCounter.get(), totalFiles, currentName, transferred, totalBytes
                )
            }
            return b
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (ImportCancellation.isCancelled(opId)) {
                throw ImportCancelledException("Import cancelled")
            }
            val n = delegate.read(b, off, len)
            if (n > 0) {
                val transferred = transferredCounter.addAndGet(n.toLong())
                ImportProgressBridge.reportProgress(
                    opId, doneCounter.get(), totalFiles, currentName, transferred, totalBytes
                )
            }
            return n
        }

        override fun close() = delegate.close()
        override fun available(): Int = delegate.available()
        override fun skip(n: Long): Long = delegate.skip(n)
        override fun markSupported(): Boolean = delegate.markSupported()
        override fun mark(readlimit: Int) = delegate.mark(readlimit)
        override fun reset() = delegate.reset()
    }

    /**
     * Abstracts the SAF (DocumentFile) vs raw (File) import source. As with
     * ExportDestination, the leaf-write mechanics genuinely differ -- SAF
     * only has a content:// Uri, so the direct-write fast path needs the
     * /proc/self/fd/<fd> trick to hand native code something that looks
     * like a real path, whereas a raw source already has one, and only SAF
     * falls back to a stream-based import if that fails -- but the
     * cancellation check, name validation, directory walk, and recursion
     * around that write were previously duplicated wholesale across
     * importEntryRecursive/importEntryRecursiveRaw. This carries only that
     * duplicated control flow; each leaf-write body below is unchanged from
     * its original function.
     */
    private sealed class ImportSource {
        abstract val name: String
        abstract val isDirectory: Boolean
        abstract val lastModifiedSeconds: Long
        abstract fun children(): List<ImportSource>
        abstract fun writeLeaf(
            volId: Int, targetFatPath: String, opId: Int, total: Int,
            doneCounter: java.util.concurrent.atomic.AtomicInteger, totalBytes: Long,
            transferredCounter: java.util.concurrent.atomic.AtomicLong?,
        ): Boolean

        class Saf(private val activity: Activity, private val doc: DocumentFile) : ImportSource() {
            override val name: String get() = doc.name ?: ""
            override val isDirectory: Boolean get() = doc.isDirectory
            override val lastModifiedSeconds: Long get() = doc.lastModified() / 1000L

            // A child with a null name is skipped entirely here (matches the
            // original loop's `child.name ?: continue`), not surfaced with a
            // fallback empty name -- that fallback is only for the current
            // node's own logging/progress calls in writeLeaf below.
            override fun children(): List<ImportSource> =
                doc.listFiles().mapNotNull { child -> if (child.name == null) null else Saf(activity, child) }

            override fun writeLeaf(
                volId: Int, targetFatPath: String, opId: Int, total: Int,
                doneCounter: java.util.concurrent.atomic.AtomicInteger, totalBytes: Long,
                transferredCounter: java.util.concurrent.atomic.AtomicLong?,
            ): Boolean {
                val isFolderVault = VaultBackendRegistry.get(volId) != null
                return if (isFolderVault) {
                    val rawStream = activity.contentResolver.openInputStream(doc.uri)
                        ?: throw java.io.IOException("Failed to open input stream for: ${doc.name}")
                    val progressStream = if (transferredCounter != null) {
                        ProgressInputStream(
                            rawStream, opId, doneCounter, total, doc.name ?: "",
                            transferredCounter, totalBytes
                        )
                    } else {
                        rawStream
                    }
                    progressStream.use { inp ->
                        ContainerFileSystem.importStream(volId, targetFatPath, inp)
                    }
                } else {
                    var wroteDirectly = false
                    var pfd: android.os.ParcelFileDescriptor? = null
                    try {
                        pfd = activity.contentResolver.openFileDescriptor(doc.uri, "r")
                        if (pfd != null) {
                            val fdPath = "/proc/self/fd/${pfd.fd}"
                            // Same fix as the raw-path import below: without opId/
                            // beginFileChunks this was one silent blocking native
                            // call with no progress signal until it returned.
                            if (transferredCounter != null) {
                                ImportProgressBridge.reportProgress(
                                    opId, doneCounter.get(), total, doc.name ?: "",
                                    transferredCounter.get(), totalBytes
                                )
                                ImportProgressBridge.beginFileChunks(opId, transferredCounter.get())
                            }
                            wroteDirectly = ContainerFileSystem.writeBackFile(volId, targetFatPath, fdPath, opId)
                            if (wroteDirectly) {
                                val transferred = transferredCounter?.addAndGet(doc.length()) ?: 0L
                                val done = doneCounter.incrementAndGet()
                                ImportProgressBridge.reportProgress(
                                    opId, done, total, doc.name ?: "",
                                    transferred, totalBytes
                                )
                            }
                        }
                    } catch (e: Exception) {
                        wroteDirectly = false
                    } finally {
                        try { pfd?.close() } catch (e: Exception) {}
                    }

                    if (wroteDirectly) {
                        true
                    } else {
                        val rawStream = activity.contentResolver.openInputStream(doc.uri)
                            ?: throw java.io.IOException("Failed to open input stream for: ${doc.name}")
                        val progressStream = if (transferredCounter != null) {
                            ProgressInputStream(
                                rawStream, opId, doneCounter, total, doc.name ?: "",
                                transferredCounter, totalBytes
                            )
                        } else {
                            rawStream
                        }
                        progressStream.use { inp ->
                            ContainerEngine.importStream(targetFatPath, inp, volId)
                        }
                    }
                }
            }
        }

        class Raw(private val file: File) : ImportSource() {
            override val name: String get() = file.name
            override val isDirectory: Boolean get() = file.isDirectory
            override val lastModifiedSeconds: Long get() = file.lastModified() / 1000L
            override fun children(): List<ImportSource> = (file.listFiles() ?: emptyArray()).map { Raw(it) }

            override fun writeLeaf(
                volId: Int, targetFatPath: String, opId: Int, total: Int,
                doneCounter: java.util.concurrent.atomic.AtomicInteger, totalBytes: Long,
                transferredCounter: java.util.concurrent.atomic.AtomicLong?,
            ): Boolean {
                // Every call site always supplies a real counter for the raw
                // path (unlike SAF's optional one) -- this was a non-null
                // constructor parameter before the two writeLeaf signatures
                // were unified; !! preserves that as a loud failure instead
                // of silently starting a fresh counter if that ever changes.
                val counter = transferredCounter!!
                val isFolderVault = VaultBackendRegistry.get(volId) != null
                return if (isFolderVault) {
                    val progressStream = ProgressInputStream(
                        FileInputStream(file), opId, doneCounter, total, file.name,
                        counter, totalBytes
                    )
                    progressStream.use { inp ->
                        ContainerFileSystem.importStream(volId, targetFatPath, inp)
                    }
                } else {
                    // Establish context (done/total/currentName/totalBytes) for
                    // reportChunk() before the blocking native call starts, and
                    // give it the byte baseline (everything transferred by
                    // previous entries) to build on -- see
                    // ImportProgressBridge.beginFileChunks. Without this,
                    // writeBackFile ran as one silent blocking call and the
                    // progress UI sat on a spinner for the file's entire transfer.
                    ImportProgressBridge.reportProgress(
                        opId, doneCounter.get(), total, file.name,
                        counter.get(), totalBytes
                    )
                    ImportProgressBridge.beginFileChunks(opId, counter.get())
                    val success = ContainerFileSystem.writeBackFile(volId, targetFatPath, file.absolutePath, opId)
                    if (success) {
                        val transferred = counter.addAndGet(file.length())
                        val done = doneCounter.incrementAndGet()
                        ImportProgressBridge.reportProgress(
                            opId, done, total, file.name,
                            transferred, totalBytes
                        )
                    }
                    success
                }
            }
        }
    }

    private fun importEntryRecursive(
        src: ImportSource, targetFatPath: String, volId: Int,
        opId: Int, total: Int, doneCounter: java.util.concurrent.atomic.AtomicInteger,
        totalBytes: Long = 0L, transferredCounter: java.util.concurrent.atomic.AtomicLong? = null,
    ): Int {
        if (ImportCancellation.isCancelled(opId)) {
            throw ImportCancelledException("Import cancelled")
        }
        if (src.isDirectory) {
            val ok = ContainerFileSystem.createDirectory(volId, targetFatPath)
            if (!ok) {
                throw java.io.IOException("Failed to create directory: $targetFatPath. Storage might be full or write-protected.")
            }
            val lastModified = src.lastModifiedSeconds
            if (lastModified > 0) {
                ContainerFileSystem.setLastModifiedTime(volId, targetFatPath, lastModified)
            }
            var count = 0
            val fsKind = FilesystemNameValidator.kindFor(volId)
            for (child in src.children()) {
                val childName = child.name
                val issues = FilesystemNameValidator.validate(childName, fsKind)
                if (issues.isNotEmpty()) {
                    ImportProgressBridge.reportSkippedInvalidName(opId, childName, issues)
                    continue
                }
                count += importEntryRecursive(
                    child, "$targetFatPath/$childName", volId,
                    opId, total, doneCounter, totalBytes, transferredCounter,
                )
            }
            return count
        }

        val ok = src.writeLeaf(volId, targetFatPath, opId, total, doneCounter, totalBytes, transferredCounter)
        if (!ok) {
            throw java.io.IOException("Failed to write file to container: $targetFatPath. Storage might be full.")
        }
        val lastModified = src.lastModifiedSeconds
        if (lastModified > 0) {
            ContainerFileSystem.setLastModifiedTime(volId, targetFatPath, lastModified)
        }
        return 1
    }

    /**
     * Shared core of [handlePickImportFiles]'s phase 1 (registers picked
     * [uris] under a fresh pickToken in [pickedFilesByToken] and reports
     * back the `{pickToken, conflicts, items}` shape [handleImportFile]
     * (phase 2, unchanged either way) expects) and
     * [handlePrepareShareImport]'s equivalent for an incoming share-sheet
     * request: the two differ only in *where* [uris] came from -- a system
     * picker's [ActivityResult] here, [IncomingShareBridge]'s buffer there
     * -- and nothing past that point cares which. Must be called off the
     * main thread (does ContentResolver/DocumentFile IO plus
     * [ContainerFileSystem.listDirectory] calls); callers already run this
     * on [ioExecutor].
     *
     * Returns `null` if none of [uris] resolved to a usable entry (mirrors
     * [handlePickImportFiles]'s `uris.isNotEmpty()` guard, just evaluated
     * after resolution instead of before it, since a share-sheet URI can
     * fail to resolve in a way a freshly-returned SAF pick result rarely
     * does).
     */
    private fun buildPickedImportFiles(
        uris: List<Uri>, containerUri: String, targetDir: String, volId: Int,
    ): Map<String, Any?>? {
        val entries = uris.mapNotNull { uri ->
            val doc = DocumentFile.fromSingleUri(activity, uri) ?: return@mapNotNull null
            val raw = rawFileFor(uri)
            val name = raw?.name ?: doc.name ?: return@mapNotNull null
            VeLog.d("VaultExplorer_Import") {
                if (raw != null) {
                    "IMPORT_SOURCE_PATH name=$name path=RAW file=${raw.absolutePath}"
                } else {
                    "IMPORT_SOURCE_PATH name=$name path=SAF uri=$uri " +
                        "(RawFileResolver/UriToPath found no local file for this source)"
                }
            }
            PickedFileEntry(doc, raw, name)
        }
        if (entries.isEmpty()) return null

        val token = nextPickToken.getAndIncrement()
        pickedFilesByToken[token] = PickedImportFiles(containerUri, targetDir, volId, entries)
        // Invalid names are excluded here (they'll never be written, so
        // there's no point asking about a conflict for one) but stay in
        // `entries` -- the actual validate-and-skip-and-report step still
        // happens in handleImportFile once a real opId exists to report
        // against.
        val fsKind = FilesystemNameValidator.kindFor(volId)
        val existingNames = existingNamesLowercase(volId, targetDir)
        val existingDirs = existingDirsLowercase(volId, targetDir)
        val conflicts = entries.mapNotNull {
            if (FilesystemNameValidator.validate(it.name, fsKind).isEmpty() &&
                existingNames.contains(it.name.lowercase())
            ) {
                val destIsDir = existingDirs.contains(it.name.lowercase())
                mapOf("name" to it.name, "destIsDir" to destIsDir)
            } else {
                null
            }
        }
        val items = entries.map {
            mapOf(
                "name" to it.name,
                "isDir" to (it.raw?.isDirectory ?: it.doc.isDirectory),
                "sizeBytes" to (it.raw?.length() ?: it.doc.length()),
            )
        }
        return mapOf("pickToken" to token, "conflicts" to conflicts, "items" to items)
    }

    private val pickImportFilesLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val pending = pendingPickFiles
        pendingPickFiles = null
        val data = activityResult.data

        if (activityResult.resultCode == Activity.RESULT_OK && data != null && pending != null) {
            val uris = mutableListOf<Uri>()
            data.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
                ?: data.data?.let { uris.add(it) }
            if (uris.isNotEmpty()) {
                ioExecutor.execute {
                    try {
                        val response = buildPickedImportFiles(
                            uris, pending.containerUri, pending.targetDir, pending.volId,
                        )
                        activity.runOnUiThread { res.success(response) }
                    } catch (e: Exception) {
                        activity.runOnUiThread { nativeOps.dispatchNativeError(e, res) }
                    }
                }
            } else {
                res.success(null)
            }
        } else {
            res.success(null)
        }
    }

    private val exportFilesFolderLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val pending = pendingExportMulti
        pendingExportMulti = null
        val data = activityResult.data

        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null && pending != null) {
            val treeUri = data.data!!
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            val opId = pending.opId
            ioExecutor.execute {
                val opStart = System.currentTimeMillis()
                try {
                    var successCount = 0
                    val validItems = pending.items.mapNotNull { item ->
                        val path = item["path"] as? String ?: return@mapNotNull null
                        val isDir = item["isDir"] as? Boolean ?: false
                        Pair(path, isDir)
                    }
                    val total = validItems.sumOf { (path, isDir) -> countContainerEntriesRecursive(pending.volId, path, isDir) }
                    val totalBytes = validItems.sumOf { (path, isDir) -> countContainerBytes(pending.volId, path, isDir) }
                    VeLog.i("VaultExplorer_Export") {
                        "EXPORT_FILES start opId=$opId volId=${pending.volId} items=${validItems.size} entries=$total bytes=$totalBytes"
                    }
                    val doneCounter = java.util.concurrent.atomic.AtomicInteger(0)
                    val transferredCounter = java.util.concurrent.atomic.AtomicLong(0L)
                    if (opId > 0) {
                        ExportProgressBridge.begin(opId)
                        ExportProgressBridge.reportProgress(opId, 0, total, "", 0L, totalBytes)
                    }
                    try {
                        val rawDestTree = rawFileFor(treeUri)
                        for ((path, isDir) in validItems) {
                            val name = path.substringAfterLast("/")
                            val dest = if (rawDestTree != null) {
                                ExportDestination.Raw(rawDestTree)
                            } else {
                                val destTree = DocumentFile.fromTreeUri(activity, treeUri) ?: continue
                                ExportDestination.Saf(activity, destTree)
                            }
                            val count = exportEntryRecursive(
                                dest, path, isDir, pending.volId,
                                opId, total, doneCounter, totalBytes, transferredCounter,
                            )
                            successCount += count
                            if (opId > 0) {
                                ExportProgressBridge.reportItemFinished(opId, name, isDir, count > 0)
                            }
                        }
                    } finally {
                        if (opId > 0) {
                            ExportCancellation.clear(opId)
                            ExportProgressBridge.clear(opId)
                        }
                    }
                    VeLog.i("VaultExplorer_Export") {
                        "EXPORT_FILES done opId=$opId successCount=$successCount totalMs=${System.currentTimeMillis() - opStart}"
                    }
                    activity.runOnUiThread { res.success(successCount) }
                } catch (e: Exception) {
                    activity.runOnUiThread { nativeOps.dispatchNativeError(e, res) }
                }
            }
        } else {
            if (pending != null && pending.opId > 0) {
                ExportCancellation.clear(pending.opId)
                ExportProgressBridge.clear(pending.opId)
            }
            res.success(0)
        }
    }

    private val pickImportFolderLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val pending = pendingPickFolder
        pendingPickFolder = null
        val data = activityResult.data

        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null && pending != null) {
            val treeUri = data.data!!
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            val srcRoot = DocumentFile.fromTreeUri(activity, treeUri)
            if (srcRoot != null) {
                val rawRoot = rawFileFor(treeUri)
                VeLog.d("VaultExplorer_Import") {
                    if (rawRoot != null) {
                        "IMPORT_SOURCE_PATH name=${rawRoot.name} path=RAW file=${rawRoot.absolutePath}"
                    } else {
                        "IMPORT_SOURCE_PATH name=${srcRoot.name} path=SAF uri=$treeUri " +
                            "(RawFileResolver/UriToPath found no local file for this source)"
                    }
                }
                val folderName = rawRoot?.name ?: srcRoot.name ?: "imported_folder"
                val token = nextPickToken.getAndIncrement()
                pickedFolderByToken[token] = PickedImportFolder(
                    pending.containerUri, pending.targetDir, pending.volId,
                    treeUri, srcRoot, rawRoot, folderName,
                )
                // Same reasoning as pickImportFilesLauncher: an invalid
                // name is excluded from the conflict list (it's getting
                // skipped either way) but handleImportFolder still does
                // the real validate-and-skip-and-report once it has a
                // real opId.
                val fsKind = FilesystemNameValidator.kindFor(pending.volId)
                val conflicts = if (FilesystemNameValidator.validate(folderName, fsKind).isEmpty() &&
                    existingNamesLowercase(pending.volId, pending.targetDir).contains(folderName.lowercase())
                ) {
                    val destIsDir = existingDirsLowercase(pending.volId, pending.targetDir)
                        .contains(folderName.lowercase())
                    listOf(mapOf("name" to folderName, "destIsDir" to destIsDir))
                } else {
                    emptyList()
                }
                val items = listOf(
                    mapOf(
                        "name" to folderName,
                        "isDir" to true,
                        "sizeBytes" to 0L,
                    )
                )
                res.success(mapOf("pickToken" to token, "conflicts" to conflicts, "items" to items))
            } else {
                res.success(null)
            }
        } else {
            res.success(null)
        }
    }

    private val exportFileLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val pending = pendingExportFile
        pendingExportFile = null
        val data = activityResult.data

        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null && pending != null) {
            val destUri = data.data!!
            ioExecutor.execute {
                try {
                    val rawDest = rawFileFor(destUri)
                    if (rawDest != null) {
                        val ok = ContainerFileSystem.extractToFile(pending.volId, pending.sourcePath, rawDest.absolutePath)
                        activity.runOnUiThread { res.success(ok && rawDest.exists()) }
                    } else {
                        val tempFile = File(activity.cacheDir, "export_${System.nanoTime()}")
                        try {
                            val ok = ContainerFileSystem.extractToFile(pending.volId, pending.sourcePath, tempFile.absolutePath)

                            if (ok && tempFile.exists()) {
                                activity.contentResolver.openOutputStream(destUri)?.use { out ->
                                    tempFile.inputStream().use { it.copyTo(out) }
                                }
                                activity.runOnUiThread { res.success(true) }
                            } else {
                                activity.runOnUiThread { res.success(false) }
                            }
                        } finally {
                            SecureFileWipe.secureDeleteFile(tempFile)
                        }
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread { nativeOps.dispatchNativeError(e, res) }
                }
            }
        } else {
            res.success(false)
        }
    }

    fun handleCancelImport(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId == null) {
            result.error("INVALID_ARGS", "opId required", null)
            return
        }
        ImportCancellation.cancel(opId)
        result.success(true)
    }

    /**
     * Deletes the original device-storage document(s) picked during the
     * import identified by [opId] (single/multi files, or the one tree Uri
     * for a folder import). Best-effort per item; returns the count deleted.
     */
    fun handleDeleteImportSources(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId == null) {
            result.error("INVALID_ARGS", "opId required", null)
            return
        }
        val recorded = ImportSourceRegistry.take(opId)
        if (recorded == null) {
            result.success(0)
            return
        }
        val (uris, isTree) = recorded
        ioExecutor.execute {
            var deleted = 0
            for (uri in uris) {
                try {
                    val doc = if (isTree) DocumentFile.fromTreeUri(activity, uri)
                              else DocumentFile.fromSingleUri(activity, uri)
                    if (doc != null && doc.delete()) deleted++
                } catch (_: Exception) {
                    // Best-effort — skip and keep going.
                }
            }
            activity.runOnUiThread { result.success(deleted) }
        }
    }

    /**
     * Phase 1 of importing files: launches the system multi-file picker
     * and reports back which picked names collide with [targetPath] --
     * nothing is written yet. Follow up with [handleImportFile], passing
     * the returned pickToken and a resolution for every conflict.
     */
    fun handlePickImportFiles(call: MethodCall, result: MethodChannel.Result) {
        val containerUriArg = call.argument<String>("filePath")
        if (isMissingContainerUri(containerUriArg)) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val containerUri = containerUriArg!!
        val volId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container is not mounted", null)
            return
        }
        pendingPickFiles = PendingPickFiles(containerUri, call.argument<String>("targetPath") ?: "", volId)
        pendingResult.stash(result)
        pickImportFilesLauncher.launch(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        })
    }

    /**
     * Share-sheet counterpart to [handlePickImportFiles]: the URIs already
     * arrived via ACTION_SEND/ACTION_SEND_MULTIPLE and are sitting in
     * [IncomingShareBridge]'s buffer (see
     * [com.aeidolon.vaultexplorer.handlers.ShareIntentHandlers.handleIncomingIntent]),
     * so there's no system picker to launch here -- just registers them
     * against [volId]/`targetPath` via [buildPickedImportFiles] and reports
     * back the same `{pickToken, conflicts, items}` shape. Follow up with
     * the existing [handleImportFile], exactly as the picker flow does;
     * that method needed no changes at all to support this second source
     * of picked files.
     *
     * Clears [IncomingShareBridge]'s buffer on success, since the URIs it
     * held are now owned by [pickedFilesByToken] under `token` instead --
     * see [IncomingShareBridge.takePendingUris]'s doc comment. Replies
     * `null` (not an error) if nothing is pending, e.g. the person
     * backgrounded the app and the share was cancelled/superseded in the
     * meantime; the Dart-side destination-picker flow treats that as "stop
     * here" the same way a `null` [handlePickImportFiles] response does.
     */
    fun handlePrepareShareImport(call: MethodCall, result: MethodChannel.Result) {
        val containerUriArg = call.argument<String>("filePath")
        if (isMissingContainerUri(containerUriArg)) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val containerUri = containerUriArg!!
        val volId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container is not mounted", null)
            return
        }
        val targetDir = call.argument<String>("targetPath") ?: ""
        val uris = IncomingShareBridge.takePendingUris()
        if (uris.isNullOrEmpty()) {
            result.success(null)
            return
        }
        ioExecutor.execute {
            try {
                val response = buildPickedImportFiles(uris, containerUri, targetDir, volId)
                activity.runOnUiThread { result.success(response) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    /**
     * Phase 2: copies the files an earlier [handlePickImportFiles] call
     * picked (identified by `pickToken`, removed from [pickedFilesByToken]
     * on use) into their target directory, applying `conflictPlan`
     * (lowercased picked name -> "skip" / "overwrite" / "keepBoth") via
     * [resolveImportName] for any name that collided at pick time. Doesn't
     * launch anything itself, so unlike [handlePickImportFiles] it never
     * stashes [pendingResult].
     */
    fun handleImportFile(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt() ?: 0
        val pickToken = call.argument<Number>("pickToken")?.toInt()
        val picked = pickToken?.let { pickedFilesByToken.remove(it) }
        if (picked == null) {
            result.error("INVALID_ARGS", "pickToken is required and must reference a pending pick", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val conflictPlan: Map<String, String> = (call.argument<Map<*, *>>("conflictPlan"))
            ?.mapNotNull { (k, v) -> (k as? String)?.let { key -> (v as? String)?.let { value -> key to value } } }
            ?.toMap() ?: emptyMap()

        val uris = picked.entries.map { it.doc.uri }
        if (uris.isNotEmpty()) {
            ImportSourceRegistry.recordFiles(opId, uris)
        }
        
        if (opId > 0) {
            ImportProgressBridge.begin(opId)
        }

        ioExecutor.execute {
            val opStart = System.currentTimeMillis()
            try {
                val total = picked.entries.sumOf { e -> e.raw?.let { countEntriesRaw(it) } ?: countEntriesRecursive(e.doc) }
                val totalBytes = picked.entries.sumOf { e -> e.raw?.let { countBytesRaw(it) } ?: countBytesRecursive(e.doc) }
                VeLog.i("VaultExplorer_Import") {
                    "IMPORT_FILES start opId=$opId volId=${picked.volId} " +
                        "sources=${picked.entries.size} (raw=${picked.entries.count { it.raw != null }}, " +
                        "saf=${picked.entries.count { it.raw == null }}) entries=$total bytes=$totalBytes"
                }
                if (rejectIfInsufficientSpace(picked.volId, totalBytes, opId, "VaultExplorer_Import", result)) {
                    return@execute
                }
                val doneCounter = java.util.concurrent.atomic.AtomicInteger(0)
                val transferredCounter = java.util.concurrent.atomic.AtomicLong(0L)
                var successCount = 0
                val fsKind = FilesystemNameValidator.kindFor(picked.volId)
                ContainerFileSystem.beginBatchWrite(picked.volId)
                try {
                    for (entry in picked.entries) {
                        val isDir = entry.raw?.isDirectory ?: entry.doc.isDirectory
                        val issues = FilesystemNameValidator.validate(entry.name, fsKind)
                        if (issues.isNotEmpty()) {
                            ImportProgressBridge.reportSkippedInvalidName(opId, entry.name, issues)
                            ImportProgressBridge.reportItemFinished(
                                opId = opId,
                                sourceName = entry.name,
                                resolvedName = entry.name,
                                isDir = isDir,
                                success = false,
                            )
                            continue
                        }
                        val name = resolveImportName(picked.volId, picked.targetDir, entry.name, conflictPlan)
                        if (name == null) {
                            ImportProgressBridge.reportItemFinished(
                                opId = opId,
                                sourceName = entry.name,
                                resolvedName = entry.name,
                                isDir = isDir,
                                success = false,
                            )
                            continue
                        }
                        val targetFatPath = if (picked.targetDir.isEmpty()) name else "${picked.targetDir}/$name"
                        val src = if (entry.raw != null) {
                            ImportSource.Raw(entry.raw)
                        } else {
                            ImportSource.Saf(activity, entry.doc)
                        }
                        val count = importEntryRecursive(
                            src, targetFatPath, picked.volId,
                            opId, total, doneCounter, totalBytes, transferredCounter,
                        )
                        successCount += count
                        ImportProgressBridge.reportItemFinished(
                            opId = opId,
                            sourceName = entry.name,
                            resolvedName = name,
                            isDir = isDir,
                            success = count > 0,
                        )
                    }
                } finally {
                    val commitStart = System.currentTimeMillis()
                    ContainerFileSystem.endBatchWrite(picked.volId)
                    VeLog.i("VaultExplorer_Import") {
                        "IMPORT_FILES endBatchWrite opId=$opId tookMs=${System.currentTimeMillis() - commitStart}"
                    }
                }
                VeLog.i("VaultExplorer_Import") {
                    "IMPORT_FILES done opId=$opId successCount=$successCount totalMs=${System.currentTimeMillis() - opStart}"
                }
                activity.runOnUiThread { result.success(successCount) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                ImportCancellation.clear(opId)
                ImportProgressBridge.clear(opId)
            }
        }
    }

    fun handleExportFilesFolder(call: MethodCall, result: MethodChannel.Result) {
        val containerUriArg = call.argument<String>("filePath")
        if (isMissingContainerUri(containerUriArg)) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val containerUri = containerUriArg!!
        val volId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container is not mounted", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val items = (call.argument<List<*>>("items"))?.mapNotNull { it as? Map<String, Any?> } ?: emptyList()
        val opId = call.argument<Number>("opId")?.toInt() ?: 0
        pendingExportMulti = PendingExportMulti(containerUri, items, volId, opId)
        pendingResult.stash(result)
        exportFilesFolderLauncher.launch(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE))
    }

    /** Mirrors [handleCancelImport]: marks opId cancelled so the export
     *  loop notices between entries (see [ExportCancellation]) and stops. */
    fun handleCancelExport(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId == null) {
            result.error("INVALID_ARGS", "opId is required", null)
            return
        }
        ExportCancellation.cancel(opId)
        result.success(null)
    }

    /**
     * Phase 1 of importing a folder: launches the system tree picker and
     * reports back whether the picked folder's own name collides with
     * [targetPath] -- nothing is written yet. Follow up with
     * [handleImportFolder], passing the returned pickToken and a
     * resolution if there was a conflict.
     */
    fun handlePickImportFolder(call: MethodCall, result: MethodChannel.Result) {
        val containerUriArg = call.argument<String>("filePath")
        if (isMissingContainerUri(containerUriArg)) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val containerUri = containerUriArg!!
        val volId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container is not mounted", null)
            return
        }
        pendingPickFolder = PendingPickFolder(containerUri, call.argument<String>("targetPath") ?: "", volId)
        pendingResult.stash(result)
        pickImportFolderLauncher.launch(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE))
    }

    /**
     * Phase 2: copies the folder an earlier [handlePickImportFolder] call
     * picked (identified by `pickToken`, removed from [pickedFolderByToken]
     * on use) into its target directory, applying `conflictPlan` (at most
     * one entry, for the folder's own lowercased name) via
     * [resolveImportName]. Doesn't launch anything itself, so unlike
     * [handlePickImportFolder] it never stashes [pendingResult].
     */
    fun handleImportFolder(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt() ?: 0
        val pickToken = call.argument<Number>("pickToken")?.toInt()
        val picked = pickToken?.let { pickedFolderByToken.remove(it) }
        if (picked == null) {
            result.error("INVALID_ARGS", "pickToken is required and must reference a pending pick", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val conflictPlan: Map<String, String> = (call.argument<Map<*, *>>("conflictPlan"))
            ?.mapNotNull { (k, v) -> (k as? String)?.let { key -> (v as? String)?.let { value -> key to value } } }
            ?.toMap() ?: emptyMap()

        ImportSourceRegistry.recordFolder(opId, picked.treeUri)
        
        if (opId > 0) {
            ImportProgressBridge.begin(opId)
        }

        ioExecutor.execute {
            val opStart = System.currentTimeMillis()
            try {
                val fsKind = FilesystemNameValidator.kindFor(picked.volId)
                val issues = FilesystemNameValidator.validate(picked.folderName, fsKind)
                if (issues.isNotEmpty()) {
                    ImportProgressBridge.reportSkippedInvalidName(opId, picked.folderName, issues)
                    activity.runOnUiThread { result.success(0) }
                    return@execute
                }
                val folderName = resolveImportName(picked.volId, picked.targetDir, picked.folderName, conflictPlan)
                if (folderName == null) {
                    activity.runOnUiThread { result.success(0) }
                    return@execute
                }
                val targetFatPath = if (picked.targetDir.isEmpty()) folderName else "${picked.targetDir}/$folderName"

                val total = picked.rawRoot?.let { countEntriesRaw(it) } ?: countEntriesRecursive(picked.srcRoot)
                val totalBytes = picked.rawRoot?.let { countBytesRaw(it) } ?: countBytesRecursive(picked.srcRoot)
                VeLog.i("VaultExplorer_Import") {
                    "IMPORT_FOLDER start opId=$opId volId=${picked.volId} " +
                        "path=${if (picked.rawRoot != null) "RAW" else "SAF"} entries=$total bytes=$totalBytes"
                }
                if (rejectIfInsufficientSpace(picked.volId, totalBytes, opId, "VaultExplorer_Import", result)) {
                    return@execute
                }
                val doneCounter = java.util.concurrent.atomic.AtomicInteger(0)
                val transferredCounter = java.util.concurrent.atomic.AtomicLong(0L)
                ContainerFileSystem.beginBatchWrite(picked.volId)
                val count = try {
                    val src = if (picked.rawRoot != null) {
                        ImportSource.Raw(picked.rawRoot)
                    } else {
                        ImportSource.Saf(activity, picked.srcRoot)
                    }
                    importEntryRecursive(
                        src, targetFatPath, picked.volId,
                        opId, total, doneCounter, totalBytes, transferredCounter,
                    )
                } finally {
                    val commitStart = System.currentTimeMillis()
                    ContainerFileSystem.endBatchWrite(picked.volId)
                    VeLog.i("VaultExplorer_Import") {
                        "IMPORT_FOLDER endBatchWrite opId=$opId tookMs=${System.currentTimeMillis() - commitStart}"
                    }
                }
                VeLog.i("VaultExplorer_Import") {
                    "IMPORT_FOLDER done opId=$opId count=$count totalMs=${System.currentTimeMillis() - opStart}"
                }
                ImportProgressBridge.reportItemFinished(
                    opId = opId,
                    sourceName = picked.folderName,
                    resolvedName = folderName,
                    isDir = true,
                    success = count > 0,
                )
                activity.runOnUiThread { result.success(count) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                ImportCancellation.clear(opId)
                ImportProgressBridge.clear(opId)
            }
        }
    }

    /**
     * Releases a pick from [handlePickImportFiles]/[handlePickImportFolder]
     * that will never be completed by [handleImportFile]/[handleImportFolder]
     * -- e.g. the person dismissed the conflict-resolution sheet instead of
     * continuing. A pick token is only ever present in one of the two maps,
     * so trying both is harmless. Never launches anything, so -- like
     * [handleImportFile]/[handleImportFolder] -- it never stashes
     * [pendingResult].
     */
    fun handleCancelPickedImport(call: MethodCall, result: MethodChannel.Result) {
        call.argument<Number>("pickToken")?.toInt()?.let { pickToken ->
            pickedFilesByToken.remove(pickToken)
            pickedFolderByToken.remove(pickToken)
        }
        result.success(null)
    }

    fun handleExportFile(call: MethodCall, result: MethodChannel.Result) {
        val containerUriArg = call.argument<String>("filePath")
        val sourcePathArg = call.argument<String>("sourcePath")
        if (isMissingContainerOrSource(containerUriArg, sourcePathArg)) {
            result.error("INVALID_ARGS", "filePath and sourcePath required", null)
            return
        }
        val containerUri = containerUriArg!!
        val sourcePath = sourcePathArg!!
        val volId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container is not mounted", null)
            return
        }
        pendingExportFile = PendingExportFile(containerUri, sourcePath, volId)
        pendingResult.stash(result)
        val fileName = sourcePath.split("/").last()
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = MimeTypeHelper.getMimeType(fileName)
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        exportFileLauncher.launch(intent)
    }
}