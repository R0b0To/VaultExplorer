package com.aeidolon.vaultexplorer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService

/**
 * Thumbnail generation for images/video inside a mounted container: a quick
 * preview thumbnail for the file browser grid (image `inSampleSize` decode,
 * video `MediaMetadataRetriever` frame extraction). The on-disk thumbnail
 * cache itself is owned entirely by the Dart-side `ThumbnailCacheService`
 * (see architecture.md Ownership Rule 2) — this class only ever returns raw
 * bytes to the platform channel and never writes to disk itself.
 */
class ThumbnailHandlers(
    private val activity: MainActivity,
    private val thumbnailExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
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

    fun handleGetVideoThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val fileName  = call.argument<String>("fileName")
        val targetSize = call.argument<Int>("targetSize") ?: 180

        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        thumbnailExecutor.execute {
            var retriever: MediaMetadataRetriever? = null
            try {
                val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                    ?: run {
                        activity.runOnUiThread {
                            result.error("NOT_MOUNTED", "Container not mounted", null)
                        }
                        return@execute
                    }

                retriever = MediaMetadataRetriever()

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val dataSource = ContainerMediaDataSource(activity, uriString, fileName, volId)
                    retriever.setDataSource(dataSource)

                    val durationMs = retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull() ?: 10_000L
                    val timeMs = minOf(1000L, durationMs / 4)

                    val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        runCatching {
                            retriever.getScaledFrameAtTime(
                                timeMs * 1000L,
                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                targetSize,
                                targetSize
                            )
                        }.getOrNull() ?: retriever.getFrameAtTime(timeMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    } else {
                        retriever.getFrameAtTime(timeMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    }

                    if (frame != null) {
                        val scaledFrame = scaledToFit(frame, targetSize)
                        val quality = (call.argument<Int>("quality") ?: 60).coerceIn(1, 100)
                        val stream = ByteArrayOutputStream()
                        scaledFrame.compress(Bitmap.CompressFormat.JPEG, quality, stream)
                        val bytes = stream.toByteArray()
                        if (scaledFrame != frame) scaledFrame.recycle()
                        frame.recycle()
                        activity.runOnUiThread { result.success(bytes) }
                    } else {
                        activity.runOnUiThread { result.error("FRAME_FAILED", "Failed to extract frame", null) }
                    }
                } else {
                    activity.runOnUiThread { result.error("UNSUPPORTED_OS", "Requires Android 6.0+", null) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                runCatching { retriever?.release() }
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

        thumbnailExecutor.execute {
            var retriever: MediaMetadataRetriever? = null
            try {
                val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                    ?: run {
                        activity.runOnUiThread {
                            result.error("NOT_MOUNTED", "Container not mounted", null)
                        }
                        return@execute
                    }

                retriever = MediaMetadataRetriever()

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val dataSource = ContainerMediaDataSource(activity, uriString, fileName, volId)
                    retriever.setDataSource(dataSource)

                    val durationMs = retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull() ?: 10_000L
                    val timeMs = minOf(1000L, durationMs / 4)

                    val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        runCatching {
                            retriever.getScaledFrameAtTime(
                                timeMs * 1000L,
                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                targetSize,
                                targetSize
                            )
                        }.getOrNull() ?: retriever.getFrameAtTime(timeMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    } else {
                        retriever.getFrameAtTime(timeMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    }

                    if (frame != null) {
                        val sourceWidth = frame.width
                        val sourceHeight = frame.height
                        val scaledFrame = scaledToFit(frame, targetSize)
                        val quality = (call.argument<Int>("quality") ?: 60).coerceIn(1, 100)
                        val stream = ByteArrayOutputStream()
                        scaledFrame.compress(Bitmap.CompressFormat.JPEG, quality, stream)
                        val bytes = stream.toByteArray()
                        if (scaledFrame != frame) scaledFrame.recycle()
                        frame.recycle()
                        activity.runOnUiThread {
                            result.success(mapOf(
                                "bytes" to bytes,
                                "width" to sourceWidth,
                                "height" to sourceHeight
                            ))
                        }
                    } else {
                        activity.runOnUiThread { result.error("FRAME_FAILED", "Failed to extract frame", null) }
                    }
                } else {
                    activity.runOnUiThread { result.error("UNSUPPORTED_OS", "Requires Android 6.0+", null) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                runCatching { retriever?.release() }
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

        thumbnailExecutor.execute {
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

        thumbnailExecutor.execute {
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