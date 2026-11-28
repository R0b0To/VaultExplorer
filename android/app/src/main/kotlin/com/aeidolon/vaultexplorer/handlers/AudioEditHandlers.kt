package com.aeidolon.vaultexplorer.handlers

import android.media.MediaExtractor
import android.net.Uri
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
import com.aeidolon.vaultexplorer.audioedit.ReadAheadMediaDataSource
import com.aeidolon.vaultexplorer.bridge.AudioEditProgressBridge
import com.aeidolon.vaultexplorer.cancellation.AudioEditCancellation
import com.aeidolon.vaultexplorer.container.ContainerMediaDataSource
import com.aeidolon.vaultexplorer.engine.AiffAwareExtractorsFactory
import com.aeidolon.vaultexplorer.engine.VaultMedia3DataSourceFactory
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

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
    }

    /**
     * The waveform decode gets a thread of its own. It is no longer cut off after a minute, so on a
     * multi-hour file it can run for many minutes, and parking that on the shared [ioExecutor] (four
     * threads for everything: unlocking, copying, exporting...) would starve other work. One thread is
     * enough: the editor asks for one waveform at a time, and leaving it cancels the decode. Daemon and
     * slightly below normal priority, so it never competes with the UI or playback for the CPU.
     */
    private val waveformExecutor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "AudioWaveform").apply {
            isDaemon = true
            priority = Thread.NORM_PRIORITY - 1
        }
    }

    /**
     * Opens the source for one operation. The platform `MediaExtractor` goes first, so every file it
     * already handled keeps behaving exactly as before; when it can't open the file (AIFF, AC-3, DTS
     * and the like -- "failed to instantiate extractor") or finds no audio in it, Media3's extractors
     * take over. Those are the player's own demuxers, so anything the player can open is readable
     * here too. Once the platform extractor has failed for this file it isn't retried: the cutter
     * asks for a fresh source more than once (cut, then re-encode).
     */
    private fun extractorFactory(
        volId: Int,
        filePath: String,
        isLocal: Boolean,
        readAhead: Boolean = false,
    ): () -> AudioSource {
        var preferMedia3 = false
        return {
            var source: AudioSource? = null
            if (!preferMedia3) {
                source = openPlatform(volId, filePath, isLocal, readAhead)
                if (source == null) preferMedia3 = true
            }
            source ?: openMedia3(volId, filePath, isLocal)
        }
    }

    /** The platform extractor, or null when it can't open the file or sees no audio track in it. */
    private fun openPlatform(volId: Int, filePath: String, isLocal: Boolean, readAhead: Boolean): AudioSource? {
        val extractor = MediaExtractor()
        try {
            if (isLocal) {
                extractor.setDataSource(filePath)
            } else {
                val vaultFile = ContainerMediaDataSource(filePath, volId)
                // A front-to-back scan (the waveform) reads in big blocks instead of one native call per
                // audio frame; the other operations keep reading exactly as before.
                extractor.setDataSource(if (readAhead) ReadAheadMediaDataSource(vaultFile) else vaultFile)
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
                    "canCompress" to probe.canCompress,
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
     * `onAudioEditProgress` events with phase `waveform`, and the finished part of the
     * waveform as `onAudioWaveformChunk` events while the decode runs (the reply carries the
     * whole thing at the end); `cancelAudioEdit` with the same opId stops the decode early.
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

        waveformExecutor.execute {
            try {
                val waveform = AudioWaveformExtractor.extract(
                    newExtractor = extractorFactory(volId, filePath, isLocal, readAhead = true),
                    isCancelled = { AudioEditCancellation.isCancelled(opId) },
                    onProgress = { f -> AudioEditProgressBridge.reportProgress(opId, 0, 1, "waveform", f) },
                    onPartial = { peaks, peaksPerSecond, from, to ->
                        // A copy: the decoder keeps writing into `peaks` while the message is in flight.
                        AudioEditProgressBridge.reportWaveformChunk(
                            opId, from, peaks.size, peaksPerSecond, peaks.copyOfRange(from, to),
                        )
                    },
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
     * Args: see [parseEditExportArgs], plus optionally
     * `compressBitratePerChannel` (re-encode to AAC at that bitrate per channel
     * instead of copying; the output is then always `.m4a`).
     */
    fun handleExport(call: MethodCall, result: MethodChannel.Result) {
        val args = parseEditExportArgs(call, result) ?: return
        val volId = args.volId
        val opId = args.opId
        val outputPaths = args.outputPaths
        val compressBitratePerChannel = call.argument<Number>("compressBitratePerChannel")?.toInt()
        val groups = args.groups { startUs, endUs -> LosslessAudioCutter.Range(startUs, endUs) }

        ioExecutor.execute {
            // A compress export decodes and re-encodes the whole selection, which for a multi-hour
            // recording takes longer than a stream copy, so it gets a longer (still bounded) timeout.
            val wakeLockMs = if (compressBitratePerChannel != null) 60 * 60 * 1000L else 15 * 60 * 1000L
            val wakeLock = EditExportSupport.acquireWakeLock(activity, "VaultExplorer:AudioExport", wakeLockMs)
            val tempFiles = ArrayList<File>()
            // Outputs created so far (successfully or not) -- rolled back if the export fails or is cancelled.
            val created = ArrayList<String>()
            try {
                EditExportSupport.checkFreeSpace(activity.cacheDir, args)

                val factory = extractorFactory(volId, args.filePath, args.isLocal)
                val sourceExtension = extensionOf(args.filePath)

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
                        compressBitratePerChannel = compressBitratePerChannel,
                    )

                    if (AudioEditCancellation.isCancelled(opId)) {
                        throw LosslessAudioCutter.CutCancelledException()
                    }
                    AudioEditProgressBridge.reportProgress(opId, i, groups.size, "saving", 0f)

                    val dest = outputPaths[i]
                    created.add(dest)
                    if (!EditExportSupport.saveOutput(args, temp, dest, TAG)) {
                        throw IOException("Could not save the cut audio (is there enough free space?)")
                    }

                    // Wipe right away: don't keep a plaintext copy around between outputs.
                    SecureFileWipe.secureDeleteFile(temp)
                    AudioEditProgressBridge.reportProgress(opId, i, groups.size, "saving", 1f)
                }

                val payload = hashMapOf<String, Any?>("outputPaths" to outputPaths)
                activity.runOnUiThread { result.success(payload) }
            } catch (e: Exception) {
                EditExportSupport.rollBack(args, created)
                EditExportSupport.replyFailure(
                    activity, result, e,
                    cancelled = e is LosslessAudioCutter.CutCancelledException,
                    tag = TAG, logMessage = "audioEditExport failed",
                )
            } finally {
                tempFiles.forEach { SecureFileWipe.secureDeleteFile(it) }
                AudioEditCancellation.clear(opId)
                EditExportSupport.releaseWakeLock(wakeLock)
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
