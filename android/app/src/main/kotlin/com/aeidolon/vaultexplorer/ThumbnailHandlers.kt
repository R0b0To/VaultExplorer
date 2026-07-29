package com.aeidolon.vaultexplorer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService

class ThumbnailHandlers(
    private val activity: MainActivity,
    private val imageExecutor: ExecutorService,
    private val videoExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    /**
     * Serialises access to the hardware video decoder between thumbnail
     * extraction ([extractVideoFrame]) and ExoPlayer playback.
     *
     * - Thumbnail extraction holds the lock for the duration of
     *   `MediaMetadataRetriever.getScaledFrameAtTime` / `getFrameAtTime`.
     * - [handleSetPlaybackActive] acquires the lock on the **calling
     *   thread** (the videoExecutor) when `active = true`.  Because the
     *   executor is a single-thread pool, this blocks until the in-flight
     *   thumbnail extraction finishes and releases its `MediaMetadataRetriever`,
     *   which guarantees the hardware decoder is free before the method
     *   returns to Flutter.
     *
     * The lock is fair so waiters are served in FIFO order, preventing
     * starvation.
     */
    private val videoDecoderLock = java.util.concurrent.locks.ReentrantLock(true)

    @Volatile
    private var isPlaybackActive: Boolean = false

    companion object {
        private const val TAG = "ThumbnailHandlers"
        /** Fallback target dimension when the primary extraction fails due to
         *  hardware decoder resource exhaustion. 180px is small enough that
         *  most SoCs will route to a software decoder path. */
        private const val FALLBACK_TARGET_SIZE = 180
    }

    /**
     * Called from Flutter when video playback starts or stops.
     *
     * When `active = true`:
     *  1. Sets the volatile flag so any *new* thumbnail extraction bails
     *     out immediately.
     *  2. Purges queued (not-yet-started) thumbnail tasks from the executor.
     *  3. Acquires [videoDecoderLock] — this **blocks** until the
     *     currently-running thumbnail extraction (if any) finishes and
     *     releases its hardware decoder.
     *  4. Immediately releases the lock (we only needed to wait, not hold it).
     *  5. Returns `success(null)` to Flutter.
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
            // Run on the videoExecutor so we queue behind any in-flight task
            // and block until it finishes (the executor is a single-thread pool).
            videoExecutor.execute {
                // Acquire the lock — this blocks until the in-flight
                // extractVideoFrame releases it.
                videoDecoderLock.lock()
                try {
                    Log.d(TAG, "Playback active: hardware decoder is now free for ExoPlayer")
                } finally {
                    videoDecoderLock.unlock()
                }
                activity.runOnUiThread { result.success(null) }
            }
        } else {
            isPlaybackActive = false
            Log.d(TAG, "Playback inactive, thumbnail extraction may resume")
            result.success(null)
        }
    }

    private fun calculateInSampleSize(width: Int, height: Int, targetSize: Int): Int {
        var inSampleSize = 1
        if (width > targetSize || height > targetSize) {
            val halfWidth = width / 2
            val halfHeight = height / 2
            while (halfWidth / inSampleSize >= targetSize && halfHeight / inSampleSize >= targetSize) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    private fun scaledToFit(src: Bitmap, maxEdge: Int): Bitmap {
        val w = src.width
        val h = src.height
        if (w <= maxEdge && h <= maxEdge) return src
        val scale = maxEdge.toFloat() / maxOf(w, h)
        val dstW  = (w * scale).toInt().coerceAtLeast(1)
        val dstH  = (h * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, dstW, dstH, true)
    }

    /** Returns true if [e] looks like a hardware video decoder resource
     *  exhaustion error (OMX_ErrorInsufficientResources / NO_MEMORY). */
    private fun isCodecResourceError(e: Throwable): Boolean {
        if (e is MediaCodec.CodecException) return true
        val msg = e.message?.lowercase() ?: return false
        return msg.contains("omx_errorinsufficientresources") ||
               msg.contains("no_memory") ||
               msg.contains("codec") ||
               msg.contains("0x80001000") // OMX_ErrorInsufficientResources hex
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
     * the result.  Holds [videoDecoderLock] for the entire extraction so
     * [handleSetPlaybackActive] can wait for the decoder to be released.
     *
     * If [isPlaybackActive] is already true when we enter, we bail out
     * immediately without touching the decoder.
     *
     * On hardware decoder resource exhaustion the retriever is released and
     * a **fallback** extraction is attempted at [FALLBACK_TARGET_SIZE].
     *
     * @return a [VideoFrameResult], or `null` if extraction failed or was
     *         skipped because playback is active.
     */
    private fun extractVideoFrame(
        uriString: String,
        fileName: String,
        volId: Int,
        targetSize: Int,
        quality: Int,
    ): VideoFrameResult? {
        // Fast bail-out before trying to acquire the lock.
        if (isPlaybackActive) {
            Log.d(TAG, "Skipping video thumbnail: playback is active (pre-lock)")
            return null
        }

        videoDecoderLock.lock()
        try {
            // Re-check after acquiring: playback may have been requested
            // while we were waiting.
            if (isPlaybackActive) {
                Log.d(TAG, "Skipping video thumbnail: playback is active (post-lock)")
                return null
            }

            return extractVideoFrameInner(uriString, fileName, volId, targetSize, quality)
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
    ): VideoFrameResult? {
        var retriever: MediaMetadataRetriever? = null
        try {
            retriever = MediaMetadataRetriever()
            val dataSource = ContainerMediaDataSource(activity, uriString, fileName, volId)
            retriever.setDataSource(dataSource)

            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 10_000L
            val timeMs = minOf(1000L, durationMs / 4)
            val timeUs = timeMs * 1000L

            val frame = tryExtractFrame(retriever, timeUs, targetSize)
            if (frame != null) {
                return compressFrame(frame, targetSize, quality)
            }
            return null
        } catch (e: Exception) {
            if (!isCodecResourceError(e)) throw e
            Log.w(TAG, "Primary frame extraction hit codec resource limit, " +
                       "retrying at ${FALLBACK_TARGET_SIZE}p: ${e.message}")
            runCatching { retriever?.release() }
            retriever = null
            return extractFrameFallback(uriString, fileName, volId, quality)
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
    ): VideoFrameResult? {
        var fallbackRetriever: MediaMetadataRetriever? = null
        try {
            fallbackRetriever = MediaMetadataRetriever()
            val dataSource = ContainerMediaDataSource(activity, uriString, fileName, volId)
            fallbackRetriever.setDataSource(dataSource)

            val durationMs = fallbackRetriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 10_000L
            val timeMs = minOf(1000L, durationMs / 4)
            val timeUs = timeMs * 1000L

            val frame = tryExtractFrame(fallbackRetriever, timeUs, FALLBACK_TARGET_SIZE)
            if (frame != null) {
                return compressFrame(frame, FALLBACK_TARGET_SIZE, quality)
            }
            return null
        } catch (e2: Exception) {
            Log.e(TAG, "Fallback frame extraction also failed: ${e2.message}")
            return null
        } finally {
            runCatching { fallbackRetriever?.release() }
        }
    }

    /** Attempts [getScaledFrameAtTime] first, falls back to [getFrameAtTime]. */
    private fun tryExtractFrame(
        retriever: MediaMetadataRetriever,
        timeUs: Long,
        size: Int,
    ): Bitmap? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            runCatching {
                retriever.getScaledFrameAtTime(
                    timeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    size,
                    size,
                )
            }.getOrNull()
                ?: retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        } else {
            retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        }
    }

    /** Scales the frame, compresses to JPEG, recycles bitmaps, returns result. */
    private fun compressFrame(
        frame: Bitmap,
        targetSize: Int,
        quality: Int,
    ): VideoFrameResult {
        val sourceWidth = frame.width
        val sourceHeight = frame.height
        val scaledFrame = scaledToFit(frame, targetSize)
        val stream = ByteArrayOutputStream()
        scaledFrame.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), stream)
        val bytes = stream.toByteArray()
        if (scaledFrame != frame) scaledFrame.recycle()
        frame.recycle()
        return VideoFrameResult(bytes, sourceWidth, sourceHeight)
    }

    // ── Public handlers ─────────────────────────────────────────────────────

    fun handleGetVideoThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val fileName  = call.argument<String>("fileName")
        val targetSize = call.argument<Int>("targetSize") ?: 180

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        videoExecutor.execute {
            try {
                val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                    ?: run {
                        activity.runOnUiThread {
                            result.error("NOT_MOUNTED", "Container not mounted", null)
                        }
                        return@execute
                    }

                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    activity.runOnUiThread { result.error("UNSUPPORTED_OS", "Requires Android 6.0+", null) }
                    return@execute
                }

                val quality = call.argument<Int>("quality") ?: 60
                val frameResult = extractVideoFrame(uriString, fileName, volId, targetSize, quality)

                if (frameResult != null) {
                    activity.runOnUiThread { result.success(frameResult.bytes) }
                } else {
                    activity.runOnUiThread { result.error("FRAME_FAILED", "Failed to extract frame", null) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    /** Identical frame-extraction/scale/compress path to
     *  [handleGetVideoThumbnail]; the only difference is the result shape:
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
        val uriString = call.argument<String>("filePath")
        val fileName  = call.argument<String>("fileName")
        val targetSize = call.argument<Int>("targetSize") ?: 180

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        videoExecutor.execute {
            try {
                val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                    ?: run {
                        activity.runOnUiThread {
                            result.error("NOT_MOUNTED", "Container not mounted", null)
                        }
                        return@execute
                    }

                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    activity.runOnUiThread { result.error("UNSUPPORTED_OS", "Requires Android 6.0+", null) }
                    return@execute
                }

                val quality = call.argument<Int>("quality") ?: 60
                val frameResult = extractVideoFrame(uriString, fileName, volId, targetSize, quality)

                if (frameResult != null) {
                    activity.runOnUiThread {
                        result.success(mapOf(
                            "bytes" to frameResult.bytes,
                            "width" to frameResult.sourceWidth,
                            "height" to frameResult.sourceHeight,
                        ))
                    }
                } else {
                    activity.runOnUiThread { result.error("FRAME_FAILED", "Failed to extract frame", null) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleGetImageThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val uriString  = call.argument<String>("filePath")
        val fileName   = call.argument<String>("fileName")
        val targetSize = call.argument<Int>("targetSize") ?: 180
        val quality = call.argument<Int>("quality") ?: 70

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        imageExecutor.execute {
            try {
                val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                    ?: run {
                        activity.runOnUiThread { result.error("NOT_MOUNTED", "Container not mounted", null) }
                        return@execute
                    }

                var inputStream = BufferedInputStream(ContainerInputStream(activity, uriString, fileName, volId), 65536)

                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeStream(inputStream, null, options)
                inputStream.close()

                val width = options.outWidth
                val height = options.outHeight

                val inSampleSize = calculateInSampleSize(width, height, targetSize)

                val decodeOptions = BitmapFactory.Options().apply {
                    this.inSampleSize = inSampleSize
                }

                inputStream = BufferedInputStream(ContainerInputStream(activity, uriString, fileName, volId), 65536)
                val rawBitmap = BitmapFactory.decodeStream(inputStream, null, decodeOptions)
                inputStream.close()

                if (rawBitmap != null) {
                    val scaledBitmap = scaledToFit(rawBitmap, targetSize)
                    if (scaledBitmap != rawBitmap) rawBitmap.recycle()

                    val stream = ByteArrayOutputStream()
                    val qualityVal = quality.coerceIn(1, 100)
                    scaledBitmap.compress(Bitmap.CompressFormat.JPEG, qualityVal, stream)
                    val bytes = stream.toByteArray()
                    scaledBitmap.recycle()

                    activity.runOnUiThread { result.success(bytes) }
                } else {
                    activity.runOnUiThread { result.error("DECODE_FAILED", "Failed to decode image bytes", null) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    /** Identical decode/scale/compress path to [handleGetImageThumbnail], the
     *  only difference being the result shape: `{"bytes": ByteArray, "width":
     *  Int, "height": Int}` instead of a bare `ByteArray`. `width`/`height`
     *  are the *source* frame's bounds (from the `inJustDecodeBounds` pass
     *  that already runs to pick `inSampleSize`) — i.e. the true content
     *  aspect ratio, not the downscaled thumbnail's own dimensions (though
     *  scaledToFit preserves the ratio, so they agree up to rounding).
     *
     *  A second method rather than changing [handleGetImageThumbnail]'s
     *  return type, so the four existing callers that only want bytes
     *  (file grid, media viewer, playlist carousel) are unaffected. */
    fun handleGetImageThumbnailWithSize(call: MethodCall, result: MethodChannel.Result) {
        val uriString  = call.argument<String>("filePath")
        val fileName   = call.argument<String>("fileName")
        val targetSize = call.argument<Int>("targetSize") ?: 180
        val quality = call.argument<Int>("quality") ?: 70

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        imageExecutor.execute {
            try {
                val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                    ?: run {
                        activity.runOnUiThread { result.error("NOT_MOUNTED", "Container not mounted", null) }
                        return@execute
                    }

                var inputStream = BufferedInputStream(ContainerInputStream(activity, uriString, fileName, volId), 65536)

                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeStream(inputStream, null, options)
                inputStream.close()

                val width = options.outWidth
                val height = options.outHeight

                if (width <= 0 || height <= 0) {
                    activity.runOnUiThread { result.error("DECODE_FAILED", "Failed to read image bounds", null) }
                    return@execute
                }

                val inSampleSize = calculateInSampleSize(width, height, targetSize)

                val decodeOptions = BitmapFactory.Options().apply {
                    this.inSampleSize = inSampleSize
                }

                inputStream = BufferedInputStream(ContainerInputStream(activity, uriString, fileName, volId), 65536)
                val rawBitmap = BitmapFactory.decodeStream(inputStream, null, decodeOptions)
                inputStream.close()

                if (rawBitmap != null) {
                    val scaledBitmap = scaledToFit(rawBitmap, targetSize)
                    if (scaledBitmap != rawBitmap) rawBitmap.recycle()

                    val stream = ByteArrayOutputStream()
                    val qualityVal = quality.coerceIn(1, 100)
                    scaledBitmap.compress(Bitmap.CompressFormat.JPEG, qualityVal, stream)
                    val bytes = stream.toByteArray()
                    scaledBitmap.recycle()

                    activity.runOnUiThread {
                        result.success(mapOf(
                            "bytes" to bytes,
                            "width" to width,
                            "height" to height
                        ))
                    }
                } else {
                    activity.runOnUiThread { result.error("DECODE_FAILED", "Failed to decode image bytes", null) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

}