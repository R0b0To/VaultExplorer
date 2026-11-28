package com.aeidolon.vaultexplorer.handlers

import android.graphics.Bitmap
import android.net.Uri
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.content.pm.PackageManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.view.PixelCopy
import android.view.Surface
import androidx.exifinterface.media.ExifInterface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.common.C
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import com.aeidolon.vaultexplorer.DocumentId
import com.aeidolon.vaultexplorer.container.ContainerDocumentsProvider
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.container.ContainerInputStream
import com.aeidolon.vaultexplorer.container.ContainerMediaDataSource
import com.aeidolon.vaultexplorer.container.VideoThumbnailCoordinator
import com.aeidolon.vaultexplorer.ImageDecodeGuard
import com.aeidolon.vaultexplorer.JpegDcPreview
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.PerfLog
import com.aeidolon.vaultexplorer.VeLog

class ThumbnailHandlers(
    private val activity: MainActivity,
    private val imageExecutor: ExecutorService,
    private val videoExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    /**
     * Serialises access to the hardware video decoder between thumbnail
     * extraction ([extractVideoFrame]) and ExoPlayer playback — and, via
     * [VideoThumbnailCoordinator], with the SAF pipeline's thumbnail
     * extraction too (see that object's doc comment for why the two
     * pipelines need to share one lock).
     *
     * - Thumbnail extraction holds the lock for the duration of
     *   `MediaMetadataRetriever.getScaledFrameAtTime` / `getFrameAtTime` —
     *   which, for a file backed by a slow cloud SAF provider, includes
     *   whatever `readAt()` I/O that requires, not just actual decoder use.
     * - [handleSetPlaybackActive] probes the lock, on its own dedicated
     *   [VideoThumbnailCoordinator.playbackGateExecutor] thread, with a
     *   bounded [DECODER_GATE_TIMEOUT_MS] timeout rather than blocking
     *   indefinitely — see that method's doc comment for why an unbounded
     *   wait here used to be able to freeze opening a video for as long as
     *   an unrelated in-flight cloud thumbnail pull took.
     *
     * The lock is fair so waiters are served in FIFO order, preventing
     * starvation.
     */
    private val videoDecoderLock get() = VideoThumbnailCoordinator.videoDecoderLock

    private var isPlaybackActive: Boolean
        get() = VideoThumbnailCoordinator.isPlaybackActive
        set(value) { VideoThumbnailCoordinator.isPlaybackActive = value }

    companion object {
        private const val TAG = "ThumbnailHandlers"
        /** Fallback target dimension when the primary extraction fails due to
         *  hardware decoder resource exhaustion. 180px is small enough that
         *  most SoCs will route to a software decoder path. */
        private const val FALLBACK_TARGET_SIZE = 180

        /**
         * Max time [handleSetPlaybackActive] waits for an in-flight
         * thumbnail decode to release [VideoThumbnailCoordinator.videoDecoderLock]
         * before giving up and letting ExoPlayer proceed anyway.
         *
         * A well-behaved decode against local/already-mirrored storage
         * finishes in well under this. A decode against a slow cloud SAF
         * provider can instead be stuck for tens of seconds inside
         * `readAt()` waiting on network I/O — see the `ContainerMediaAccess`
         * doc comments and `MirrorSyncCoordinator` — and that has nothing
         * to do with actually holding the hardware decoder. This bound
         * exists so a stalled cloud pull can delay, but never freeze,
         * opening the video the user actually tapped on. If we do give up
         * early, worst case is a brief window where ExoPlayer and the
         * straggling decode both want the hardware decoder at once —
         * `isCodecResourceError`'s software-decoder fallback already
         * handles that contention; it's a far better outcome than a
         * multi-second frozen tap.
         */
        private const val DECODER_GATE_TIMEOUT_MS = 1500L

        /**
         * How long [extractVideoFrameExoPlayer] waits, after seeking away
         * from a blank frame at time 0, before capturing the surface again.
         *
         * There's no second [Player.Listener.onRenderedFirstFrame] to hook
         * this to -- that callback fires once per surface/stream, not once
         * per seek -- so this is a fixed wait rather than an event, long
         * enough for a same-stream seek to actually decode and render the
         * new position first.
         */
        private const val EXOPLAYER_BLANK_RETRY_DELAY_MS = 200L

        /** Starting quality for [handleEncodeImage] when the caller sends none. */
        private const val ENCODE_DEFAULT_QUALITY = 92

        /**
         * Lowest quality [handleEncodeImage] will fall back to while trying to
         * meet a `maxBytes` budget. Below this, JPEG/WebP artefacts on a
         * photo become obvious, so a budget that can't be met by here is
         * simply missed rather than trading away more quality.
         */
        private const val ENCODE_MIN_QUALITY = 60

        /** Quality decrement between [handleEncodeImage] retries. */
        private const val ENCODE_QUALITY_STEP = 8
    }

    /**
     * Called from Flutter when video playback starts or stops.
     *
     * When `active = true`:
     *  1. Sets the volatile flag so any *new* thumbnail extraction bails
     *     out immediately (or routes to the software decoder path).
     *  2. Purges queued (not-yet-started) thumbnail tasks from
     *     [videoExecutor].
     *  3. Probes [videoDecoderLock] with a bounded [DECODER_GATE_TIMEOUT_MS]
     *     timeout, on [VideoThumbnailCoordinator.playbackGateExecutor] —
     *     **not** [videoExecutor]. Using a dedicated single-thread pool
     *     here (rather than queueing behind whatever is currently running
     *     on videoExecutor) is what actually makes the timeout meaningful:
     *     if this probe were queued on videoExecutor, it couldn't even
     *     start running — let alone time out — until a slow, I/O-stuck
     *     in-flight thumbnail decode vacated that thread, which on a slow
     *     cloud provider can take tens of seconds or more.
     *  4. Whether the lock was acquired or the wait timed out, returns
     *     `success(null)` to Flutter promptly either way.
     *
     * When `active = false`:
     *  1. Clears the flag so thumbnail extraction can resume.
     */
    fun handleSetPlaybackActive(call: MethodCall, result: MethodChannel.Result) {
        val active = call.argument<Boolean>("active") ?: false
        if (active) {
            isPlaybackActive = true
            // Purge any queued thumbnail tasks that haven't started yet.
            runCatching {
                (videoExecutor as? java.util.concurrent.ThreadPoolExecutor)?.queue?.clear()
            }
            VideoThumbnailCoordinator.playbackGateExecutor.execute {
                val acquired = try {
                    videoDecoderLock.tryLock(DECODER_GATE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                    false
                }
                if (acquired) {
                    try {
                        VeLog.d(TAG) { "Playback active: hardware decoder is now free for ExoPlayer" }
                    } finally {
                        videoDecoderLock.unlock()
                    }
                } else {
                    // Gave up waiting. Almost certainly an in-flight decode
                    // stuck on slow cloud I/O rather than genuinely still
                    // using the decoder -- isPlaybackActive is already
                    // true, so it will release the lock (and back off from
                    // any further hardware-decoder use) as soon as its I/O
                    // completes. We just won't make the user's tap wait on it.
                    VeLog.w(TAG) {
                        "Playback active: gave up waiting for decoder lock after " +
                            "${DECODER_GATE_TIMEOUT_MS}ms (likely a slow/cloud thumbnail decode in flight); proceeding anyway"
                    }
                }
                activity.runOnUiThread { result.success(null) }
            }
        } else {
            isPlaybackActive = false
            VeLog.d(TAG) { "Playback inactive, thumbnail extraction may resume" }
            result.success(null)
        }
    }

    // calculateInSampleSize, scaledToFit, isCodecResourceError, and
    // findSoftwareDecoderName now live on [VideoThumbnailCoordinator],
    // shared with the SAF thumbnail pipeline in ContainerDocumentsProvider
    // (each used to have its own copy). Small `private fun` forwarders
    // are kept below so every existing call site in this file is
    // unchanged.
    private fun calculateInSampleSize(width: Int, height: Int, targetSize: Int): Int =
        VideoThumbnailCoordinator.calculateInSampleSize(width, height, targetSize)

    private fun scaledToFit(src: Bitmap, maxEdge: Int): Bitmap =
        VideoThumbnailCoordinator.scaledToFit(src, maxEdge)

    private fun isCodecResourceError(e: Throwable): Boolean =
        VideoThumbnailCoordinator.isCodecResourceError(e)



    private fun extractVideoFrameExoPlayer(
        uriString: String,
        fileName: String,
        volId: Int,
        targetSize: Int,
        quality: Int,
        isLocalStorage: Boolean = false,
        localFile: java.io.File? = null,
        explicitTimeUs: Long? = null,
        strategy: String = "hybrid",
        framePosition: Double = 0.12,
    ): VideoFrameResult? {
        val latch = CountDownLatch(1)
        var extractedBitmap: Bitmap? = null
        var srcWidth = 0
        var srcHeight = 0
        var dstW = targetSize
        var dstH = targetSize

        activity.runOnUiThread {
            var player: ExoPlayer? = null
            var surface: Surface? = null
            var surfaceTexture: SurfaceTexture? = null
            var released = false

            try {
                surfaceTexture = SurfaceTexture(10)
                surfaceTexture.setDefaultBufferSize(targetSize, targetSize)
                surface = Surface(surfaceTexture)

                player = ExoPlayer.Builder(activity).build()
                // A frame grab needs the video track only. Leaving audio and
                // text enabled spun up audio codecs (and their buffers) for
                // files whose audio stream is the corrupt part, which is how a
                // failed thumbnail could take the native decoder down with it.
                player.trackSelectionParameters = player.trackSelectionParameters
                    .buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                    .build()
                player.setVideoSurface(surface)

                val dataSourceFactory: DataSource.Factory = if (isLocalStorage) {
                    androidx.media3.datasource.DefaultDataSource.Factory(activity)
                } else {
                    // Adapt ContainerMediaDataSource into a Media3 DataSource
                    DataSource.Factory {
                        object : DataSource {
                            private val mediaDataSource = ContainerMediaDataSource(fileName, volId)
                            private var currentPosition: Long = 0L
                            private var openUri: android.net.Uri? = null

                            override fun addTransferListener(transferListener: TransferListener) {}

                            private var remaining: Long = C.LENGTH_UNSET.toLong()

                            override fun open(dataSpec: DataSpec): Long {
                                openUri = dataSpec.uri
                                currentPosition = dataSpec.position
                                val totalSize = mediaDataSource.size
                                if (totalSize <= 0) {
                                    remaining = C.LENGTH_UNSET.toLong()
                                    return C.LENGTH_UNSET.toLong()
                                }
                                if (currentPosition > totalSize) {
                                    throw androidx.media3.datasource.DataSourceException(
                                        PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE
                                    )
                                }
                                remaining = totalSize - currentPosition
                                return remaining
                            }

                            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                                if (length == 0) return 0
                                if (remaining == 0L) return C.RESULT_END_OF_INPUT
                                val request = if (remaining > 0L) {
                                    minOf(length.toLong(), remaining).toInt()
                                } else {
                                    length
                                }
                                val bytesRead = mediaDataSource.readAt(currentPosition, buffer, offset, request)
                                if (bytesRead <= 0) {
                                    // Promised bytes that never arrive are a truncated
                                    // or undecryptable file, not a clean end of input.
                                    if (remaining > 0L) {
                                        throw java.io.IOException(
                                            "Vault stream ended early at $currentPosition: $fileName"
                                        )
                                    }
                                    return C.RESULT_END_OF_INPUT
                                }
                                currentPosition += bytesRead
                                if (remaining > 0L) remaining -= bytesRead
                                return bytesRead
                            }

                            override fun getUri(): android.net.Uri? = openUri

                            override fun close() {
                                runCatching { mediaDataSource.close() }
                            }
                        }
                    }
                }

                val mediaUri = if (isLocalStorage && localFile != null) {
                    android.net.Uri.fromFile(localFile)
                } else {
                    android.net.Uri.parse("file:///$fileName")
                }

                val mediaItem = MediaItem.Builder()
                    .setUri(mediaUri)
                    .apply {
                        val mime = MimeTypeHelper.getMimeType(fileName)
                        if (!mime.isNullOrEmpty()) {
                            setMimeType(mime)
                        }
                    }
                    .build()

                val extractorsFactory = androidx.media3.extractor.DefaultExtractorsFactory()
                    .setConstantBitrateSeekingEnabled(true)

                val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory, extractorsFactory)
                    .createMediaSource(mediaItem)

                player.setMediaSource(mediaSource)
                player.playWhenReady = false

                /**
                 * Captures the current surface contents and, if the result
                 * looks blank (see [VideoThumbnailCoordinator.isLikelyBlankFrame])
                 * and [allowBlankRetry] is still true, seeks forward once and
                 * tries again instead of settling for a black/white/fixed-color
                 * thumbnail. [allowBlankRetry] is only ever true on the very
                 * first call (from [Player.Listener.onRenderedFirstFrame]) so
                 * this can retry at most once.
                 */
                fun capturePixelCopy(allowBlankRetry: Boolean) {
                    // The 4s budget below releases the player and surface; a
                    // delayed capture that fires afterwards would hit a dead
                    // Surface (PixelCopy throws) on the main thread.
                    if (released || surface?.isValid != true) {
                        latch.countDown()
                        return
                    }
                    val bitmap = Bitmap.createBitmap(dstW, dstH, Bitmap.Config.ARGB_8888)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        PixelCopy.request(
                            surface,
                            bitmap,
                            { copyResult ->
                                if (copyResult == PixelCopy.SUCCESS) {
                                    val durationMs = player?.duration ?: C.TIME_UNSET
                                    val looksBlank = VideoThumbnailCoordinator.isLikelyBlankFrame(bitmap)
                                    if (allowBlankRetry && strategy == "hybrid" && explicitTimeUs == null && looksBlank && durationMs != C.TIME_UNSET && durationMs > 0) {
                                        val retryPositionMs = (durationMs * framePosition.coerceIn(0.05, 0.90))
                                            .toLong()
                                            .coerceAtLeast(1L)
                                        VeLog.d(TAG) { "ExoPlayer frame at 0 looked blank, retrying at ${retryPositionMs}ms" }
                                        bitmap.recycle()
                                        player?.seekTo(retryPositionMs)
                                        Handler(Looper.getMainLooper()).postDelayed({
                                            capturePixelCopy(allowBlankRetry = false)
                                        }, EXOPLAYER_BLANK_RETRY_DELAY_MS)
                                    } else {
                                        extractedBitmap = bitmap
                                        latch.countDown()
                                    }
                                } else {
                                    bitmap.recycle()
                                    latch.countDown()
                                }
                            },
                            Handler(Looper.getMainLooper())
                        )
                    } else {
                        latch.countDown()
                    }
                }

                player.addListener(object : Player.Listener {
                    override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
                        val w = videoSize.width
                        val h = videoSize.height
                        if (w > 0 && h > 0) {
                            val rot = videoSize.unappliedRotationDegrees
                            if (rot == 90 || rot == 270) {
                                srcWidth = h
                                srcHeight = w
                            } else {
                                srcWidth = w
                                srcHeight = h
                            }

                            // Calculate target surface bounds matching exact aspect ratio
                            val scale = targetSize.toFloat() / maxOf(srcWidth, srcHeight)
                            dstW = (srcWidth * scale).toInt().coerceAtLeast(1)
                            dstH = (srcHeight * scale).toInt().coerceAtLeast(1)

                            surfaceTexture?.setDefaultBufferSize(dstW, dstH)
                        }
                    }

                    override fun onRenderedFirstFrame() {
                        val activePlayer = player
                        val durationMs = activePlayer?.duration ?: C.TIME_UNSET
                        val seekPositionMs = explicitTimeUs?.div(1000L)
                            ?: if (strategy == "frameAtPercentage" && durationMs != C.TIME_UNSET && durationMs > 0L) {
                                (durationMs * framePosition.coerceIn(0.05, 0.90)).toLong()
                            } else 0L
                        if (seekPositionMs > 0L && activePlayer != null && activePlayer.currentPosition + 100L < seekPositionMs) {
                            activePlayer.seekTo(seekPositionMs)
                            Handler(Looper.getMainLooper()).postDelayed({
                                capturePixelCopy(allowBlankRetry = strategy == "hybrid" && explicitTimeUs == null)
                            }, EXOPLAYER_BLANK_RETRY_DELAY_MS)
                            return
                        }
                        capturePixelCopy(allowBlankRetry = true)
                    }

                   override fun onPlayerError(error: PlaybackException) {
                        val ext = fileName.substringAfterLast('.', "").lowercase()
                        VeLog.i("VE_PERF") {
                            "[native] thumb.vid.exo_err ext=$ext code=${error.errorCodeName} msg=${error.message} cause=${error.cause?.javaClass?.simpleName}:${error.cause?.message}"
                        }
                        latch.countDown()
                    }
                })

                player.prepare()
            } catch (e: Exception) {
                VeLog.w(TAG) { "ExoPlayer thumbnail extraction setup failed: ${e.message}" }
                latch.countDown()
            } finally {
                // 4s rather than 3s: a blank first frame costs one extra
                // EXOPLAYER_BLANK_RETRY_DELAY_MS hop (seek + re-render +
                // re-copy) on top of the original budget for preparing and
                // rendering the first frame at all.
                Thread {
                    latch.await(4, TimeUnit.SECONDS)
                    activity.runOnUiThread {
                        released = true
                        runCatching {
                            player?.release()
                            surface?.release()
                            surfaceTexture?.release()
                        }
                    }
                }.start()
            }
        }

        latch.await(4, TimeUnit.SECONDS)

        val frame = extractedBitmap ?: return null
        return compressFrame(
            frame,
            targetSize,
            quality,
            overrideSourceWidth = if (srcWidth > 0) srcWidth else null,
            overrideSourceHeight = if (srcHeight > 0) srcHeight else null,
        )
    }

    // ── Shared video frame extraction with codec-failure fallback ───────────

    /**
     * Result holder for [extractVideoFrame] — bundles the compressed JPEG
     * bytes with the *pre-scale* frame dimensions (needed by the
     * "WithSize" variant).
     */
    private data class VideoFrameResult(
        val bytes: ByteArray,
        val sourceWidth: Int,
        val sourceHeight: Int,
        val pathTag: String = "",
    )

    /**
     * Extracts a single video frame, compresses it to JPEG, and returns
     * the result.
     *
     * When [isPlaybackActive] is true, this method routes directly to an
     * explicit **Software-Only [MediaCodec]** (`c2.android.*` / `OMX.google.*`).
     * Because software codecs run on CPU without allocating hardware decoder
     * instances, thumbnails (e.g. for the carousel) can extract safely while
     * ExoPlayer plays a 4K video on the hardware decoder.
     */
     private data class RawVideoFrame(
        val bitmap: Bitmap,
        val srcWidth: Int,
        val srcHeight: Int,
    )

    private fun extractVideoFrame(
        uriString: String,
        fileName: String,
        volId: Int,
        targetSize: Int,
        quality: Int,
        isLocalStorage: Boolean = false,
        localFile: java.io.File? = null,
        explicitTimeUs: Long? = null,
        strategy: String = "hybrid",
        framePosition: Double = 0.12,
    ): VideoFrameResult? {
        if (isPlaybackActive) {
            VeLog.d(TAG) { "Playback active: attempting software MediaCodec frame extraction (len=${fileName.length})" }
            val swStart = PerfLog.begin()
            val swResult = extractVideoFrameSoftware(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile, explicitTimeUs, strategy, framePosition)
            PerfLog.end("thumb.vid.sw_codec", swStart)
            if (swResult != null) return swResult.copy(pathTag = "playback_sw")
            VeLog.d(TAG) { "Software extraction unavailable or failed while playing (len=${fileName.length})" }
            return null
        }

       var triedSwFirst = false
        var swMs = 0L
        val swTrace = SwTrace()
        if (fileName.endsWith(".webm", ignoreCase = true)) {
            triedSwFirst = true
            val swT0 = System.nanoTime()
            val swStart = PerfLog.begin()
            val swResult = extractVideoFrameSoftware(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile, explicitTimeUs, strategy, framePosition, swTrace)
            PerfLog.end("thumb.vid.sw_codec", swStart)
            swMs = (System.nanoTime() - swT0) / 1_000_000L
            if (swResult != null) {
                return swResult.copy(pathTag = "webm_sw(${swTrace.summary()},total=${swMs}ms)")
            }
        }

        var rawFrame: RawVideoFrame? = null
        var codecResourceHit = false
        var playbackStartedWhileWaiting = false
        var retrReason = "ok"
        var lockWaitMs = 0L
        var retrMs = 0L

       val retrTrace = RetrTrace()
        val lockT0 = System.nanoTime()
        val lockStart = PerfLog.begin()
      val gotImmediateLock = if (triedSwFirst) {
            videoDecoderLock.lock()
            true
        } else {
            // Wait up to 100ms for hardware decoder lock before falling back to
            // CPU software decoding, preventing catastrophic lock contention and 680ms SW decodes.
            try {
                videoDecoderLock.tryLock(100L, TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                false
            }
        }
        PerfLog.end("thumb.vid.lock_wait", lockStart)
        lockWaitMs = (System.nanoTime() - lockT0) / 1_000_000L
        if (gotImmediateLock) {
            try {
                if (isPlaybackActive) {
                    playbackStartedWhileWaiting = true
                    retrReason = "playback"
                } else {
                    val retrT0 = System.nanoTime()
                    try {
                        rawFrame = extractRetrieverRawFrame(
                            uriString, fileName, volId, targetSize, isLocalStorage, localFile, explicitTimeUs, strategy, framePosition, retrTrace,
                        )
                        if (rawFrame == null) retrReason = "null"
                    } catch (e: Exception) {
                        if (isCodecResourceError(e)) {
                            codecResourceHit = true
                            retrReason = "codec_err"
                            VeLog.w(TAG) { "Primary frame extraction hit codec resource limit, retrying at ${FALLBACK_TARGET_SIZE}p: ${e.message}" }
                            val fallbackResult = extractFrameFallback(uriString, fileName, volId, quality, isLocalStorage, localFile)
                            if (fallbackResult != null) {
                                retrMs = (System.nanoTime() - retrT0) / 1_000_000L
                                return fallbackResult.copy(pathTag = "fallback(lock=${lockWaitMs}ms,retr=${retrMs}ms,${retrTrace.summary()})")
                            }
                        } else {
                            retrReason = "err:${e.javaClass.simpleName}"
                            VeLog.w(TAG) { "Native retriever failed (len=${fileName.length}): ${e.message}" }
                        }
                    } finally {
                        retrMs = (System.nanoTime() - retrT0) / 1_000_000L
                    }
                }
            } finally {
                videoDecoderLock.unlock()
            }
        } else {
            retrReason = "lock_busy"
        }

        // Compress outside videoDecoderLock so the next video can acquire the HW decoder immediately.
        if (rawFrame != null) {
            return compressFrame(
                rawFrame.bitmap,
                targetSize,
                quality,
                overrideSourceWidth = if (rawFrame.srcWidth > 0) rawFrame.srcWidth else null,
                overrideSourceHeight = if (rawFrame.srcHeight > 0) rawFrame.srcHeight else null,
            ).copy(pathTag = "retr(lock=${lockWaitMs}ms,retr=${retrMs}ms,${retrTrace.summary()})")
        }

        // Software MediaCodec path (c2.android.* / OMX.google.*): handles 4K VP9/AV1
        // and busy HW lock overflow in parallel across CPU cores without blocking on videoDecoderLock.
       if (!triedSwFirst) {
            triedSwFirst = true
            val swT0 = System.nanoTime()
            val swStart = PerfLog.begin()
            val swResult = extractVideoFrameSoftware(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile, explicitTimeUs, strategy, framePosition, swTrace)
            PerfLog.end("thumb.vid.sw_codec", swStart)
            swMs = (System.nanoTime() - swT0) / 1_000_000L
            if (swResult != null) {
                return swResult.copy(pathTag = "retr_$retrReason->sw(lock=${lockWaitMs}ms,retr=${retrMs}ms,${retrTrace.summary()},${swTrace.summary()},sw=${swMs}ms)")
            }
        }

        if (playbackStartedWhileWaiting || isPlaybackActive || codecResourceHit) {
            return null
        }

        if (retrReason == "lock_busy") {
            val lock2T0 = System.nanoTime()
            val lock2Start = PerfLog.begin()
            videoDecoderLock.lock()
            PerfLog.end("thumb.vid.lock_wait", lock2Start)
            lockWaitMs += (System.nanoTime() - lock2T0) / 1_000_000L
            try {
                if (isPlaybackActive) {
                    playbackStartedWhileWaiting = true
                    retrReason = "playback"
                } else {
                    val retrT0 = System.nanoTime()
                    try {
                        rawFrame = extractRetrieverRawFrame(
                            uriString, fileName, volId, targetSize, isLocalStorage, localFile, explicitTimeUs, strategy, framePosition, retrTrace,
                        )
                        if (rawFrame == null) retrReason = "null"
                    } catch (e: Exception) {
                        if (isCodecResourceError(e)) {
                            codecResourceHit = true
                            retrReason = "codec_err"
                            val fallbackResult = extractFrameFallback(uriString, fileName, volId, quality, isLocalStorage, localFile)
                            if (fallbackResult != null) {
                                retrMs = (System.nanoTime() - retrT0) / 1_000_000L
                                return fallbackResult.copy(pathTag = "fallback(lock=${lockWaitMs}ms,retr=${retrMs}ms,${retrTrace.summary()})")
                            }
                        } else {
                            retrReason = "err:${e.javaClass.simpleName}"
                        }
                    } finally {
                        retrMs = (System.nanoTime() - retrT0) / 1_000_000L
                    }
                }
            } finally {
                videoDecoderLock.unlock()
            }
            if (rawFrame != null) {
                return compressFrame(
                    rawFrame.bitmap,
                    targetSize,
                    quality,
                    overrideSourceWidth = if (rawFrame.srcWidth > 0) rawFrame.srcWidth else null,
                    overrideSourceHeight = if (rawFrame.srcHeight > 0) rawFrame.srcHeight else null,
                ).copy(pathTag = "sw_null->retr(lock=${lockWaitMs}ms,retr=${retrMs}ms,${retrTrace.summary()},sw=${swMs}ms)")
            }
            if (playbackStartedWhileWaiting || isPlaybackActive || codecResourceHit) {
                return null
            }
        }

        // Final fallback: ExoPlayer (for containers MediaMetadataRetriever/MediaExtractor don't demux).
        val exoLockStart = PerfLog.begin()
        videoDecoderLock.lock()
        PerfLog.end("thumb.vid.lock_wait", exoLockStart)
        return try {
            if (isPlaybackActive) {
                null
            } else {
                val exoStart = PerfLog.begin()
                val exoResult = extractVideoFrameExoPlayer(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile, explicitTimeUs, strategy, framePosition)
                PerfLog.end("thumb.vid.exoplayer", exoStart)
                exoResult?.copy(pathTag = "retr_$retrReason->exo(lock=${lockWaitMs}ms,retr=${retrMs}ms,sw=${swMs}ms)")
            }
        } finally {
            videoDecoderLock.unlock()
        }
    }

  private class RetrTrace {
        var dsMs: Long = 0L
        var c1Ms: Long = 0L
        var c2Ms: Long = 0L
        var c3Ms: Long = 0L
        var hit: String = "none"
        fun summary(): String = "ds=${dsMs}ms,c1=${c1Ms}ms,c2=${c2Ms}ms,c3=${c3Ms}ms,hit=$hit"
    }

    private class SwTrace {
        var dsMs: Long = 0L
        var cfgMs: Long = 0L
        var decMs: Long = 0L
        var blankMs: Long = 0L
        var rotMs: Long = 0L
        fun summary(): String = "ds=${dsMs}ms,cfg=${cfgMs}ms,dec=${decMs}ms,blk=${blankMs}ms,rot=${rotMs}ms"
    }

    /** Runs [MediaMetadataRetriever] while the caller holds [videoDecoderLock]. */
    private fun extractRetrieverRawFrame(
        uriString: String,
        fileName: String,
        volId: Int,
        targetSize: Int,
        isLocalStorage: Boolean = false,
        localFile: java.io.File? = null,
        explicitTimeUs: Long? = null,
        strategy: String = "hybrid",
        framePosition: Double = 0.12,
        trace: RetrTrace? = null,
    ): RawVideoFrame? {
        var retriever: MediaMetadataRetriever? = null
        try {
            retriever = MediaMetadataRetriever()
            val dsT0 = System.nanoTime()
            if (isLocalStorage && localFile != null) {
                retriever.setDataSource(localFile.absolutePath)
            } else {
                val dataSource = ContainerMediaDataSource(fileName, volId)
                retriever.setDataSource(dataSource)
            }
            trace?.dsMs = (System.nanoTime() - dsT0) / 1_000_000L

            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 10_000L
            val durationUs = durationMs * 1000L
            val timeUs = explicitTimeUs ?: when (strategy) {
                "firstFrame", "hybrid" -> 0L
                "frameAtPercentage" -> (durationUs * framePosition.coerceIn(0.05, 0.90)).toLong()
                else -> 0L
            }

            val metaW = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val metaH = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0

            val srcWidth = if (rot == 90 || rot == 270) metaH ?: 0 else metaW ?: 0
            val srcHeight = if (rot == 90 || rot == 270) metaW ?: 0 else metaH ?: 0

              val retrStart = PerfLog.begin()
            var frame = tryExtractFrame(retriever, timeUs, targetSize, trace)
            PerfLog.end("thumb.vid.retriever", retrStart)

            // Only retry alternate timestamps when the retriever decoded a real
            // (but blank) frame; if it returned null, let software/ExoPlayer handle it
            // instead of burning 9 more failing retriever calls.
            if (frame != null && explicitTimeUs == null && strategy == "hybrid" &&
                VideoThumbnailCoordinator.isLikelyBlankFrame(frame)
            ) {
                val blankStart = PerfLog.begin()
                val alternate = tryAlternateFrameIfBlank(retriever, durationMs, targetSize, framePosition)
                PerfLog.end("thumb.vid.blank_retry", blankStart)
                if (alternate != null) {
                    frame.recycle()
                    frame = alternate
                }
            }
            return frame?.let { RawVideoFrame(it, srcWidth, srcHeight) }
        } finally {
            runCatching { retriever?.release() }
        }
    }

    /**
     * Attempts frame extraction at [FALLBACK_TARGET_SIZE] with a fresh
     * [MediaMetadataRetriever]. Returns null on any failure — the caller
     * will surface the appropriate error to Flutter.
     */
    private fun extractFrameFallback(
        uriString: String,
        fileName: String,
        volId: Int,
        quality: Int,
        isLocalStorage: Boolean = false,
        localFile: java.io.File? = null,
    ): VideoFrameResult? {
        var fallbackRetriever: MediaMetadataRetriever? = null
        try {
            fallbackRetriever = MediaMetadataRetriever()
            if (isLocalStorage && localFile != null) {
                fallbackRetriever.setDataSource(localFile.absolutePath)
            } else {
                val dataSource = ContainerMediaDataSource(fileName, volId)
                fallbackRetriever.setDataSource(dataSource)
            }

            val durationMs = fallbackRetriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 10_000L
            val durationUs = durationMs * 1000L
            val timeUs = VideoThumbnailCoordinator.getInitialThumbnailTimeUs(durationUs)

            var frame = tryExtractFrame(fallbackRetriever, timeUs, FALLBACK_TARGET_SIZE)
            if (frame != null && VideoThumbnailCoordinator.isLikelyBlankFrame(frame)) {
                val alternate = tryAlternateFrameIfBlank(fallbackRetriever, durationMs, FALLBACK_TARGET_SIZE)
                if (alternate != null) {
                    frame.recycle()
                    frame = alternate
                }
            }
            if (frame != null) {
                return compressFrame(frame, FALLBACK_TARGET_SIZE, quality)
            }
            return null
        } catch (e2: Exception) {
            VeLog.e(TAG) { "Fallback frame extraction also failed: ${e2.message}" }
            return null
        } finally {
            runCatching { fallbackRetriever?.release() }
        }
    }

   /** Attempts [getScaledFrameAtTime] with [OPTION_PREVIOUS_SYNC] and RGB_565 for speed. */
    private fun tryExtractFrame(
        retriever: MediaMetadataRetriever,
        timeUs: Long,
        size: Int,
        trace: RetrTrace? = null,
    ): Bitmap? {
        val option = MediaMetadataRetriever.OPTION_PREVIOUS_SYNC
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val params = MediaMetadataRetriever.BitmapParams().apply {
                preferredConfig = Bitmap.Config.RGB_565
            }
           val t1 = System.nanoTime()
            var threw = false
            val f1 = try {
                retriever.getScaledFrameAtTime(timeUs, option, size, size, params)
            } catch (_: Throwable) {
                threw = true
                null
            }
            if (trace != null && trace.hit == "none") trace.c1Ms = (System.nanoTime() - t1) / 1_000_000L
            if (f1 != null) {
                if (trace != null && trace.hit == "none") trace.hit = "c1"
                return f1
            }
            if (!threw) {
                if (trace != null && trace.hit == "none") trace.hit = "null"
                return null
            }

            val t3 = System.nanoTime()
            val f3 = runCatching { retriever.getFrameAtTime(timeUs, option) }.getOrNull()
            if (trace != null && trace.hit == "none") {
                trace.c3Ms = (System.nanoTime() - t3) / 1_000_000L
                trace.hit = if (f3 != null) "c3" else "null"
            }
            f3
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            runCatching {
                retriever.getScaledFrameAtTime(
                    timeUs,
                    option,
                    size,
                    size,
                )
            }.getOrNull()
                ?: retriever.getFrameAtTime(timeUs, option)
        } else {
            retriever.getFrameAtTime(timeUs, option)
        }
    }

    /**
     * Called when the frame at the primary timestamp looked blank (see
     * [VideoThumbnailCoordinator.isLikelyBlankFrame]) -- retries at a
     * couple of later points in the video (
     * [VideoThumbnailCoordinator.BLANK_FRAME_RETRY_FRACTIONS]), stopping
     * at the first one that doesn't also look blank. Reuses [retriever]
     * rather than opening a new one, but each retry is still a real
     * seek+decode -- same cost as the primary attempt on a slow
     * cloud-backed volume -- which is why the fraction list stays short.
     *
     * Returns null (caller keeps its original blank frame -- still a
     * valid thumbnail, just not a great one) if every retry also looks
     * blank, fails to decode, or the video is too short to have a
     * meaningfully later point.
     */
    private fun tryAlternateFrameIfBlank(
        retriever: MediaMetadataRetriever,
        durationMs: Long,
        targetSize: Int,
        preferredPosition: Double = 0.12,
    ): Bitmap? {
        val durationUs = durationMs * 1000L
        if (durationUs <= 0L) return null
        val fractions = (listOf(preferredPosition.coerceIn(0.05, 0.90)) + VideoThumbnailCoordinator.BLANK_FRAME_RETRY_FRACTIONS.toList()).distinct()
        for (fraction in fractions) {
            val candidateUs = (durationUs * fraction).toLong()
            if (candidateUs <= 0L) continue
            val candidate = runCatching { tryExtractFrame(retriever, candidateUs, targetSize) }.getOrNull()
                ?: continue
            if (!VideoThumbnailCoordinator.isLikelyBlankFrame(candidate)) {
                VeLog.d(TAG) { "Blank frame at time 0 replaced with frame at ${(fraction * 100).toInt()}% of duration" }
                return candidate
            }
            candidate.recycle()
        }
        return null
    }

    /** Scales the frame, compresses to JPEG, recycles bitmaps, returns result. */
    private fun compressFrame(
        frame: Bitmap,
        targetSize: Int,
        quality: Int,
        overrideSourceWidth: Int? = null,
        overrideSourceHeight: Int? = null,
    ): VideoFrameResult {
        val sourceWidth = overrideSourceWidth ?: frame.width
        val sourceHeight = overrideSourceHeight ?: frame.height
        val scaledFrame = scaledToFit(frame, targetSize)
        val stream = ByteArrayOutputStream(32768)
        scaledFrame.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), stream)
        val bytes = stream.toByteArray()
        if (scaledFrame != frame) scaledFrame.recycle()
        frame.recycle()
        return VideoFrameResult(bytes, sourceWidth, sourceHeight)
    }
    // ── Public handlers ─────────────────────────────────────────────────────

    /** Shared body for [handleGetVideoThumbnail] and
     *  [handleGetVideoThumbnailWithSize] (TD-15) — arg parsing, volume
     *  resolution, the OS-version gate, frame extraction, and error
     *  dispatch were previously copy-pasted between the two handlers with
     *  only the success payload differing. That's now the one thing left
     *  to each of them, via [onFrame]. No behavior change versus the
     *  previous two independent copies. */
    private fun runVideoThumbnail(
        call: MethodCall,
        result: MethodChannel.Result,
        onFrame: (VideoFrameResult) -> Any,
    ) {
        val uriString = call.argument<String>("filePath")
        val fileName  = call.argument<String>("fileName")
        val targetSize = call.argument<Int>("targetSize") ?: 180
        val isLocalStorage = call.argument<Boolean>("isLocalStorage") ?: false
        val strategy = call.argument<String>("strategy") ?: "hybrid"
        val framePosition = call.argument<Number>("framePosition")?.toDouble() ?: 0.12
        val explicitTimeUs = call.argument<Number>("timeUs")?.toLong()

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        val enqueuedAt = PerfLog.begin()
        videoExecutor.execute {
            PerfLog.end("thumb.vid.queue_wait", enqueuedAt)
            try {
                // Guarded on isLocalStorage, not just the URI scheme: for a
                // mounted vault container, `filePath`/uriString is the
                // *container's own* URI (used below only to look up which
                // mounted volume this is, via ContainerSessionRegistry) --
                // and that's a genuine content:// URI whenever the
                // container file itself lives on SAF-accessible external
                // storage, which is the common case, not an edge case.
                // Without this guard, every video request for such a vault
                // took this branch and asked SafStorageManager to resolve
                // `fileName` as a SAF-relative child of the *container's*
                // document -- nonsensical, since the container is one
                // opaque encrypted file, not a folder containing the
                // video as a sibling -- so it always failed with
                // FRAME_FAILED. This only short-circuits here for genuine
                // raw-SAF local-storage browsing, where uriString truly is
                // the folder root fileName lives under.
                if (isLocalStorage && uriString.startsWith("content://")) {
                    val thumb = activity.safStorageManager.getThumbnail(
                        Uri.parse(uriString),
                        fileName,
                        targetSize,
                        call.argument<Int>("quality") ?: 60,
                        isVideo = true,
                        strategy = strategy,
                        framePosition = framePosition,
                        explicitTimeUs = explicitTimeUs,
                    )
                    if (thumb != null) {
                        val bytes = thumb["bytes"] as ByteArray
                        val w = thumb["width"] as Int
                        val h = thumb["height"] as Int
                        activity.runOnUiThread {
                            result.success(onFrame(VideoFrameResult(bytes, w, h)))
                        }
                    } else {
                        activity.runOnUiThread { result.error("FRAME_FAILED", "Failed to extract SAF video frame", null) }
                    }
                    return@execute
                }

                var volId = -1
                var localFile: java.io.File? = null
                if (isLocalStorage) {
                    val file = if (fileName.startsWith("/")) java.io.File(fileName) else java.io.File(uriString, fileName)
                    if (!file.exists()) {
                        activity.runOnUiThread {
                            result.error("NOT_FOUND", "Local file not found", null)
                        }
                        return@execute
                    }
                    localFile = file
                } else {
                    volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                        ?: run {
                            activity.runOnUiThread {
                                result.error("NOT_MOUNTED", "Container not mounted", null)
                            }
                            return@execute
                        }
                }

                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    activity.runOnUiThread { result.error("UNSUPPORTED_OS", "Requires Android 6.0+", null) }
                    return@execute
                }

                 val quality = call.argument<Int>("quality") ?: 60
                val runStart = PerfLog.begin()
                val frameResult = extractVideoFrame(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile, explicitTimeUs, strategy, framePosition)
                PerfLog.end("thumb.vid.run", runStart)
                if (runStart != 0L) {
                    val elapsedMs = (System.nanoTime() - runStart) / 1_000_000L
                    if (elapsedMs >= 500L || frameResult == null) {
                        val ext = fileName.substringAfterLast('.', "").lowercase()
                        VeLog.i("VE_PERF") {
                            "[native] SLOW thumb.vid ext=$ext ok=${frameResult != null} path=${frameResult?.pathTag ?: "fail"} size=${frameResult?.sourceWidth ?: 0}x${frameResult?.sourceHeight ?: 0} ${elapsedMs}ms"
                        }
                    }
                }

                if (frameResult != null) {
                    activity.runOnUiThread { result.success(onFrame(frameResult)) }
                } else {
                    activity.runOnUiThread { result.error("FRAME_FAILED", "Failed to extract frame", null) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleGetVideoThumbnail(call: MethodCall, result: MethodChannel.Result) {
        runVideoThumbnail(call, result) { frame -> frame.bytes }
    }

    /** Same extraction as [handleGetVideoThumbnail] (see [runVideoThumbnail]);
     *  the only difference is the result shape:
     *  `{"bytes": ByteArray, "width": Int, "height": Int}` using the
     *  *extracted frame's* pre-scale dimensions (there's no separate
     *  bounds-only pass for video the way there is for images — the decoded
     *  frame's own width/height, read before scaledToFit touches it, is the
     *  true source aspect ratio).
     *
     *  A second method rather than changing [handleGetVideoThumbnail]'s
     *  return type, for the same reason as [handleGetImageThumbnailWithSize]
     *  — existing byte-only callers stay untouched. */
    fun handleGetVideoThumbnailWithSize(call: MethodCall, result: MethodChannel.Result) {
        runVideoThumbnail(call, result) { frame ->
            mapOf(
                "bytes" to frame.bytes,
                "width" to frame.sourceWidth,
                "height" to frame.sourceHeight,
            )
        }
    }

    /** Outcome of [extractImageThumbnail] (TD-15) — a sealed result instead
     *  of a nullable so the two specific failure reasons that existed
     *  before this was shared (bad bounds vs. failed decode) still reach
     *  the caller with their original code/message, not a collapsed
     *  generic one. */
    private sealed class ImageThumbnailOutcome {
        data class Success(val bytes: ByteArray, val sourceWidth: Int, val sourceHeight: Int) : ImageThumbnailOutcome()
        data class Failure(val code: String, val message: String) : ImageThumbnailOutcome()
    }

    /** Reads the EXIF `Orientation` tag (defaulting to
     *  [ExifInterface.ORIENTATION_NORMAL] for images with no tag, e.g. PNG)
     *  and returns the [Matrix] needed to display the pixel data upright.
     *  Identity for the normal/undefined case so callers can skip the
     *  `createBitmap` copy entirely when nothing needs rotating. */
    private fun exifOrientationMatrix(orientation: Int): Matrix {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            // NORMAL, UNDEFINED, or anything unrecognized: no-op identity.
        }
        return matrix
    }

    /** Applies [matrix] to [src], recycling [src] once the rotated/flipped
     *  copy exists. Returns [src] unchanged (no copy, no recycle) if
     *  [matrix] is the identity -- the common case for the vast majority
     *  of photos, which already have EXIF orientation 1/Normal or no tag
     *  at all, so this stays a no-op cost for them. */
    private fun applyExifOrientation(src: Bitmap, matrix: Matrix): Bitmap {
        if (matrix.isIdentity) return src
        val rotated = Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
        if (rotated != src) src.recycle()
        return rotated
    }

   /**
     * Peeks the first 32 bytes of [stream] (must support mark/reset, e.g.
     * [BufferedInputStream]) and returns false when the format cannot hold
     * EXIF orientation (simple WebP or VP8X without the 0x08 EXIF flag, GIF,
     * BMP, PNG). Avoids letting [ExifInterface] scan megabytes of pixel data
     * to EOF and blow the stream's mark limit.
     */
    private data class ExifSniff(
        val mightHaveExif: Boolean,
        val isAnimWebp: Boolean = false,
        val hasWebpExifBit: Boolean = false,
    )

    private class StreamReadStats {
        var bytesRead: Long = 0L
        var readCalls: Int = 0
        var readNanos: Long = 0L
    }

    private class TimedInputStream(
        inner: java.io.InputStream,
        private val stats: StreamReadStats,
    ) : java.io.FilterInputStream(inner) {
        override fun read(): Int {
            val t0 = System.nanoTime()
            val b = super.read()
            stats.readNanos += System.nanoTime() - t0
            stats.readCalls++
            if (b >= 0) stats.bytesRead++
            return b
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            val t0 = System.nanoTime()
            val n = super.read(b, off, len)
            stats.readNanos += System.nanoTime() - t0
            stats.readCalls++
            if (n > 0) stats.bytesRead += n
            return n
        }

        override fun skip(n: Long): Long {
            val t0 = System.nanoTime()
            val skipped = super.skip(n)
            stats.readNanos += System.nanoTime() - t0
            stats.readCalls++
            return skipped
        }
    }

    private fun sniffExif(stream: BufferedInputStream): ExifSniff {
        stream.mark(32)
        val header = ByteArray(32)
        var read = 0
        while (read < header.size) {
            val n = stream.read(header, read, header.size - read)
            if (n <= 0) break
            read += n
        }
        stream.reset()
        if (read < 12) return ExifSniff(mightHaveExif = true)

        // GIF / BMP never have EXIF orientation.
        if (header[0] == 'G'.code.toByte() && header[1] == 'I'.code.toByte() &&
            header[2] == 'F'.code.toByte() && header[3] == '8'.code.toByte()
        ) return ExifSniff(mightHaveExif = false)
        if (header[0] == 'B'.code.toByte() && header[1] == 'M'.code.toByte()) {
            return ExifSniff(mightHaveExif = false)
        }

        // RIFF WebP: EXIF only exists in extended VP8X when flag bit 0x08 is set.
        if (header[0] == 'R'.code.toByte() && header[1] == 'I'.code.toByte() &&
            header[2] == 'F'.code.toByte() && header[3] == 'F'.code.toByte() &&
            header[8] == 'W'.code.toByte() && header[9] == 'E'.code.toByte() &&
            header[10] == 'B'.code.toByte() && header[11] == 'P'.code.toByte()
        ) {
            val isVp8x = read >= 21 &&
                header[12] == 'V'.code.toByte() && header[13] == 'P'.code.toByte() &&
                header[14] == '8'.code.toByte() && header[15] == 'X'.code.toByte()
            if (!isVp8x) return ExifSniff(mightHaveExif = false)
            val flags = header[20].toInt()
            val hasExif = (flags and 0x08) != 0
            val isAnim = (flags and 0x02) != 0
            return ExifSniff(mightHaveExif = hasExif, isAnimWebp = isAnim, hasWebpExifBit = hasExif)
        }

        // PNG: ExifInterface scans through IDAT to EOF when no eXIf chunk exists.
        if (header[0] == 0x89.toByte() && header[1] == 0x50.toByte() &&
            header[2] == 0x4E.toByte() && header[3] == 0x47.toByte() &&
            header[4] == 0x0D.toByte() && header[5] == 0x0A.toByte() &&
            header[6] == 0x1A.toByte() && header[7] == 0x0A.toByte()
        ) return ExifSniff(mightHaveExif = false)

        return ExifSniff(mightHaveExif = true)
    }

    private fun mightHaveExif(stream: BufferedInputStream): Boolean =
        sniffExif(stream).mightHaveExif

    private fun readFully(stream: java.io.InputStream, buf: ByteArray, len: Int): Boolean {
        var offset = 0
        while (offset < len) {
            val n = stream.read(buf, offset, len - offset)
            if (n <= 0) return false
            offset += n
        }
        return true
    }

    /**
     * Reads only up to the end of the first `ANMF` frame of an animated WebP
     * and patches the RIFF length + VP8X trailing-metadata flags so
     * [BitmapFactory] decodes Frame 1 from memory without draining all
     * remaining frames from a slow/encrypted stream. Returns null on any
     * unexpected layout so the caller falls back to streaming decode.
     */
    private fun readAnimatedWebpFirstFrame(
        stream: java.io.InputStream,
        maxBytes: Int = 2 * 1024 * 1024,
    ): ByteArray? {
        val fileHeader = ByteArray(12)
        if (!readFully(stream, fileHeader, 12)) return null
        if (fileHeader[0] != 'R'.code.toByte() || fileHeader[1] != 'I'.code.toByte() ||
            fileHeader[2] != 'F'.code.toByte() || fileHeader[3] != 'F'.code.toByte() ||
            fileHeader[8] != 'W'.code.toByte() || fileHeader[9] != 'E'.code.toByte() ||
            fileHeader[10] != 'B'.code.toByte() || fileHeader[11] != 'P'.code.toByte()
        ) return null

        val out = ByteArrayOutputStream(262144)
        out.write(fileHeader)

        val chunkHeader = ByteArray(8)
        val scratch = ByteArray(65536)
        var vp8xPayloadOffset = -1
        var seenExif = false
        var seenXmp = false
        var foundFirstFrame = false

        while (out.size() < maxBytes) {
            if (!readFully(stream, chunkHeader, 8)) break
            val c0 = chunkHeader[0].toInt() and 0xFF
            val c1 = chunkHeader[1].toInt() and 0xFF
            val c2 = chunkHeader[2].toInt() and 0xFF
            val c3 = chunkHeader[3].toInt() and 0xFF
            val chunkSize = (chunkHeader[4].toLong() and 0xFFL) or
                ((chunkHeader[5].toLong() and 0xFFL) shl 8) or
                ((chunkHeader[6].toLong() and 0xFFL) shl 16) or
                ((chunkHeader[7].toLong() and 0xFFL) shl 24)
            if (chunkSize < 0L || out.size().toLong() + 8L + chunkSize > maxBytes.toLong()) {
                return null
            }

            val isVp8x = c0 == 'V'.code && c1 == 'P'.code && c2 == '8'.code && c3 == 'X'.code
            val isExif = c0 == 'E'.code && c1 == 'X'.code && c2 == 'I'.code && c3 == 'F'.code
            val isXmp  = c0 == 'X'.code && c1 == 'M'.code && c2 == 'P'.code && c3 == ' '.code
            val isAnmf = c0 == 'A'.code && c1 == 'N'.code && c2 == 'M'.code && c3 == 'F'.code

            if (isVp8x && chunkSize == 10L && vp8xPayloadOffset < 0) {
                vp8xPayloadOffset = out.size() + 8
            }
            if (isExif) seenExif = true
            if (isXmp) seenXmp = true

            out.write(chunkHeader)
            var remaining = chunkSize.toInt()
            while (remaining > 0) {
                val n = stream.read(scratch, 0, minOf(scratch.size, remaining))
                if (n <= 0) return null
                out.write(scratch, 0, n)
                remaining -= n
            }
            if ((chunkSize.toInt() and 1) != 0) {
                val pad = stream.read()
                out.write(if (pad >= 0) pad else 0)
            }
            if (isAnmf) {
                foundFirstFrame = true
                break
            }
        }

        if (!foundFirstFrame) return null
        val bytes = out.toByteArray()
        val riffSize = bytes.size - 8
        bytes[4] = (riffSize and 0xFF).toByte()
        bytes[5] = ((riffSize ushr 8) and 0xFF).toByte()
        bytes[6] = ((riffSize ushr 16) and 0xFF).toByte()
        bytes[7] = ((riffSize ushr 24) and 0xFF).toByte()
        if (vp8xPayloadOffset >= 0 && vp8xPayloadOffset < bytes.size) {
            var flags = bytes[vp8xPayloadOffset].toInt()
            if (!seenExif) flags = flags and 0x08.inv()
            if (!seenXmp) flags = flags and 0x04.inv()
            bytes[vp8xPayloadOffset] = flags.toByte()
        }
        return bytes
    }

    /** Opens the stream [extractImageThumbnail] reads from: a plain
     *  [java.io.FileInputStream] for real on-disk files ([isLocalStorage],
     *  mirroring [extractVideoFrameSoftware]'s `isLocalStorage && localFile
     *  != null` bypass), or the usual decrypting [ContainerInputStream]
     *  otherwise. Always wrapped in the same 64 KB [BufferedInputStream]
     *  either way, since callers rely on mark()/reset() being available. */
    private fun openRawImageInputStream(
        uriString: String,
        fileName: String,
        volId: Int,
        isLocalStorage: Boolean,
        localFile: java.io.File?,
    ): java.io.InputStream = if (isLocalStorage && localFile != null) {
        java.io.FileInputStream(localFile)
    } else {
        ContainerInputStream(fileName, volId).apply { mark(0) }
    }

    private fun imageBufferSize(isLocalStorage: Boolean, localFile: java.io.File?): Int = 65536

    private fun openImageInputStream(
        uriString: String,
        fileName: String,
        volId: Int,
        isLocalStorage: Boolean,
        localFile: java.io.File?,
        stats: StreamReadStats? = null,
    ): BufferedInputStream {
        val raw = openRawImageInputStream(uriString, fileName, volId, isLocalStorage, localFile)
        val tracked = if (stats != null) TimedInputStream(raw, stats) else raw
        return BufferedInputStream(tracked, imageBufferSize(isLocalStorage, localFile))
    }

    private fun readExactOrEof(stream: java.io.InputStream, buf: ByteArray, len: Int): Boolean {
        var off = 0
        while (off < len) {
            val n = stream.read(buf, off, len - off)
            if (n <= 0) return false
            off += n
        }
        return true
    }

    private fun skipExact(stream: java.io.InputStream, bytes: Long): Boolean {
        var remaining = bytes
        while (remaining > 0L) {
            val skipped = stream.skip(remaining)
            if (skipped > 0L) {
                remaining -= skipped
                continue
            }
            if (stream.read() < 0) return false
            remaining--
        }
        return true
    }

    /** Walks RIFF WebP chunks on an unmarked [stream] using `skip()` so pixel
     *  chunks (`VP8 `, `VP8L`, `ANMF`) are skipped without decryption, then
     *  hands only the `EXIF` chunk to [ExifInterface] inside a minimal RIFF
     *  WebP wrapper. */
    private fun readWebpExifOrientation(stream: java.io.InputStream): Int {
        val riffHeader = ByteArray(12)
        if (!readExactOrEof(stream, riffHeader, 12)) return ExifInterface.ORIENTATION_NORMAL
        if (riffHeader[0] != 'R'.code.toByte() || riffHeader[1] != 'I'.code.toByte() ||
            riffHeader[2] != 'F'.code.toByte() || riffHeader[3] != 'F'.code.toByte() ||
            riffHeader[8] != 'W'.code.toByte() || riffHeader[9] != 'E'.code.toByte() ||
            riffHeader[10] != 'B'.code.toByte() || riffHeader[11] != 'P'.code.toByte()
        ) return ExifInterface.ORIENTATION_NORMAL

        val chunkHeader = ByteArray(8)
        while (readExactOrEof(stream, chunkHeader, 8)) {
            val chunkSize = (chunkHeader[4].toLong() and 0xFFL) or
                ((chunkHeader[5].toLong() and 0xFFL) shl 8) or
                ((chunkHeader[6].toLong() and 0xFFL) shl 16) or
                ((chunkHeader[7].toLong() and 0xFFL) shl 24)
            if (chunkSize < 0L || chunkSize > 256L * 1024L * 1024L) break

            val isExif = chunkHeader[0] == 'E'.code.toByte() &&
                chunkHeader[1] == 'X'.code.toByte() &&
                chunkHeader[2] == 'I'.code.toByte() &&
                chunkHeader[3] == 'F'.code.toByte()
            if (isExif) {
                if (chunkSize < 8L || chunkSize > 512L * 1024L) {
                    return ExifInterface.ORIENTATION_NORMAL
                }
                val payloadLen = chunkSize.toInt()
                val paddedLen = payloadLen + (payloadLen and 1)
                val wrapper = ByteArray(20 + paddedLen)
                val riffPayloadLen = 12 + paddedLen
                wrapper[0] = 'R'.code.toByte(); wrapper[1] = 'I'.code.toByte()
                wrapper[2] = 'F'.code.toByte(); wrapper[3] = 'F'.code.toByte()
                wrapper[4] = (riffPayloadLen and 0xFF).toByte()
                wrapper[5] = ((riffPayloadLen ushr 8) and 0xFF).toByte()
                wrapper[6] = ((riffPayloadLen ushr 16) and 0xFF).toByte()
                wrapper[7] = ((riffPayloadLen ushr 24) and 0xFF).toByte()
                wrapper[8] = 'W'.code.toByte(); wrapper[9] = 'E'.code.toByte()
                wrapper[10] = 'B'.code.toByte(); wrapper[11] = 'P'.code.toByte()
                System.arraycopy(chunkHeader, 0, wrapper, 12, 8)
                var read = 0
                while (read < payloadLen) {
                    val n = stream.read(wrapper, 20 + read, payloadLen - read)
                    if (n <= 0) return ExifInterface.ORIENTATION_NORMAL
                    read += n
                }
                return runCatching {
                    ExifInterface(java.io.ByteArrayInputStream(wrapper)).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL,
                    )
                }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
            }

            if (!skipExact(stream, chunkSize + (chunkSize and 1L))) break
        }
        return ExifInterface.ORIENTATION_NORMAL
    }

    /**
     * Fast-path EXIF orientation reader for JPEGs.
     * Scans the APP1 segment in the first 16 KB of [stream] (must support mark/reset)
     * and extracts the TIFF IFD0 orientation tag (0x0112) without invoking
     * [ExifInterface] or scanning through megabytes of pixel data.
     * Returns null if not a JPEG, if APP1 is absent or beyond 16 KB, or if parsing fails.
     */
    private fun readJpegExifOrientation(stream: BufferedInputStream): Int? {
        val peekLimit = 16 * 1024
        stream.mark(peekLimit)
        val buf = ByteArray(peekLimit)
        var totalRead = 0
        while (totalRead < buf.size) {
            val n = stream.read(buf, totalRead, buf.size - totalRead)
            if (n <= 0) break
            totalRead += n
        }
        try {
            stream.reset()
        } catch (_: Exception) {
            return null
        }
        if (totalRead < 4) return null
        if ((buf[0].toInt() and 0xFF) != 0xFF || (buf[1].toInt() and 0xFF) != 0xD8) {
            return null
        }

        var pos = 2
        while (pos + 4 <= totalRead) {
            if ((buf[pos].toInt() and 0xFF) != 0xFF) return null
            while (pos < totalRead && (buf[pos].toInt() and 0xFF) == 0xFF) {
                pos++
            }
            if (pos >= totalRead) return null
            val marker = buf[pos++].toInt() and 0xFF
            if (marker == 0xDA || marker == 0xD9) return null

            if (pos + 2 > totalRead) return null
            val segLen = ((buf[pos].toInt() and 0xFF) shl 8) or (buf[pos + 1].toInt() and 0xFF)
            pos += 2
            val payloadLen = segLen - 2
            if (payloadLen < 0) return null

            if (marker == 0xE1) {
                if (payloadLen >= 14 && pos + payloadLen <= totalRead) {
                    if (buf[pos] == 'E'.code.toByte() &&
                        buf[pos + 1] == 'x'.code.toByte() &&
                        buf[pos + 2] == 'i'.code.toByte() &&
                        buf[pos + 3] == 'f'.code.toByte() &&
                        buf[pos + 4] == 0.toByte() &&
                        buf[pos + 5] == 0.toByte()
                    ) {
                        val tiff = pos + 6
                        val tiffLen = payloadLen - 6
                        if (tiffLen >= 8) {
                            val isLE = buf[tiff] == 'I'.code.toByte() && buf[tiff + 1] == 'I'.code.toByte()
                            val isBE = buf[tiff] == 'M'.code.toByte() && buf[tiff + 1] == 'M'.code.toByte()
                            if (isLE || isBE) {
                                val magic = if (isLE) {
                                    (buf[tiff + 2].toInt() and 0xFF) or ((buf[tiff + 3].toInt() and 0xFF) shl 8)
                                } else {
                                    ((buf[tiff + 2].toInt() and 0xFF) shl 8) or (buf[tiff + 3].toInt() and 0xFF)
                                }
                                if (magic == 42) {
                                    val ifd0Offset = if (isLE) {
                                        (buf[tiff + 4].toLong() and 0xFFL) or
                                            ((buf[tiff + 5].toLong() and 0xFFL) shl 8) or
                                            ((buf[tiff + 6].toLong() and 0xFFL) shl 16) or
                                            ((buf[tiff + 7].toLong() and 0xFFL) shl 24)
                                    } else {
                                        ((buf[tiff + 4].toLong() and 0xFFL) shl 24) or
                                            ((buf[tiff + 5].toLong() and 0xFFL) shl 16) or
                                            ((buf[tiff + 6].toLong() and 0xFFL) shl 8) or
                                            (buf[tiff + 7].toLong() and 0xFFL)
                                    }
                                    val ifd0 = tiff + ifd0Offset.toInt()
                                    if (ifd0 >= tiff && ifd0 + 2 <= pos + payloadLen) {
                                        val count = if (isLE) {
                                            (buf[ifd0].toInt() and 0xFF) or ((buf[ifd0 + 1].toInt() and 0xFF) shl 8)
                                        } else {
                                            ((buf[ifd0].toInt() and 0xFF) shl 8) or (buf[ifd0 + 1].toInt() and 0xFF)
                                        }
                                        var entryPos = ifd0 + 2
                                        for (i in 0 until count) {
                                            if (entryPos + 12 > pos + payloadLen) break
                                            val tag = if (isLE) {
                                                (buf[entryPos].toInt() and 0xFF) or ((buf[entryPos + 1].toInt() and 0xFF) shl 8)
                                            } else {
                                                ((buf[entryPos].toInt() and 0xFF) shl 8) or (buf[entryPos + 1].toInt() and 0xFF)
                                            }
                                            if (tag == 0x0112) {
                                                val orientation = if (isLE) {
                                                    (buf[entryPos + 8].toInt() and 0xFF) or ((buf[entryPos + 9].toInt() and 0xFF) shl 8)
                                                } else {
                                                    ((buf[entryPos + 8].toInt() and 0xFF) shl 8) or (buf[entryPos + 9].toInt() and 0xFF)
                                                }
                                                if (orientation in 1..8) {
                                                    return orientation
                                                }
                                            }
                                            entryPos += 12
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            pos += payloadLen
        }
        return null
    }

    /** Single-pass native scaling + EXIF orientation via API 28+ [ImageDecoder]
     *  for local files. Returns null if [ImageDecoder] cannot handle the format
     *  so the caller falls back to [BitmapFactory]. */
    private fun tryLocalImageDecoder(
        uriString: String,
        fileName: String,
        localFile: java.io.File,
        targetSize: Int,
        quality: Int,
        preserveAlpha: Boolean,
    ): ImageThumbnailOutcome? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        var rawWidth = 0
        var rawHeight = 0
        var permit: ImageDecodeGuard.Permit? = null
        var refused: ImageDecodeGuard.RefusedException? = null
        var headerCache: ByteArray? = null
        var headerMs = 0L
        var guardMs = 0L

        val decodeT0 = PerfLog.begin()
        val localWallT0 = if (VeLog.enabled) System.nanoTime() else 0L
        val decoded: Bitmap = try {
            val source = ImageDecoder.createSource(localFile)
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                rawWidth = info.size.width
                rawHeight = info.size.height
                if (rawWidth <= 0 || rawHeight <= 0) {
                    throw java.io.IOException("Failed to read image bounds")
                }
                val worstCaseBytes = rawWidth.toLong() * rawHeight.toLong() *
                    ImageDecodeGuard.WORST_CASE_BYTES_PER_PIXEL
                if (worstCaseBytes >= ImageDecodeGuard.HEAVY_ESTIMATE_BYTES) {
                    val hdrT0 = if (localWallT0 != 0L) System.nanoTime() else 0L
                    headerCache = readImageHeader(uriString, fileName, -1, true, localFile)
                    if (hdrT0 != 0L) headerMs = (System.nanoTime() - hdrT0) / 1_000_000L
                }
                val guardStart = PerfLog.begin()
                val guardT0 = if (localWallT0 != 0L) System.nanoTime() else 0L
                try {
                    permit = ImageDecodeGuard.admit(activity, rawWidth, rawHeight, headerCache)
                } catch (e: ImageDecodeGuard.RefusedException) {
                    refused = e
                    throw e
                } finally {
                    PerfLog.end("thumb.img.guard", guardStart)
                    if (guardT0 != 0L) guardMs = (System.nanoTime() - guardT0) / 1_000_000L
                }
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                if (!preserveAlpha) {
                    decoder.setMemorySizePolicy(ImageDecoder.MEMORY_POLICY_LOW_RAM)
                }
                val maxDim = maxOf(rawWidth, rawHeight)
                if (maxDim > targetSize) {
                    val scale = targetSize.toFloat() / maxDim
                    val dstW = (rawWidth * scale).toInt().coerceAtLeast(1)
                    val dstH = (rawHeight * scale).toInt().coerceAtLeast(1)
                    decoder.setTargetSize(dstW, dstH)
                }
            }
        } catch (t: Throwable) {
            PerfLog.end("thumb.img.decode", decodeT0)
            val refEx = refused ?: (t as? ImageDecodeGuard.RefusedException)
            if (refEx != null) {
                VeLog.w(TAG) { "Not fully decoding ${rawWidth}x$rawHeight image: ${refEx.message}" }
                val dcPreview = decodeProgressiveJpegDcPreview(
                    headerCache, targetSize, uriString, fileName, -1, true, localFile,
                )
                if (dcPreview != null) {
                    val orientation = runCatching {
                        ExifInterface(localFile).getAttributeInt(
                            ExifInterface.TAG_ORIENTATION,
                            ExifInterface.ORIENTATION_NORMAL,
                        )
                    }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
                    return finishThumbnail(
                        dcPreview, orientation, rawWidth, rawHeight, targetSize, quality, preserveAlpha,
                    )
                }
                return ImageThumbnailOutcome.Failure(
                    refEx.code,
                    refEx.message ?: "Image is too large to decode",
                )
            }
            if (t is OutOfMemoryError) {
                return ImageThumbnailOutcome.Failure(
                    ImageDecodeGuard.CODE_OUT_OF_MEMORY,
                    "Not enough memory to decode image",
                )
            }
            return null
        } finally {
            permit?.close()
        }
        PerfLog.end("thumb.img.decode", decodeT0)

        return try {
            val encodeStart = PerfLog.begin()
            val stream = ByteArrayOutputStream(32768)
            val format = if (preserveAlpha) {
                Bitmap.CompressFormat.WEBP
            } else {
                Bitmap.CompressFormat.JPEG
            }
            decoded.compress(format, quality.coerceIn(1, 100), stream)
            PerfLog.end("thumb.img.encode", encodeStart)
            decoded.recycle()
            val outBytes = stream.toByteArray()
            if (localWallT0 != 0L) {
                val totalLocalMs = (System.nanoTime() - localWallT0) / 1_000_000L
                if (totalLocalMs >= 150L) {
                    val ext = fileName.substringAfterLast('.', "").lowercase()
                    VeLog.i("VE_PERF") {
                        "[native] SLOW thumb.img.local ext=$ext target=$targetSize src=${rawWidth}x$rawHeight hdr=${headerMs}ms guard=${guardMs}ms total=${totalLocalMs}ms"
                    }
                }
            }
            ImageThumbnailOutcome.Success(outBytes, rawWidth, rawHeight)
        } catch (e: OutOfMemoryError) {
            decoded.recycle()
            ImageThumbnailOutcome.Failure(
                ImageDecodeGuard.CODE_OUT_OF_MEMORY,
                "Not enough memory to decode image",
            )
        }
    }

    /** First [ImageDecodeGuard.HEADER_SNIFF_BYTES] of the image, from a stream
     *  of its own, so [ImageDecodeGuard] can tell a cheap streaming decode
     *  (baseline JPEG, non-interlaced PNG) from one that needs memory
     *  proportional to the whole image. Null if it can't be read -- the guard
     *  then falls back to its worst-case assumption. */
    private fun readImageHeader(
        uriString: String,
        fileName: String,
        volId: Int,
        isLocalStorage: Boolean,
        localFile: java.io.File?,
    ): ByteArray? = try {
        openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile).use { stream ->
            val buffer = ByteArray(ImageDecodeGuard.HEADER_SNIFF_BYTES)
            var filled = 0
            while (filled < buffer.size) {
                val n = stream.read(buffer, filled, buffer.size - filled)
                if (n <= 0) break
                filled += n
            }
            if (filled == buffer.size) buffer else buffer.copyOf(filled)
        }
    } catch (e: Exception) {
        null
    }

    /** Shared body for [handleGetImageThumbnail] and
     *  [handleGetImageThumbnailWithSize] (TD-15): decode bounds, pick a
     *  sample size, decode, scale, compress, recycle — previously
     *  copy-pasted between the two handlers with only the success payload
     *  differing.
     *
     *  One deliberate behavior change while unifying: the `width <= 0 ||
     *  height <= 0` bounds-validity check previously only existed in
     *  [handleGetImageThumbnailWithSize]. [handleGetImageThumbnail] didn't
     *  have it, so a 0x0-bounds file would fall through into
     *  `calculateInSampleSize(0, 0, targetSize)` and only fail later at the
     *  null-bitmap check — same eventual "DECODE_FAILED" outcome, just
     *  later and less precisely diagnosed. Both callers now get the
     *  earlier, more precise check.
     *
     *  Also applies EXIF `Orientation` correction (see [exifOrientationMatrix]) —
     *  previously missing here, which is why a portrait phone photo's
     *  thumbnail displayed sideways (landscape sensor data, uncorrected)
     *  even though the full-res image looked correct (Flutter/Skia applies
     *  EXIF orientation itself when decoding JPEG bytes on the Dart side). */
    private fun extractImageThumbnail(
        uriString: String,
        fileName: String,
        volId: Int,
        targetSize: Int,
        quality: Int,
        isLocalStorage: Boolean = false,
        localFile: java.io.File? = null,
        preserveAlpha: Boolean = false,
    ): ImageThumbnailOutcome {
        // One stream serves the EXIF read, the bounds pass and the decode.
        // The EXIF read used to get a stream of its own, because ExifInterface
        // consumes whatever it is given; but that meant every thumbnail opened
        // the file twice (a size query, a lock acquisition, and decrypting the
        // file's first blocks all over again) and that read was measured at
        // ~4.9 ms of a ~24 ms thumbnail. The stream is a BufferedInputStream,
        // so it is rewound with reset() afterwards, exactly as it already is
        // between the bounds and decode passes below.
        //
        // If the rewind fails (ExifInterface read past the mark limit, e.g. a
        // PNG whose eXIf chunk follows its pixel data, or a large HEIF), a
        // fresh stream is opened: the same cost as before, never a wrong
        // result.
         if (isLocalStorage && localFile != null) {
            tryLocalImageDecoder(
                uriString, fileName, localFile, targetSize, quality, preserveAlpha,
            )?.let { return it }
        }

       val streamStats = StreamReadStats()
        val streamBufSize = imageBufferSize(isLocalStorage, localFile)
        val rawStream = openRawImageInputStream(uriString, fileName, volId, isLocalStorage, localFile)
        var inputStream = BufferedInputStream(TimedInputStream(rawStream, streamStats), streamBufSize)
        val exifMarkLimit = 128 * 1024
        val boundsMarkLimit = streamBufSize

        // Camera phones almost universally store portrait photos as landscape
        // sensor data plus an EXIF orientation tag -- BitmapFactory below
        // knows nothing about it and decodes the raw (landscape) pixels, so
        // skipping this step is exactly what left thumbnails sideways while
        // the full-res viewer (decoded by Flutter/Skia, which *does* apply
        // EXIF orientation for JPEG) looked correct.
        val exifStart = PerfLog.begin()
        var exifResetFailed = false
        val exifSniff = sniffExif(inputStream)
        val exifOrientation = if (exifSniff.hasWebpExifBit) {
            if (rawStream is ContainerInputStream) {
                rawStream.reset()
                val orientation = readWebpExifOrientation(TimedInputStream(rawStream, streamStats))
                rawStream.reset()
                inputStream = BufferedInputStream(TimedInputStream(rawStream, streamStats), streamBufSize)
                orientation
            } else {
                inputStream.close()
                val orientation = openRawImageInputStream(uriString, fileName, volId, isLocalStorage, localFile).use { s ->
                    readWebpExifOrientation(TimedInputStream(s, streamStats))
                }
                inputStream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile, streamStats)
                orientation
            }
        } else if (exifSniff.mightHaveExif) {
            val fastJpegOrientation = readJpegExifOrientation(inputStream)
            if (fastJpegOrientation != null) {
                fastJpegOrientation
            } else {
                inputStream.mark(exifMarkLimit)
                val orientation = runCatching {
                    ExifInterface(inputStream).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL,
                    )
                }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
                try {
                    inputStream.reset()
                } catch (e: Exception) {
                    exifResetFailed = true
                    inputStream.close()
                    inputStream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile, streamStats)
                }
                orientation
            }
        } else {
            ExifInterface.ORIENTATION_NORMAL
        }
        val exifEndNs = if (exifStart != 0L) System.nanoTime() else 0L
        val afterExifBytes = streamStats.bytesRead
        val afterExifIoNs = streamStats.readNanos
        PerfLog.end("thumb.img.exif", exifStart)
        inputStream.mark(boundsMarkLimit)

        val boundsStart = PerfLog.begin()
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeStream(inputStream, null, options)
        PerfLog.end("thumb.img.bounds", boundsStart)

        // outWidth/outHeight are the raw decoded frame's bounds, i.e.
        // *before* EXIF rotation -- this is what extractImageThumbnail has
        // always returned as the "source" size (see handleGetImageThumbnailWithSize's
        // doc comment), so a 90/270 rotation below means the thumbnail
        // bytes' actual aspect ratio no longer matches these two numbers.
        // Swap them here so callers deriving an aspect ratio from this
        // Success's width/height (MediaAspectRatioCache) see the same
        // upright ratio the thumbnail/full-res image will actually render
        // at, instead of laying out a grid tile sideways.
        val rawWidth = options.outWidth
        val rawHeight = options.outHeight

        if (rawWidth <= 0 || rawHeight <= 0) {
            inputStream.close()
            return ImageThumbnailOutcome.Failure("DECODE_FAILED", "Failed to read image bounds")
        }

        // Refuse (or serialize) decodes whose *source* is huge before touching
        // the real decoder -- see ImageDecodeGuard for why inSampleSize alone
        // doesn't bound the decoder's memory.
        //
        // The header is only worth a third stream (and up to 1 MB of
        // decryption) when even the worst-case estimate would be heavy; every
        // ordinary-sized image skips straight past it.
        val worstCaseBytes = rawWidth.toLong() * rawHeight.toLong() *
            ImageDecodeGuard.WORST_CASE_BYTES_PER_PIXEL
        val header = if (worstCaseBytes >= ImageDecodeGuard.HEAVY_ESTIMATE_BYTES) {
            readImageHeader(uriString, fileName, volId, isLocalStorage, localFile)
        } else {
            null
        }
        val guardStart = PerfLog.begin()
        val permit = try {
            ImageDecodeGuard.admit(activity, rawWidth, rawHeight, header)
        } catch (e: ImageDecodeGuard.RefusedException) {
            inputStream.close()
            VeLog.w(TAG) { "Not fully decoding ${rawWidth}x$rawHeight image: ${e.message}" }
            // A progressive JPEG too big to decode normally can still be
            // previewed from its first (DC) scan alone: 1/8 scale, from a
            // small slice of the file, in memory proportional to the output.
            val dcPreview = decodeProgressiveJpegDcPreview(
                header, targetSize, uriString, fileName, volId, isLocalStorage, localFile,
            )
            if (dcPreview != null) {
                VeLog.w(TAG) { "Using DC-scan preview (${dcPreview.width}x${dcPreview.height}) instead" }
                return finishThumbnail(
                    dcPreview, exifOrientation, rawWidth, rawHeight, targetSize, quality, preserveAlpha,
                )
            }
            return ImageThumbnailOutcome.Failure(e.code, e.message ?: "Image is too large to decode")
        }

        PerfLog.end("thumb.img.guard", guardStart)

        try {
            val inSampleSize = calculateInSampleSize(rawWidth, rawHeight, targetSize)
            fun decodeOptionsFor(sampleSize: Int) = BitmapFactory.Options().apply {
                this.inSampleSize = sampleSize
                this.inPreferredConfig = if (preserveAlpha) {
                    Bitmap.Config.ARGB_8888
                } else {
                    Bitmap.Config.RGB_565
                }
            }

            try {
                inputStream.reset()
            } catch (e: Exception) {
                inputStream.close()
                inputStream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile, streamStats)
            }

            val beforeDecodeBytes = streamStats.bytesRead
            val beforeDecodeCalls = streamStats.readCalls
            val beforeDecodeIoNs = streamStats.readNanos
            val decodeT0 = if (exifStart != 0L) System.nanoTime() else 0L
          val decodeStart = PerfLog.begin()
            val firstFrameBytes = if (exifSniff.isAnimWebp) {
                readAnimatedWebpFirstFrame(inputStream)
            } else {
                null
            }
            val decodedBitmap: Bitmap? = if (firstFrameBytes != null) {
                inputStream.close()
                try {
                    BitmapFactory.decodeByteArray(
                        firstFrameBytes,
                        0,
                        firstFrameBytes.size,
                        decodeOptionsFor(inSampleSize),
                    )
                } catch (e: OutOfMemoryError) {
                    VeLog.w(TAG) { "OOM decoding ${rawWidth}x$rawHeight at sample $inSampleSize; retrying coarser" }
                    System.gc()
                    BitmapFactory.decodeByteArray(
                        firstFrameBytes,
                        0,
                        firstFrameBytes.size,
                        decodeOptionsFor(inSampleSize * 2),
                    )
                } ?: run {
                    val fallbackStream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile, streamStats)
                    try {
                        BitmapFactory.decodeStream(fallbackStream, null, decodeOptionsFor(inSampleSize))
                    } finally {
                        fallbackStream.close()
                    }
                }
            } else {
                if (exifSniff.isAnimWebp) {
                    inputStream.close()
                    inputStream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile, streamStats)
                }
                try {
                    BitmapFactory.decodeStream(inputStream, null, decodeOptionsFor(inSampleSize))
                } catch (e: OutOfMemoryError) {
                    // One coarser retry (half the linear resolution) before giving
                    // up; a fresh stream is needed since this one is mid-decode.
                    VeLog.w(TAG) { "OOM decoding ${rawWidth}x$rawHeight at sample $inSampleSize; retrying coarser" }
                    inputStream.close()
                    System.gc()
                    val retryStream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile, streamStats)
                    try {
                        BitmapFactory.decodeStream(retryStream, null, decodeOptionsFor(inSampleSize * 2))
                    } finally {
                        retryStream.close()
                    }
                } finally {
                    inputStream.close()
                }
            }
            PerfLog.end("thumb.img.decode", decodeStart)
            val decodeT1 = if (exifStart != 0L) System.nanoTime() else 0L

            if (decodedBitmap == null) {
                return ImageThumbnailOutcome.Failure("DECODE_FAILED", "Failed to decode image bytes")
            }

            val outcome = finishThumbnail(
                decodedBitmap, exifOrientation, rawWidth, rawHeight, targetSize, quality, preserveAlpha,
            )
             if (exifStart != 0L) {
                val totalMs = (System.nanoTime() - exifStart) / 1_000_000L
                val exifMs = (exifEndNs - exifStart) / 1_000_000L
                if (exifMs >= 50L || totalMs >= 200L || exifResetFailed) {
                    val ext = fileName.substringAfterLast('.', "").lowercase()
                    val decodeTotalMs = (decodeT1 - decodeT0) / 1_000_000L
                    val decodeIoMs = (streamStats.readNanos - beforeDecodeIoNs) / 1_000_000L
                    val decodeCpuMs = (decodeTotalMs - decodeIoMs).coerceAtLeast(0L)
                    val decodeBytes = streamStats.bytesRead - beforeDecodeBytes
                    val decodeCalls = streamStats.readCalls - beforeDecodeCalls
                    val exifIoMs = afterExifIoNs / 1_000_000L
                    val totalIoMs = streamStats.readNanos / 1_000_000L
                    VeLog.i("VE_PERF") {
                        "[native] SLOW thumb.img ext=$ext target=$targetSize src=${rawWidth}x$rawHeight " +
                            "sample=$inSampleSize exif=${exifMs}ms(io=${exifIoMs}ms,${afterExifBytes}B,might=${exifSniff.mightHaveExif},anim=${exifSniff.isAnimWebp},exifBit=${exifSniff.hasWebpExifBit}) " +
                            "decode=${decodeTotalMs}ms(io=${decodeIoMs}ms,cpu=${decodeCpuMs}ms,${decodeBytes}B/${decodeCalls}c) " +
                            "ioTotal=${totalIoMs}ms/${streamStats.bytesRead}B/${streamStats.readCalls}c resetFailed=$exifResetFailed total=${totalMs}ms"
                    }
                }
            }
            return outcome
        } catch (e: OutOfMemoryError) {
            // OutOfMemoryError is an Error, not an Exception: without this it
            // sails past every `catch (e: Exception)` up the stack and kills
            // the whole app instead of just failing this one decode.
            VeLog.w(TAG) { "Out of memory decoding ${rawWidth}x$rawHeight image" }
            return ImageThumbnailOutcome.Failure(
                ImageDecodeGuard.CODE_OUT_OF_MEMORY,
                "Not enough memory to decode image",
            )
        } finally {
            permit.close()
        }
    }

    /** Orients, fits and compresses an already-decoded [decoded] bitmap into
     *  the thumbnail result. [rawWidth]/[rawHeight] are the *source* image's
     *  size (not [decoded]'s, which may be a reduced-scale decode); the
     *  reported size has them swapped for sideways EXIF orientations. */
    private fun finishThumbnail(
        decoded: Bitmap,
        exifOrientation: Int,
        rawWidth: Int,
        rawHeight: Int,
        targetSize: Int,
        quality: Int,
        preserveAlpha: Boolean,
    ): ImageThumbnailOutcome {
        val orientationMatrix = exifOrientationMatrix(exifOrientation)
        val isSideways = exifOrientation == ExifInterface.ORIENTATION_ROTATE_90 ||
            exifOrientation == ExifInterface.ORIENTATION_ROTATE_270 ||
            exifOrientation == ExifInterface.ORIENTATION_TRANSPOSE ||
            exifOrientation == ExifInterface.ORIENTATION_TRANSVERSE
        val width = if (isSideways) rawHeight else rawWidth
        val height = if (isSideways) rawWidth else rawHeight

       return try {
            val scaleStart = PerfLog.begin()
            val srcW = decoded.width
            val srcH = decoded.height
            val maxDim = maxOf(srcW, srcH)
            val needsScale = maxDim > targetSize && maxDim > 0
            val scale = if (needsScale) targetSize.toFloat() / maxDim else 1f
            val scaledBitmap = if (needsScale && (srcW * scale < 1f || srcH * scale < 1f)) {
                val fitted = scaledToFit(decoded, targetSize)
                if (fitted != decoded) decoded.recycle()
                applyExifOrientation(fitted, orientationMatrix)
            } else {
                val combined = Matrix(orientationMatrix)
                if (needsScale) combined.preScale(scale, scale)
                if (combined.isIdentity) {
                    decoded
                } else {
                    Bitmap.createBitmap(decoded, 0, 0, srcW, srcH, combined, true).also {
                        if (it != decoded) decoded.recycle()
                    }
                }
            }
            PerfLog.end("thumb.img.orient_scale", scaleStart)

            val stream = ByteArrayOutputStream(32768)
            val format = if (preserveAlpha) {
                Bitmap.CompressFormat.WEBP
            } else {
                Bitmap.CompressFormat.JPEG
            }
            val encodeStart = PerfLog.begin()
            scaledBitmap.compress(format, quality.coerceIn(1, 100), stream)
            PerfLog.end("thumb.img.encode", encodeStart)
            val bytes = stream.toByteArray()
            scaledBitmap.recycle()

            ImageThumbnailOutcome.Success(bytes, width, height)
        } catch (e: OutOfMemoryError) {
            VeLog.w(TAG) { "Out of memory finishing ${rawWidth}x$rawHeight thumbnail" }
            ImageThumbnailOutcome.Failure(
                ImageDecodeGuard.CODE_OUT_OF_MEMORY,
                "Not enough memory to decode image",
            )
        }
    }

    /** DC-scan-only preview of a progressive JPEG (see [JpegDcPreview]), as a
     *  bitmap, or null if [header] isn't a progressive JPEG or the decoder
     *  can't handle the file. */
    private fun decodeProgressiveJpegDcPreview(
        header: ByteArray?,
        targetSize: Int,
        uriString: String,
        fileName: String,
        volId: Int,
        isLocalStorage: Boolean,
        localFile: java.io.File?,
    ): Bitmap? {
        if (header == null || ImageDecodeGuard.sniffJpeg(header)?.progressive != true) return null
        return try {
            openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile).use { stream ->
                JpegDcPreview.decode(stream, targetSize)?.let { preview ->
                    Bitmap.createBitmap(preview.argb, preview.width, preview.height, Bitmap.Config.ARGB_8888)
                }
            }
        } catch (e: OutOfMemoryError) {
            VeLog.w(TAG) { "Out of memory building DC-scan preview" }
            null
        } catch (e: Exception) {
            VeLog.w(TAG) { "DC-scan preview failed: ${e.message}" }
            null
        }
    }

    private fun runImageThumbnail(
        call: MethodCall,
        result: MethodChannel.Result,
        onSuccess: (ImageThumbnailOutcome.Success) -> Any,
    ) {
        val uriString  = call.argument<String>("filePath")
        val fileName   = call.argument<String>("fileName")
        val targetSize = call.argument<Int>("targetSize") ?: 180
        val quality = call.argument<Int>("quality") ?: 70
        val isLocalStorage = call.argument<Boolean>("isLocalStorage") ?: false
        val preserveAlpha = call.argument<Boolean>("preserveAlpha") ?: false

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        val sentAtMs = call.argument<Number>("sentAtMs")?.toLong() ?: 0L
        val channelHopMs = if (VeLog.enabled && sentAtMs > 0L) {
            (System.currentTimeMillis() - sentAtMs).coerceAtLeast(0L)
        } else 0L
        val wallStartNs = if (VeLog.enabled) System.nanoTime() else 0L
        val enqueuedAt = PerfLog.begin()
        imageExecutor.execute {
            PerfLog.end("thumb.img.queue_wait", enqueuedAt)
            try {
                // Same isLocalStorage guard as runVideoThumbnail above, and
                // for the identical reason: uriString is the *container's*
                // URI for a mounted vault, not necessarily fileName's own
                // directly-openable document, so a bare content:// scheme
                // check isn't enough to say this is genuine raw-SAF
                // browsing.
                if (isLocalStorage && uriString.startsWith("content://")) {
                    val thumb = activity.safStorageManager.getThumbnail(
                        Uri.parse(uriString),
                        fileName,
                        targetSize,
                        quality,
                        isVideo = false,
                        preserveAlpha = preserveAlpha,
                    )
                    if (thumb != null) {
                        val bytes = thumb["bytes"] as ByteArray
                        val w = thumb["width"] as Int
                        val h = thumb["height"] as Int
                        activity.runOnUiThread {
                            result.success(onSuccess(ImageThumbnailOutcome.Success(bytes, w, h)))
                        }
                    } else {
                        activity.runOnUiThread { result.error("DECODE_FAILED", "Failed to extract SAF image thumbnail", null) }
                    }
                    return@execute
                }

                var volId = -1
                var localFile: java.io.File? = null
                if (isLocalStorage) {
                    val file = if (fileName.startsWith("/")) java.io.File(fileName) else java.io.File(uriString, fileName)
                    if (!file.exists()) {
                        activity.runOnUiThread {
                            result.error("NOT_FOUND", "Local file not found", null)
                        }
                        return@execute
                    }
                    localFile = file
                } else {
                    volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                        ?: run {
                            activity.runOnUiThread { result.error("NOT_MOUNTED", "Container not mounted", null) }
                            return@execute
                        }
                }

                val preRunMs = if (wallStartNs != 0L) (System.nanoTime() - wallStartNs) / 1_000_000L else 0L
                val runStart = PerfLog.begin()
                val extracted = extractImageThumbnail(
                    uriString,
                    fileName,
                    volId,
                    targetSize,
                    quality,
                    isLocalStorage,
                    localFile,
                    preserveAlpha,
                )
                PerfLog.end("thumb.img.run", runStart)
                val postStartNs = if (wallStartNs != 0L) System.nanoTime() else 0L
                val runMs = if (wallStartNs != 0L) (postStartNs - wallStartNs) / 1_000_000L - preRunMs else 0L
                when (val outcome = extracted) {
                    is ImageThumbnailOutcome.Success ->
                        activity.runOnUiThread {
                            if (postStartNs != 0L) {
                                val totalMs = (System.nanoTime() - wallStartNs) / 1_000_000L
                                if (totalMs >= 250L || channelHopMs >= 100L) {
                                    val uiDelayMs = (System.nanoTime() - postStartNs) / 1_000_000L
                                    val ext = fileName.substringAfterLast('.', "").lowercase()
                                    VeLog.i("VE_PERF") {
                                        "[native] SLOW thumb.img.wall ext=$ext local=$isLocalStorage target=$targetSize hop=${channelHopMs}ms pre=${preRunMs}ms run=${runMs}ms ui=${uiDelayMs}ms total=${totalMs}ms"
                                    }
                                }
                            }
                            result.success(onSuccess(outcome))
                        }
                    is ImageThumbnailOutcome.Failure ->
                        activity.runOnUiThread { result.error(outcome.code, outcome.message, null) }
                }
            } catch (e: OutOfMemoryError) {
                // Backstop for anything outside extractImageThumbnail (EXIF
                // read, the SAF thumbnail path, ...): fail this request, not
                // the process.
                VeLog.w(TAG) { "Image thumbnail request ran out of memory" }
                activity.runOnUiThread {
                    result.error(ImageDecodeGuard.CODE_OUT_OF_MEMORY, "Not enough memory to decode image", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleGetImageThumbnail(call: MethodCall, result: MethodChannel.Result) {
        runImageThumbnail(call, result) { outcome -> outcome.bytes }
    }

    /** Same extraction as [handleGetImageThumbnail] (see
     *  [extractImageThumbnail]/[runImageThumbnail]); the only difference is
     *  the result shape: `{"bytes": ByteArray, "width": Int, "height": Int}`
     *  instead of a bare `ByteArray`. `width`/`height` are the *source*
     *  frame's bounds (from the `inJustDecodeBounds` pass that already runs
     *  to pick `inSampleSize`) — i.e. the true content aspect ratio, not the
     *  downscaled thumbnail's own dimensions (though scaledToFit preserves
     *  the ratio, so they agree up to rounding).
     *
     *  A second method rather than changing [handleGetImageThumbnail]'s
     *  return type, so the four existing callers that only want bytes
     *  (file grid, media viewer, playlist carousel) are unaffected. */
    fun handleGetImageThumbnailWithSize(call: MethodCall, result: MethodChannel.Result) {
        runImageThumbnail(call, result) { outcome ->
            mapOf(
                "bytes" to outcome.bytes,
                "width" to outcome.sourceWidth,
                "height" to outcome.sourceHeight,
            )
        }
    }

    /**
     * Header-only dimension probe for a *batch* of images, so the gallery can
     * lay a folder out with the right tile shapes before a single thumbnail
     * has been decoded.
     *
     * Reads only what [BitmapFactory]'s bounds pass and [ExifInterface] need
     * (a few KB per file, decrypted on the fly) -- no pixel decode, no
     * thumbnail, nothing cached or written anywhere. The result is
     * `[w0, h0, w1, h1, ...]`, one pair per requested name in the same order,
     * with `0, 0` for a file whose size could not be read (not an image this
     * device can parse, unreadable, or SAF-backed browsing, which has no
     * stream to open from here). Sizes are the *upright* ones: swapped when
     * the EXIF orientation turns the image sideways, exactly as
     * [finishThumbnail] reports them, so a tile is never laid out sideways.
     *
     * One executor task per batch (the caller sends modest batches and keeps
     * at most one in flight) so a large folder cannot flood [imageExecutor]
     * ahead of the thumbnail requests that are actually on screen.
     */
    fun handleProbeImageDimensions(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val fileNames = call.argument<List<String>>("fileNames")
        val isLocalStorage = call.argument<Boolean>("isLocalStorage") ?: false

        if (uriString == null || fileNames == null) {
            result.error("INVALID_ARGS", "filePath and fileNames required", null)
            return
        }

       VideoThumbnailCoordinator.probeExecutor.execute {
            try {
                val out = IntArray(fileNames.size * 2)
                val safBacked = isLocalStorage && uriString.startsWith("content://")
                var volId = -1
                if (!isLocalStorage) {
                    volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                        ?: run {
                            activity.runOnUiThread { result.error("NOT_MOUNTED", "Container not mounted", null) }
                            return@execute
                        }
                }
                if (!safBacked) {
                    for ((i, fileName) in fileNames.withIndex()) {
                        var localFile: java.io.File? = null
                        if (isLocalStorage) {
                            val file = if (fileName.startsWith("/")) java.io.File(fileName) else java.io.File(uriString, fileName)
                            if (!file.exists()) continue
                            localFile = file
                        }
                        val dims = probeImageDimensions(uriString, fileName, volId, isLocalStorage, localFile)
                        if (dims != null) {
                            out[i * 2] = dims.first
                            out[i * 2 + 1] = dims.second
                        }
                    }
                }
                activity.runOnUiThread { result.success(out) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    /** Upright (width, height) of one image from its headers, or null. Blocking. */
    private fun probeImageDimensions(
        uriString: String,
        fileName: String,
        volId: Int,
        isLocalStorage: Boolean,
        localFile: java.io.File?,
    ): Pair<Int, Int>? {
        return try {
            var stream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile)
            val markLimit = 1024 * 1024
            val exifOrientation = if (mightHaveExif(stream)) {
                val fastJpegOrientation = readJpegExifOrientation(stream)
                if (fastJpegOrientation != null) {
                    fastJpegOrientation
                } else {
                    stream.mark(markLimit)
                    val orientation = runCatching {
                        ExifInterface(stream).getAttributeInt(
                            ExifInterface.TAG_ORIENTATION,
                            ExifInterface.ORIENTATION_NORMAL,
                        )
                    }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
                    try {
                        stream.reset()
                    } catch (e: Exception) {
                        stream.close()
                        stream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile)
                    }
                    orientation
                }
            } else {
                ExifInterface.ORIENTATION_NORMAL
            }
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            stream.use { BitmapFactory.decodeStream(it, null, options) }
            val rawWidth = options.outWidth
            val rawHeight = options.outHeight
            if (rawWidth <= 0 || rawHeight <= 0) return null
            val isSideways = exifOrientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                exifOrientation == ExifInterface.ORIENTATION_ROTATE_270 ||
                exifOrientation == ExifInterface.ORIENTATION_TRANSPOSE ||
                exifOrientation == ExifInterface.ORIENTATION_TRANSVERSE
            if (isSideways) Pair(rawHeight, rawWidth) else Pair(rawWidth, rawHeight)
        } catch (e: Exception) {
            null
        }
    }

    /** A thumbnail made by [thumbnailFromImageBytes]; sizes are the *source* image's. */
    class BytesThumbnail(val bytes: ByteArray, val sourceWidth: Int, val sourceHeight: Int)

    /** Why [thumbnailFromImageBytes] gave up; [code] is the wire code the file-based path uses. */
    class BytesThumbnailException(val code: String, message: String) : Exception(message)

    /**
     * Same result as [extractImageThumbnail], but from image bytes already in
     * memory instead of a file or vault path. Used for images that live
     * *inside* another file -- a book's cover inside its ZIP -- and so have no
     * path of their own to hand to the stream-based decoder. Nothing is written
     * to disk.
     *
     * Goes through the same memory admission ([ImageDecodeGuard]), sample-size
     * choice, EXIF correction and scale/compress step ([finishThumbnail]) as an
     * ordinary image thumbnail, so a cover looks exactly like one and a huge
     * source is refused (or retried coarser) the same way instead of taking the
     * process down. Unlike the file-based path there is no progressive-JPEG
     * DC-scan fallback for an over-large source: that works from a stream, and
     * a cover that big simply gets no thumbnail.
     *
     * Decodes at full colour depth (the file path's RGB_565 saves memory but
     * bands on the gradients covers are full of), and flattens transparency
     * onto white since the output is JPEG, which would otherwise render it
     * black.
     *
     * Blocking; call from the image executor, never the main thread.
     *
     * @throws BytesThumbnailException
     */
    fun thumbnailFromImageBytes(data: ByteArray, targetSize: Int, quality: Int): BytesThumbnail {
        val bytesStart = PerfLog.begin()
        try {
        val exifOrientation = runCatching {
            ExifInterface(java.io.ByteArrayInputStream(data))
                .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        val rawWidth = bounds.outWidth
        val rawHeight = bounds.outHeight
        if (rawWidth <= 0 || rawHeight <= 0) {
            throw BytesThumbnailException("DECODE_FAILED", "Failed to read image bounds")
        }

        // As in extractImageThumbnail: the header only matters (to spot a
        // progressive JPEG) when the worst-case estimate is already heavy.
        val header = if (rawWidth.toLong() * rawHeight.toLong() * ImageDecodeGuard.WORST_CASE_BYTES_PER_PIXEL >=
            ImageDecodeGuard.HEAVY_ESTIMATE_BYTES
        ) {
            data.copyOf(minOf(data.size, ImageDecodeGuard.HEADER_SNIFF_BYTES))
        } else {
            null
        }
        val permit = try {
            ImageDecodeGuard.admit(activity, rawWidth, rawHeight, header)
        } catch (e: ImageDecodeGuard.RefusedException) {
            VeLog.w(TAG) { "Not decoding ${rawWidth}x$rawHeight embedded image: ${e.message}" }
            throw BytesThumbnailException(e.code, e.message ?: "Image is too large to decode")
        }

        try {
            val inSampleSize = calculateInSampleSize(rawWidth, rawHeight, targetSize)
            fun decodeAt(sampleSize: Int): Bitmap? = BitmapFactory.decodeByteArray(
                data,
                0,
                data.size,
                BitmapFactory.Options().apply {
                    this.inSampleSize = sampleSize
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                },
            )

            val decodedOrNull: Bitmap? = try {
                decodeAt(inSampleSize)
            } catch (e: OutOfMemoryError) {
                VeLog.w(TAG) { "OOM decoding ${rawWidth}x$rawHeight at sample $inSampleSize; retrying coarser" }
                System.gc()
                decodeAt(inSampleSize * 2)
            }
            val decoded = decodedOrNull
                ?: throw BytesThumbnailException("DECODE_FAILED", "Failed to decode image bytes")

            val opaque = if (decoded.hasAlpha()) {
                val flat = Bitmap.createBitmap(decoded.width, decoded.height, Bitmap.Config.ARGB_8888)
                Canvas(flat).apply {
                    drawColor(android.graphics.Color.WHITE)
                    drawBitmap(decoded, 0f, 0f, null)
                }
                decoded.recycle()
                flat
            } else {
                decoded
            }

            return when (val outcome = finishThumbnail(
                opaque, exifOrientation, rawWidth, rawHeight, targetSize, quality, preserveAlpha = false,
            )) {
                is ImageThumbnailOutcome.Success ->
                    BytesThumbnail(outcome.bytes, outcome.sourceWidth, outcome.sourceHeight)
                is ImageThumbnailOutcome.Failure ->
                    throw BytesThumbnailException(outcome.code, outcome.message)
            }
        } catch (e: OutOfMemoryError) {
            VeLog.w(TAG) { "Out of memory decoding ${rawWidth}x$rawHeight embedded image" }
            throw BytesThumbnailException(ImageDecodeGuard.CODE_OUT_OF_MEMORY, "Not enough memory to decode image")
        } finally {
            permit.close()
        }
        } finally {
            PerfLog.end("thumb.bytes.run", bytesStart)
        }
    }

    /**
     * Extracts an APK's own launcher icon for use as a file-manager
     * thumbnail, via `PackageManager.getPackageArchiveInfo` +
     * `ApplicationInfo.loadIcon` -- i.e. the same resource-resolution and
     * (crucially) adaptive-icon compositing Android itself uses once the
     * app is actually installed. This is deliberately *not* implemented
     * by hand-parsing the compiled manifest/resource table the way the
     * Dart-side fallback in `apk_icon_support.dart` does: that approach
     * can't render an adaptive icon (foreground+background layering,
     * masking, vector-drawable layers) and can miss real icons behind a
     * few binary-format edge cases (resource aliasing/reference chains,
     * newer "compact" resource-table entries) -- exactly the gap a plain
     * `PackageManager` call doesn't have, because it's the OS's own
     * code doing the resolving.
     *
     * The catch: `getPackageArchiveInfo` needs a real, openable file
     * path -- it does a plain `open()` under the hood, nothing more. Three
     * cases, mirroring [runImageThumbnail]'s branching exactly:
     *
     *  - Local storage (decoy): the file already has a real absolute
     *    path -- pass it straight through, no file descriptor needed.
     *  - SAF external storage (`content://` from another app/provider):
     *    resolve via [SafStorageManager.getDocumentUri] and open a real
     *    `ParcelFileDescriptor` for it, same as [runImageThumbnail]'s own
     *    `content://` branch already does for image/video thumbnails.
     *  - An actual encrypted vault: there's no OS-level file or file
     *    descriptor for decrypted content -- it only ever exists in this
     *    process's memory, produced on demand by the native engine. But
     *    this app already exposes unlocked vault content to *other* apps
     *    as a `DocumentsProvider` ([ContainerDocumentsProvider]) backed by
     *    `StorageManager.openProxyFileDescriptor` (a real fd whose reads
     *    are served by callbacks straight from the vault session, with no
     *    disk write of any kind -- see `ContainerProxyCallback`). Building
     *    a `content://` URI for our own provider and opening it via our
     *    own `ContentResolver` reuses exactly that existing, tested
     *    plumbing to get a real fd for vault content -- same-process
     *    `ContentResolver` calls to a provider in this process skip Binder
     *    entirely, so this isn't real IPC.
     *
     * Either way, once there's a real path or fd, the technique is the
     * same one used by other Android file managers that support APK icon
     * preview from arbitrary sources (e.g. MaterialFiles'
     * `PackageManagerPathExtensions.getPackageArchiveInfoCompat`): open
     * `/proc/self/fd/<fd>` as the "archive file path" -- a Linux procfs
     * trick that gives `getPackageArchiveInfo`'s plain `open()` call
     * something to resolve back to the already-open fd -- then manually
     * point the returned `ApplicationInfo.sourceDir`/`publicSourceDir` at
     * that same pseudo-path, since `loadIcon` reads resources from
     * wherever those fields say, and `getPackageArchiveInfo` doesn't
     * reliably fill them in for a fd-backed path on its own.
     */
    fun handleGetApkIcon(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val fileName = call.argument<String>("fileName")
        val targetSize = call.argument<Int>("targetSize") ?: 192
        val isLocalStorage = call.argument<Boolean>("isLocalStorage") ?: false

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        val apkEnqueuedAt = PerfLog.begin()
        imageExecutor.execute {
            PerfLog.end("thumb.apk.queue_wait", apkEnqueuedAt)
            val apkStart = PerfLog.begin()
            var pfd: ParcelFileDescriptor? = null
            try {
                val archiveFilePath: String
                when {
                    // Same isLocalStorage guard as runVideoThumbnail/
                    // runImageThumbnail: uriString is the *container's*
                    // own URI for a mounted vault (content:// whenever the
                    // container file lives on SAF-accessible storage),
                    // not necessarily fileName's own document, so the
                    // scheme alone can't tell genuine raw-SAF browsing
                    // apart from a vault case below.
                    isLocalStorage && uriString.startsWith("content://") -> {
                        val docUri = activity.safStorageManager.getDocumentUri(Uri.parse(uriString), fileName)
                            ?: throw java.io.FileNotFoundException("Could not resolve SAF document for $fileName")
                        pfd = activity.contentResolver.openFileDescriptor(docUri, "r")
                            ?: throw java.io.FileNotFoundException("Could not open SAF file descriptor for $fileName")
                        archiveFilePath = "/proc/self/fd/${pfd.fd}"
                    }
                    isLocalStorage -> {
                        val file = if (fileName.startsWith("/")) java.io.File(fileName) else java.io.File(uriString, fileName)
                        if (!file.exists()) throw java.io.FileNotFoundException("Local file not found: $fileName")
                        archiveFilePath = file.path
                    }
                    else -> {
                        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                            ?: throw java.io.FileNotFoundException("Container not mounted")
                        val docId = DocumentId(volId, "file", fileName).toString()
                        val docUri = DocumentsContract.buildDocumentUri(ContainerDocumentsProvider.AUTHORITY, docId)
                        pfd = activity.contentResolver.openFileDescriptor(docUri, "r")
                            ?: throw java.io.FileNotFoundException("Could not open vault file descriptor for $fileName")
                        archiveFilePath = "/proc/self/fd/${pfd.fd}"
                    }
                }

                val packageManager = activity.packageManager
                val packageInfo = packageManager.getPackageArchiveInfo(archiveFilePath, 0)
                    ?: throw java.io.IOException("Not a valid APK: $fileName")
                val applicationInfo = packageInfo.applicationInfo
                    ?: throw java.io.IOException("APK has no application info: $fileName")
                if (applicationInfo.icon == 0) {
                    // No android:icon at all -- Android would otherwise
                    // hand back its own generic package-icon drawable
                    // here, which would look like a real (if boring) icon
                    // rather than a missing one. Error out instead so the
                    // Dart side falls back the same way it does for any
                    // other unresolvable icon.
                    throw java.io.FileNotFoundException("APK has no android:icon: $fileName")
                }
                // loadIcon() resolves resources (including a full
                // adaptive-icon definition, if that's what android:icon
                // points at) from sourceDir/publicSourceDir -- neither of
                // which getPackageArchiveInfo reliably fills in for a
                // fd-backed pseudo-path, so both are set explicitly here.
                applicationInfo.sourceDir = archiveFilePath
                applicationInfo.publicSourceDir = archiveFilePath

                val drawable = applicationInfo.loadIcon(packageManager)
                val size = targetSize.coerceIn(48, 512)
                val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, size, size)
                drawable.draw(canvas)

                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                bitmap.recycle()
                val bytes = stream.toByteArray()

                activity.runOnUiThread { result.success(bytes) }
            } catch (e: Exception) {
                VeLog.w(TAG) { "handleGetApkIcon failed for $fileName: ${e.message}" }
                activity.runOnUiThread { result.error("APK_ICON_FAILED", e.message, null) }
            } finally {
                PerfLog.end("thumb.apk.run", apkStart)
                try {
                    pfd?.close()
                } catch (e: Exception) {
                    VeLog.w(TAG) { "Error closing APK icon file descriptor for $fileName" }
                }
            }
        }
    }

    /**
     * Encodes raw RGBA pixels as a lossy image file (JPEG or WebP) using the
     * platform encoder ([Bitmap.compress]).
     *
     * `dart:ui` can only encode PNG, which is lossless and several times
     * larger than the JPEG/WebP an edited photo started out as, so the image
     * editor hands its pixels here for any source that was lossy instead.
     *
     * Arguments:
     *  - `rgba`: `width * height * 4` bytes of *premultiplied* RGBA
     *    (`ui.ImageByteFormat.rawRgba`). That is exactly the in-memory
     *    layout of an `ARGB_8888` [Bitmap], so it is copied in unchanged.
     *  - `width`, `height`: pixel dimensions of `rgba`.
     *  - `format`: `"jpeg"` or `"webp"` (lossy).
     *  - `quality`: starting quality, 1..100 (default [ENCODE_DEFAULT_QUALITY]).
     *  - `maxBytes`: if > 0, the result is re-encoded at progressively lower
     *    quality (down to [ENCODE_MIN_QUALITY]) until it fits, so an image
     *    that lost pixels to a crop can't end up larger than the share of the
     *    original file it kept. Best effort: if even the floor doesn't fit,
     *    the smallest attempt is returned.
     *
     * Replies with the encoded bytes, or an error (`INVALID_ARGS`,
     * `ENCODE_FAILED`, `ENCODE_OOM`).
     */
    fun handleEncodeImage(call: MethodCall, result: MethodChannel.Result) {
        val rgba = call.argument<ByteArray>("rgba")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        val format = call.argument<String>("format")
        val startQuality = (call.argument<Int>("quality") ?: ENCODE_DEFAULT_QUALITY).coerceIn(1, 100)
        // Number, not Int: Dart sends an int that doesn't fit 32 bits as a Long.
        val maxBytes = call.argument<Number>("maxBytes")?.toLong() ?: 0L

        if (rgba == null || width == null || height == null || format == null) {
            result.error("INVALID_ARGS", "rgba, width, height and format required", null)
            return
        }
        if (width <= 0 || height <= 0 ||
            rgba.size.toLong() != width.toLong() * height.toLong() * 4L
        ) {
            result.error("INVALID_ARGS", "rgba length does not match width * height * 4", null)
            return
        }
        val compressFormat = when (format) {
            "jpeg" -> Bitmap.CompressFormat.JPEG
            "webp" -> lossyWebpFormat()
            else -> {
                result.error("INVALID_ARGS", "Unsupported format: $format", null)
                return
            }
        }

        imageExecutor.execute {
            var bitmap: Bitmap? = null
            try {
                val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                bitmap = bmp
                bmp.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(rgba))

                var quality = startQuality
                var encoded = compressBitmap(bmp, compressFormat, quality)
                while (maxBytes > 0 && encoded.size > maxBytes && quality > ENCODE_MIN_QUALITY) {
                    quality = (quality - ENCODE_QUALITY_STEP).coerceAtLeast(ENCODE_MIN_QUALITY)
                    encoded = compressBitmap(bmp, compressFormat, quality)
                }

                val out = encoded
                activity.runOnUiThread { result.success(out) }
            } catch (e: OutOfMemoryError) {
                VeLog.w(TAG) { "handleEncodeImage out of memory for ${width}x$height" }
                activity.runOnUiThread { result.error("ENCODE_OOM", "Not enough memory to encode image", null) }
            } catch (e: Exception) {
                VeLog.w(TAG) { "handleEncodeImage failed for ${width}x$height: ${e.message}" }
                activity.runOnUiThread { result.error("ENCODE_FAILED", e.message, null) }
            } finally {
                bitmap?.recycle()
            }
        }
    }

    /** Lossy WebP: `WEBP_LOSSY` on API 30+, the (lossy) legacy `WEBP` before. */
    @Suppress("DEPRECATION")
    private fun lossyWebpFormat(): Bitmap.CompressFormat =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Bitmap.CompressFormat.WEBP_LOSSY
        } else {
            Bitmap.CompressFormat.WEBP
        }

    private fun compressBitmap(
        bitmap: Bitmap,
        format: Bitmap.CompressFormat,
        quality: Int,
    ): ByteArray {
        val stream = ByteArrayOutputStream()
        if (!bitmap.compress(format, quality, stream)) {
            throw java.io.IOException("Bitmap.compress returned false")
        }
        return stream.toByteArray()
    }

    /**
     * Runs one decode attempt with an already-configured, already-started
     * software [codec]/[extractor] pair, seeking to [seekTimeUs] first.
     *
     * Callable more than once against the same open codec+extractor --
     * each call does its own `extractor.seekTo` and `codec.flush()`
     * first, so [extractVideoFrameSoftware] can retry at a different
     * point in the video (see [VideoThumbnailCoordinator.isLikelyBlankFrame])
     * without paying to reopen either. `codec.flush()` is the documented
     * way to discard in-flight buffers and return a running codec to its
     * post-`start()` state, so this is safe to call repeatedly.
     */
    // decodeSoftwareFrameAt and yuv420ToBitmap now live on
    // [VideoThumbnailCoordinator], shared with NativePlayerManager's
    // scrub-preview session (each used to have -- or would otherwise have
    // needed -- its own copy of this drain loop). Small forwarders are
    // kept below so every existing call site in this file is unchanged.
    private fun decodeSoftwareFrameAt(
        extractor: MediaExtractor,
        codec: MediaCodec,
        seekTimeUs: Long,
        targetSize: Int = 0,
    ): Bitmap? = VideoThumbnailCoordinator.decodeSoftwareFrameAt(
        extractor, codec, seekTimeUs, targetSize,
    )

    /**
     * Attempts frame extraction using an explicit Software-Only [MediaCodec]
     * decoder (`c2.android.*` or `OMX.google.*`).
     *
     * Because this explicitly selects Google's CPU software decoder, it
     * **does not allocate or contend for hardware video decoder instances**
     * (such as Qualcomm `c2.qti.vp9.decoder` or `OMX.qcom...`), allowing video
     * thumbnails to be extracted safely while ExoPlayer is actively playing
     * 4K videos on the GPU/HW decoder.
     */
     private fun extractVideoFrameSoftware(
        uriString: String,
        fileName: String,
        volId: Int,
        targetSize: Int,
        quality: Int,
        isLocalStorage: Boolean = false,
        localFile: java.io.File? = null,
        explicitTimeUs: Long? = null,
        strategy: String = "hybrid",
        framePosition: Double = 0.12,
        trace: SwTrace? = null,
    ): VideoFrameResult? {
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
            val swDsT0 = System.nanoTime()
            val swDsStart = PerfLog.begin()
            extractor = MediaExtractor()
            if (isLocalStorage && localFile != null) {
                extractor.setDataSource(localFile.absolutePath)
            } else {
                val dataSource = ContainerMediaDataSource(fileName, volId)
                extractor.setDataSource(dataSource)
            }
            PerfLog.end("thumb.vid.sw_ds", swDsStart)
            trace?.dsMs = (System.nanoTime() - swDsT0) / 1_000_000L

            var videoTrackIndex = -1
            var format: MediaFormat? = null
            var mimeType: String? = null

            for (i in 0 until extractor.trackCount) {
                val trackFormat = extractor.getTrackFormat(i)
                val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/")) {
                    videoTrackIndex = i
                    format = trackFormat
                    mimeType = mime
                    break
                }
            }

            if (videoTrackIndex < 0 || format == null || mimeType == null) {
                return null
            }

            val swCodecName = findSoftwareDecoderName(mimeType) ?: return null
            VeLog.d(TAG) { "Using software video decoder '$swCodecName' for thumbnail (len=${fileName.length})" }

            extractor.selectTrack(videoTrackIndex)

            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION)
            } else 10_000_000L
            val rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                format.getInteger(MediaFormat.KEY_ROTATION)
            } else 0
            val fmtW = if (format.containsKey(MediaFormat.KEY_WIDTH)) format.getInteger(MediaFormat.KEY_WIDTH) else 0
            val fmtH = if (format.containsKey(MediaFormat.KEY_HEIGHT)) format.getInteger(MediaFormat.KEY_HEIGHT) else 0
            val srcWidth = if (rotation == 90 || rotation == 270) fmtH else fmtW
            val srcHeight = if (rotation == 90 || rotation == 270) fmtW else fmtH

            val swCfgT0 = System.nanoTime()
            val swCfgStart = PerfLog.begin()
            codec = MediaCodec.createByCodecName(swCodecName)
            codec.configure(format, null, null, 0)
            codec.start()
            PerfLog.end("thumb.vid.sw_cfg", swCfgStart)
            trace?.cfgMs = (System.nanoTime() - swCfgT0) / 1_000_000L

            val ext = extractor
            val dec = codec

            val seekTimeUs = explicitTimeUs ?: when (strategy) {
                "firstFrame", "hybrid" -> 0L
                "frameAtPercentage" -> (durationUs * framePosition.coerceIn(0.05, 0.90)).toLong()
                else -> 0L
            }
            val swDecT0 = System.nanoTime()
            val swDecStart = PerfLog.begin()
            var outputFrame = decodeSoftwareFrameAt(ext, dec, seekTimeUs, targetSize)
            PerfLog.end("thumb.vid.sw_dec", swDecStart)
            trace?.decMs = (System.nanoTime() - swDecT0) / 1_000_000L
            if (strategy == "hybrid" && explicitTimeUs == null &&
                (outputFrame == null || VideoThumbnailCoordinator.isLikelyBlankFrame(outputFrame))
            ) {
                val swBlankT0 = System.nanoTime()
                val swBlankStart = PerfLog.begin()
                val fractions = (listOf(framePosition.coerceIn(0.05, 0.90)) + VideoThumbnailCoordinator.BLANK_FRAME_RETRY_FRACTIONS.toList()).distinct()
                for (fraction in fractions) {
                    val candidateUs = (durationUs * fraction).toLong()
                    if (candidateUs <= seekTimeUs) continue
                    val candidate = runCatching { decodeSoftwareFrameAt(ext, dec, candidateUs, targetSize) }.getOrNull()
                        ?: continue
                    if (!VideoThumbnailCoordinator.isLikelyBlankFrame(candidate)) {
                        outputFrame?.recycle()
                        outputFrame = candidate
                        break
                    }
                    candidate.recycle()
                }
                PerfLog.end("thumb.vid.sw_blank_retry", swBlankStart)
                trace?.blankMs = (System.nanoTime() - swBlankT0) / 1_000_000L
            }

            if (outputFrame != null) {
                val swRotT0 = System.nanoTime()
                val res = compressFrame(
                    rotatedUpright(outputFrame, rotation),
                    targetSize,
                    quality,
                    overrideSourceWidth = if (srcWidth > 0) srcWidth else null,
                    overrideSourceHeight = if (srcHeight > 0) srcHeight else null,
                )
                trace?.rotMs = (System.nanoTime() - swRotT0) / 1_000_000L
                return res
            }   
            return null
        } catch (e: Exception) {
            VeLog.w(TAG) { "Software MediaCodec extraction failed (len=${fileName.length}): ${e.message}" }
            return null
        } finally {
            runCatching {
                codec?.stop()
                codec?.release()
            }
            runCatching { extractor?.release() }
        }
    }

    /** [src] turned by [degrees] clockwise (0/90/180/270), recycling [src]
     *  when a rotated copy is made. A multiple of 360 returns [src] as is. */
    private fun rotatedUpright(src: Bitmap, degrees: Int): Bitmap {
        val d = ((degrees % 360) + 360) % 360
        if (d == 0) return src
        val matrix = Matrix().apply { postRotate(d.toFloat()) }
        val rotated = Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
        if (rotated != src) src.recycle()
        return rotated
    }

    private fun findSoftwareDecoderName(mimeType: String): String? =
        VideoThumbnailCoordinator.findSoftwareDecoderName(mimeType)

    private fun yuv420ToBitmap(image: android.media.Image): Bitmap =
        VideoThumbnailCoordinator.yuv420ToBitmap(image)
}
