package com.aeidolon.vaultexplorer.panorama

import kotlin.math.acos
import kotlin.math.sqrt

/**
 * One captured panorama frame, kept as a small JPEG plus where it points.
 *
 * [rows] is the camera's rotation, row-major, mapping the upright image's axes
 * (x right, y up, the camera looks down -z) to the panorama frame
 * (East, Up, -North). [tanX]/[tanY] are tan(half the field of view) across the
 * upright image's width and height. [explicitRotationDegrees] rotates raw
 * YUV-encoded JPEGs upright without rewriting EXIF on disk.
 */
class PanoFrame(
    val jpeg: ByteArray,
    val width: Int,
    val height: Int,
    val rows: FloatArray,
    val tanX: Float,
    val tanY: Float,
)

/**
 * Thread-safe ring buffer of recent device poses from [ViewerOrientationPlugin],
 * in `SystemClock.elapsedRealtimeNanos()` time, so captures can look up the
 * exact orientation at exposure start/mid/end instead of guessing across
 * encoding/channel latency.
 */
object PanoramaPoseTracker {
    private const val CAPACITY = 64
    private const val MAX_AGE_NS = 500_000_000L

    private val lock = Any()
    private val timesNs = LongArray(CAPACITY)
    private val poses = Array(CAPACITY) { FloatArray(9) }
    private var count = 0
    private var head = 0

    fun clear() = synchronized(lock) {
        count = 0
        head = 0
    }

    /** Converts Android screen->world (East, North, Up) to panorama pose (East, Up, -North). */
    fun recordAndroidMatrix(timeNs: Long, m: FloatArray) {
        if (m.size < 9) return
        val pose = floatArrayOf(
            m[0], m[1], m[2],
            m[6], m[7], m[8],
            -m[3], -m[4], -m[5],
        )
        synchronized(lock) {
            val idx = if (count < CAPACITY) {
                (head + count).also { count++ } % CAPACITY
            } else {
                head.also { head = (head + 1) % CAPACITY }
            }
            timesNs[idx] = timeNs
            System.arraycopy(pose, 0, poses[idx], 0, 9)
        }
    }

    /** Interpolated pose at [targetTimeNs], or null if no recent samples exist. */
    fun poseAt(targetTimeNs: Long): FloatArray? {
        synchronized(lock) {
            if (count == 0) return null
            val newestIdx = (head + count - 1) % CAPACITY
            val newestT = timesNs[newestIdx]
            if (targetTimeNs - newestT > MAX_AGE_NS) return null
            if (targetTimeNs >= newestT || count == 1) return poses[newestIdx].copyOf()

            val oldestIdx = head
            if (targetTimeNs <= timesNs[oldestIdx]) {
                return if (timesNs[oldestIdx] - targetTimeNs <= MAX_AGE_NS) {
                    poses[oldestIdx].copyOf()
                } else {
                    null
                }
            }

            var prevIdx = oldestIdx
            for (i in 1 until count) {
                val curIdx = (head + i) % CAPACITY
                val tCur = timesNs[curIdx]
                if (tCur >= targetTimeNs) {
                    val tPrev = timesNs[prevIdx]
                    val dt = (tCur - tPrev).toDouble()
                    if (dt <= 0.0) return poses[curIdx].copyOf()
                    val alpha = ((targetTimeNs - tPrev).toDouble() / dt).toFloat().coerceIn(0f, 1f)
                    return blendPoses(poses[prevIdx], poses[curIdx], alpha)
                }
                prevIdx = curIdx
            }
            return poses[newestIdx].copyOf()
        }
    }

    fun poseAngle(a: FloatArray, b: FloatArray): Float {
        var trace = 0f
        for (i in 0 until 9) trace += a[i] * b[i]
        return acos(((trace - 1f) * 0.5f).coerceIn(-1f, 1f))
    }

    fun blendPoses(a: FloatArray, b: FloatArray, t: Float): FloatArray {
        val m = FloatArray(9) { i -> a[i] + (b[i] - a[i]) * t }
        return orthonormalize(m)
    }

    fun orthonormalize(m: FloatArray): FloatArray {
        fun norm(x: Float, y: Float, z: Float): FloatArray {
            val len = sqrt(x * x + y * y + z * z)
            return if (len < 1e-9f) floatArrayOf(x, y, z) else floatArrayOf(x / len, y / len, z / len)
        }
        val r0 = norm(m[0], m[1], m[2])
        val d = r0[0] * m[3] + r0[1] * m[4] + r0[2] * m[5]
        val r1 = norm(m[3] - r0[0] * d, m[4] - r0[1] * d, m[5] - r0[2] * d)
        val r2 = floatArrayOf(
            r0[1] * r1[2] - r0[2] * r1[1],
            r0[2] * r1[0] - r0[0] * r1[2],
            r0[0] * r1[1] - r0[1] * r1[0],
        )
        return floatArrayOf(
            r0[0], r0[1], r0[2],
            r1[0], r1[1], r1[2],
            r2[0], r2[1], r2[2],
        )
    }
}

/**
 * In-memory holding area for the panorama being captured. Frames live only in
 * RAM (this is a vault app: nothing is written unencrypted) and never travel
 * to Dart: the camera plugin parks a fresh JPEG here as "pending", and Dart
 * then commits it together with the device pose, or discards it.
 */
object PanoramaStore {
    const val MAX_FRAMES = 72

    private val lock = Any()
    private var pending: ByteArray? = null
    private var pendingRotationDegrees: Int? = null
    private val frames = ArrayList<PanoFrame>()

    fun setPending(bytes: ByteArray, rotationDegrees: Int? = null) = synchronized(lock) {
        pending = bytes
        pendingRotationDegrees = rotationDegrees
    }

    fun discardPending() = synchronized(lock) {
        pending = null
        pendingRotationDegrees = null
    }

    fun begin() = synchronized(lock) {
        pending = null
        pendingRotationDegrees = null
        frames.clear()
    }

    fun count(): Int = synchronized(lock) { frames.size }

    fun snapshot(): List<PanoFrame> = synchronized(lock) { frames.toList() }

    /** Returns null on success, otherwise a short reason. */
    fun commitPending(rows: FloatArray, tanHalfLong: Double): String? {
        val (bytes, rotDeg) = synchronized(lock) {
            val p = pending
            val r = pendingRotationDegrees
            pending = null
            pendingRotationDegrees = null
            p to r
        }
        if (bytes == null) return "no pending frame"
        if (count() >= MAX_FRAMES) return "too many frames"
        val frame = PanoramaStitcher.prepareFrame(bytes, rows, tanHalfLong, rotDeg)
            ?: return "could not decode frame"
        synchronized(lock) { frames.add(frame) }
        return null
    }
}