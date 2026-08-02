package com.aeidolon.vaultexplorer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
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
    ): VideoFrameResult? {
        if (isPlaybackActive) {
            Log.d(TAG, "Playback active: attempting software MediaCodec frame extraction for $fileName")
            val swResult = extractVideoFrameSoftware(uriString, fileName, volId, targetSize, quality)
            if (swResult != null) return swResult
            Log.d(TAG, "Software extraction unavailable or failed for $fileName while playing")
            return null
        }

        videoDecoderLock.lock()
        try {
            if (isPlaybackActive) {
                return extractVideoFrameSoftware(uriString, fileName, volId, targetSize, quality)
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
     *  earlier, more precise check. */
    private fun extractImageThumbnail(
        uriString: String,
        fileName: String,
        volId: Int,
        targetSize: Int,
        quality: Int,
    ): ImageThumbnailOutcome {
        var inputStream = BufferedInputStream(ContainerInputStream(activity, uriString, fileName, volId), 65536)

        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeStream(inputStream, null, options)
        inputStream.close()

        val width = options.outWidth
        val height = options.outHeight

        if (width <= 0 || height <= 0) {
            return ImageThumbnailOutcome.Failure("DECODE_FAILED", "Failed to read image bounds")
        }

        val inSampleSize = calculateInSampleSize(width, height, targetSize)
        val decodeOptions = BitmapFactory.Options().apply { this.inSampleSize = inSampleSize }

        inputStream = BufferedInputStream(ContainerInputStream(activity, uriString, fileName, volId), 65536)
        val rawBitmap = BitmapFactory.decodeStream(inputStream, null, decodeOptions)
        inputStream.close()

        if (rawBitmap == null) {
            return ImageThumbnailOutcome.Failure("DECODE_FAILED", "Failed to decode image bytes")
        }

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

                when (val outcome = extractImageThumbnail(uriString, fileName, volId, targetSize, quality)) {
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
    ): VideoFrameResult? {
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
            val dataSource = ContainerMediaDataSource(activity, uriString, fileName, volId)
            extractor = MediaExtractor()
            extractor.setDataSource(dataSource)

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
            Log.d(TAG, "Using software video decoder '$swCodecName' for thumbnail: $fileName")

            extractor.selectTrack(videoTrackIndex)

            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION)
            } else 10_000_000L
            val seekTimeUs = minOf(1_000_000L, durationUs / 4)
            extractor.seekTo(seekTimeUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            codec = MediaCodec.createByCodecName(swCodecName)
            codec.configure(format, null, null, 0)
            codec.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputFrame: Bitmap? = null
            val timeoutUs = 10_000L
            // 30 attempts (~300ms) was too tight for slower software decoders
            // to reliably yield a first frame; 100 (~1s worst case) gives
            // real headroom without risking a multi-second stall. Note this
            // budget matters beyond just this one request: handleGetVideoThumbnail
            // and handleSetPlaybackActive(active=true) both run on the same
            // single-thread videoExecutor, so a slow extraction here also
            // delays how long ExoPlayer's initialize() has to wait — keep
            // this bounded, don't just crank it up further.
            val maxAttempts = 100
            var attempts = 0

            while (outputFrame == null && attempts < maxAttempts) {
                attempts++
                if (!inputDone) {
                    val inputIndex = codec.dequeueInputBuffer(timeoutUs)
                    if (inputIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputIndex)
                        if (inputBuffer != null) {
                            val sampleSize = extractor.readSampleData(inputBuffer, 0)
                            if (sampleSize < 0) {
                                codec.queueInputBuffer(inputIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                val presentationTimeUs = extractor.sampleTime
                                codec.queueInputBuffer(inputIndex, 0, sampleSize, presentationTimeUs, 0)
                                extractor.advance()
                            }
                        }
                    }
                }

                val outputIndex = codec.dequeueOutputBuffer(info, timeoutUs)
                if (outputIndex >= 0) {
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        break
                    }
                    if (info.size > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        val image = codec.getOutputImage(outputIndex)
                        if (image != null) {
                            outputFrame = yuv420ToBitmap(image)
                            image.close()
                        }
                    }
                    codec.releaseOutputBuffer(outputIndex, false)
                }
            }

            if (outputFrame != null) {
                return compressFrame(outputFrame, targetSize, quality)
            }
            return null
        } catch (e: Exception) {
            Log.w(TAG, "Software MediaCodec extraction failed for $fileName: ${e.message}")
            return null
        } finally {
            runCatching {
                codec?.stop()
                codec?.release()
            }
            runCatching { extractor?.release() }
        }
    }

    private fun findSoftwareDecoderName(mimeType: String): String? {
        try {
            // REGULAR_CODECS (not ALL_CODECS): ALL_CODECS can surface
            // vendor/restricted codecs that aren't safely instantiable
            // through normal MediaCodec.createByCodecName calls, which
            // defeats the point of asking for a *reliable* software path.
            val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            for (info in codecList.codecInfos) {
                if (info.isEncoder) continue
                val types = info.supportedTypes
                var matches = false
                for (t in types) {
                    if (t.equals(mimeType, ignoreCase = true)) {
                        matches = true
                        break
                    }
                }
                if (!matches) continue
                val name = info.name
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && info.isSoftwareOnly) {
                    return name
                }
                if (name.startsWith("c2.android.", ignoreCase = true) ||
                    name.startsWith("OMX.google.", ignoreCase = true)) {
                    return name
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error listing software decoders: ${e.message}")
        }
        return null
    }

    private fun yuv420ToBitmap(image: android.media.Image): Bitmap {
        val width = image.width
        val height = image.height
        val planes = image.planes

        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]

        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer

        val yRowStride = yPlane.rowStride
        val uvRowStride = uPlane.rowStride
        val uvPixelStride = uPlane.pixelStride

        // Ceiling division: 4:2:0 chroma planes still exist for odd
        // width/height (e.g. a cropped or user-generated source), just
        // rounded up by one sample. width/2, height/2 (floor) would
        // under-size the NV21 buffer and silently drop the last chroma
        // row/column for such videos.
        val chromaWidth = (width + 1) / 2
        val chromaHeight = (height + 1) / 2
        // NV21 requires exactly width * height Y bytes followed by
        // 2 * chromaWidth * chromaHeight interleaved V and U bytes.
        val nv21 = ByteArray(width * height + chromaWidth * chromaHeight * 2)

        // 1. Copy Y plane, stripping row padding if yRowStride > width
        var nvIndex = 0
        if (yRowStride == width) {
            yBuffer.get(nv21, 0, width * height)
            nvIndex = width * height
        } else {
            val yRow = ByteArray(yRowStride)
            for (row in 0 until height) {
                val toRead = minOf(yRowStride, yBuffer.remaining())
                if (toRead <= 0) break
                yBuffer.get(yRow, 0, toRead)
                val copyLen = minOf(width, toRead)
                System.arraycopy(yRow, 0, nv21, nvIndex, copyLen)
                nvIndex += width
            }
        }

        // 2. Interleave V and U planes into NV21 format (V0, U0, V1, U1...)
        val vRow = ByteArray(uvRowStride)
        val uRow = ByteArray(uvRowStride)

        for (row in 0 until chromaHeight) {
            val vPos = row * uvRowStride
            val uPos = row * uvRowStride

            if (vPos < vBuffer.capacity() && uPos < uBuffer.capacity()) {
                vBuffer.position(vPos)
                uBuffer.position(uPos)

                val vRead = minOf(uvRowStride, vBuffer.remaining())
                val uRead = minOf(uvRowStride, uBuffer.remaining())

                if (vRead > 0 && uRead > 0) {
                    vBuffer.get(vRow, 0, vRead)
                    uBuffer.get(uRow, 0, uRead)

                    for (col in 0 until chromaWidth) {
                        val vIdx = col * uvPixelStride
                        val uIdx = col * uvPixelStride
                        if (vIdx < vRead && uIdx < uRead && nvIndex + 1 < nv21.size) {
                            nv21[nvIndex++] = vRow[vIdx]
                            nv21[nvIndex++] = uRow[uIdx]
                        }
                    }
                }
            }
        }

        val yuvImage = YuvImage(
            nv21,
            ImageFormat.NV21,
            width,
            height,
            null
        )
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, width, height), 90, out)
        val jpegBytes = out.toByteArray()
        return BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
    }


}