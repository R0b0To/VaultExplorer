package com.aeidolon.vaultexplorer.container

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.os.Build
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.locks.ReentrantLock
import com.aeidolon.vaultexplorer.VeLog

/**
 * Process-wide coordinator for hardware video-decoder access and thumbnail
 * work concurrency.
 *
 * Two independent thumbnail pipelines exist in this app, and both can be
 * active at the same moment:
 *  - the in-app pipeline ([com.aeidolon.vaultexplorer.handlers.ThumbnailHandlers],
 *    reached over the Flutter platform channel for content the app's own
 *    file browser is showing)
 *  - the SAF pipeline ([ContainerDocumentsProvider.openDocumentThumbnail],
 *    reached by other installed apps browsing a container/vault exposed
 *    through the system's document-provider integration)
 *
 * [ContainerDocumentsProvider] has no `android:process` override in the
 * manifest, so both pipelines run in this single process and can compete
 * for the same limited hardware video-decoder instances at once — e.g. the
 * user is watching a video in-app while a different app (Files, a gallery,
 * a share-sheet preview) pulls a thumbnail, via SAF, for a different video
 * in the same exposed folder. Before this object existed, each pipeline
 * allocated `MediaMetadataRetriever`/`MediaCodec` resources with zero
 * awareness of the other, which is exactly the contention the in-app
 * pipeline's own lock/flag were built to prevent — just never extended to
 * the SAF caller.
 *
 * This object is the shared choke point both pipelines now go through:
 *  - [videoDecoderLock] serialises hardware-decoder use between the two
 *    pipelines, the same way it previously only serialised within the
 *    in-app pipeline. This is a real, single physical resource, so it
 *    stays genuinely shared.
 *  - [isPlaybackActive] is the single flag both pipelines check before
 *    deciding whether to route to a software-only decoder. Also genuinely
 *    shared, for the same reason.
 *  - [imageExecutor]/[videoExecutor] (in-app) and [safImageExecutor]/
 *    [safVideoExecutor] (SAF) are now **separate** bounded pools, each
 *    replacing what used to be an unbounded raw `Thread` per request.
 *    They used to be the same pool objects shared by both pipelines --
 *    which meant the in-app pipeline's device-capability-sized,
 *    user-facing decode work could queue behind an external app's SAF
 *    thumbnail burst with no priority distinction at all, since a plain
 *    `ThreadPoolExecutor` is FIFO and has no concept of "this caller
 *    matters more." Splitting them means SAF traffic can no longer stall
 *    the app's own visible UI; the SAF pools are deliberately small and
 *    fixed rather than device-tier-sized, since they're servicing another
 *    app's background request, not this app's foreground screen.
 *  - [isCodecResourceError]/[findSoftwareDecoderName] are shared so both
 *    pipelines recognise decoder exhaustion and pick a software decoder
 *    the same way, rather than keeping their own copies that could drift.
 *  - [isLikelyBlankFrame]/[BLANK_FRAME_RETRY_FRACTIONS] are shared so both
 *    pipelines recognise a video's blank leading frame (solid
 *    black/white/other fixed color -- common at time 0: fade-ins, black
 *    leader, a title card/slate) the same way, and retry at the same
 *    later points in the video, rather than keeping their own copies that
 *    could drift or disagree on what "bad" looks like.
 */
object VideoThumbnailCoordinator {
    private const val TAG = "VideoThumbCoordinator"

    /** Serialises hardware video-decoder access across both thumbnail
     *  pipelines (and ExoPlayer's own playback). Fair, so waiters are
     *  served FIFO and neither pipeline can starve the other under
     *  sustained load. */
    val videoDecoderLock = ReentrantLock(true)

    /** True while ExoPlayer is actively decoding in-app. Set/cleared from
     *  `ThumbnailHandlers.handleSetPlaybackActive` — the SAF pipeline only
     *  ever reads it, the same way it only ever reads [videoDecoderLock]
     *  (it never drives playback state itself). */
    @Volatile
    var isPlaybackActive: Boolean = false

    /** Bounded pool for image thumbnail decode work from the **in-app**
     *  pipeline only. Resized per device capability by
     *  `MainActivity.resizeExecutorPools()` — only the ownership of the
     *  pool moved here, not the sizing policy. */
    val imageExecutor: ThreadPoolExecutor =
        Executors.newFixedThreadPool(2) as ThreadPoolExecutor

    /** Bounded pool for video thumbnail decode work from the **in-app**
     *  pipeline only. Single-threaded by default — video frame extraction
     *  is the expensive, decoder-contending case, so it stays
     *  intentionally narrow. */
    val videoExecutor: ThreadPoolExecutor =
        Executors.newFixedThreadPool(1) as ThreadPoolExecutor

    /** Bounded pool for image thumbnail decode work from the **SAF**
     *  pipeline only (other installed apps browsing an exposed vault
     *  folder). Deliberately fixed and small rather than device-tier-sized
     *  or shared with [imageExecutor] -- this is background work for
     *  another app, not the user's own foreground screen, and it should
     *  never be able to make the in-app grid feel slow. */
    val safImageExecutor: ThreadPoolExecutor =
        Executors.newFixedThreadPool(1) as ThreadPoolExecutor

    /** Bounded pool for video thumbnail decode work from the **SAF**
     *  pipeline only. Same rationale as [safImageExecutor]; kept
     *  single-threaded since video frame extraction is the more
     *  decoder-contending case. */
    val safVideoExecutor: ThreadPoolExecutor =
        Executors.newFixedThreadPool(1) as ThreadPoolExecutor

    /** Single-thread pool dedicated to the playback-active "gate" probe
     *  in `ThumbnailHandlers.handleSetPlaybackActive` — deliberately its
     *  *own* pool, never [videoExecutor] or [safVideoExecutor].
     *
     *  Those two pools run the actual thumbnail decode work, which on a
     *  slow/cloud-backed SAF root can be blocked for tens of seconds
     *  inside `readAt()` (pulling+decrypting bytes from Drive/WebDAV/etc.
     *  over Binder) while still holding [videoDecoderLock]. If the gate
     *  probe were queued onto either of those pools, it would sit behind
     *  that in-flight I/O — on their single thread — regardless of any
     *  timeout placed *inside* the probe, since it wouldn't even start
     *  running until the thread freed up. Giving the probe its own
     *  thread means a [videoDecoderLock] wait-with-timeout is actually
     *  bounded in wall-clock time, which is the whole point: the user
     *  tapping a video to play it must never be held hostage by an
     *  unrelated (or even the same) file's slow cloud thumbnail pull. */
    val playbackGateExecutor: ThreadPoolExecutor =
        Executors.newFixedThreadPool(1) as ThreadPoolExecutor

    /** Returns true if [e] looks like a hardware video-decoder resource
     *  exhaustion error (OMX_ErrorInsufficientResources / NO_MEMORY). */
    fun isCodecResourceError(e: Throwable): Boolean {
        if (e is MediaCodec.CodecException) return true
        val msg = e.message?.lowercase() ?: return false
        return msg.contains("omx_errorinsufficientresources") ||
               msg.contains("no_memory") ||
               msg.contains("codec") ||
               msg.contains("0x80001000") // OMX_ErrorInsufficientResources hex
    }

    /**
     * Finds an explicit software-only decoder name for [mimeType]
     * (`c2.android.*` / `OMX.google.*`), so a caller can extract a frame
     * without allocating or contending for hardware decoder instances.
     *
     * REGULAR_CODECS (not ALL_CODECS): ALL_CODECS can surface
     * vendor/restricted codecs that aren't safely instantiable through
     * normal MediaCodec.createByCodecName calls, which defeats the point
     * of asking for a *reliable* software path.
     */
    fun findSoftwareDecoderName(mimeType: String): String? {
        try {
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
            VeLog.w(TAG) { "Error listing software decoders: ${e.message}" }
        }
        return null
    }

    /** Shared bounds-preserving inSampleSize calculation, used by both
     *  pipelines' bitmap decoders (previously two near-identical private
     *  copies — one per pipeline, with different parameter shapes).
     *  Guarantees the decoded bitmap is at least [reqWidth]x[reqHeight]
     *  (standard Android BitmapFactory sample-size pattern). */
    fun calculateInSampleSize(width: Int, height: Int, reqWidth: Int, reqHeight: Int): Int {
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            while (halfHeight / inSampleSize >= reqHeight &&
                   halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    /** Square-target convenience overload — the in-app pipeline only ever
     *  requests square thumbnails. */
    fun calculateInSampleSize(width: Int, height: Int, targetSize: Int): Int =
        calculateInSampleSize(width, height, targetSize, targetSize)

    /** Scales [src] down to fit within [maxEdge] on its longer side,
     *  preserving aspect ratio. Returns [src] unchanged if it already
     *  fits. Shared with [ContainerDocumentsProvider]'s video-thumbnail
     *  path, which previously had no scaling step of its own and relied
     *  entirely on the surface/decoder target size. */
    fun scaledToFit(src: Bitmap, maxEdge: Int): Bitmap {
        val w = src.width
        val h = src.height
        if (w <= maxEdge && h <= maxEdge) return src
        val scale = maxEdge.toFloat() / maxOf(w, h)
        val dstW = (w * scale).toInt().coerceAtLeast(1)
        val dstH = (h * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, dstW, dstH, true)
    }
/**
     * Fractions of a video's duration to try if the initial frame turns out
     * to be blank, a title card, or an intro slate.
     * Retrying at 25% and 45% bypasses extended opening themes and title sequences.
     */
    val BLANK_FRAME_RETRY_FRACTIONS: DoubleArray = doubleArrayOf(0.25, 0.45)

    /**
     * Calculates the best starting timestamp (in microseconds) for a thumbnail.
     * Seeking to 0L hits camera auto-exposure hunting, black fade-ins, or
     * distributor/studio bumpers. Aiming for ~10-12% (or 1.5s for shorter clips)
     * hits real content on the first seek.
     */
    fun getInitialThumbnailTimeUs(durationUs: Long): Long {
        if (durationUs <= 0L) return 1_500_000L // 1.5s default if duration is unknown
        val target = (durationUs * 0.12).toLong()
        val maxSafe = (durationUs * 0.5).toLong()
        return when {
            durationUs < 3_000_000L -> durationUs / 3               // Very short (<3s): 1/3 point
            target < 1_500_000L -> minOf(1_500_000L, maxSafe)       // Short clip: 1.5s
            else -> minOf(target, maxSafe)                           // Standard/long video: ~12%
        }
    }

    private const val BLANK_FRAME_LUMA_RANGE_THRESHOLD = 14
    private const val BLANK_FRAME_CHANNEL_RANGE_THRESHOLD = 18

    /**
     * Detects whether [bitmap] is an uninformative or "bad" thumbnail frame:
     * - Solid or flat colors (black leader, white screen, slate)
     * - Murky / underexposed frames (average luma < 18)
     * - Blown-out white frames (average luma > 240)
     * - Title cards & logo slates (e.g. 80%+ of sampled pixels are dark background)
     * - Low-contrast frames (standard deviation < 8.0)
     */
    fun isLikelyBlankFrame(bitmap: Bitmap): Boolean {
        return try {
            val width = bitmap.width
            val height = bitmap.height
            if (width <= 0 || height <= 0) return false

            val gridSize = 8
            val totalSamples = gridSize * gridSize
            var minLuma = 255; var maxLuma = 0
            var minR = 255; var maxR = 0
            var minG = 255; var maxG = 0
            var minB = 255; var maxB = 0

            var sumLuma = 0L
            var darkPixels = 0
            var brightPixels = 0
            val lumas = IntArray(totalSamples)
            var sampleIdx = 0

            for (row in 0 until gridSize) {
                for (col in 0 until gridSize) {
                    val x = (((col + 0.5) / gridSize) * width).toInt().coerceIn(0, width - 1)
                    val y = (((row + 0.5) / gridSize) * height).toInt().coerceIn(0, height - 1)
                    val pixel = bitmap.getPixel(x, y)
                    val r = (pixel shr 16) and 0xFF
                    val g = (pixel shr 8) and 0xFF
                    val b = pixel and 0xFF
                    val luma = (r * 299 + g * 587 + b * 114) / 1000

                    lumas[sampleIdx++] = luma
                    sumLuma += luma
                    if (luma < 25) darkPixels++
                    if (luma > 230) brightPixels++

                    if (luma < minLuma) minLuma = luma
                    if (luma > maxLuma) maxLuma = luma
                    if (r < minR) minR = r
                    if (r > maxR) maxR = r
                    if (g < minG) minG = g
                    if (g > maxG) maxG = g
                    if (b < minB) minB = b
                    if (b > maxB) maxB = b
                }
            }

            val lumaRange = maxLuma - minLuma
            val channelRange = maxOf(maxR - minR, maxG - minG, maxB - minB)

            // 1. Solid / flat color frame
            if (lumaRange <= BLANK_FRAME_LUMA_RANGE_THRESHOLD && channelRange <= BLANK_FRAME_CHANNEL_RANGE_THRESHOLD) {
                return true
            }

            val avgLuma = sumLuma.toDouble() / totalSamples

            // 2. Near pitch-black or blown-out white
            if (avgLuma < 18.0 || avgLuma > 240.0) {
                return true
            }

            // 3. Logo slates / title cards (majority of frame is background)
            if (darkPixels >= (totalSamples * 0.80) && avgLuma < 35.0) {
                return true
            }
            if (brightPixels >= (totalSamples * 0.85) && avgLuma > 215.0) {
                return true
            }

            // 4. Low-contrast / low-detail frame
            var varianceSum = 0.0
            for (l in lumas) {
                val diff = l - avgLuma
                varianceSum += diff * diff
            }
            val stdDev = Math.sqrt(varianceSum / totalSamples)
            if (stdDev < 8.0) {
                return true
            }

            false
        } catch (e: Exception) {
            VeLog.w(TAG) { "isLikelyBlankFrame check failed, treating frame as not blank: ${e.message}" }
            false
        }
    }

    /**
     * Drains [extractor]/[codec] for a single decoded frame at [seekTimeUs],
     * flushing the codec and re-seeking the extractor first so the pair can
     * be reused for another timestamp on the very next call rather than
     * torn down and rebuilt.
     *
     * Moved here (from `ThumbnailHandlers`, which still forwards to this
     * copy so its own call sites are unchanged) so
     * `NativePlayerManager`'s scrub-preview session -- repeated seeks
     * against one long-lived software decoder while the user drags the
     * seekbar -- can drive the same extractor/codec pair this way without
     * a second, drifting copy of the drain loop.
     */
    fun decodeSoftwareFrameAt(
        extractor: MediaExtractor,
        codec: MediaCodec,
        seekTimeUs: Long,
    ): Bitmap? {
        extractor.seekTo(seekTimeUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        codec.flush()

        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputFrame: Bitmap? = null
        val timeoutUs = 10_000L
        // 30 attempts (~300ms) was too tight for slower software decoders
        // to reliably yield a first frame; 100 (~1s worst case) gives
        // real headroom without risking a multi-second stall. See the
        // matching note on the original call site in ThumbnailHandlers
        // for why this budget is kept bounded rather than raised further.
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
        return outputFrame
    }

    // How long the decode loop may go without the codec producing anything
    // before it gives up. Matches the ~1s worst case the fixed attempt
    // budget in decodeSoftwareFrameAt works out to.
    private const val DECODE_STALL_LIMIT_NS = 1_000_000_000L

    /**
     * Like [decodeSoftwareFrameAt], but returns the frame at [targetUs]
     * (to within [toleranceUs]) instead of just the keyframe the seek
     * lands on.
     *
     * [decodeSoftwareFrameAt] hands back the first frame the decoder
     * produces after a seek, which is always a keyframe. That's plenty for
     * a browser thumbnail, and for scrubbing a long video where a slider
     * pixel spans many seconds -- but for a short clip, whose keyframes
     * may be a second apart, the preview can only ever show a handful of
     * distinct frames however finely the user drags.
     *
     * This keeps decoding forward from the keyframe and *drops* every frame
     * before the target without converting it, so the extra cost per
     * request is decoding, not the (much heavier) YUV -> Bitmap conversion.
     * Two things keep that cost bounded:
     *  - [budgetMs]: once it has been spent, the next frame out is returned
     *    even if it is still short of the target. The [cursor] remembers
     *    where the decoder got to, so the following request carries on from
     *    there and closes the gap.
     *  - [cursor]: a request at or just past the previous one keeps
     *    decoding forward instead of seeking and flushing, which makes a
     *    steady forward drag cost only the handful of frames between
     *    requests.
     *
     * [cursor] must be reset by the caller whenever the codec is torn down
     * or this throws.
     */
    fun decodeSoftwareFrameNear(
        extractor: MediaExtractor,
        codec: MediaCodec,
        targetUs: Long,
        toleranceUs: Long,
        cursor: SoftwareDecodeCursor,
        budgetMs: Long,
    ): Bitmap? = decodeNear(
        extractor, codec, targetUs, toleranceUs, cursor, budgetMs, allowEndRetry = true,
    )

    private fun decodeNear(
        extractor: MediaExtractor,
        codec: MediaCodec,
        targetUs: Long,
        toleranceUs: Long,
        cursor: SoftwareDecodeCursor,
        budgetMs: Long,
        allowEndRetry: Boolean,
    ): Bitmap? {
        if (!cursor.canContinueTo(targetUs)) {
            extractor.seekTo(targetUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            codec.flush()
            cursor.reset()
        }

        val info = MediaCodec.BufferInfo()
        val timeoutUs = 10_000L
        val startNs = System.nanoTime()
        val budgetNs = budgetMs * 1_000_000L
        var lastProgressNs = startNs
        var newestPtsUs = SoftwareDecodeCursor.NONE
        var reachedEnd = false

        while (System.nanoTime() - lastProgressNs < DECODE_STALL_LIMIT_NS) {
            if (!cursor.inputDone) {
                val inputIndex = codec.dequeueInputBuffer(timeoutUs)
                if (inputIndex >= 0) {
                    val inputBuffer = codec.getInputBuffer(inputIndex)
                    if (inputBuffer != null) {
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            cursor.inputDone = true
                        } else {
                            val presentationTimeUs = extractor.sampleTime
                            codec.queueInputBuffer(inputIndex, 0, sampleSize, presentationTimeUs, 0)
                            extractor.advance()
                        }
                    }
                }
            }

            val outputIndex = codec.dequeueOutputBuffer(info, timeoutUs)
            if (outputIndex < 0) continue
            lastProgressNs = System.nanoTime()

            var frame: Bitmap? = null
            if (info.size > 0) {
                val ptsUs = info.presentationTimeUs
                cursor.lastOutputPtsUs = ptsUs
                if (ptsUs > newestPtsUs) newestPtsUs = ptsUs
                val outOfTime = lastProgressNs - startNs >= budgetNs
                if (hasReachedTarget(ptsUs, targetUs, toleranceUs) || outOfTime) {
                    frame = outputToBitmap(codec, outputIndex)
                }
            }
            val endOfStream = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
            codec.releaseOutputBuffer(outputIndex, false)

            if (frame != null) return frame
            if (endOfStream) {
                reachedEnd = true
                break
            }
        }

        // The stream ended before any frame got to the target, i.e. the
        // target is past the last frame -- a container's reported duration
        // usually runs a little longer than its final video frame, so
        // dragging to the very end of the slider lands here. Show that last
        // frame rather than nothing, now that we know its time.
        if (reachedEnd && allowEndRetry && newestPtsUs != SoftwareDecodeCursor.NONE) {
            return decodeNear(
                extractor, codec, newestPtsUs, 0L, cursor, budgetMs, allowEndRetry = false,
            )
        }
        return null
    }

    /** Converts the decoder output buffer at [outputIndex] to a [Bitmap], or null if it has no image. */
    private fun outputToBitmap(codec: MediaCodec, outputIndex: Int): Bitmap? {
        val image = codec.getOutputImage(outputIndex) ?: return null
        return try {
            yuv420ToBitmap(image)
        } finally {
            image.close()
        }
    }

    /** Converts a YUV_420_888 [android.media.Image] (the output format of
     *  an explicit software [MediaCodec] decoder) to a [Bitmap] via an
     *  intermediate NV21 buffer + JPEG round-trip -- there's no direct
     *  YUV-to-Bitmap constructor in the framework. Shared with
     *  `ThumbnailHandlers` for the same reason as [decodeSoftwareFrameAt]. */
    fun yuv420ToBitmap(image: android.media.Image): Bitmap {
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
