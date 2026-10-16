package com.aeidolon.vaultexplorer.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ThumbnailUtils
import android.os.Handler
import android.os.Looper
import androidx.exifinterface.media.ExifInterface
import com.aeidolon.vaultexplorer.VeLog
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.max

private const val DOC_SCAN_CHANNEL = "com.aeidolon.vaultexplorer/docscan"
private const val DOC_SCAN_TAG = "DocumentScan"

// Long side of the image used for detection and for the on-screen crop editor.
private const val DETECT_LONG_SIDE = 1600

/** JNI entry points implemented in cpp/jni/docscan_bridge.cpp. */
object DocumentScanNative {
    init {
        // Already loaded by NativeEngine in a normal run; loading is idempotent.
        System.loadLibrary("vaultexplorer")
    }

    /** RGBA_8888 in a direct buffer -> [x0,y0,..,x3,y3,score] normalised, or null. */
    external fun nativeDetectRgba(rgba: ByteBuffer, width: Int, height: Int): FloatArray?

    external fun nativeOutputSize(quad: FloatArray, srcW: Int, srcH: Int, maxLongSide: Int): IntArray?

    external fun nativeWarp(
        src: ByteBuffer, srcW: Int, srcH: Int, quad: FloatArray,
        dst: ByteBuffer, dstW: Int, dstH: Int,
    ): Boolean

    external fun nativeFilter(rgba: ByteBuffer, width: Int, height: Int, filter: Int): Boolean

    /** Page sizes are read from the JPEG headers; null if a page is not an embeddable JPEG. */
    external fun nativeBuildPdf(jpegs: Array<ByteArray>): ByteArray?
}

/**
 * Document scanning on top of the camera: edge detection on a captured photo,
 * perspective correction + filters, and PDF assembly.
 *
 * Everything stays in memory (byte arrays, direct buffers, bitmaps): no temp
 * files are created, in keeping with the "no plaintext on disk" rule. Heavy work
 * runs on one worker thread; results are posted back on the main thread.
 */
class DocumentScanPlugin(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, DOC_SCAN_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    // Pages are big (tens of MB each): never process two at once.
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "docscan-worker").apply { isDaemon = true }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "detect" -> {
                val bytes = call.argument<ByteArray>("bytes")
                    ?: return result.error("bad_args", "bytes missing", null)
                runAsync(result) { detect(bytes) }
            }

            "process" -> {
                val bytes = call.argument<ByteArray>("bytes")
                    ?: return result.error("bad_args", "bytes missing", null)
                val corners = call.argument<List<Double>>("corners")?.takeIf { it.size == 8 }
                    ?: return result.error("bad_args", "corners must hold 8 numbers", null)
                val filter = (call.argument<Int>("filter") ?: 1).coerceIn(0, 3)
                val rotation = call.argument<Int>("rotation") ?: 0
                val maxLongSide = (call.argument<Int>("maxLongSide") ?: 3000).coerceIn(300, 6000)
                val quality = (call.argument<Int>("quality") ?: 88).coerceIn(50, 100)
                runAsync(result) { process(bytes, corners, filter, rotation, maxLongSide, quality) }
            }

            "buildPdf" -> {
                val pages = call.argument<List<ByteArray>>("pages")
                if (pages.isNullOrEmpty()) return result.error("bad_args", "pages missing", null)
                runAsync(result) { buildPdf(pages) }
            }

            else -> result.notImplemented()
        }
    }

    private fun runAsync(result: MethodChannel.Result, work: () -> Any?) {
        executor.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: OutOfMemoryError) {
                mainHandler.post { result.error("out_of_memory", "Not enough memory to process the page", null) }
            } catch (e: Exception) {
                VeLog.w(DOC_SCAN_TAG, e) { "scan task failed" }
                mainHandler.post { result.error("scan_failed", e.message, null) }
            }
        }
    }

    // ───────────────────────────── detect ─────────────────────────────

    /**
     * Decodes the (EXIF-rotated) photo at ~1600 px, finds the document quad and
     * returns that same upright image as a preview, so the corners the editor
     * shows always line up with the pixels it displays.
     */
    private fun detect(bytes: ByteArray): Map<String, Any?> {
        val bmp = decodeUpright(bytes, DETECT_LONG_SIDE)
            ?: throw IllegalArgumentException("Cannot decode image")
        try {
            val w = bmp.width
            val h = bmp.height
            val det = DocumentScanNative.nativeDetectRgba(toDirectBuffer(bmp), w, h)
            val preview = ByteArrayOutputStream(w * h / 8).also {
                bmp.compress(Bitmap.CompressFormat.JPEG, 85, it)
            }.toByteArray()
            return mapOf(
                "preview" to preview,
                "width" to w,
                "height" to h,
                "corners" to det?.let { d -> List(8) { i -> d[i].toDouble() } },
                "score" to (det?.get(8)?.toDouble() ?: 0.0),
            )
        } finally {
            bmp.recycle()
        }
    }

    // ───────────────────────────── process ─────────────────────────────

    private fun process(
        bytes: ByteArray, corners: List<Double>, filter: Int, rotation: Int,
        maxLongSide: Int, quality: Int,
    ): Map<String, Any?> {
        return try {
            processOnce(bytes, corners, filter, rotation, maxLongSide, quality)
        } catch (_: OutOfMemoryError) {
            // Low-memory device: retry once at half the size instead of failing the scan.
            processOnce(bytes, corners, filter, rotation, maxLongSide / 2, quality)
        }
    }

    private fun processOnce(
        bytes: ByteArray, corners: List<Double>, filter: Int, rotation: Int,
        maxLongSide: Int, quality: Int,
    ): Map<String, Any?> {
        val quad = FloatArray(8) { corners[it].toFloat().coerceIn(0f, 1f) }

        // Decode just large enough for the requested output, and hand the pixels
        // to native code through a direct buffer so the heap copy can go early.
        val src = decodeUpright(bytes, maxLongSide) ?: throw IllegalArgumentException("Cannot decode image")
        val srcW = src.width
        val srcH = src.height
        val srcBuf = toDirectBuffer(src)
        src.recycle()

        val size = DocumentScanNative.nativeOutputSize(quad, srcW, srcH, maxLongSide)
            ?: throw IllegalStateException("Invalid corner geometry")
        val dstW = size[0]
        val dstH = size[1]
        val dstBuf = ByteBuffer.allocateDirect(dstW * dstH * 4)
        check(DocumentScanNative.nativeWarp(srcBuf, srcW, srcH, quad, dstBuf, dstW, dstH)) { "Warp failed" }
        if (filter != 0) {
            check(DocumentScanNative.nativeFilter(dstBuf, dstW, dstH, filter)) { "Filter failed" }
        }

        var page = Bitmap.createBitmap(dstW, dstH, Bitmap.Config.ARGB_8888)
        page.copyPixelsFromBuffer(dstBuf)

        val turns = ((rotation % 360) + 360) % 360
        if (turns != 0) {
            val rotated = Bitmap.createBitmap(
                page, 0, 0, page.width, page.height,
                Matrix().apply { postRotate(turns.toFloat()) }, true,
            )
            page.recycle()
            page = rotated
        }

        try {
            val jpeg = ByteArrayOutputStream(page.width * page.height / 6).also {
                page.compress(Bitmap.CompressFormat.JPEG, quality, it)
            }.toByteArray()
            // Same tile shape the regular camera produces for its tray.
            val thumb = ThumbnailUtils.extractThumbnail(page, 160, 160)
            val thumbBytes = ByteArrayOutputStream().also {
                thumb.compress(Bitmap.CompressFormat.JPEG, 70, it)
            }.toByteArray()
            if (thumb !== page) thumb.recycle()
            return mapOf(
                "bytes" to jpeg,
                "thumbnail" to thumbBytes,
                "width" to page.width,
                "height" to page.height,
            )
        } finally {
            page.recycle()
        }
    }

    // ───────────────────────────── pdf ─────────────────────────────

    private fun buildPdf(pages: List<ByteArray>): ByteArray {
        DocumentScanNative.nativeBuildPdf(pages.toTypedArray())?.let { return it }
        // A page was not a plain JPEG (e.g. the photo editor emitted a PNG, or an
        // exotic JPEG variant): re-encode every page as JPEG once and retry.
        val normalised = Array(pages.size) { toJpeg(pages[it]) }
        return DocumentScanNative.nativeBuildPdf(normalised) ?: throw IllegalStateException("PDF build failed")
    }

    private fun toJpeg(bytes: ByteArray): ByteArray {
        val bmp = decodeUpright(bytes, Int.MAX_VALUE) ?: throw IllegalArgumentException("Cannot decode page")
        try {
            return ByteArrayOutputStream(bytes.size).also {
                bmp.compress(Bitmap.CompressFormat.JPEG, 90, it)
            }.toByteArray()
        } finally {
            bmp.recycle()
        }
    }

    // ───────────────────────────── helpers ─────────────────────────────

    /** RGBA bytes of an ARGB_8888 bitmap, tightly packed, in a direct buffer. */
    private fun toDirectBuffer(bmp: Bitmap): ByteBuffer {
        val buf = ByteBuffer.allocateDirect(bmp.width * bmp.height * 4)
        bmp.copyPixelsToBuffer(buf)
        buf.rewind()
        return buf
    }

    /**
     * Decodes a JPEG with the EXIF orientation applied, sub-sampled by a power
     * of two but never below [minLongSide] on the long edge.
     */
    private fun decodeUpright(bytes: ByteArray, minLongSide: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val longSide = max(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (longSide / (sample * 2) >= minLongSide) sample *= 2

        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) ?: return null
        val matrix = exifMatrix(bytes)
        if (matrix.isIdentity) return decoded
        val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        if (upright !== decoded) decoded.recycle()
        return upright
    }

    private fun exifMatrix(bytes: ByteArray): Matrix {
        val orientation = try {
            ExifInterface(ByteArrayInputStream(bytes))
                .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                m.setRotate(180f)
                m.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                m.setRotate(90f)
                m.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> m.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                m.setRotate(-90f)
                m.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> m.setRotate(-90f)
        }
        return m
    }
}
