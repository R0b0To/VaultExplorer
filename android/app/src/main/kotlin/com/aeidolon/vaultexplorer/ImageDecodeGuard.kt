package com.aeidolon.vaultexplorer

import android.app.ActivityManager
import android.content.Context
import java.io.Closeable
import java.util.concurrent.Semaphore

/**
 * Admission control for decoding very large images (e.g. a 100 MB photo or
 * scan) down to a thumbnail/preview.
 *
 * `BitmapFactory`'s `inSampleSize` bounds the *output* bitmap, but not the
 * decoder's own working memory: a progressive JPEG or an interlaced PNG still
 * needs buffers proportional to the full source size, so a huge file can
 * balloon native memory by gigabytes even when we only want a 2048 px preview.
 * That ends either in an `OutOfMemoryError` (an `Error`, not an `Exception`,
 * so the usual `catch (e: Exception)` never sees it and the app dies) or in
 * the system's low-memory killer taking the whole process.
 *
 * Callers read the image bounds first (cheap, header only) and then call
 * [admit] before the real decode:
 *  - sources above [MAX_SOURCE_PIXELS] are refused outright
 *    ([CODE_TOO_LARGE]) -- that never changes, so callers may remember it;
 *  - "heavy" sources (above [HEAVY_SOURCE_PIXELS]) are decoded one at a time,
 *    so two of them can never peak together, and are refused
 *    ([CODE_OUT_OF_MEMORY]) when the OS reports too little free memory right
 *    now -- that one is transient, so callers should not remember it.
 *
 * The returned [Permit] MUST be closed when the decode is finished.
 */
object ImageDecodeGuard {
    const val CODE_TOO_LARGE = "IMAGE_TOO_LARGE"
    const val CODE_OUT_OF_MEMORY = "OUT_OF_MEMORY"

    /** Hard ceiling on source pixels (~22.6k x 22.6k). Tunable. */
    const val MAX_SOURCE_PIXELS: Long = 512_000_000L

    /** Above this many source pixels a decode is serialized and memory-checked. */
    const val HEAVY_SOURCE_PIXELS: Long = 48_000_000L

    /** Worst-case decoder working set per source pixel (interlaced RGBA PNG). */
    private const val WORST_CASE_BYTES_PER_PIXEL = 4L

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
     * Decides whether a [width] x [height] source may be decoded now.
     * Throws [RefusedException] if not; otherwise returns a [Permit] to close
     * after decoding (in a `finally`).
     */
    @Throws(RefusedException::class)
    fun admit(context: Context, width: Int, height: Int): Permit {
        val pixels = width.toLong() * height.toLong()
        if (pixels > MAX_SOURCE_PIXELS) {
            throw RefusedException(
                CODE_TOO_LARGE,
                "Image is ${width}x$height (${pixels / 1_000_000} MP), above the " +
                    "${MAX_SOURCE_PIXELS / 1_000_000} MP preview limit",
            )
        }
        if (pixels < HEAVY_SOURCE_PIXELS) return Permit(false)

        heavyDecodeGate.acquire()
        try {
            // Checked after acquiring: waiting for the gate can take a while and
            // the other decode's memory has been released by now.
            checkAvailableMemory(context, pixels)
        } catch (t: Throwable) {
            heavyDecodeGate.release()
            throw t
        }
        return Permit(true)
    }

    private fun checkAvailableMemory(context: Context, pixels: Long) {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return
        val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val usable = (info.availMem - info.threshold).coerceAtLeast(0L)
        val budget = (usable * AVAILABLE_MEMORY_FRACTION).toLong()
        val estimate = pixels * WORST_CASE_BYTES_PER_PIXEL
        if (info.lowMemory || estimate > budget) {
            throw RefusedException(
                CODE_OUT_OF_MEMORY,
                "Decoding a ${pixels / 1_000_000} MP image needs about ${estimate shr 20} MB " +
                    "but only ${budget shr 20} MB can be spared right now",
            )
        }
    }
}
