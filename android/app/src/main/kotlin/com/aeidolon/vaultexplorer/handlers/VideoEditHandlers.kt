package com.aeidolon.vaultexplorer.handlers

import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.bridge.VideoEditProgressBridge
import com.aeidolon.vaultexplorer.cancellation.VideoEditCancellation
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
    }

    private fun extractorFactory(volId: Int, filePath: String, isLocal: Boolean): () -> MediaExtractor = {
        val extractor = MediaExtractor()
        try {
            if (isLocal) {
                extractor.setDataSource(filePath)
            } else {
                extractor.setDataSource(ContainerMediaDataSource(filePath, volId))
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
        val includeKeyframes = call.argument<Boolean>("includeKeyframes") ?: true
        val includeDateMetadata = call.argument<Boolean>("includeDateMetadata") ?: false
        if (volId == null || filePath.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "volId and filePath are required", null)
            return
        }

        ioExecutor.execute {
            try {
                val probe = LosslessVideoCutter.probe(
                    extractorFactory(volId, filePath, isLocal),
                    includeKeyframes = includeKeyframes,
                )
                val creationDate = if (includeDateMetadata) {
                    runCatching {
                        val retriever = MediaMetadataRetriever()
                        try {
                            if (isLocal) {
                                retriever.setDataSource(filePath)
                            } else {
                                retriever.setDataSource(
                                    ContainerMediaDataSource(filePath, volId),
                                )
                            }
                            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)
                        } finally {
                            runCatching { retriever.release() }
                        }
                    }.getOrNull()
                } else {
                    null
                }
                val map = hashMapOf<String, Any?>(
                    "creationDate" to creationDate,
                    "durationUs" to probe.durationUs,
                    "width" to probe.width,
                    "height" to probe.height,
                    "rotationDegrees" to probe.rotationDegrees,
                    "hasVideo" to probe.hasVideo,
                    "hasAudio" to probe.hasAudio,
                    "videoMime" to probe.videoMime,
                    "audioMime" to probe.audioMime,
                    "videoBitrate" to probe.videoBitrate,
                    "audioBitrate" to probe.audioBitrate,
                    "frameRate" to probe.frameRate,
                    "audioSampleRate" to probe.audioSampleRate,
                    "audioChannels" to probe.audioChannels,
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
     * Args: see [parseEditExportArgs]; each output is one lossless cut of the
     * requested segments.
     */
    fun handleExport(call: MethodCall, result: MethodChannel.Result) {
        val args = parseEditExportArgs(call, result) ?: return
        val volId = args.volId
        val opId = args.opId
        val outputPaths = args.outputPaths
        val groups = args.groups { startUs, endUs -> LosslessVideoCutter.Range(startUs, endUs) }

        ioExecutor.execute {
            val wakeLock = EditExportSupport.acquireWakeLock(activity, "VaultExplorer:VideoExport", 15 * 60 * 1000L)
            val tempFiles = ArrayList<File>()
            // Outputs created so far (successfully or not) -- rolled back if the export fails or is cancelled.
            val created = ArrayList<String>()
            try {
                EditExportSupport.checkFreeSpace(activity.cacheDir, args)

                val factory = extractorFactory(volId, args.filePath, args.isLocal)
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
                    if (!EditExportSupport.saveOutput(args, temp, dest, TAG)) {
                        throw IOException("Could not save the cut video (is there enough free space?)")
                    }

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
                EditExportSupport.rollBack(args, created)
                EditExportSupport.replyFailure(
                    activity, result, e,
                    cancelled = e is LosslessVideoCutter.CutCancelledException,
                    tag = TAG, logMessage = "videoEditExport failed",
                )
            } finally {
                tempFiles.forEach { SecureFileWipe.secureDeleteFile(it) }
                VideoEditCancellation.clear(opId)
                EditExportSupport.releaseWakeLock(wakeLock)
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
