package com.aeidolon.vaultexplorer

import android.app.ActivityManager
import android.content.Context
import java.io.Closeable
import java.util.concurrent.Semaphore

/**
 * Admission control for decoding very large images (e.g. a 100 MB, 857
 * megapixel photo) down to a thumbnail/preview.
 *
 * `BitmapFactory`'s `inSampleSize` bounds the *output* bitmap, not the
 * decoder's working memory, and that working memory depends on the format:
 *  - baseline JPEG and non-interlaced PNG decode row by row, so a sampled
 *    decode needs next to nothing however many pixels the source has;
 *  - progressive JPEG keeps every DCT coefficient of the image in memory
 *    (2 bytes per sample: 6 B/px for 4:4:4, 3 B/px for 4:2:0), and
 *    interlaced PNG keeps the whole image -- an 857 MP progressive 4:4:4 JPEG
 *    wants ~5 GB, which is exactly what got the app killed by the low-memory
 *    killer;
 *  - anything else is assumed to need [WORST_CASE_BYTES_PER_PIXEL].
 * When memory runs out the failure is an `OutOfMemoryError` (an `Error`, so
 * the usual `catch (e: Exception)` never sees it) or the system killing the
 * whole process.
 *
 * Callers read the image bounds and the first bytes of the file (cheap), then
 * call [admit] before the real decode:
 *  - an estimated working set above [MAX_DECODE_ESTIMATE_BYTES] is refused
 *    outright ([CODE_TOO_LARGE]) -- that never changes for the file, so
 *    callers may remember it;
 *  - "heavy" decodes (estimate above [HEAVY_ESTIMATE_BYTES]) run one at a
 *    time, so two of them can never peak together, and are refused
 *    ([CODE_OUT_OF_MEMORY]) when the OS reports too little free memory right
 *    now -- transient, so callers should not remember it.
 *
 * The returned [Permit] MUST be closed when the decode is finished.
 */
object ImageDecodeGuard {
    const val CODE_TOO_LARGE = "IMAGE_TOO_LARGE"
    const val CODE_OUT_OF_MEMORY = "OUT_OF_MEMORY"

    /** Hard ceiling on the estimated decoder working set (2 GiB). Tunable. */
    const val MAX_DECODE_ESTIMATE_BYTES: Long = 2L * 1024 * 1024 * 1024

    /** Sanity ceiling on source pixels; JPEG itself tops out near 4.3 billion. */
    const val ABSOLUTE_MAX_PIXELS: Long = 4_300_000_000L

    /** Above this estimate a decode is serialized and checked against free memory. */
    const val HEAVY_ESTIMATE_BYTES: Long = 192L * 1024 * 1024

    /** Working set assumed for a streaming decode (row buffers, output, slack). */
    const val STREAMING_DECODE_BYTES: Long = 64L * 1024 * 1024

    /** Working set per source pixel when the format can't be classified. */
    const val WORST_CASE_BYTES_PER_PIXEL = 4L

    /** How much of the file's start callers should pass as `header`. */
    const val HEADER_SNIFF_BYTES = 1024 * 1024

    /** Share of the memory available above the OS low-memory line one decode may budget. */
    private const val AVAILABLE_MEMORY_FRACTION = 0.5

    private val heavyDecodeGate = Semaphore(1, true)

    class RefusedException(val code: String, message: String) : Exception(message)

    class Permit internal constructor(private var holdsGate: Boolean) : Closeable {
        @Synchronized
        override fun close() {
            if (holdsGate) {
                holdsGate = false
                heavyDecodeGate.release()
            }
        }
    }

    /**
     * Estimated peak native memory, in bytes, of decoding a [width] x
     * [height] image whose first bytes are [header] (null/unrecognized: the
     * worst-case assumption).
     */
    fun estimateWorkingSetBytes(header: ByteArray?, width: Int, height: Int): Long {
        val pixels = width.toLong() * height.toLong()
        val worstCase = pixels * WORST_CASE_BYTES_PER_PIXEL
        if (header == null) return worstCase
        sniffJpeg(header)?.let { jpeg ->
            if (!jpeg.progressive) return STREAMING_DECODE_BYTES
            // Every component's coefficients are held: 2 bytes per sample,
            // each component sampled h*v/(hmax*vmax) times per pixel.
            val samplesPerPixel = jpeg.samplesPerPixel()
            return STREAMING_DECODE_BYTES + (pixels * samplesPerPixel * 2).toLong()
        }
        sniffPngInterlaced(header)?.let { interlaced ->
            return if (interlaced) pixels * 8L else STREAMING_DECODE_BYTES
        }
        return worstCase
    }

    /**
     * Decides whether a [width] x [height] source (first bytes: [header], if
     * known) may be decoded now. Throws [RefusedException] if not; otherwise
     * returns a [Permit] to close after decoding (in a `finally`).
     */
    @Throws(RefusedException::class)
    fun admit(context: Context, width: Int, height: Int, header: ByteArray? = null): Permit {
        val pixels = width.toLong() * height.toLong()
        val estimate = estimateWorkingSetBytes(header, width, height)
        if (pixels > ABSOLUTE_MAX_PIXELS || estimate > MAX_DECODE_ESTIMATE_BYTES) {
            throw RefusedException(
                CODE_TOO_LARGE,
                "Image is ${width}x$height (${pixels / 1_000_000} MP); decoding it needs about " +
                    "${estimate shr 20} MB, above the ${MAX_DECODE_ESTIMATE_BYTES shr 20} MB limit",
            )
        }
        if (estimate < HEAVY_ESTIMATE_BYTES) return Permit(false)

        heavyDecodeGate.acquire()
        try {
            // Checked after acquiring: waiting for the gate can take a while and
            // the other decode's memory has been released by now.
            checkAvailableMemory(context, pixels, estimate)
        } catch (t: Throwable) {
            heavyDecodeGate.release()
            throw t
        }
        return Permit(true)
    }

    private fun checkAvailableMemory(context: Context, pixels: Long, estimate: Long) {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return
        val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val usable = (info.availMem - info.threshold).coerceAtLeast(0L)
        val budget = (usable * AVAILABLE_MEMORY_FRACTION).toLong()
        if (info.lowMemory || estimate > budget) {
            throw RefusedException(
                CODE_OUT_OF_MEMORY,
                "Decoding a ${pixels / 1_000_000} MP image needs about ${estimate shr 20} MB " +
                    "but only ${budget shr 20} MB can be spared right now",
            )
        }
    }

    // ---- header sniffing ------------------------------------------------

    internal class JpegInfo(val progressive: Boolean, private val samplingFactors: IntArray) {
        /** Sum over components of h*v / (hmax*vmax). */
        fun samplesPerPixel(): Double {
            if (samplingFactors.isEmpty()) return 3.0
            var maxFactor = 1
            for (f in samplingFactors) if (f > maxFactor) maxFactor = f
            var total = 0.0
            for (f in samplingFactors) total += f.toDouble() / maxFactor
            return total
        }
    }

    /** Null if [b] isn't a JPEG or its SOF marker isn't within [b]. */
    internal fun sniffJpeg(b: ByteArray): JpegInfo? {
        if (b.size < 4 || b[0] != 0xFF.toByte() || b[1] != 0xD8.toByte()) return null
        var i = 2
        while (i + 3 < b.size) {
            if (b[i] != 0xFF.toByte()) {
                i++
                continue
            }
            val marker = b[i + 1].toInt() and 0xFF
            if (marker == 0xFF) {
                i++ // fill byte
                continue
            }
            i += 2
            if (marker == 0xD8 || marker == 0x01 || marker in 0xD0..0xD7) continue
            if (marker == 0xDA) return null // scan data before any SOF: malformed
            if (i + 2 > b.size) return null
            val length = ((b[i].toInt() and 0xFF) shl 8) or (b[i + 1].toInt() and 0xFF)
            val isSof = marker in 0xC0..0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if (isSof) {
                // length(2) precision(1) height(2) width(2) components(1) {id hv tq}*
                if (i + 8 > b.size) return null
                val components = b[i + 7].toInt() and 0xFF
                if (components == 0 || i + 8 + 3 * components > b.size) return null
                val factors = IntArray(components) { c ->
                    val hv = b[i + 8 + 3 * c + 1].toInt() and 0xFF
                    ((hv shr 4) * (hv and 0x0F)).coerceAtLeast(1)
                }
                return JpegInfo(progressive = marker != 0xC0 && marker != 0xC1, samplingFactors = factors)
            }
            if (length < 2) return null
            i += length
        }
        return null
    }

    /** True/false if [b] is a PNG (interlaced or not); null if it isn't one. */
    internal fun sniffPngInterlaced(b: ByteArray): Boolean? {
        val signature = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        if (b.size < 29) return null
        for (k in signature.indices) if (b[k] != signature[k]) return null
        // IHDR: length(4) "IHDR"(4) width(4) height(4) depth(1) colour(1) compression(1) filter(1) interlace(1)
        if (b[12] != 0x49.toByte() || b[13] != 0x48.toByte()) return null // "IH"
        return (b[28].toInt() and 0xFF) != 0
    }
}
