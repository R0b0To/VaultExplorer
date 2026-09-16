package com.aeidolon.vaultexplorer.container

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaCodecList
import android.os.Build
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
}
