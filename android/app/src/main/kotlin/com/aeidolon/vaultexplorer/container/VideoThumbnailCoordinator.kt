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
}
