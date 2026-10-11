package com.aeidolon.vaultexplorer.handlers

import android.content.Context
import android.media.MediaExtractor
import android.net.Uri
import android.os.PowerManager
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.inspector.MediaExtractorCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.audioedit.AudioSource
import com.aeidolon.vaultexplorer.audioedit.AudioWaveformExtractor
import com.aeidolon.vaultexplorer.audioedit.LosslessAudioCutter
import com.aeidolon.vaultexplorer.audioedit.Media3AudioSource
import com.aeidolon.vaultexplorer.audioedit.PlatformAudioSource
import com.aeidolon.vaultexplorer.bridge.AudioEditProgressBridge
import com.aeidolon.vaultexplorer.cancellation.AudioEditCancellation
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerMediaDataSource
import com.aeidolon.vaultexplorer.engine.AiffAwareExtractorsFactory
import com.aeidolon.vaultexplorer.engine.VaultMedia3DataSourceFactory
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService

/**
 * Audio Editor (trim / cut / merge, plus the waveform) -- the native half of
 * `lib/features/audio_editor`, and the sibling of [VideoEditHandlers]. The
 * cutting lives in [LosslessAudioCutter] (stream copy, with [AudioReencoder] as
 * the AAC fallback for codecs that can't be copied) and the waveform in
 * [AudioWaveformExtractor]; this class is the channel plumbing around them:
 * where the source bytes come from, where the result goes, progress,
 * cancellation and cleanup.
 *
 * **Plaintext handling** is exactly the video editor's: each output is written
 * into a temp file in the app's cache dir, moved into the vault with
 * `writeBackFile`, and zero-filled and deleted right after (and again in
 * `finally`). The temp name deliberately uses the `vx_vid_` prefix and `.mp4`
 * suffix -- whatever the real output format is, the muxer is told the format
 * explicitly and doesn't care about the name -- so
 * `VaultVideoRecorder.sweepOrphanedTempFiles` (run at startup) also wipes any
 * a crash or force-stop leaves behind. The *source* is never copied out: for a
 * vault it is read straight through [ContainerMediaDataSource], decrypting on
 * demand, for the waveform as well as the cut.
 */
class AudioEditHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    private companion object {
        const val TAG = "AudioEditHandlers"
        const val TEMP_PREFIX = "vx_vid_aud_cut_"
        const val TEMP_SUFFIX = ".mp4"
        const val COPY_BUFFER = 256 * 1024
    }

    /**
     * Opens the source for one operation. The platform `MediaExtractor` goes first, so every file it
     * already handled keeps behaving exactly as before; when it can't open the file (AIFF, AC-3, DTS
     * and the like -- "failed to instantiate extractor") or finds no audio in it, Media3's extractors
     * take over. Those are the player's own demuxers, so anything the player can open is readable
     * here too. Once the platform extractor has failed for this file it isn't retried: the cutter
     * asks for a fresh source more than once (cut, then re-encode).
     */
    private fun extractorFactory(volId: Int, filePath: String, isLocal: Boolean): () -> AudioSource {
        var preferMedia3 = false
        return {
            var source: AudioSource? = null
            if (!preferMedia3) {
                source = openPlatform(volId, filePath, isLocal)
                if (source == null) preferMedia3 = true
            }
            source ?: openMedia3(volId, filePath, isLocal)
        }
    }

    /** The platform extractor, or null when it can't open the file or sees no audio track in it. */
    private fun openPlatform(volId: Int, filePath: String, isLocal: Boolean): AudioSource? {
        val extractor = MediaExtractor()
        try {
            if (isLocal) {
                extractor.setDataSource(filePath)
            } else {
                extractor.setDataSource(ContainerMediaDataSource(activity, filePath, filePath, volId))
            }
            val source = PlatformAudioSource(extractor)
            if (LosslessAudioCutter.firstAudioTrack(source) < 0) {
                source.release()
                return null
            }
            return source
        } catch (e: Exception) {
            runCatching { extractor.release() }
            VeLog.i(TAG) { "platform extractor can't open this file (${e.message}); using Media3's" }
            return null
        }
    }

    /**
     * Media3's extractors through `MediaExtractorCompat`: the same factory the player uses
     * (`AiffAwareExtractorsFactory` over the default extractors) and the same data sources -- a vault
     * file is decrypted on demand by [VaultMedia3DataSourceFactory], never copied out.
     */
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun openMedia3(volId: Int, filePath: String, isLocal: Boolean): AudioSource {
        val defaults = DefaultExtractorsFactory()
        // As in the player: lets CBR audio without a seek table (plain MP3, ADTS AAC) still be seeked.
        // Not AC-3: Media3's extractor for it stays unseekable here, which is what the cutter wants --
        // it scans from the start so frame timestamps are exact (the player wraps it, see SeekableAc3Extractor).
        defaults.setConstantBitrateSeekingEnabled(true)
        val dataSourceFactory: DataSource.Factory =
            if (isLocal) DefaultDataSource.Factory(activity) else VaultMedia3DataSourceFactory(volId, filePath)
        val uri: Uri = when {
            !isLocal -> Uri.parse("vault://$volId/$filePath")
            filePath.startsWith("content://") ->
                activity.safStorageManager.resolveDocumentUriFromTreePath(filePath) ?: Uri.parse(filePath)
            else -> Uri.fromFile(File(filePath))
        }
        val compat = MediaExtractorCompat(AiffAwareExtractorsFactory(defaults), dataSourceFactory)
        try {
            compat.setDataSource(uri, 0L)
        } catch (e: Exception) {
            runCatching { compat.release() }
            throw IOException("Couldn't open this audio file: ${e.message ?: e.javaClass.simpleName}", e)
        }
        val source = Media3AudioSource(compat)
        if (LosslessAudioCutter.firstAudioTrack(source) < 0) {
            source.release()
            throw IOException("No audio track found in this file")
        }
        return source
    }

    private fun extensionOf(path: String): String {
        val name = path.substringAfterLast('/')
        val dot = name.lastIndexOf('.')
        return if (dot >= 0) name.substring(dot + 1) else ""
    }

    // ── audioEditProbe ───────────────────────────────────────────────────

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
                val probe = LosslessAudioCutter.probe(
                    extractorFactory(volId, filePath, isLocal),
                    extensionOf(filePath),
                )
                val map = hashMapOf<String, Any?>(
                    "durationUs" to probe.durationUs,
                    "mime" to probe.mime,
                    "bitrate" to probe.bitrate,
                    "sampleRate" to probe.sampleRate,
                    "channels" to probe.channels,
                    "outputExtension" to probe.outputExtension,
                    "cutSupported" to probe.cutSupported,
                    "reencode" to probe.reencode,
                    "unsupportedReason" to probe.unsupportedReason,
                )
                activity.runOnUiThread { result.success(map) }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "audioEditProbe failed" }
                activity.runOnUiThread { result.error("PROBE_FAILED", e.message ?: "Could not read this audio file", null) }
            }
        }
    }

    // ── audioEditWaveform ────────────────────────────────────────────────

    /**
     * Args: `volId`, `filePath`, `isLocalStorage`, `opId`. Progress arrives as
     * `onAudioEditProgress` events with phase `waveform`; `cancelAudioEdit`
     * with the same opId stops the decode early.
     */
    fun handleWaveform(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Number>("volId")?.toInt()
        val filePath = call.argument<String>("filePath")
        val isLocal = call.argument<Boolean>("isLocalStorage") ?: false
        val opId = call.argument<Number>("opId")?.toInt() ?: 0
        if (volId == null || filePath.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "volId and filePath are required", null)
            return
        }

        ioExecutor.execute {
            try {
                val waveform = AudioWaveformExtractor.extract(
                    newExtractor = extractorFactory(volId, filePath, isLocal),
                    isCancelled = { AudioEditCancellation.isCancelled(opId) },
                    onProgress = { f -> AudioEditProgressBridge.reportProgress(opId, 0, 1, "waveform", f) },
                )
                val map = hashMapOf<String, Any?>(
                    "peaks" to waveform.peaks,
                    "peaksPerSecond" to waveform.peaksPerSecond,
                    "complete" to waveform.complete,
                )
                activity.runOnUiThread { result.success(map) }
            } catch (e: AudioWaveformExtractor.CancelledException) {
                activity.runOnUiThread { result.error("CANCELLED", "Waveform cancelled", null) }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "audioEditWaveform failed" }
                activity.runOnUiThread { result.error("WAVEFORM_FAILED", e.message ?: "Could not read the waveform", null) }
            } finally {
                AudioEditCancellation.clear(opId)
            }
        }
    }

    // ── audioEditExport ──────────────────────────────────────────────────

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
        val ranges = rawSegments.map { LosslessAudioCutter.Range(it[0].toLong(), it[1].toLong()) }
        if (ranges.any { it.endUs <= it.startUs }) {
            result.error("INVALID_ARGS", "Every segment needs an end after its start", null)
            return
        }
        val groups: List<List<LosslessAudioCutter.Range>> =
            if (merge) listOf(ranges) else ranges.map { listOf(it) }
        if (outputPaths.size != groups.size) {
            result.error("INVALID_ARGS", "Expected ${groups.size} output path(s), got ${outputPaths.size}", null)
            return
        }

        ioExecutor.execute {
            val powerManager = activity.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VaultExplorer:AudioExport")
            wakeLock?.acquire(15 * 60 * 1000L) // 15 mins timeout
            val tempFiles = ArrayList<File>()
            // Outputs created so far (successfully or not) -- rolled back if the export fails or is cancelled.
            val created = ArrayList<String>()
            try {
                // Free-space preflight: the output is never larger than the source, so size the check on it.
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
                val sourceExtension = extensionOf(filePath)

                for ((i, group) in groups.withIndex()) {
                    if (AudioEditCancellation.isCancelled(opId)) {
                        throw LosslessAudioCutter.CutCancelledException()
                    }

                    val temp = File.createTempFile(TEMP_PREFIX, TEMP_SUFFIX, activity.cacheDir)
                    tempFiles.add(temp)

                    LosslessAudioCutter.cut(
                        newExtractor = factory,
                        sourceExtension = sourceExtension,
                        ranges = group,
                        outFile = temp,
                        isCancelled = { AudioEditCancellation.isCancelled(opId) },
                        onProgress = { f ->
                            AudioEditProgressBridge.reportProgress(opId, i, groups.size, "cutting", f)
                        },
                    )

                    if (AudioEditCancellation.isCancelled(opId)) {
                        throw LosslessAudioCutter.CutCancelledException()
                    }
                    AudioEditProgressBridge.reportProgress(opId, i, groups.size, "saving", 0f)

                    val dest = outputPaths[i]
                    created.add(dest)
                    val saved = if (isLocal) {
                        copyToLocal(temp, File(dest))
                    } else {
                        val written = ContainerFileSystem.writeBackFile(volId, dest, temp.absolutePath)
                        written && ContainerFileSystem.finishWrite(volId, dest)
                    }
                    if (!saved) throw IOException("Could not save the cut audio (is there enough free space?)")

                    // Wipe right away: don't keep a plaintext copy around between outputs.
                    SecureFileWipe.secureDeleteFile(temp)
                    AudioEditProgressBridge.reportProgress(opId, i, groups.size, "saving", 1f)
                }

                val payload = hashMapOf<String, Any?>("outputPaths" to outputPaths)
                activity.runOnUiThread { result.success(payload) }
            } catch (e: Exception) {
                rollBack(volId, isLocal, created)
                val cancelled = e is LosslessAudioCutter.CutCancelledException
                if (!cancelled) VeLog.w(TAG, e) { "audioEditExport failed" }
                activity.runOnUiThread {
                    if (cancelled) {
                        result.error("CANCELLED", "Export cancelled", null)
                    } else {
                        result.error("EXPORT_FAILED", e.message ?: "Export failed", null)
                    }
                }
            } finally {
                tempFiles.forEach { SecureFileWipe.secureDeleteFile(it) }
                AudioEditCancellation.clear(opId)
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

    // ── cancelAudioEdit ──────────────────────────────────────────────────

    fun handleCancel(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId != null) AudioEditCancellation.cancel(opId)
        result.success(null)
    }
}
