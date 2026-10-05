package com.aeidolon.vaultexplorer.handlers

import android.content.Context
import android.media.MediaExtractor
import android.os.PowerManager
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.bridge.VideoEditProgressBridge
import com.aeidolon.vaultexplorer.cancellation.VideoEditCancellation
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerMediaDataSource
import com.aeidolon.vaultexplorer.videoedit.LosslessVideoCutter
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService

/**
 * Video Editor (lossless trim / cut / merge) -- the native half of
 * `lib/features/video_editor`. All the actual cutting lives in
 * [LosslessVideoCutter]; this class is the channel plumbing around it:
 * where the source bytes come from, where the result goes, progress,
 * cancellation and cleanup.
 *
 * **Plaintext handling.** `MediaMuxer` needs a real, seekable file to write
 * an MP4, so each output is muxed into a temp file in the app's cache dir
 * and then moved into the vault with `writeBackFile` -- the same
 * temp-file-then-wipe sequence `ArchiveHandlers` and the recording pipeline
 * use. The temp file is zero-filled and deleted as soon as it has been
 * copied (and again in `finally`), and it uses the `vx_vid_` prefix so
 * `VaultVideoRecorder.sweepOrphanedTempFiles` (run at startup) also wipes
 * any that a crash or force-stop leaves behind. The *source* is never
 * copied out: for a vault it is read straight through
 * [ContainerMediaDataSource], decrypting on demand.
 *
 * **Local storage** (the decoy's plain-folder file manager) is the same
 * flow with a real path in and a real path out.
 */
class VideoEditHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    private companion object {
        const val TAG = "VideoEditHandlers"
        const val TEMP_PREFIX = "vx_vid_cut_"
        const val TEMP_SUFFIX = ".mp4"
        const val COPY_BUFFER = 256 * 1024
    }

    private fun extractorFactory(volId: Int, filePath: String, isLocal: Boolean): () -> MediaExtractor = {
        val extractor = MediaExtractor()
        try {
            if (isLocal) {
                extractor.setDataSource(filePath)
            } else {
                extractor.setDataSource(ContainerMediaDataSource(activity, filePath, filePath, volId))
            }
        } catch (e: Exception) {
            runCatching { extractor.release() }
            throw e
        }
        extractor
    }

    // ── videoEditProbe ───────────────────────────────────────────────────

    fun handleProbe(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Number>("volId")?.toInt()
        val filePath = call.argument<String>("filePath")
        val isLocal = call.argument<Boolean>("isLocalStorage") ?: false
        if (volId == null || filePath.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "volId and filePath are required", null)
            return
        }

        ioExecutor.execute {
            try {
                val probe = LosslessVideoCutter.probe(extractorFactory(volId, filePath, isLocal))
                val map = hashMapOf<String, Any?>(
                    "durationUs" to probe.durationUs,
                    "width" to probe.width,
                    "height" to probe.height,
                    "rotationDegrees" to probe.rotationDegrees,
                    "hasVideo" to probe.hasVideo,
                    "hasAudio" to probe.hasAudio,
                    "videoMime" to probe.videoMime,
                    "audioMime" to probe.audioMime,
                    "keyframesUs" to probe.keyframesUs.toList(),
                    "keyframesComplete" to probe.keyframesComplete,
                    "outputExtension" to probe.outputExtension,
                    "hasSubtitles" to probe.hasSubtitles,
                    "subtitleTracks" to probe.subtitleTracks,
                )
                activity.runOnUiThread { result.success(map) }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "videoEditProbe failed" }
                activity.runOnUiThread { result.error("PROBE_FAILED", e.message ?: "Could not read this video", null) }
            }
        }
    }

    // ── videoEditExport ──────────────────────────────────────────────────

    /**
     * Args: `volId`, `filePath`, `isLocalStorage`, `segments` (list of
     * `[startUs, endUs]`), `merge` (one output holding every segment vs. one
     * output per segment), `outputPaths` (exactly 1 when merging, else one
     * per segment -- container-relative for a vault, absolute for local
     * storage; Dart has already made them unique), `opId`.
     */
    fun handleExport(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Number>("volId")?.toInt()
        val filePath = call.argument<String>("filePath")
        val isLocal = call.argument<Boolean>("isLocalStorage") ?: false
        val merge = call.argument<Boolean>("merge") ?: false
        val opId = call.argument<Number>("opId")?.toInt() ?: 0
        val rawSegments = call.argument<List<List<Number>>>("segments")
        val outputPaths = call.argument<List<String>>("outputPaths")

        if (volId == null || filePath.isNullOrEmpty() || rawSegments.isNullOrEmpty() || outputPaths.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "volId, filePath, segments and outputPaths are required", null)
            return
        }
        val ranges = rawSegments.map { LosslessVideoCutter.Range(it[0].toLong(), it[1].toLong()) }
        if (ranges.any { it.endUs <= it.startUs }) {
            result.error("INVALID_ARGS", "Every segment needs an end after its start", null)
            return
        }
        val groups: List<List<LosslessVideoCutter.Range>> =
            if (merge) listOf(ranges) else ranges.map { listOf(it) }
        if (outputPaths.size != groups.size) {
            result.error("INVALID_ARGS", "Expected ${groups.size} output path(s), got ${outputPaths.size}", null)
            return
        }

        ioExecutor.execute {
            val powerManager = activity.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VaultExplorer:VideoExport")
            wakeLock?.acquire(15 * 60 * 1000L) // 15 mins timeout
            val tempFiles = ArrayList<File>()
            // Outputs created so far (successfully or not) -- rolled back if the export fails or is cancelled.
            val created = ArrayList<String>()
            try {
                // Free-space preflight check: estimate required space based on source file size and cuts.
                val sourceSize = if (isLocal) {
                    File(filePath).length().coerceAtLeast(1L)
                } else {
                    ContainerFileSystem.getFileSize(volId, filePath).coerceAtLeast(1L)
                }
                val estimatedBytes = ((sourceSize * 1.2).toLong() + 5 * 1024 * 1024L).coerceAtLeast(10 * 1024 * 1024L)

                val cacheUsable = activity.cacheDir.usableSpace
                if (cacheUsable in 1 until estimatedBytes) {
                    val needMb = estimatedBytes / (1024 * 1024)
                    val freeMb = cacheUsable / (1024 * 1024)
                    throw IOException("Not enough free space in app cache (need $needMb MB, only $freeMb MB available)")
                }

                if (isLocal) {
                    val destDir = File(outputPaths[0]).parentFile ?: File(outputPaths[0])
                    val localUsable = destDir.usableSpace
                    if (localUsable in 1 until estimatedBytes) {
                        val needMb = estimatedBytes / (1024 * 1024)
                        val freeMb = localUsable / (1024 * 1024)
                        throw IOException("Not enough free space on storage (need $needMb MB, only $freeMb MB available)")
                    }
                } else {
                    val freeBytes = ContainerFileSystem.getSpaceInfo(volId)
                        ?.let { if (it.size > 1) it[1] else null }
                    if (freeBytes != null && freeBytes in 1 until estimatedBytes) {
                        val needMb = estimatedBytes / (1024 * 1024)
                        val freeMb = freeBytes / (1024 * 1024)
                        throw IOException("Not enough free space in vault (need $needMb MB, only $freeMb MB available)")
                    }
                }

                val factory = extractorFactory(volId, filePath, isLocal)
                var dropped = 0
                val actual = ArrayList<List<Long>>()

                for ((i, group) in groups.withIndex()) {
                    if (VideoEditCancellation.isCancelled(opId)) {
                        throw LosslessVideoCutter.CutCancelledException()
                    }

                    val temp = File.createTempFile(TEMP_PREFIX, TEMP_SUFFIX, activity.cacheDir)
                    tempFiles.add(temp)

                    val cut = LosslessVideoCutter.cut(
                        newExtractor = factory,
                        ranges = group,
                        outFile = temp,
                        isCancelled = { VideoEditCancellation.isCancelled(opId) },
                        onProgress = { f ->
                            VideoEditProgressBridge.reportProgress(opId, i, groups.size, "cutting", f)
                        },
                    )
                    dropped += cut.droppedAudioTracks
                    cut.actualRanges.forEach { actual.add(listOf(it.startUs, it.endUs)) }

                    if (VideoEditCancellation.isCancelled(opId)) {
                        throw LosslessVideoCutter.CutCancelledException()
                    }
                    VideoEditProgressBridge.reportProgress(opId, i, groups.size, "saving", 0f)

                    val dest = outputPaths[i]
                    created.add(dest)
                    val saved = if (isLocal) {
                        copyToLocal(temp, File(dest))
                    } else {
                        val written = ContainerFileSystem.writeBackFile(volId, dest, temp.absolutePath)
                        written && ContainerFileSystem.finishWrite(volId, dest)
                    }
                    if (!saved) throw IOException("Could not save the cut video (is there enough free space?)")

                    // Wipe right away: don't keep a plaintext copy around between outputs.
                    SecureFileWipe.secureDeleteFile(temp)
                    VideoEditProgressBridge.reportProgress(opId, i, groups.size, "saving", 1f)
                }

                val payload = hashMapOf<String, Any?>(
                    "outputPaths" to outputPaths,
                    "droppedAudioTracks" to dropped,
                    "actualRangesUs" to actual,
                )
                activity.runOnUiThread { result.success(payload) }
            } catch (e: Exception) {
                rollBack(volId, isLocal, created)
                val cancelled = e is LosslessVideoCutter.CutCancelledException
                if (!cancelled) VeLog.w(TAG, e) { "videoEditExport failed" }
                activity.runOnUiThread {
                    if (cancelled) {
                        result.error("CANCELLED", "Export cancelled", null)
                    } else {
                        result.error("EXPORT_FAILED", e.message ?: "Export failed", null)
                    }
                }
            } finally {
                tempFiles.forEach { SecureFileWipe.secureDeleteFile(it) }
                VideoEditCancellation.clear(opId)
                if (wakeLock?.isHeld == true) {
                    runCatching { wakeLock.release() }
                }
            }
        }
    }

    private fun copyToLocal(src: File, dest: File): Boolean = try {
        dest.parentFile?.mkdirs()
        src.inputStream().use { input ->
            dest.outputStream().use { output -> input.copyTo(output, COPY_BUFFER) }
        }
        true
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "copyToLocal failed" }
        false
    }

    /** Removes outputs this call created, so a failed/cancelled export leaves nothing half-written behind. */
    private fun rollBack(volId: Int, isLocal: Boolean, created: List<String>) {
        for (path in created) {
            runCatching {
                if (isLocal) File(path).delete() else ContainerFileSystem.deleteFile(volId, path)
            }
        }
    }

    // ── cancelVideoEdit ──────────────────────────────────────────────────

    fun handleCancel(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId != null) VideoEditCancellation.cancel(opId)
        result.success(null)
    }
}
