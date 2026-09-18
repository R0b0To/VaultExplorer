package com.aeidolon.vaultexplorer.handlers

import android.graphics.Bitmap
import android.net.Uri
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.graphics.YuvImage
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
import java.io.Closeable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import com.aeidolon.vaultexplorer.DocumentId
import com.aeidolon.vaultexplorer.container.ContainerDocumentsProvider
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.container.ContainerInputStream
import com.aeidolon.vaultexplorer.container.ContainerMediaDataSource
import com.aeidolon.vaultexplorer.container.VideoThumbnailCoordinator
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.NativeOpSupport
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

            try {
                surfaceTexture = SurfaceTexture(10)
                surfaceTexture.setDefaultBufferSize(targetSize, targetSize)
                surface = Surface(surfaceTexture)

                player = ExoPlayer.Builder(activity).build()
                player.setVideoSurface(surface)

                val dataSourceFactory: DataSource.Factory = if (isLocalStorage) {
                    androidx.media3.datasource.DefaultDataSource.Factory(activity)
                } else {
                    // Adapt ContainerMediaDataSource into a Media3 DataSource
                    DataSource.Factory {
                        object : DataSource {
                            private val mediaDataSource = ContainerMediaDataSource(activity, uriString, fileName, volId)
                            private var currentPosition: Long = 0L
                            private var openUri: android.net.Uri? = null

                            override fun addTransferListener(transferListener: TransferListener) {}

                            override fun open(dataSpec: DataSpec): Long {
                                openUri = dataSpec.uri
                                currentPosition = dataSpec.position
                                val totalSize = mediaDataSource.size
                                if (totalSize <= 0) return C.LENGTH_UNSET.toLong()
                                return totalSize - currentPosition
                            }

                            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                                if (length == 0) return 0
                                val bytesRead = mediaDataSource.readAt(currentPosition, buffer, offset, length)
                                if (bytesRead > 0) {
                                    currentPosition += bytesRead
                                }
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
                    val bitmap = Bitmap.createBitmap(dstW, dstH, Bitmap.Config.ARGB_8888)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        PixelCopy.request(
                            surface,
                            bitmap,
                            { copyResult ->
                                if (copyResult == PixelCopy.SUCCESS) {
                                    val durationMs = player?.duration ?: C.TIME_UNSET
                                    val looksBlank = VideoThumbnailCoordinator.isLikelyBlankFrame(bitmap)
                                    if (allowBlankRetry && looksBlank && durationMs != C.TIME_UNSET && durationMs > 0) {
                                        val retryPositionMs = (durationMs * VideoThumbnailCoordinator.BLANK_FRAME_RETRY_FRACTIONS[0])
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
                        capturePixelCopy(allowBlankRetry = true)
                    }

                    override fun onPlayerError(error: PlaybackException) {
                        VeLog.w(TAG) { "ExoPlayer thumbnail extraction error: ${error.message}" }
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
    private fun extractVideoFrame(
        uriString: String,
        fileName: String,
        volId: Int,
        targetSize: Int,
        quality: Int,
        isLocalStorage: Boolean = false,
        localFile: java.io.File? = null,
    ): VideoFrameResult? {
        if (isPlaybackActive) {
            VeLog.d(TAG) { "Playback active: attempting software MediaCodec frame extraction (len=${fileName.length})" }
            val swResult = extractVideoFrameSoftware(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile)
            if (swResult != null) return swResult
            VeLog.d(TAG) { "Software extraction unavailable or failed while playing (len=${fileName.length})" }
            return null
        }

        videoDecoderLock.lock()
        try {
            if (isPlaybackActive) {
                return extractVideoFrameSoftware(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile)
            }
            return extractVideoFrameInner(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile)
        } finally {
            videoDecoderLock.unlock()
        }
    }




    /** Does the actual extraction work while the caller holds [videoDecoderLock]. */
    private fun extractVideoFrameInner(
        uriString: String,
        fileName: String,
        volId: Int,
        targetSize: Int,
        quality: Int,
        isLocalStorage: Boolean = false,
        localFile: java.io.File? = null,
    ): VideoFrameResult? {
        var retriever: MediaMetadataRetriever? = null
        try {
            retriever = MediaMetadataRetriever()
            if (isLocalStorage && localFile != null) {
                retriever.setDataSource(localFile.absolutePath)
            } else {
                val dataSource = ContainerMediaDataSource(activity, uriString, fileName, volId)
                retriever.setDataSource(dataSource)
            }

            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 10_000L
            val durationUs = durationMs * 1000L
            val timeUs = VideoThumbnailCoordinator.getInitialThumbnailTimeUs(durationUs)

            val metaW = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val metaH = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0

            val srcWidth = if (rot == 90 || rot == 270) metaH ?: 0 else metaW ?: 0
            val srcHeight = if (rot == 90 || rot == 270) metaW ?: 0 else metaH ?: 0

            var frame = tryExtractFrame(retriever, timeUs, targetSize)
            if (frame != null && VideoThumbnailCoordinator.isLikelyBlankFrame(frame)) {
                val alternate = tryAlternateFrameIfBlank(retriever, durationMs, targetSize)
                if (alternate != null) {
                    frame.recycle()
                    frame = alternate
                }
            }
            if (frame != null) {
                return compressFrame(
                    frame,
                    targetSize,
                    quality,
                    overrideSourceWidth = if (srcWidth > 0) srcWidth else null,
                    overrideSourceHeight = if (srcHeight > 0) srcHeight else null,
                )
            }
            // If tryExtractFrame returned null, attempt ExoPlayer fallback
            return extractVideoFrameExoPlayer(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile)
        } catch (e: Exception) {
            runCatching { retriever?.release() }
            retriever = null

            // 1. If hardware decoder capacity is full, retry at 180p native fallback
            if (isCodecResourceError(e)) {
                VeLog.w(TAG) { "Primary frame extraction hit codec resource limit, retrying at ${FALLBACK_TARGET_SIZE}p: ${e.message}" }
                val fallbackResult = extractFrameFallback(uriString, fileName, volId, quality, isLocalStorage, localFile)
                if (fallbackResult != null) return fallbackResult
            }

            // 2. Try software MediaCodec extraction first (does not contend with HW decoder)
            val swResult = extractVideoFrameSoftware(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile)
            if (swResult != null) return swResult

            // 3. For unsupported formats (like .flv, .wmv, .webm), fall back to ExoPlayer
            VeLog.w(TAG) { "Native retriever failed for $fileName (${e.message}), falling back to ExoPlayer" }
            return extractVideoFrameExoPlayer(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile)
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
                val dataSource = ContainerMediaDataSource(activity, uriString, fileName, volId)
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
    ): Bitmap? {
        val option = MediaMetadataRetriever.OPTION_PREVIOUS_SYNC
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val params = MediaMetadataRetriever.BitmapParams().apply {
                preferredConfig = Bitmap.Config.RGB_565
            }
            runCatching {
                retriever.getScaledFrameAtTime(timeUs, option, size, size, params)
            }.getOrNull()
                ?: runCatching { retriever.getScaledFrameAtTime(timeUs, option, size, size) }.getOrNull()
                ?: retriever.getFrameAtTime(timeUs, option)
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
    ): Bitmap? {
        val durationUs = durationMs * 1000L
        if (durationUs <= 0L) return null
        for (fraction in VideoThumbnailCoordinator.BLANK_FRAME_RETRY_FRACTIONS) {
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
        val stream = ByteArrayOutputStream()
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

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        videoExecutor.execute {
            try {
                if (uriString.startsWith("content://")) {
                    val thumb = activity.safStorageManager.getThumbnail(
                        Uri.parse(uriString),
                        fileName,
                        targetSize,
                        call.argument<Int>("quality") ?: 60,
                        isVideo = true,
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
                val frameResult = extractVideoFrame(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile)

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

    /** Opens the stream [extractImageThumbnail] reads from: a plain
     *  [java.io.FileInputStream] for real on-disk files ([isLocalStorage],
     *  mirroring [extractVideoFrameSoftware]'s `isLocalStorage && localFile
     *  != null` bypass), or the usual decrypting [ContainerInputStream]
     *  otherwise. Always wrapped in the same 64 KB [BufferedInputStream]
     *  either way, since callers rely on mark()/reset() being available. */
    private fun openImageInputStream(
        uriString: String,
        fileName: String,
        volId: Int,
        isLocalStorage: Boolean,
        localFile: java.io.File?,
    ): BufferedInputStream {
        val raw: java.io.InputStream = if (isLocalStorage && localFile != null) {
            java.io.FileInputStream(localFile)
        } else {
            ContainerInputStream(activity, uriString, fileName, volId)
        }
        return BufferedInputStream(raw, 65536)
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
    ): ImageThumbnailOutcome {
        // Read EXIF orientation from its own stream, before the bounds pass
        // below -- ExifInterface consumes/seeks the stream it's given, so it
        // needs a fresh one just like the bounds and decode passes each get
        // their own (ContainerInputStream is cheap to reopen; see its doc
        // comment). Camera phones almost universally store portrait photos
        // as landscape sensor data plus this tag -- BitmapFactory below
        // knows nothing about it and decodes the raw (landscape) pixels, so
        // skipping this step is exactly what left thumbnails sideways while
        // the full-res viewer (decoded by Flutter/Skia, which *does* apply
        // EXIF orientation for JPEG) looked correct.
        val exifOrientation = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile)
            .use { stream ->
                runCatching {
                    ExifInterface(stream).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL,
                    )
                }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
            }

        var inputStream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile)
        // Reuse this single stream across the bounds and decode passes via
        // mark()/reset() instead of opening a third ContainerInputStream
        // from byte 0 (the EXIF read above already gets its own -- see that
        // block's comment for why that one stays separate). Previously the
        // bounds and decode passes here each opened their own stream, which
        // meant every image thumbnail paid for an extra
        // ContainerFileSystem.getFileSize() call, an extra per-volume lock
        // acquisition on backends that don't skip it (native block-device,
        // CryFS), and re-decrypted whatever small prefix the bounds-only
        // pass had already read. BufferedInputStream is what makes reset()
        // actually free here: the decode pass re-reads that prefix from its
        // own buffer instead of calling back into ContainerInputStream, and
        // only pulls fresh decrypted bytes once it reads past what the
        // bounds pass consumed.
        //
        // Falls back to the old separate-stream approach if reset() fails
        // for any reason (e.g. a decoder that consumes more than markLimit
        // while sniffing format) -- correctness always wins over the
        // optimization.
        val markLimit = 1024 * 1024
        inputStream.mark(markLimit)

        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeStream(inputStream, null, options)

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

        val orientationMatrix = exifOrientationMatrix(exifOrientation)
        val isSideways = exifOrientation == ExifInterface.ORIENTATION_ROTATE_90 ||
            exifOrientation == ExifInterface.ORIENTATION_ROTATE_270 ||
            exifOrientation == ExifInterface.ORIENTATION_TRANSPOSE ||
            exifOrientation == ExifInterface.ORIENTATION_TRANSVERSE
        val width = if (isSideways) rawHeight else rawWidth
        val height = if (isSideways) rawWidth else rawHeight

        val inSampleSize = calculateInSampleSize(rawWidth, rawHeight, targetSize)
        val decodeOptions = BitmapFactory.Options().apply {
            this.inSampleSize = inSampleSize
            this.inPreferredConfig = Bitmap.Config.RGB_565
        }

        try {
            inputStream.reset()
        } catch (e: Exception) {
            inputStream.close()
            inputStream = openImageInputStream(uriString, fileName, volId, isLocalStorage, localFile)
        }

        val decodedBitmap = BitmapFactory.decodeStream(inputStream, null, decodeOptions)
        inputStream.close()

        if (decodedBitmap == null) {
            return ImageThumbnailOutcome.Failure("DECODE_FAILED", "Failed to decode image bytes")
        }

        val rawBitmap = applyExifOrientation(decodedBitmap, orientationMatrix)

        val scaledBitmap = scaledToFit(rawBitmap, targetSize)
        if (scaledBitmap != rawBitmap) rawBitmap.recycle()

        val stream = ByteArrayOutputStream()
        scaledBitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), stream)
        val bytes = stream.toByteArray()
        scaledBitmap.recycle()

        return ImageThumbnailOutcome.Success(bytes, width, height)
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

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        imageExecutor.execute {
            try {
                if (uriString.startsWith("content://")) {
                    val thumb = activity.safStorageManager.getThumbnail(
                        Uri.parse(uriString),
                        fileName,
                        targetSize,
                        quality,
                        isVideo = false,
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

                when (val outcome = extractImageThumbnail(uriString, fileName, volId, targetSize, quality, isLocalStorage, localFile)) {
                    is ImageThumbnailOutcome.Success ->
                        activity.runOnUiThread { result.success(onSuccess(outcome)) }
                    is ImageThumbnailOutcome.Failure ->
                        activity.runOnUiThread { result.error(outcome.code, outcome.message, null) }
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

        imageExecutor.execute {
            var pfd: ParcelFileDescriptor? = null
            try {
                val archiveFilePath: String
                when {
                    uriString.startsWith("content://") -> {
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
                try {
                    pfd?.close()
                } catch (e: Exception) {
                    VeLog.w(TAG) { "Error closing APK icon file descriptor for $fileName" }
                }
            }
        }
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
    ): Bitmap? = VideoThumbnailCoordinator.decodeSoftwareFrameAt(extractor, codec, seekTimeUs)

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
    ): VideoFrameResult? {
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
            extractor = MediaExtractor()
            if (isLocalStorage && localFile != null) {
                extractor.setDataSource(localFile.absolutePath)
            } else {
                val dataSource = ContainerMediaDataSource(activity, uriString, fileName, volId)
                extractor.setDataSource(dataSource)
            }

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

            codec = MediaCodec.createByCodecName(swCodecName)
            codec.configure(format, null, null, 0)
            codec.start()

            val ext = extractor
            val dec = codec

            val seekTimeUs = VideoThumbnailCoordinator.getInitialThumbnailTimeUs(durationUs)
            var outputFrame = decodeSoftwareFrameAt(ext, dec, seekTimeUs)
            if (outputFrame != null && VideoThumbnailCoordinator.isLikelyBlankFrame(outputFrame)) {
                for (fraction in VideoThumbnailCoordinator.BLANK_FRAME_RETRY_FRACTIONS) {
                    val candidateUs = (durationUs * fraction).toLong()
                    if (candidateUs <= seekTimeUs) continue
                    val candidate = runCatching { decodeSoftwareFrameAt(ext, dec, candidateUs) }.getOrNull()
                        ?: continue
                    if (!VideoThumbnailCoordinator.isLikelyBlankFrame(candidate)) {
                        outputFrame?.recycle()
                        outputFrame = candidate
                        break
                    }
                    candidate.recycle()
                }
            }

            if (outputFrame != null) {
                return compressFrame(outputFrame, targetSize, quality)
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

    private fun findSoftwareDecoderName(mimeType: String): String? =
        VideoThumbnailCoordinator.findSoftwareDecoderName(mimeType)

    private fun yuv420ToBitmap(image: android.media.Image): Bitmap =
        VideoThumbnailCoordinator.yuv420ToBitmap(image)
}