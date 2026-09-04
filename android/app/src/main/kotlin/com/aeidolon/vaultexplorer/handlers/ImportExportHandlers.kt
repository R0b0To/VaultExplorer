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
     * A 5% margin is reserved past the raw byte count -- mirrors
     * `FileOperationService._run`'s upfront check on the Dart side (used
     * for intra-vault copy/paste), which applies the same margin for the
     * same reason: container/filesystem overhead (FAT metadata, cluster
     * rounding, per-file headers) means a transfer sized to exactly fill
     * "available" can still legitimately come up short.
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
        if (totalBytes <= (available * 0.95).toLong()) return false
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
    private fun exportEntryRecursive(
        destParent: DocumentFile, fatPath: String, isDir: Boolean,
        containerUri: String, volId: Int,
        opId: Int = 0, total: Int = 0, doneCounter: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(0),
        totalBytes: Long = 0L, transferredCounter: java.util.concurrent.atomic.AtomicLong = java.util.concurrent.atomic.AtomicLong(0L),
    ): Int {
        if (opId > 0 && ExportCancellation.isCancelled(opId)) {
            throw ExportCancelledException("Export cancelled")
        }
        val name = fatPath.substringAfterLast("/")
        if (!isDir) {
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
                    destParent.findFile(name)?.delete()
                    val outDoc = destParent.createFile(MimeTypeHelper.getMimeType(name), name)
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
        val destDir = destParent.createDirectory(name) ?: return 0
        val children = ContainerFileSystem.listDirectory(volId, fatPath) ?: return 0
        var count = 0
        for (entry in children) {
            if (entry.startsWith("System:")) continue
            val parsed = DirEntryWire.parse(entry) ?: continue
            count += exportEntryRecursive(
                destDir, "$fatPath/${parsed.name}", parsed.isDir, containerUri, volId,
                opId, total, doneCounter, totalBytes, transferredCounter,
            )
        }
        return count
    }

    /**
     * Raw-file counterpart of [exportEntryRecursive]. Since decryption
     * already goes through [ContainerFileSystem.extractToFile] (native
     * writes straight to a destination path), a raw destination lets us
     * decrypt directly into the final location — no cache temp file, no
     * SAF create/open round trip per item.
     */
    private fun exportEntryRecursiveRaw(
        destParent: File, fatPath: String, isDir: Boolean, volId: Int,
        opId: Int = 0, total: Int = 0, doneCounter: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(0),
        totalBytes: Long = 0L, transferredCounter: java.util.concurrent.atomic.AtomicLong = java.util.concurrent.atomic.AtomicLong(0L),
    ): Int {
        if (opId > 0 && ExportCancellation.isCancelled(opId)) {
            throw ExportCancelledException("Export cancelled")
        }
        val name = fatPath.substringAfterLast("/")
        if (!isDir) {
            if (opId > 0) {
                ExportProgressBridge.reportProgress(opId, doneCounter.get(), total, name, transferredCounter.get(), totalBytes)
                ExportProgressBridge.beginFileChunks(opId, transferredCounter.get())
            }
            return try {
                val target = File(destParent, name)
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
        val destDir = File(destParent, name)
        if (!destDir.exists() && !destDir.mkdirs()) return 0
        val children = ContainerFileSystem.listDirectory(volId, fatPath) ?: return 0
        var count = 0
        for (entry in children) {
            if (entry.startsWith("System:")) continue
            val parsed = DirEntryWire.parse(entry) ?: continue
            count += exportEntryRecursiveRaw(
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
    private fun countEntriesRecursive(srcDoc: DocumentFile): Int {
        if (!srcDoc.isDirectory) return 1
        var count = 0
        for (child in srcDoc.listFiles()) {
            count += countEntriesRecursive(child)
        }
        return count
    }

    private fun countBytesRecursive(srcDoc: DocumentFile): Long {
        if (!srcDoc.isDirectory) return srcDoc.length()
        var bytes = 0L
        for (child in srcDoc.listFiles()) {
            bytes += countBytesRecursive(child)
        }
        return bytes
    }

    // ── Raw-file fast path (All Files Access) ──────────────────────────────
    // Mirrors the two functions above but walks java.io.File directly —
    // no Binder/ContentResolver round trip per node — for the common case
    // of importing from local external storage with MANAGE_EXTERNAL_STORAGE
    // granted. Falls back to the SAF versions per-item wherever it isn't.

    private fun countEntriesRaw(file: File): Int {
        if (!file.isDirectory) return 1
        var count = 0
        for (child in file.listFiles() ?: emptyArray()) {
            count += countEntriesRaw(child)
        }
        return count
    }

    private fun countBytesRaw(file: File): Long {
        if (!file.isDirectory) return file.length()
        var bytes = 0L
        for (child in file.listFiles() ?: emptyArray()) {
            bytes += countBytesRaw(child)
        }
        return bytes
    }

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

    private fun importEntryRecursive(
        srcDoc: DocumentFile, containerUri: String, targetFatPath: String, volId: Int,
        opId: Int, total: Int, doneCounter: java.util.concurrent.atomic.AtomicInteger,
        totalBytes: Long = 0L, transferredCounter: java.util.concurrent.atomic.AtomicLong? = null,
    ): Int {
        if (ImportCancellation.isCancelled(opId)) {
            throw ImportCancelledException("Import cancelled")
        }
        if (srcDoc.isDirectory) {
            val ok = ContainerFileSystem.createDirectory(volId, targetFatPath)
            if (!ok) {
                throw java.io.IOException("Failed to create directory: $targetFatPath. Storage might be full or write-protected.")
            }
            val lastModified = srcDoc.lastModified() / 1000L
            if (lastModified > 0) {
                ContainerFileSystem.setLastModifiedTime(volId, targetFatPath, lastModified)
            }
            var count = 0
            val fsKind = FilesystemNameValidator.kindFor(volId)
            for (child in srcDoc.listFiles()) {
                val childName = child.name ?: continue
                val issues = FilesystemNameValidator.validate(childName, fsKind)
                if (issues.isNotEmpty()) {
                    ImportProgressBridge.reportSkippedInvalidName(opId, childName, issues)
                    continue
                }
                count += importEntryRecursive(
                    child, containerUri, "$targetFatPath/$childName", volId,
                    opId, total, doneCounter, totalBytes, transferredCounter,
                )
            }
            return count
        }

        val isFolderVault = VaultBackendRegistry.get(volId) != null
        val ok: Boolean = if (isFolderVault) {
            val rawStream = activity.contentResolver.openInputStream(srcDoc.uri)
                ?: throw java.io.IOException("Failed to open input stream for: ${srcDoc.name}")
            val progressStream = if (transferredCounter != null) {
                ProgressInputStream(
                    rawStream, opId, doneCounter, total, srcDoc.name ?: "",
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
                pfd = activity.contentResolver.openFileDescriptor(srcDoc.uri, "r")
                if (pfd != null) {
                    val fdPath = "/proc/self/fd/${pfd.fd}"
                    // Same fix as the raw-path import below: without opId/
                    // beginFileChunks this was one silent blocking native
                    // call with no progress signal until it returned.
                    if (transferredCounter != null) {
                        ImportProgressBridge.reportProgress(
                            opId, doneCounter.get(), total, srcDoc.name ?: "",
                            transferredCounter.get(), totalBytes
                        )
                        ImportProgressBridge.beginFileChunks(opId, transferredCounter.get())
                    }
                    wroteDirectly = ContainerFileSystem.writeBackFile(volId, targetFatPath, fdPath, opId)
                    if (wroteDirectly) {
                        val transferred = transferredCounter?.addAndGet(srcDoc.length()) ?: 0L
                        val done = doneCounter.incrementAndGet()
                        ImportProgressBridge.reportProgress(
                            opId, done, total, srcDoc.name ?: "",
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
                val rawStream = activity.contentResolver.openInputStream(srcDoc.uri)
                    ?: throw java.io.IOException("Failed to open input stream for: ${srcDoc.name}")
                val progressStream = if (transferredCounter != null) {
                    ProgressInputStream(
                        rawStream, opId, doneCounter, total, srcDoc.name ?: "",
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

        if (!ok) {
            throw java.io.IOException("Failed to write file to container: $targetFatPath. Storage might be full.")
        }
        val lastModified = srcDoc.lastModified() / 1000L
        if (lastModified > 0) {
            ContainerFileSystem.setLastModifiedTime(volId, targetFatPath, lastModified)
        }
        return 1
    }

    /**
     * Raw-file counterpart of [importEntryRecursive]: same behavior, but
     * reads directly from [java.io.File] instead of going through
     * [DocumentFile]/[android.content.ContentResolver]. Used whenever
     * [rawFileFor] can resolve the picked document to a real path.
     */
    private fun importEntryRecursiveRaw(
        srcFile: File, targetFatPath: String, volId: Int,
        opId: Int, total: Int, doneCounter: java.util.concurrent.atomic.AtomicInteger,
        totalBytes: Long, transferredCounter: java.util.concurrent.atomic.AtomicLong,
    ): Int {
        if (ImportCancellation.isCancelled(opId)) {
            throw ImportCancelledException("Import cancelled")
        }
        if (srcFile.isDirectory) {
            val ok = ContainerFileSystem.createDirectory(volId, targetFatPath)
            if (!ok) {
                throw java.io.IOException("Failed to create directory: $targetFatPath. Storage might be full or write-protected.")
            }
            val lastModified = srcFile.lastModified() / 1000L
            if (lastModified > 0) {
                ContainerFileSystem.setLastModifiedTime(volId, targetFatPath, lastModified)
            }
            var count = 0
            val fsKind = FilesystemNameValidator.kindFor(volId)
            for (child in srcFile.listFiles() ?: emptyArray()) {
                val childName = child.name
                val issues = FilesystemNameValidator.validate(childName, fsKind)
                if (issues.isNotEmpty()) {
                    ImportProgressBridge.reportSkippedInvalidName(opId, childName, issues)
                    continue
                }
                count += importEntryRecursiveRaw(
                    child, "$targetFatPath/$childName", volId,
                    opId, total, doneCounter, totalBytes, transferredCounter,
                )
            }
            return count
        }

        val isFolderVault = VaultBackendRegistry.get(volId) != null
        val ok: Boolean = if (isFolderVault) {
            val progressStream = ProgressInputStream(
                FileInputStream(srcFile), opId, doneCounter, total, srcFile.name,
                transferredCounter, totalBytes
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
                opId, doneCounter.get(), total, srcFile.name,
                transferredCounter.get(), totalBytes
            )
            ImportProgressBridge.beginFileChunks(opId, transferredCounter.get())
            val success = ContainerFileSystem.writeBackFile(volId, targetFatPath, srcFile.absolutePath, opId)
            if (success) {
                val transferred = transferredCounter.addAndGet(srcFile.length())
                val done = doneCounter.incrementAndGet()
                ImportProgressBridge.reportProgress(
                    opId, done, total, srcFile.name,
                    transferred, totalBytes
                )
            }
            success
        }

        if (!ok) {
            throw java.io.IOException("Failed to write file to container: $targetFatPath. Storage might be full.")
        }
        val lastModified = srcFile.lastModified() / 1000L
        if (lastModified > 0) {
            ContainerFileSystem.setLastModifiedTime(volId, targetFatPath, lastModified)
        }
        return 1
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
                        val token = nextPickToken.getAndIncrement()
                        pickedFilesByToken[token] = PickedImportFiles(
                            pending.containerUri, pending.targetDir, pending.volId, entries,
                        )
                        // Invalid names are excluded here (they'll never be
                        // written, so there's no point asking about a
                        // conflict for one) but stay in `entries` -- the
                        // actual validate-and-skip-and-report step still
                        // happens in handleImportFile once a real opId
                        // exists to report against.
                        val fsKind = FilesystemNameValidator.kindFor(pending.volId)
                        val existingNames = existingNamesLowercase(pending.volId, pending.targetDir)
                        val existingDirs = existingDirsLowercase(pending.volId, pending.targetDir)
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
                        activity.runOnUiThread {
                            res.success(mapOf("pickToken" to token, "conflicts" to conflicts, "items" to items))
                        }
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
                            val count = if (rawDestTree != null) {
                                exportEntryRecursiveRaw(
                                    rawDestTree, path, isDir, pending.volId,
                                    opId, total, doneCounter, totalBytes, transferredCounter,
                                )
                            } else {
                                val destTree = DocumentFile.fromTreeUri(activity, treeUri) ?: continue
                                exportEntryRecursive(
                                    destTree, path, isDir, pending.containerUri, pending.volId,
                                    opId, total, doneCounter, totalBytes, transferredCounter,
                                )
                            }
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
                        val count = if (entry.raw != null) {
                            importEntryRecursiveRaw(
                                entry.raw, targetFatPath, picked.volId,
                                opId, total, doneCounter, totalBytes, transferredCounter,
                            )
                        } else {
                            importEntryRecursive(
                                entry.doc, picked.containerUri, targetFatPath, picked.volId,
                                opId, total, doneCounter, totalBytes, transferredCounter,
                            )
                        }
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
                    if (picked.rawRoot != null) {
                        importEntryRecursiveRaw(
                            picked.rawRoot, targetFatPath, picked.volId,
                            opId, total, doneCounter, totalBytes, transferredCounter,
                        )
                    } else {
                        importEntryRecursive(
                            picked.srcRoot, picked.containerUri, targetFatPath, picked.volId,
                            opId, total, doneCounter, totalBytes, transferredCounter,
                        )
                    }
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