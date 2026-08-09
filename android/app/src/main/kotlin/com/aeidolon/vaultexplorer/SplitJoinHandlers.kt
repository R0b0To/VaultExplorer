package com.aeidolon.vaultexplorer

import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.UriToPath
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.ExecutorService

/**
 * Container Splitter/Joiner (Tools tab → Split & Join, [ContainerSplitterSheet]
 * on the Dart side). Splits an unmounted VeraCrypt/LUKS/BitLocker container
 * file into fixed-size `<name>.NNN` chunks — for storage providers with
 * per-file size limits, or so a change deep inside a large container only
 * has to re-upload the handful of chunks it actually touched — and rejoins
 * a chunk sequence back into one file.
 *
 * Deliberately outside the `ContainerEngine`/`volId` world
 * (docs/architecture.md §1, §3.2): the source/target file here is never
 * mounted, and splitting/joining never decrypts anything — it only moves
 * ciphertext bytes around exactly as they sit on disk — so there is no
 * `VolumeState`, no per-volId lock, and no `ContainerSessionRegistry` entry
 * involved anywhere in this class. Both directions run entirely on
 * [ioExecutor] and report progress via [SplitJoinProgressBridge]; the
 * opId/cancellation contract ([SplitJoinCancellation],
 * [SplitJoinCancelledException]) mirrors [ImportExportHandlers]'s import
 * cancellation in shape but keeps its own id space (see that object's doc
 * comment for why).
 *
 * Join needs to enumerate a chunk's sibling files by name, which requires
 * a real on-disk path — a single-document SAF pick (`pickContainer`, used
 * for the "first part" picker) doesn't carry tree access to its parent
 * folder. [UriToPath.getRawFile] is the same "All Files Access" raw-path
 * fast path [ImportExportHandlers] already uses elsewhere in this codebase;
 * here it's not just an optimization but the only way join can find the
 * rest of the sequence. When it's unavailable, [handleJoinContainer] fails
 * with a message telling the user to grant that permission (already
 * surfaced in-app via `hasAllFilesAccess`/`requestAllFilesAccess`) rather
 * than silently joining just the one picked file.
 */
class SplitJoinHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    // Read/write step size for both directions. Deliberately much smaller
    // than any chunk-size preset so cancellation and progress stay
    // reasonably granular even at the 2-4 GB legacy presets -- this is a
    // copy buffer, not the on-disk chunk boundary.
    private val copyBufferSize = 256 * 1024

    /**
     * Opens [uri] for reading, returning the stream alongside its byte
     * length (-1 if undeterminable). Prefers a raw [FileInputStream] when a
     * local path is resolvable (faster, no Binder round trip per read
     * step); falls back to [android.content.ContentResolver] otherwise --
     * the same raw-file-fast-path/SAF-fallback shape used throughout
     * [ImportExportHandlers].
     */
    private fun openSourceForRead(uri: Uri): Pair<InputStream, Long> {
        val rawFile = UriToPath.getRawFile(activity, uri)
        if (rawFile != null && rawFile.canRead()) {
            val stream: InputStream = FileInputStream(rawFile)
            return stream to rawFile.length()
        }
        val size = try {
            activity.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1L
        } catch (e: Exception) {
            -1L
        }
        val stream = activity.contentResolver.openInputStream(uri)
            ?: throw Exception("Could not open source document: $uri")
        return stream to size
    }

    /**
     * Whether [path] can be written via plain `java.io.File`/[FileOutputStream]
     * from this process. Mirrors the scoped-storage gate in
     * [UriToPath.getRawFile]'s doc comment, but for a destination that may
     * not exist on disk yet (a not-yet-written chunk), so it can't rely on
     * that function's `file.exists()` check: on API 30+, a path outside
     * app-private storage needs `MANAGE_EXTERNAL_STORAGE` ("All files
     * access") granted, or every raw write attempt fails with `EPERM`
     * regardless of what [File.canWrite] claims -- `canWrite()` reflects
     * legacy POSIX permission bits, not scoped-storage enforcement, so it
     * can't be trusted here either. When this is false, split/join falls
     * back to [DocumentFile]-based writes through the picked folder's tree
     * URI, the same raw-fast-path/SAF-fallback shape
     * [ImportExportHandlers]'s export path already uses
     * (`rawFileFor`/`exportEntryRecursiveRaw` vs `exportEntryRecursive`).
     */
    private fun canWriteRawPath(path: String): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val isAppPrivate = path.startsWith(activity.filesDir.absolutePath) ||
                activity.getExternalFilesDirs(null).any { it != null && path.startsWith(it.absolutePath) }
            if (!isAppPrivate && !Environment.isExternalStorageManager()) return false
        }
        return true
    }

    /**
     * One destination file to write into, abstracting over the raw-file
     * fast path and the [DocumentFile] SAF fallback so the split/join
     * copy loops below don't need to know which one is active. [delete]
     * removes the just-created output (used on cancellation, mirroring
     * the raw path's existing "drop the in-flight partial part" behavior)
     * and is safe to call more than once.
     */
    private class WritableOutput(val stream: OutputStream, private val onDelete: () -> Unit) {
        fun delete() {
            try { onDelete() } catch (_: Exception) {}
        }
    }

    /**
     * Opens [name] for writing inside the destination folder -- either
     * [destDir] directly (raw fast path, when [canWriteRaw]) or, when raw
     * writes aren't viable under scoped storage, a freshly created
     * [DocumentFile] child of [destTreeDoc]. Deletes any existing entry of
     * the same name first so re-running split/join into the same folder
     * overwrites cleanly either way.
     */
    private fun openDestOutput(
        name: String,
        canWriteRaw: Boolean,
        destDir: File,
        destTreeDoc: DocumentFile?,
    ): WritableOutput {
        if (canWriteRaw) {
            val f = File(destDir, name)
            return WritableOutput(FileOutputStream(f)) { f.delete() }
        }
        val tree = destTreeDoc
            ?: throw Exception("Couldn't write to the destination folder. Grant \"All files access\" in system settings, or pick the destination folder again.")
        tree.findFile(name)?.delete()
        val doc = tree.createFile("application/octet-stream", name)
            ?: throw Exception("Could not create \"$name\" in the destination folder")
        val out = activity.contentResolver.openOutputStream(doc.uri)
            ?: throw Exception("Could not open \"$name\" for writing")
        return WritableOutput(out) { doc.delete() }
    }

    /**
     * Resolves the destination folder for a write: [destinationPath] as a
     * raw [File] when [canWriteRawPath] allows it, else a [DocumentFile]
     * tree rooted at [destinationTreeUri] (required in that case -- see
     * [openDestOutput]). Returns the raw dir (created if needed, for the
     * raw path) alongside whichever tree doc applies.
     */
    private fun resolveDestFolder(
        destinationPath: String,
        destinationTreeUri: String?,
    ): Triple<File, Boolean, DocumentFile?> {
        val destDir = File(destinationPath)
        val canWriteRaw = canWriteRawPath(destinationPath)
        if (canWriteRaw) {
            if (!destDir.exists() && !destDir.mkdirs()) {
                throw Exception("Could not create destination folder: $destinationPath")
            }
            return Triple(destDir, true, null)
        }
        val treeDoc = destinationTreeUri?.let { DocumentFile.fromTreeUri(activity, Uri.parse(it)) }
        if (treeDoc == null || !treeDoc.isDirectory || !treeDoc.canWrite()) {
            throw Exception("Couldn't write to the destination folder. Grant \"All files access\" in system settings, or pick the destination folder again.")
        }
        return Triple(destDir, false, treeDoc)
    }

    /**
     * Writes a `manifest.json` next to a split's parts, for interop with
     * other split/join tools that key off this shape (`displayName`,
     * `format`, `totalSizeBytes`, `chunkSizeBytes`) rather than the
     * `.NNN` naming convention alone. Best-effort: a failure here doesn't
     * fail the split itself, since every part is already written and
     * valid without it.
     */
    private fun writeManifest(
        canWriteRaw: Boolean,
        destDir: File,
        destTreeDoc: DocumentFile?,
        displayName: String,
        format: String,
        totalSizeBytes: Long,
        chunkSizeBytes: Long,
    ) {
        try {
            val json = JSONObject()
                .put("displayName", displayName)
                .put("format", format)
                .put("totalSizeBytes", totalSizeBytes)
                .put("chunkSizeBytes", chunkSizeBytes)
                .toString()
            val out = openDestOutput("manifest.json", canWriteRaw, destDir, destTreeDoc)
            out.stream.use { it.write(json.toByteArray(Charsets.UTF_8)) }
        } catch (_: Exception) {
            // Non-fatal -- see doc comment above.
        }
    }

    /**
     * Best-effort guess at the container format for [writeManifest]'s
     * `format` field, from the source file's name. Purely informational
     * for interop with other tools; this app's own join never reads it
     * back.
     */
    private fun guessFormat(displayName: String): String {
        val lower = displayName.lowercase()
        return when {
            lower.contains("luks") -> "LUKS"
            lower.contains("bitlocker") -> "BITLOCKER"
            else -> "VERACRYPT"
        }
    }

    private fun dispatchSplitJoinError(e: Exception, result: MethodChannel.Result) {
        if (e is SplitJoinCancelledException) {
            result.error("CANCELLED", e.message, null)
        } else {
            result.error("IO_ERROR", e.message ?: e.toString(), null)
        }
    }

    fun handleSplitContainer(call: MethodCall, result: MethodChannel.Result) {
        val sourceUriStr = call.argument<String>("sourceUri")
        val destinationPath = call.argument<String>("destinationPath")
        val destinationTreeUri = call.argument<String>("destinationTreeUri")
        val chunkSizeBytes = call.argument<Number>("chunkSizeBytes")?.toLong()
        val opId = call.argument<Number>("opId")?.toInt() ?: 0

        if (sourceUriStr == null || destinationPath == null || chunkSizeBytes == null || chunkSizeBytes <= 0L) {
            result.error("INVALID_ARGS", "sourceUri, destinationPath, and a positive chunkSizeBytes are required", null)
            return
        }

        ioExecutor.execute {
            var inputToClose: InputStream? = null
            var partOutToClose: WritableOutput? = null
            var partInProgress: WritableOutput? = null
            try {
                val uri = Uri.parse(sourceUriStr)
                val displayName = UriNameResolver.resolve(activity.contentResolver, uri)
                val (src, totalSize) = openSourceForRead(uri)
                inputToClose = src
                if (totalSize <= 0L) throw Exception("Could not determine source file size")

                val (destDir, canWriteRaw, destTreeDoc) = resolveDestFolder(destinationPath, destinationTreeUri)

                val buffer = ByteArray(copyBufferSize)
                var partIndex = 1
                var bytesWrittenTotal = 0L
                var bytesInCurrentPart = 0L

                fun partName(index: Int) = "$displayName.%03d".format(index)

                var partOut = openDestOutput(partName(partIndex), canWriteRaw, destDir, destTreeDoc)
                partInProgress = partOut
                partOutToClose = partOut

                while (true) {
                    if (SplitJoinCancellation.isCancelled(opId)) {
                        throw SplitJoinCancelledException("Split cancelled")
                    }
                    val remainingInPart = chunkSizeBytes - bytesInCurrentPart
                    val toRead = if (remainingInPart < buffer.size.toLong()) remainingInPart.toInt() else buffer.size
                    val n = src.read(buffer, 0, toRead)
                    if (n < 0) break

                    partOut.stream.write(buffer, 0, n)
                    bytesInCurrentPart += n
                    bytesWrittenTotal += n
                    SplitJoinProgressBridge.reportProgress(opId, bytesWrittenTotal, totalSize)

                    if (bytesInCurrentPart >= chunkSizeBytes) {
                        partOut.stream.close()
                        partIndex++
                        bytesInCurrentPart = 0L
                        partOut = openDestOutput(partName(partIndex), canWriteRaw, destDir, destTreeDoc)
                        partInProgress = partOut
                        partOutToClose = partOut
                    }
                }

                partOut.stream.close()
                partOutToClose = null
                // An exact multiple of chunkSizeBytes leaves one empty
                // trailing part from the last part-rollover above -- drop
                // it rather than shipping a useless zero-byte last chunk.
                if (bytesInCurrentPart == 0L && partIndex > 1) partOut.delete()

                // Best-effort, for interop with other split/join tools
                // that expect a manifest alongside the `.NNN` parts (see
                // writeManifest's doc comment).
                writeManifest(
                    canWriteRaw, destDir, destTreeDoc,
                    displayName, guessFormat(displayName), totalSize, chunkSizeBytes,
                )

                activity.runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                try { partOutToClose?.stream?.close() } catch (_: Exception) {}
                if (e is SplitJoinCancelledException) {
                    // Every earlier part is already complete on disk and is
                    // left in place (same as a cancelled import leaves
                    // already-imported files) -- only the in-flight partial
                    // part gets dropped.
                    partInProgress?.delete()
                }
                activity.runOnUiThread { dispatchSplitJoinError(e, result) }
            } finally {
                try { inputToClose?.close() } catch (_: Exception) {}
                SplitJoinCancellation.clear(opId)
            }
        }
    }

    fun handleJoinContainer(call: MethodCall, result: MethodChannel.Result) {
        val firstPartUriStr = call.argument<String>("firstPartUri")
        val destinationPath = call.argument<String>("destinationPath")
        val destinationTreeUri = call.argument<String>("destinationTreeUri")
        val opId = call.argument<Number>("opId")?.toInt() ?: 0

        if (firstPartUriStr == null || destinationPath == null) {
            result.error("INVALID_ARGS", "firstPartUri and destinationPath are required", null)
            return
        }

        ioExecutor.execute {
            var outToClose: WritableOutput? = null
            try {
                val uri = Uri.parse(firstPartUriStr)
                val firstFile = UriToPath.getRawFile(activity, uri)
                    ?: throw Exception(
                        "Couldn't access the picked file directly on disk. " +
                            "Grant \"All files access\" for this app in system settings and try again."
                    )

                val parts = SplitPartResolver.resolvePartSequence(firstFile)
                val totalSize = parts.sumOf { it.length() }

                val destFile = File(destinationPath)
                val destParentPath = destFile.parent ?: destinationPath
                val (destDir, canWriteRaw, destTreeDoc) = resolveDestFolder(destParentPath, destinationTreeUri)

                val out = openDestOutput(destFile.name, canWriteRaw, destDir, destTreeDoc)
                outToClose = out
                val buffer = ByteArray(copyBufferSize)
                var bytesWrittenTotal = 0L

                for (part in parts) {
                    if (SplitJoinCancellation.isCancelled(opId)) {
                        throw SplitJoinCancelledException("Join cancelled")
                    }
                    FileInputStream(part).use { partIn ->
                        while (true) {
                            if (SplitJoinCancellation.isCancelled(opId)) {
                                throw SplitJoinCancelledException("Join cancelled")
                            }
                            val n = partIn.read(buffer)
                            if (n < 0) break
                            out.stream.write(buffer, 0, n)
                            bytesWrittenTotal += n
                            SplitJoinProgressBridge.reportProgress(opId, bytesWrittenTotal, totalSize)
                        }
                    }
                }
                out.stream.close()
                outToClose = null

                activity.runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                try { outToClose?.stream?.close() } catch (_: Exception) {}
                if (e is SplitJoinCancelledException) {
                    outToClose?.delete()
                }
                activity.runOnUiThread { dispatchSplitJoinError(e, result) }
            } finally {
                SplitJoinCancellation.clear(opId)
            }
        }
    }

    fun handleCancelSplitJoin(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId == null) {
            result.error("INVALID_ARGS", "opId required", null)
            return
        }
        SplitJoinCancellation.cancel(opId)
        result.success(true)
    }
}