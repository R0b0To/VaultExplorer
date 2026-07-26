package com.aeidolon.vaultexplorer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.concurrent.ExecutorService

/**
 * Bulk import/export between SAF documents on the outside and a mounted
 * container's virtual filesystem on the inside: single/multi-file import,
 * whole-folder import, single-file export, and multi-item export-to-folder.
 * Progress for the two import flows streams to Dart via
 * [ImportProgressBridge]; [ImportCancellation] lets the Dart side cancel an
 * in-flight import by opId.
 */
class ImportExportHandlers(
    private val activity: MainActivity,
    private val pendingResult: PendingActivityResult,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    private data class PendingImport(val containerUri: String, val targetDir: String, val volId: Int, val opId: Int)
    private var pendingImport: PendingImport? = null

    private data class PendingExportMulti(val containerUri: String, val items: List<Map<String, Any?>>, val volId: Int)
    private var pendingExportMulti: PendingExportMulti? = null

    private data class PendingImportFolder(val containerUri: String, val targetDir: String, val volId: Int, val opId: Int)
    private var pendingImportFolder: PendingImportFolder? = null

    private data class PendingExportFile(val containerUri: String, val sourcePath: String, val volId: Int)
    private var pendingExportFile: PendingExportFile? = null

    private fun existingNamesLowercase(volId: Int, dirPath: String): Set<String> {
        val entries = ContainerFileSystem.listDirectory(volId, dirPath) ?: return emptySet()
        return entries.mapNotNull { entry ->
            if (entry.startsWith("System:")) return@mapNotNull null
            val isDir = entry.startsWith("[DIR] ")
            val name = if (isDir) entry.substringAfter("[DIR] ").substringBefore("|")
                       else entry.substringBefore("|")
            name.lowercase()
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
    private fun uniqueImportName(volId: Int, dirPath: String, desiredName: String): String {
        val existing = existingNamesLowercase(volId, dirPath)
        if (desiredName.lowercase() !in existing) return desiredName

        val dot = desiredName.lastIndexOf('.')
        val hasExt = dot > 0 && dot < desiredName.length - 1
        val base = if (hasExt) desiredName.substring(0, dot) else desiredName
        val ext = if (hasExt) desiredName.substring(dot) else ""

        var n = 1
        while (true) {
            val candidate = "$base ($n)$ext"
            if (candidate.lowercase() !in existing) return candidate
            n++
        }
    }

    private fun exportEntryRecursive(
        destParent: DocumentFile, fatPath: String, isDir: Boolean,
        containerUri: String, volId: Int
    ): Int {
        val name = fatPath.substringAfterLast("/")
        if (!isDir) {
            return try {
                val tempFile = File(activity.cacheDir, "export_${System.nanoTime()}")
                val ok = ContainerFileSystem.extractToFile(volId, fatPath, tempFile.absolutePath)
                var written = 0
                if (ok && tempFile.exists()) {
                    destParent.findFile(name)?.delete()
                    val outDoc = destParent.createFile(MimeTypeHelper.getMimeType(name), name)
                    if (outDoc != null) {
                        activity.contentResolver.openOutputStream(outDoc.uri)?.use { out ->
                            tempFile.inputStream().use { it.copyTo(out) }
                        }
                        written = 1
                    }
                }
                tempFile.delete()
                written
            } catch (_: Exception) { 0 }
        }
        val destDir = destParent.createDirectory(name) ?: return 0
        val children = ContainerFileSystem.listDirectory(volId, fatPath) ?: return 0
        var count = 0
        for (entry in children) {
            if (entry.startsWith("System:")) continue
            val childIsDir = entry.startsWith("[DIR] ")
            val childName = if (childIsDir) entry.substringAfter("[DIR] ").substringBefore("|")
                            else entry.substringBefore("|")
            count += exportEntryRecursive(destDir, "$fatPath/$childName", childIsDir, containerUri, volId)
        }
        return count
    }

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
            for (child in srcDoc.listFiles()) {
                val childName = FatFileNameSanitizer.sanitize(child.name ?: continue)
                count += importEntryRecursive(
                    child, containerUri, "$targetFatPath/$childName", volId,
                    opId, total, doneCounter, totalBytes, transferredCounter,
                )
            }
            return count
        }

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
        val ok = progressStream.use { inp ->
            ContainerFileSystem.importStream(volId, targetFatPath, inp)
        }
        if (!ok) {
            throw java.io.IOException("Failed to write file to container: $targetFatPath. Storage might be full.")
        }
        val lastModified = srcDoc.lastModified() / 1000L
        if (lastModified > 0) {
            ContainerFileSystem.setLastModifiedTime(volId, targetFatPath, lastModified)
        }
        val done = doneCounter.incrementAndGet()
        ImportProgressBridge.reportProgress(
            opId, done, total, srcDoc.name ?: "",
            transferredCounter?.get() ?: 0L, totalBytes
        )
        return 1
    }

    private val importFileLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val pending = pendingImport
        pendingImport = null
        val data = activityResult.data

        if (activityResult.resultCode == Activity.RESULT_OK && data != null && pending != null) {
            val uris = mutableListOf<Uri>()
            data.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
                ?: data.data?.let { uris.add(it) }
            if (uris.isNotEmpty()) {
                ImportSourceRegistry.recordFiles(pending.opId, uris)
                ioExecutor.execute {
                    try {
                        val srcDocs = uris.mapNotNull { DocumentFile.fromSingleUri(activity, it) }
                        val total = srcDocs.sumOf { countEntriesRecursive(it) }
                        val totalBytes = srcDocs.sumOf { countBytesRecursive(it) }
                        val doneCounter = java.util.concurrent.atomic.AtomicInteger(0)
                        val transferredCounter = java.util.concurrent.atomic.AtomicLong(0L)
                        var successCount = 0
                        for (srcDoc in srcDocs) {
                            val rawName = FatFileNameSanitizer.sanitize(srcDoc.name ?: "imported_file")
                            val name = uniqueImportName(pending.volId, pending.targetDir, rawName)
                            val targetFatPath = if (pending.targetDir.isEmpty()) name else "${pending.targetDir}/$name"
                            successCount += importEntryRecursive(
                                srcDoc, pending.containerUri, targetFatPath, pending.volId,
                                pending.opId, total, doneCounter, totalBytes, transferredCounter,
                            )
                        }
                        activity.runOnUiThread { res.success(successCount) }
                    } catch (e: Exception) {
                        activity.runOnUiThread { nativeOps.dispatchNativeError(e, res) }
                    } finally {
                        ImportCancellation.clear(pending.opId)
                    }
                }
            } else {
                res.success(0)
            }
        } else {
            res.success(0)
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
            ioExecutor.execute {
                try {
                    var successCount = 0
                    val destTree = DocumentFile.fromTreeUri(activity, treeUri)
                    if (destTree != null) {
                        for (item in pending.items) {
                            val path  = item["path"] as? String ?: continue
                            val isDir = item["isDir"] as? Boolean ?: false
                            successCount += exportEntryRecursive(destTree, path, isDir, pending.containerUri, pending.volId)
                        }
                    }
                    activity.runOnUiThread { res.success(successCount) }
                } catch (e: Exception) {
                    activity.runOnUiThread { nativeOps.dispatchNativeError(e, res) }
                }
            }
        } else {
            res.success(0)
        }
    }

    private val importFolderLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val pending = pendingImportFolder
        pendingImportFolder = null
        val data = activityResult.data

        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null && pending != null) {
            val treeUri = data.data!!
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            val srcRoot = DocumentFile.fromTreeUri(activity, treeUri)
            if (srcRoot != null) {
                ImportSourceRegistry.recordFolder(pending.opId, treeUri)
                val rawFolderName = FatFileNameSanitizer.sanitize(srcRoot.name ?: "imported_folder")
                val folderName = uniqueImportName(pending.volId, pending.targetDir, rawFolderName)
                val targetFatPath = if (pending.targetDir.isEmpty()) folderName else "${pending.targetDir}/$folderName"
                ioExecutor.execute {
                    try {
                        val total = countEntriesRecursive(srcRoot)
                        val totalBytes = countBytesRecursive(srcRoot)
                        val doneCounter = java.util.concurrent.atomic.AtomicInteger(0)
                        val transferredCounter = java.util.concurrent.atomic.AtomicLong(0L)
                        val count = importEntryRecursive(
                            srcRoot, pending.containerUri, targetFatPath, pending.volId,
                            pending.opId, total, doneCounter, totalBytes, transferredCounter,
                        )
                        activity.runOnUiThread { res.success(count) }
                    } catch (e: Exception) {
                        activity.runOnUiThread { nativeOps.dispatchNativeError(e, res) }
                    } finally {
                        ImportCancellation.clear(pending.opId)
                    }
                }
            } else {
                res.success(0)
            }
        } else {
            res.success(0)
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
                    val tempFile = File(activity.cacheDir, "export_temp")
                    val ok = ContainerFileSystem.extractToFile(pending.volId, pending.sourcePath, tempFile.absolutePath)

                    if (ok && tempFile.exists()) {
                        activity.contentResolver.openOutputStream(destUri)?.use { out ->
                            tempFile.inputStream().use { it.copyTo(out) }
                        }
                        tempFile.delete()
                        activity.runOnUiThread { res.success(true) }
                    } else {
                        tempFile.delete()
                        activity.runOnUiThread { res.success(false) }
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

    fun handleImportFile(call: MethodCall, result: MethodChannel.Result) {
        val containerUri = call.argument<String>("filePath")
        if (containerUri == null) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container is not mounted", null)
            return
        }
        val opId = call.argument<Number>("opId")?.toInt() ?: 0
        pendingImport = PendingImport(containerUri, call.argument<String>("targetPath") ?: "", volId, opId)
        pendingResult.stash(result)
        importFileLauncher.launch(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        })
    }

    fun handleExportFilesFolder(call: MethodCall, result: MethodChannel.Result) {
        val containerUri = call.argument<String>("filePath")
        if (containerUri == null) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container is not mounted", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val items = (call.argument<List<*>>("items"))?.mapNotNull { it as? Map<String, Any?> } ?: emptyList()
        pendingExportMulti = PendingExportMulti(containerUri, items, volId)
        pendingResult.stash(result)
        exportFilesFolderLauncher.launch(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE))
    }

    fun handleImportFolder(call: MethodCall, result: MethodChannel.Result) {
        val containerUri = call.argument<String>("filePath")
        if (containerUri == null) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(containerUri)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container is not mounted", null)
            return
        }
        val opId = call.argument<Number>("opId")?.toInt() ?: 0
        pendingImportFolder = PendingImportFolder(containerUri, call.argument<String>("targetPath") ?: "", volId, opId)
        pendingResult.stash(result)
        importFolderLauncher.launch(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE))
    }

    fun handleExportFile(call: MethodCall, result: MethodChannel.Result) {
        val containerUri = call.argument<String>("filePath")
        val sourcePath = call.argument<String>("sourcePath")
        if (containerUri == null || sourcePath == null) {
            result.error("INVALID_ARGS", "filePath and sourcePath required", null)
            return
        }
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