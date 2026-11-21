package com.aeidolon.vaultexplorer.panorama

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import com.aeidolon.vaultexplorer.VeLog
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

class StitchResult(
    val jpeg: ByteArray,
    val thumbnail: ByteArray,
    val width: Int,
    val height: Int,
)

/**
 * Image-registered, seam-carved, multi-band panorama stitcher.
 */
object PanoramaStitcher {
    private const val TAG = "PanoramaStitcher"

    private const val STORE_LONG_SIDE = 1440
    private const val ALIGN_LONG_SIDE = 640
    private const val SMALL_LONG_SIDE = 320
    private const val MAX_OUTPUT_PIXELS = 24_000_000

    private const val BAND_ROWS = 128
    private const val HALO = 32
    private const val PYRAMID_LEVELS = 4

    // ── Frame preparation ────────────────────────────────────────────────

    /** Decodes a camera JPEG, rotates it upright and shrinks it for storage. */
    fun prepareFrame(
        bytes: ByteArray,
        rows: FloatArray,
        tanHalfLong: Double,
        explicitRotationDegrees: Int? = null,
    ): PanoFrame? {
        if (rows.size < 9 || !tanHalfLong.isFinite() || tanHalfLong <= 0.0) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= STORE_LONG_SIDE) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(
            bytes, 0, bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: return null

        val matrix = Matrix()
        if (explicitRotationDegrees != null) {
            val rot = ((explicitRotationDegrees % 360) + 360) % 360
            if (rot != 0) matrix.postRotate(rot.toFloat())
        } else {
            val orientation = try {
                ExifInterface(ByteArrayInputStream(bytes))
                    .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            } catch (_: Exception) {
                ExifInterface.ORIENTATION_NORMAL
            }
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> {
                    matrix.postRotate(90f)
                    matrix.postScale(-1f, 1f)
                }
                ExifInterface.ORIENTATION_TRANSVERSE -> {
                    matrix.postRotate(270f)
                    matrix.postScale(-1f, 1f)
                }
            }
        }
        var bmp = decoded
        if (!matrix.isIdentity) {
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            if (rotated !== bmp) bmp.recycle()
            bmp = rotated
        }
        val longSide = max(bmp.width, bmp.height)
        if (longSide > STORE_LONG_SIDE) {
            val scale = STORE_LONG_SIDE.toFloat() / longSide
            val scaled = Bitmap.createScaledBitmap(
                bmp,
                (bmp.width * scale).roundToInt().coerceAtLeast(1),
                (bmp.height * scale).roundToInt().coerceAtLeast(1),
                true,
            )
            if (scaled !== bmp) bmp.recycle()
            bmp = scaled
        }
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 92, out)
        val w = bmp.width
        val h = bmp.height
        bmp.recycle()
        val l = max(w, h).toDouble()
        return PanoFrame(
            jpeg = out.toByteArray(),
            width = w,
            height = h,
            rows = PanoramaPoseTracker.orthonormalize(rows.copyOf(9)),
            tanX = (tanHalfLong * w / l).toFloat(),
            tanY = (tanHalfLong * h / l).toFloat(),
        )
    }

    private fun decodePixels(frame: PanoFrame, targetLong: Int?): Triple<IntArray, Int, Int> {
        val opts = BitmapFactory.Options()
        if (targetLong != null) {
            val maxDim = max(frame.width, frame.height)
            var sample = 1
            while (maxDim / (sample * 2) >= targetLong) sample *= 2
            opts.inSampleSize = sample
        }
        var bmp = BitmapFactory.decodeByteArray(frame.jpeg, 0, frame.jpeg.size, opts)
            ?: return Triple(IntArray(frame.width * frame.height), frame.width, frame.height)
        if (targetLong != null && max(bmp.width, bmp.height) > targetLong) {
            val s = targetLong.toFloat() / max(bmp.width, bmp.height)
            val scaled = Bitmap.createScaledBitmap(
                bmp,
                (bmp.width * s).roundToInt().coerceAtLeast(1),
                (bmp.height * s).roundToInt().coerceAtLeast(1),
                true,
            )
            if (scaled !== bmp) bmp.recycle()
            bmp = scaled
        }
        val px = IntArray(bmp.width * bmp.height)
        bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
        val w = bmp.width
        val h = bmp.height
        bmp.recycle()
        return Triple(px, w, h)
    }

    // ── Geometry ─────────────────────────────────────────────────────────

    private class Geo(val frame: PanoFrame) {
        val rows = frame.rows
        val tanX = frame.tanX
        val tanY = frame.tanY

        val fx = -rows[2]
        val fy = -rows[5]
        val fz = -rows[8]
        val lat = asin(fy.toDouble().coerceIn(-1.0, 1.0))
        val lon = atan2(fx.toDouble(), -fz.toDouble())

        val radius = atan(hypot(tanX.toDouble(), tanY.toDouble()))
        val cosRadius = cos(radius).toFloat()
    }

    private fun recentre(frames: List<PanoFrame>, sphere: Boolean): List<PanoFrame> {
        fun heading(f: PanoFrame) = atan2(-f.rows[2].toDouble(), f.rows[8].toDouble())
        val h0 = if (sphere || frames.size == 1) {
            heading(frames[0])
        } else {
            val sorted = DoubleArray(frames.size) { heading(frames[it]) }.apply { sort() }
            var bestGap = -1.0
            var bestIdx = 0
            for (i in sorted.indices) {
                val next = if (i + 1 < sorted.size) sorted[i + 1] else sorted[0] + 2.0 * PI
                val gap = next - sorted[i]
                if (gap > bestGap) {
                    bestGap = gap
                    bestIdx = i
                }
            }
            val gapStart = sorted[bestIdx]
            val covered = 2.0 * PI - bestGap
            wrapAngle(gapStart + bestGap + covered * 0.5)
        }
        val theta = -h0
        val c = cos(theta).toFloat()
        val s = sin(theta).toFloat()
        return frames.map { f ->
            val r = f.rows
            val n = floatArrayOf(
                c * r[0] - s * r[6], c * r[1] - s * r[7], c * r[2] - s * r[8],
                r[3], r[4], r[5],
                s * r[0] + c * r[6], s * r[1] + c * r[7], s * r[2] + c * r[8],
            )
            PanoFrame(f.jpeg, f.width, f.height, PanoramaPoseTracker.orthonormalize(n), f.tanX, f.tanY)
        }
    }

    private fun wrapAngle(a: Double): Double {
        var r = (a + PI) % (2.0 * PI)
        if (r < 0.0) r += 2.0 * PI
        return r - PI
    }

    // ── Image-based alignment & Bundle Adjustment ────────────────────────

    private class LumaLevel(val w: Int, val h: Int, val data: ByteArray) {
        fun sample(x: Float, y: Float): Float {
            val sx = x.coerceIn(0f, (w - 1).toFloat())
            val sy = y.coerceIn(0f, (h - 1).toFloat())
            val x0 = sx.toInt()
            val y0 = sy.toInt()
            val x1 = min(x0 + 1, w - 1)
            val y1 = min(y0 + 1, h - 1)
            val fx = sx - x0
            val fy = sy - y0
            val v00 = data[y0 * w + x0].toInt() and 0xFF
            val v10 = data[y0 * w + x1].toInt() and 0xFF
            val v01 = data[y1 * w + x0].toInt() and 0xFF
            val v11 = data[y1 * w + x1].toInt() and 0xFF
            val top = v00 + (v10 - v00) * fx
            val bot = v01 + (v11 - v01) * fx
            return top + (bot - top) * fy
        }
    }

    private class Corner(val nx: Float, val ny: Float, val x320: Int, val y320: Int, val score: Float)

    private class AlignFrame(
        val l640: LumaLevel,
        val l320: LumaLevel,
        val l160: LumaLevel,
        val corners: List<Corner>,
    )

    private class RayPair(
        val i: Int,
        val j: Int,
        val nxi: Float,
        val nyi: Float,
        val nxj: Float,
        val nyj: Float,
        val weight: Float = 1f,
    )

    private fun downsampleLuma2x(src: LumaLevel): LumaLevel {
        val nw = max(1, src.w / 2)
        val nh = max(1, src.h / 2)
        val dst = ByteArray(nw * nh)
        for (y in 0 until nh) {
            val sy = min(y * 2, src.h - 1)
            val sy1 = min(sy + 1, src.h - 1)
            for (x in 0 until nw) {
                val sx = min(x * 2, src.w - 1)
                val sx1 = min(sx + 1, src.w - 1)
                val sum = (src.data[sy * src.w + sx].toInt() and 0xFF) +
                    (src.data[sy * src.w + sx1].toInt() and 0xFF) +
                    (src.data[sy1 * src.w + sx].toInt() and 0xFF) +
                    (src.data[sy1 * src.w + sx1].toInt() and 0xFF)
                dst[y * nw + x] = ((sum + 2) shr 2).toByte()
            }
        }
        return LumaLevel(nw, nh, dst)
    }

    private fun buildAlignFrame(frame: PanoFrame): AlignFrame {
        val (px, w, h) = decodePixels(frame, ALIGN_LONG_SIDE)
        val luma = ByteArray(w * h)
        for (k in px.indices) {
            val c = px[k]
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            luma[k] = (((r * 77 + g * 150 + b * 29) + 128) shr 8).coerceIn(0, 255).toByte()
        }
        val l640 = LumaLevel(w, h, luma)
        val l320 = downsampleLuma2x(l640)
        val l160 = downsampleLuma2x(l320)
        val corners = detectCorners(l320)
        return AlignFrame(l640, l320, l160, corners)
    }

    private fun detectCorners(lvl: LumaLevel): List<Corner> {
        val w = lvl.w
        val h = lvl.h
        if (w < 20 || h < 20) return emptyList()

        val d = lvl.data
        val ixx = FloatArray(w * h)
        val iyy = FloatArray(w * h)
        val ixy = FloatArray(w * h)
        for (y in 1 until h - 1) {
            val row = y * w
            for (x in 1 until w - 1) {
                val idx = row + x
                val gx = ((d[idx + 1].toInt() and 0xFF) - (d[idx - 1].toInt() and 0xFF)) * 0.5f
                val gy = ((d[idx + w].toInt() and 0xFF) - (d[idx - w].toInt() and 0xFF)) * 0.5f
                ixx[idx] = gx * gx
                iyy[idx] = gy * gy
                ixy[idx] = gx * gy
            }
        }

        val resp = FloatArray(w * h)
        val marginX = max(6, (w * 0.04f).toInt())
        val marginY = max(6, (h * 0.04f).toInt())
        for (y in marginY until h - marginY) {
            for (x in marginX until w - marginX) {
                var sxx = 0f
                var syy = 0f
                var sxy = 0f
                for (oy in -1..1) {
                    val base = (y + oy) * w + x
                    for (ox in -1..1) {
                        val k = base + ox
                        sxx += ixx[k]
                        syy += iyy[k]
                        sxy += ixy[k]
                    }
                }
                val det = sxx * syy - sxy * sxy
                val trace = sxx + syy
                val r = det - 0.04f * trace * trace
                if (r > 3500f) resp[y * w + x] = r
            }
        }

        val cols = 8
        val rows = 8
        val cellW = max(1, (w - 2 * marginX + cols - 1) / cols)
        val cellH = max(1, (h - 2 * marginY + rows - 1) / rows)
        val bucketCandidates = Array(cols * rows) { ArrayList<Corner>() }

        for (y in marginY + 1 until h - marginY - 1) {
            val by = ((y - marginY) / cellH).coerceIn(0, rows - 1)
            for (x in marginX + 1 until w - marginX - 1) {
                val v = resp[y * w + x]
                if (v <= 0f) continue
                var isMax = true
                for (oy in -1..1) {
                    for (ox in -1..1) {
                        if ((ox != 0 || oy != 0) && resp[(y + oy) * w + (x + ox)] > v) {
                            isMax = false
                            break
                        }
                    }
                    if (!isMax) break
                }
                if (!isMax) continue
                val bx = ((x - marginX) / cellW).coerceIn(0, cols - 1)
                val nx = ((x + 0.5f) / w - 0.5f) * 2f
                val ny = (0.5f - (y + 0.5f) / h) * 2f
                bucketCandidates[by * cols + bx].add(Corner(nx, ny, x, y, v))
            }
        }

        val out = ArrayList<Corner>(cols * rows * 2)
        for (cell in bucketCandidates) {
            if (cell.isEmpty()) continue
            cell.sortByDescending { it.score }
            val picked = ArrayList<Corner>(2)
            for (c in cell) {
                if (picked.none { abs(it.x320 - c.x320) < 6 && abs(it.y320 - c.y320) < 6 }) {
                    picked.add(c)
                    out.add(c)
                    if (picked.size == 2) break
                }
            }
        }
        return out
    }

    private fun normToRay(nx: Float, ny: Float, tanX: Float, tanY: Float): FloatArray {
        val rx = nx * tanX
        val ry = ny * tanY
        val inv = 1f / sqrt(rx * rx + ry * ry + 1f)
        return floatArrayOf(rx * inv, ry * inv, -inv)
    }

    private fun relRot(ri: FloatArray, rj: FloatArray): FloatArray {
        val m = FloatArray(9)
        for (a in 0 until 3) {
            for (b in 0 until 3) {
                m[a * 3 + b] = rj[0 * 3 + a] * ri[0 * 3 + b] +
                    rj[1 * 3 + a] * ri[1 * 3 + b] +
                    rj[2 * 3 + a] * ri[2 * 3 + b]
            }
        }
        return m
    }

    private fun mulMatVec(m: FloatArray, v: FloatArray): FloatArray = floatArrayOf(
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    )

    private fun mulMatMat(a: FloatArray, b: FloatArray): FloatArray {
        val m = FloatArray(9)
        for (r in 0 until 3) {
            for (c in 0 until 3) {
                m[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c]
            }
        }
        return m
    }

    private fun projectRayToPixel(
        u: FloatArray,
        tanX: Float,
        tanY: Float,
        w: Int,
        h: Int,
    ): Pair<Float, Float>? {
        if (u[2] > -0.1f) return null
        val inv = -1f / u[2]
        val nx = u[0] * inv / tanX
        val ny = u[1] * inv / tanY
        if (abs(nx) > 1.2f || abs(ny) > 1.2f) return null
        val px = (nx * 0.5f + 0.5f) * w - 0.5f
        val py = (0.5f - ny * 0.5f) * h - 0.5f
        return px to py
    }

    private fun rotBetween(a: FloatArray, b: FloatArray): FloatArray {
        val c = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]).coerceIn(-1f, 1f)
        if (c > 0.999999f) return floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f)
        val vx = a[1] * b[2] - a[2] * b[1]
        val vy = a[2] * b[0] - a[0] * b[2]
        val vz = a[0] * b[1] - a[1] * b[0]
        if (c < -0.99999f) return floatArrayOf(-1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, -1f)
        val k = 1f / (1f + c)
        val r = floatArrayOf(
            1f - k * (vy * vy + vz * vz), -vz + k * vx * vy, vy + k * vx * vz,
            vz + k * vx * vy, 1f - k * (vx * vx + vz * vz), -vx + k * vy * vz,
            -vy + k * vx * vz, vx + k * vy * vz, 1f - k * (vx * vx + vy * vy),
        )
        return PanoramaPoseTracker.orthonormalize(r)
    }

    private fun zncc(
        tpl: FloatArray,
        radius: Int,
        lvlB: LumaLevel,
        cx: Float,
        cy: Float,
        exX: Float,
        exY: Float,
        eyX: Float,
        eyY: Float,
    ): Float {
        val n = (2 * radius + 1) * (2 * radius + 1)
        val samples = FloatArray(n)
        var sum = 0f
        var idx = 0
        for (oy in -radius..radius) {
            val bx = cx + oy * eyX
            val by = cy + oy * eyY
            for (ox in -radius..radius) {
                val sx = bx + ox * exX
                val sy = by + ox * exY
                if (sx < 0f || sx > (lvlB.w - 1).toFloat() || sy < 0f || sy > (lvlB.h - 1).toFloat()) {
                    return -1f
                }
                val v = lvlB.sample(sx, sy)
                samples[idx++] = v
                sum += v
            }
        }
        val mean = sum / n
        var normSq = 0f
        var dot = 0f
        for (k in 0 until n) {
            val d = samples[k] - mean
            normSq += d * d
            dot += d * tpl[k]
        }
        if (normSq < 1e-3f) return -1f
        return dot / sqrt(normSq)
    }

    private fun extractNormalizedPatch(lvl: LumaLevel, cx: Int, cy: Int, radius: Int): FloatArray? {
        if (cx - radius < 0 || cx + radius >= lvl.w || cy - radius < 0 || cy + radius >= lvl.h) return null
        val side = 2 * radius + 1
        val n = side * side
        val raw = FloatArray(n)
        var sum = 0f
        var idx = 0
        for (oy in -radius..radius) {
            val row = (cy + oy) * lvl.w
            for (ox in -radius..radius) {
                val v = (lvl.data[row + cx + ox].toInt() and 0xFF).toFloat()
                raw[idx++] = v
                sum += v
            }
        }
        val mean = sum / n
        var normSq = 0f
        for (k in 0 until n) {
            val d = raw[k] - mean
            raw[k] = d
            normSq += d * d
        }
        val std = sqrt(normSq / n)
        if (std < 5f) return null
        val invNorm = 1f / sqrt(normSq)
        for (k in 0 until n) raw[k] *= invNorm
        return raw
    }

    private class CoarseResult(
        val rot: FloatArray,
        val score: Float,
        val overlapPoints: List<Pair<Float, Float>>,
    )

    private fun coarseAlignPair(
        fi: Geo,
        fj: Geo,
        ai: AlignFrame,
        aj: AlignFrame,
        rji0: FloatArray,
    ): CoarseResult {
        val li = ai.l160
        val lj = aj.l160
        val rPatch = 3

        data class SamplePatch(
            val nx: Float,
            val ny: Float,
            val tpl: FloatArray,
            val jx: Float,
            val jy: Float,
            val exX: Float,
            val exY: Float,
            val eyX: Float,
            val eyY: Float,
        )

        val patches = ArrayList<SamplePatch>(16)
        var sumNx = 0f
        var sumNy = 0f
        for (gy in 0 until 6) {
            val ny = -0.7f + gy * (1.4f / 5f)
            val py = ((0.5f - ny * 0.5f) * li.h - 0.5f).roundToInt()
            for (gx in 0 until 6) {
                val nx = -0.7f + gx * (1.4f / 5f)
                val px = ((nx * 0.5f + 0.5f) * li.w - 0.5f).roundToInt()
                val tpl = extractNormalizedPatch(li, px, py, rPatch) ?: continue

                val u0 = normToRay(nx, ny, fi.tanX, fi.tanY)
                val uj0 = mulMatVec(rji0, u0)
                if (uj0[2] > -0.2f) continue
                val inv = -1f / uj0[2]
                val nxj = uj0[0] * inv / fj.tanX
                val nyj = uj0[1] * inv / fj.tanY
                if (abs(nxj) > 0.85f || abs(nyj) > 0.85f) continue

                val p0 = projectRayToPixel(uj0, fj.tanX, fj.tanY, lj.w, lj.h) ?: continue
                val dNx = 2f / li.w
                val dNy = -2f / li.h
                val px1 = projectRayToPixel(mulMatVec(rji0, normToRay(nx + dNx, ny, fi.tanX, fi.tanY)), fj.tanX, fj.tanY, lj.w, lj.h) ?: continue
                val py1 = projectRayToPixel(mulMatVec(rji0, normToRay(nx, ny + dNy, fi.tanX, fi.tanY)), fj.tanX, fj.tanY, lj.w, lj.h) ?: continue

                patches.add(
                    SamplePatch(
                        nx, ny, tpl,
                        p0.first, p0.second,
                        px1.first - p0.first, px1.second - p0.second,
                        py1.first - p0.first, py1.second - p0.second,
                    ),
                )
                sumNx += nx
                sumNy += ny
                if (patches.size >= 14) break
            }
            if (patches.size >= 14) break
        }
        if (patches.size < 3) return CoarseResult(rji0, -1f, emptyList())

        fun evalShift(dx: Int, dy: Int): Float {
            var sum = 0f
            var cnt = 0
            for (p in patches) {
                val cx = p.jx + p.exX * dx + p.eyX * dy
                val cy = p.jy + p.exY * dx + p.eyY * dy
                val score = zncc(p.tpl, rPatch, lj, cx, cy, p.exX, p.exY, p.eyX, p.eyY)
                if (score > -0.5f) {
                    sum += score
                    cnt++
                }
            }
            return if (cnt >= 3 && cnt * 2 >= patches.size) sum / cnt else -1f
        }

        val maxShift = max(8, (0.14 * max(li.w, li.h) / (2.0 * max(fi.tanX, fi.tanY))).roundToInt().coerceIn(8, 18))
        val zeroScore = evalShift(0, 0)
        var bestDx = 0
        var bestDy = 0
        var bestScore = zeroScore
        for (dy in -maxShift..maxShift step 2) {
            for (dx in -maxShift..maxShift step 2) {
                val s = evalShift(dx, dy)
                if (s > bestScore) {
                    bestScore = s
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        val cx = bestDx
        val cy = bestDy
        for (dy in (cy - 2)..(cy + 2)) {
            for (dx in (cx - 2)..(cx + 2)) {
                val s = evalShift(dx, dy)
                if (s > bestScore) {
                    bestScore = s
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        val pts = patches.map { it.nx to it.ny }
        if (bestScore < 0.50f || (bestDx == 0 && bestDy == 0) || bestScore < zeroScore + 0.02f) {
            return CoarseResult(rji0, zeroScore, pts)
        }

        val avgNx = sumNx / patches.size
        val avgNy = sumNy / patches.size
        val dNx = bestDx * (2f / li.w)
        val dNy = -bestDy * (2f / li.h)
        val uFrom = normToRay(avgNx, avgNy, fi.tanX, fi.tanY)
        val uTo = normToRay(avgNx + dNx, avgNy + dNy, fi.tanX, fi.tanY)
        val corrected = PanoramaPoseTracker.orthonormalize(mulMatMat(rji0, rotBetween(uFrom, uTo)))
        return CoarseResult(corrected, bestScore, pts)
    }

    private fun triadRotation(a1: FloatArray, b1: FloatArray, a2: FloatArray, b2: FloatArray): FloatArray? {
        fun cross(u: FloatArray, v: FloatArray): FloatArray = floatArrayOf(
            u[1] * v[2] - u[2] * v[1],
            u[2] * v[0] - u[0] * v[2],
            u[0] * v[1] - u[1] * v[0],
        )
        fun norm(v: FloatArray): FloatArray? {
            val l = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
            return if (l < 1e-6f) null else floatArrayOf(v[0] / l, v[1] / l, v[2] / l)
        }
        val u2 = norm(cross(a1, a2)) ?: return null
        val v2 = norm(cross(b1, b2)) ?: return null
        val u3 = cross(a1, u2)
        val v3 = cross(b1, v2)
        val m = FloatArray(9)
        for (r in 0 until 3) {
            for (c in 0 until 3) {
                m[r * 3 + c] = b1[r] * a1[c] + v2[r] * u2[c] + v3[r] * u3[c]
            }
        }
        return m
    }

    private fun matchPair(
        i: Int,
        j: Int,
        fi: Geo,
        fj: Geo,
        ai: AlignFrame,
        aj: AlignFrame,
    ): List<RayPair> {
        val rji0 = relRot(fi.rows, fj.rows)
        val coarse = coarseAlignPair(fi, fj, ai, aj, rji0)
        val rji = coarse.rot

        val li320 = ai.l320
        val lj320 = aj.l320
        val li640 = ai.l640
        val lj640 = aj.l640
        val r320 = 4
        val r640 = 4

        val candVi = ArrayList<FloatArray>()
        val candVj = ArrayList<FloatArray>()
        val candNxI = ArrayList<Float>()
        val candNyI = ArrayList<Float>()
        val candNxJ = ArrayList<Float>()
        val candNyJ = ArrayList<Float>()

        for (c in ai.corners) {
            val ui = normToRay(c.nx, c.ny, fi.tanX, fi.tanY)
            val uj0 = mulMatVec(rji, ui)
            if (uj0[2] > -0.2f) continue
            val inv0 = -1f / uj0[2]
            val nxj0 = uj0[0] * inv0 / fj.tanX
            val nyj0 = uj0[1] * inv0 / fj.tanY
            if (abs(nxj0) > 0.90f || abs(nyj0) > 0.90f) continue

            val p320 = projectRayToPixel(uj0, fj.tanX, fj.tanY, lj320.w, lj320.h) ?: continue
            val dNx320 = 2f / li320.w
            val dNy320 = -2f / li320.h
            val px1 = projectRayToPixel(mulMatVec(rji, normToRay(c.nx + dNx320, c.ny, fi.tanX, fi.tanY)), fj.tanX, fj.tanY, lj320.w, lj320.h) ?: continue
            val py1 = projectRayToPixel(mulMatVec(rji, normToRay(c.nx, c.ny + dNy320, fi.tanX, fi.tanY)), fj.tanX, fj.tanY, lj320.w, lj320.h) ?: continue
            val exX = px1.first - p320.first
            val exY = px1.second - p320.second
            val eyX = py1.first - p320.first
            val eyY = py1.second - p320.second
            val exLen = hypot(exX, exY)
            val eyLen = hypot(eyX, eyY)
            if (exLen < 0.35f || exLen > 2.8f || eyLen < 0.35f || eyLen > 2.8f) continue

            val tpl320 = extractNormalizedPatch(li320, c.x320, c.y320, r320) ?: continue

            var bestScore = -1f
            var bestOx = 0
            var bestOy = 0
            val gridScores = FloatArray(17 * 17) { -1f }
            for (oy in -8..8) {
                for (ox in -8..8) {
                    val cx = p320.first + exX * ox + eyX * oy
                    val cy = p320.second + exY * ox + eyY * oy
                    val s = zncc(tpl320, r320, lj320, cx, cy, exX, exY, eyX, eyY)
                    gridScores[(oy + 8) * 17 + (ox + 8)] = s
                    if (s > bestScore) {
                        bestScore = s
                        bestOx = ox
                        bestOy = oy
                    }
                }
            }
            if (bestScore < 0.72f) continue

            var secondPeak = -1f
            for (oy in -8..8) {
                for (ox in -8..8) {
                    if (abs(ox - bestOx) <= 2 && abs(oy - bestOy) <= 2) continue
                    val s = gridScores[(oy + 8) * 17 + (ox + 8)]
                    if (s > secondPeak) secondPeak = s
                }
            }
            if (bestScore - secondPeak < 0.04f) continue

            val x640 = ((c.nx * 0.5f + 0.5f) * li640.w - 0.5f).roundToInt()
            val y640 = ((0.5f - c.ny * 0.5f) * li640.h - 0.5f).roundToInt()
            val tpl640 = extractNormalizedPatch(li640, x640, y640, r640) ?: continue
            val nxI640 = ((x640 + 0.5f) / li640.w - 0.5f) * 2f
            val nyI640 = (0.5f - (y640 + 0.5f) / li640.h) * 2f

            val jx320 = p320.first + exX * bestOx + eyX * bestOy
            val jy320 = p320.second + exY * bestOx + eyY * bestOy
            val nxJPred = ((jx320 + 0.5f) / lj320.w - 0.5f) * 2f
            val nyJPred = (0.5f - (jy320 + 0.5f) / lj320.h) * 2f
            val jx640Pred = (nxJPred * 0.5f + 0.5f) * lj640.w - 0.5f
            val jy640Pred = (0.5f - nyJPred * 0.5f) * lj640.h - 0.5f

            val scaleJx = lj640.w.toFloat() / lj320.w / (li640.w.toFloat() / li320.w)
            val scaleJy = lj640.h.toFloat() / lj320.h / (li640.h.toFloat() / li320.h)
            val ex640X = exX * scaleJx
            val ex640Y = exY * scaleJy
            val ey640X = eyX * scaleJx
            val ey640Y = eyY * scaleJy

            val localScores = FloatArray(7 * 7) { -1f }
            var b640Score = -1f
            var b640Ox = 0
            var b640Oy = 0
            for (oy in -3..3) {
                for (ox in -3..3) {
                    val cx = jx640Pred + ex640X * ox + ey640X * oy
                    val cy = jy640Pred + ex640Y * ox + ey640Y * oy
                    val s = zncc(tpl640, r640, lj640, cx, cy, ex640X, ex640Y, ey640X, ey640Y)
                    localScores[(oy + 3) * 7 + (ox + 3)] = s
                    if (s > b640Score) {
                        b640Score = s
                        b640Ox = ox
                        b640Oy = oy
                    }
                }
            }
            if (b640Score < 0.74f) continue

            var subOx = 0f
            var subOy = 0f
            if (abs(b640Ox) < 3) {
                val sl = localScores[(b640Oy + 3) * 7 + (b640Ox + 2)]
                val sr = localScores[(b640Oy + 3) * 7 + (b640Ox + 4)]
                val denom = sl - 2f * b640Score + sr
                if (denom < -1e-4f && sl > 0f && sr > 0f) {
                    subOx = (0.5f * (sl - sr) / denom).coerceIn(-0.5f, 0.5f)
                }
            }
            if (abs(b640Oy) < 3) {
                val su = localScores[(b640Oy + 2) * 7 + (b640Ox + 3)]
                val sd = localScores[(b640Oy + 4) * 7 + (b640Ox + 3)]
                val denom = su - 2f * b640Score + sd
                if (denom < -1e-4f && su > 0f && sd > 0f) {
                    subOy = (0.5f * (su - sd) / denom).coerceIn(-0.5f, 0.5f)
                }
            }

            val jxFin = jx640Pred + ex640X * (b640Ox + subOx) + ey640X * (b640Oy + subOy)
            val jyFin = jy640Pred + ex640Y * (b640Ox + subOx) + ey640Y * (b640Oy + subOy)
            val nxJFin = ((jxFin + 0.5f) / lj640.w - 0.5f) * 2f
            val nyJFin = (0.5f - (jyFin + 0.5f) / lj640.h) * 2f
            if (abs(nxJFin) > 0.96f || abs(nyJFin) > 0.96f) continue

            candVi.add(normToRay(nxI640, nyI640, fi.tanX, fi.tanY))
            candVj.add(normToRay(nxJFin, nyJFin, fj.tanX, fj.tanY))
            candNxI.add(nxI640)
            candNyI.add(nyI640)
            candNxJ.add(nxJFin)
            candNyJ.add(nyJFin)
        }

        val m = candVi.size
        var bestInliers = IntArray(0)
        if (m >= 6) {
            val cosInlier = cos(0.0055f)
            val rng = java.util.Random(0x5EED1234L + i * 131L + j)
            val trials = min(90, m * (m - 1) / 2)
            for (t in 0 until trials) {
                val a = rng.nextInt(m)
                var b = rng.nextInt(m)
                if (a == b) b = (a + 1) % m
                val va = candVi[a]
                val vb = candVi[b]
                val dotSep = va[0] * vb[0] + va[1] * vb[1] + va[2] * vb[2]
                if (dotSep > 0.996f) continue
                val rot = triadRotation(va, candVj[a], vb, candVj[b]) ?: continue
                if (PanoramaPoseTracker.poseAngle(rot, rji0) > 0.26f) continue

                var count = 0
                val buf = IntArray(m)
                for (k in 0 until m) {
                    val p = mulMatVec(rot, candVi[k])
                    val q = candVj[k]
                    val d = p[0] * q[0] + p[1] * q[1] + p[2] * q[2]
                    if (d >= cosInlier) buf[count++] = k
                }
                if (count > bestInliers.size) {
                    bestInliers = buf.copyOf(count)
                }
            }
        }

        if (bestInliers.size >= 6) {
            return bestInliers.map { idx ->
                RayPair(i, j, candNxI[idx], candNyI[idx], candNxJ[idx], candNyJ[idx], weight = 1f)
            }
        }

        // Low-corner fallback: emit soft constraints from strong coarse ZNCC overlap alignment.
        if (coarse.score >= 0.68f && coarse.overlapPoints.size >= 4) {
            val out = ArrayList<RayPair>()
            for ((nxI, nyI) in coarse.overlapPoints) {
                val uJ = mulMatVec(rji, normToRay(nxI, nyI, fi.tanX, fi.tanY))
                if (uJ[2] > -0.2f) continue
                val inv = -1f / uJ[2]
                val nxJ = uJ[0] * inv / fj.tanX
                val nyJ = uJ[1] * inv / fj.tanY
                if (abs(nxJ) > 0.95f || abs(nyJ) > 0.95f) continue
                out.add(RayPair(i, j, nxI, nyI, nxJ, nyJ, weight = 0.35f))
                if (out.size >= 6) break
            }
            if (out.size >= 3) return out
        }
        return emptyList()
    }

    private fun expRot(wx: Double, wy: Double, wz: Double): DoubleArray {
        val theta = sqrt(wx * wx + wy * wy + wz * wz)
        if (theta < 1e-8) {
            return doubleArrayOf(
                1.0, -wz, wy,
                wz, 1.0, -wx,
                -wy, wx, 1.0,
            )
        }
        val inv = 1.0 / theta
        val kx = wx * inv
        val ky = wy * inv
        val kz = wz * inv
        val c = cos(theta)
        val s = sin(theta)
        val v = 1.0 - c
        return doubleArrayOf(
            c + kx * kx * v, kx * ky * v - kz * s, kx * kz * v + ky * s,
            ky * kx * v + kz * s, c + ky * ky * v, ky * kz * v - kx * s,
            kz * kx * v - ky * s, kz * ky * v + kx * s, c + kz * kz * v,
        )
    }

    private fun orthonormalizeD(m: DoubleArray): DoubleArray {
        fun norm(x: Double, y: Double, z: Double): DoubleArray {
            val l = sqrt(x * x + y * y + z * z)
            return if (l < 1e-12) doubleArrayOf(x, y, z) else doubleArrayOf(x / l, y / l, z / l)
        }
        val r0 = norm(m[0], m[1], m[2])
        val d = r0[0] * m[3] + r0[1] * m[4] + r0[2] * m[5]
        val r1 = norm(m[3] - r0[0] * d, m[4] - r0[1] * d, m[5] - r0[2] * d)
        val r2 = doubleArrayOf(
            r0[1] * r1[2] - r0[2] * r1[1],
            r0[2] * r1[0] - r0[0] * r1[2],
            r0[0] * r1[1] - r0[1] * r1[0],
        )
        return doubleArrayOf(
            r0[0], r0[1], r0[2],
            r1[0], r1[1], r1[2],
            r2[0], r2[1], r2[2],
        )
    }

    private fun mulMatD(a: DoubleArray, b: DoubleArray): DoubleArray {
        val out = DoubleArray(9)
        for (r in 0 until 3) {
            for (c in 0 until 3) {
                out[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c]
            }
        }
        return out
    }

    private fun logRotD(m: DoubleArray): DoubleArray {
        val cosT = ((m[0] + m[4] + m[8] - 1.0) * 0.5).coerceIn(-1.0, 1.0)
        val theta = acos(cosT)
        if (theta < 1e-6) {
            return doubleArrayOf(
                (m[7] - m[5]) * 0.5,
                (m[2] - m[6]) * 0.5,
                (m[3] - m[1]) * 0.5,
            )
        }
        val s = theta / (2.0 * sin(theta).coerceAtLeast(1e-6))
        return doubleArrayOf(
            (m[7] - m[5]) * s,
            (m[2] - m[6]) * s,
            (m[3] - m[1]) * s,
        )
    }

    private fun solveCholesky(a: DoubleArray, b: DoubleArray, n: Int): DoubleArray? {
        val l = DoubleArray(n * n)
        for (i in 0 until n) {
            for (j in 0..i) {
                var sum = a[i * n + j]
                for (k in 0 until j) sum -= l[i * n + k] * l[j * n + k]
                if (i == j) {
                    if (sum <= 1e-12 || !sum.isFinite()) return null
                    l[i * n + j] = sqrt(sum)
                } else {
                    l[i * n + j] = sum / l[j * n + j]
                }
            }
        }
        val y = DoubleArray(n)
        for (i in 0 until n) {
            var sum = b[i]
            for (k in 0 until i) sum -= l[i * n + k] * y[k]
            y[i] = sum / l[i * n + i]
        }
        val x = DoubleArray(n)
        for (i in n - 1 downTo 0) {
            var sum = y[i]
            for (k in i + 1 until n) sum -= l[k * n + i] * x[k]
            x[i] = sum / l[i * n + i]
            if (!x[i].isFinite()) return null
        }
        return x
    }

    private fun alignFrames(frames: List<PanoFrame>, sphere: Boolean): List<PanoFrame> {
        val count = frames.size
        if (count < 2) return frames

        val geos = frames.map { Geo(it) }
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4)
        val pool = Executors.newFixedThreadPool(threads)
        val alignFrames = try {
            val tasks = frames.map { f -> Callable { buildAlignFrame(f) } }
            pool.invokeAll(tasks).map { it.get() }
        } finally {
            pool.shutdownNow()
        }

        val pairs = ArrayList<Pair<Int, Int>>()
        for (i in 0 until count) {
            val a = geos[i]
            for (j in i + 1 until count) {
                val b = geos[j]
                val dot = a.fx * b.fx + a.fy * b.fy + a.fz * b.fz
                if (dot >= cos(max(0.05, a.radius + b.radius - 0.12)).toFloat()) {
                    pairs.add(i to j)
                }
            }
        }

        val matchPool = Executors.newFixedThreadPool(threads)
        val allMatches = ArrayList<RayPair>()
        var matchedEdges = 0
        try {
            val tasks = pairs.map { (i, j) ->
                Callable { matchPair(i, j, geos[i], geos[j], alignFrames[i], alignFrames[j]) }
            }
            for (fut in matchPool.invokeAll(tasks)) {
                val edgeMatches = fut.get()
                if (edgeMatches.isNotEmpty()) {
                    matchedEdges++
                    allMatches.addAll(edgeMatches)
                }
            }
        } finally {
            matchPool.shutdownNow()
        }

        if (allMatches.isEmpty()) {
            VeLog.w(TAG) { "alignFrames: no image matches found across $count frames; using IMU poses" }
            return frames
        }

        val rInit = Array(count) { k -> DoubleArray(9) { frames[k].rows[it].toDouble() } }
        val rCur = Array(count) { k -> rInit[k].copyOf() }
        var logScale = 0.0

        val dim = 3 * count + 1
        val huber = 0.005
        // Light per-frame IMU prior: constrains textureless frames while letting
        // even a small set of image matches dominate without pull-back jumps.
        val wTilt = 0.25
        val wYaw = 0.03
        val wScale = if (sphere) 20.0 else 80.0

        fun evalState(rots: Array<DoubleArray>, s: Double): Pair<Double, Double> {
            val scale = exp(s)
            var cost = 0.0
            var sqErrSum = 0.0
            for (m in allMatches) {
                val rxI = m.nxi * frames[m.i].tanX * scale
                val ryI = m.nyi * frames[m.i].tanY * scale
                val lenI = sqrt(rxI * rxI + ryI * ryI + 1.0)
                val ui0 = rxI / lenI
                val ui1 = ryI / lenI
                val ui2 = -1.0 / lenI
                val ri = rots[m.i]
                val pi0 = ri[0] * ui0 + ri[1] * ui1 + ri[2] * ui2
                val pi1 = ri[3] * ui0 + ri[4] * ui1 + ri[5] * ui2
                val pi2 = ri[6] * ui0 + ri[7] * ui1 + ri[8] * ui2

                val rxJ = m.nxj * frames[m.j].tanX * scale
                val ryJ = m.nyj * frames[m.j].tanY * scale
                val lenJ = sqrt(rxJ * rxJ + ryJ * ryJ + 1.0)
                val uj0 = rxJ / lenJ
                val uj1 = ryJ / lenJ
                val uj2 = -1.0 / lenJ
                val rj = rots[m.j]
                val pj0 = rj[0] * uj0 + rj[1] * uj1 + rj[2] * uj2
                val pj1 = rj[3] * uj0 + rj[4] * uj1 + rj[5] * uj2
                val pj2 = rj[6] * uj0 + rj[7] * uj1 + rj[8] * uj2

                val dx = pi0 - pj0
                val dy = pi1 - pj1
                val dz = pi2 - pj2
                val r2 = dx * dx + dy * dy + dz * dz
                val norm = sqrt(r2)
                sqErrSum += r2
                val term = if (norm <= huber) 0.5 * r2 else huber * (norm - 0.5 * huber)
                cost += m.weight * term
            }
            for (k in 0 until count) {
                val rk = rots[k]
                val r0 = rInit[k]
                val d = DoubleArray(9)
                for (a in 0 until 3) {
                    for (b in 0 until 3) {
                        d[a * 3 + b] = rk[a * 3] * r0[b * 3] + rk[a * 3 + 1] * r0[b * 3 + 1] + rk[a * 3 + 2] * r0[b * 3 + 2]
                    }
                }
                val e = logRotD(d)
                cost += 0.5 * (wTilt * e[0] * e[0] + wYaw * e[1] * e[1] + wTilt * e[2] * e[2])
            }
            cost += 0.5 * wScale * s * s
            val rmsDeg = Math.toDegrees(sqrt(sqErrSum / allMatches.size))
            return cost to rmsDeg
        }

        val initialRmsDeg = evalState(rCur, logScale).second
        var lambda = 1e-3
        var (curCost, _) = evalState(rCur, logScale)

        val hMat = DoubleArray(dim * dim)
        val gVec = DoubleArray(dim)
        val hDamped = DoubleArray(dim * dim)

        for (iter in 0 until 12) {
            hMat.fill(0.0)
            gVec.fill(0.0)
            val scale = exp(logScale)

            for (m in allMatches) {
                val rxI = m.nxi * frames[m.i].tanX * scale
                val ryI = m.nyi * frames[m.i].tanY * scale
                val lenI = sqrt(rxI * rxI + ryI * ryI + 1.0)
                val ui0 = rxI / lenI
                val ui1 = ryI / lenI
                val ui2 = -1.0 / lenI
                val dotI = (ui0 * rxI + ui1 * ryI)
                val dui0 = (rxI - ui0 * dotI) / lenI
                val dui1 = (ryI - ui1 * dotI) / lenI
                val dui2 = (-ui2 * dotI) / lenI

                val ri = rCur[m.i]
                val pi0 = ri[0] * ui0 + ri[1] * ui1 + ri[2] * ui2
                val pi1 = ri[3] * ui0 + ri[4] * ui1 + ri[5] * ui2
                val pi2 = ri[6] * ui0 + ri[7] * ui1 + ri[8] * ui2
                val dpi0 = ri[0] * dui0 + ri[1] * dui1 + ri[2] * dui2
                val dpi1 = ri[3] * dui0 + ri[4] * dui1 + ri[5] * dui2
                val dpi2 = ri[6] * dui0 + ri[7] * dui1 + ri[8] * dui2

                val rxJ = m.nxj * frames[m.j].tanX * scale
                val ryJ = m.nyj * frames[m.j].tanY * scale
                val lenJ = sqrt(rxJ * rxJ + ryJ * ryJ + 1.0)
                val uj0 = rxJ / lenJ
                val uj1 = ryJ / lenJ
                val uj2 = -1.0 / lenJ
                val dotJ = (uj0 * rxJ + uj1 * ryJ)
                val duj0 = (rxJ - uj0 * dotJ) / lenJ
                val duj1 = (ryJ - uj1 * dotJ) / lenJ
                val duj2 = (-uj2 * dotJ) / lenJ

                val rj = rCur[m.j]
                val pj0 = rj[0] * uj0 + rj[1] * uj1 + rj[2] * uj2
                val pj1 = rj[3] * uj0 + rj[4] * uj1 + rj[5] * uj2
                val pj2 = rj[6] * uj0 + rj[7] * uj1 + rj[8] * uj2
                val dpj0 = rj[0] * duj0 + rj[1] * duj1 + rj[2] * duj2
                val dpj1 = rj[3] * duj0 + rj[4] * duj1 + rj[5] * duj2
                val dpj2 = rj[6] * duj0 + rj[7] * duj1 + rj[8] * duj2

                val rx = pi0 - pj0
                val ry = pi1 - pj1
                val rz = pi2 - pj2
                val norm = sqrt(rx * rx + ry * ry + rz * rz)
                val w = m.weight * (if (norm > huber) huber / norm else 1.0)

                val js0 = dpi0 - dpj0
                val js1 = dpi1 - dpj1
                val js2 = dpi2 - dpj2

                val jCol0 = doubleArrayOf(0.0, -pi2, pi1, 0.0, pj2, -pj1, js0)
                val jCol1 = doubleArrayOf(pi2, 0.0, -pi0, -pj2, 0.0, pj0, js1)
                val jCol2 = doubleArrayOf(-pi1, pi0, 0.0, pj1, -pj0, 0.0, js2)

                val bi = 3 * m.i
                val bj = 3 * m.j
                val bs = 3 * count
                val mapIdx = intArrayOf(bi, bi + 1, bi + 2, bj, bj + 1, bj + 2, bs)

                for (a in 0 until 7) {
                    val ia = mapIdx[a]
                    val ja0 = jCol0[a]
                    val ja1 = jCol1[a]
                    val ja2 = jCol2[a]
                    gVec[ia] += w * (ja0 * rx + ja1 * ry + ja2 * rz)
                    for (b in 0..a) {
                        val ib = mapIdx[b]
                        val v = w * (ja0 * jCol0[b] + ja1 * jCol1[b] + ja2 * jCol2[b])
                        hMat[ia * dim + ib] += v
                        if (ia != ib) hMat[ib * dim + ia] += v
                    }
                }
            }

            for (k in 0 until count) {
                val rk = rCur[k]
                val r0 = rInit[k]
                val d = DoubleArray(9)
                for (a in 0 until 3) {
                    for (b in 0 until 3) {
                        d[a * 3 + b] = rk[a * 3] * r0[b * 3] + rk[a * 3 + 1] * r0[b * 3 + 1] + rk[a * 3 + 2] * r0[b * 3 + 2]
                    }
                }
                val e = logRotD(d)
                val base = 3 * k
                hMat[base * dim + base] += wTilt
                hMat[(base + 1) * dim + (base + 1)] += wYaw
                hMat[(base + 2) * dim + (base + 2)] += wTilt
                gVec[base] += wTilt * e[0]
                gVec[base + 1] += wYaw * e[1]
                gVec[base + 2] += wTilt * e[2]
            }
            val sIdx = 3 * count
            hMat[sIdx * dim + sIdx] += wScale
            gVec[sIdx] += wScale * logScale

            val rhs = DoubleArray(dim) { -gVec[it] }
            var accepted = false
            for (attempt in 0 until 5) {
                System.arraycopy(hMat, 0, hDamped, 0, dim * dim)
                for (dIdx in 0 until dim) {
                    hDamped[dIdx * dim + dIdx] += lambda * max(1.0, hDamped[dIdx * dim + dIdx])
                }
                val delta = solveCholesky(hDamped, rhs, dim)
                if (delta == null) {
                    lambda *= 10.0
                    continue
                }
                val nextScale = (logScale + delta[sIdx]).coerceIn(-0.12, 0.12)
                val trialR = Array(count) { k ->
                    val b = 3 * k
                    orthonormalizeD(mulMatD(expRot(delta[b], delta[b + 1], delta[b + 2]), rCur[k]))
                }
                val (trialCost, _) = evalState(trialR, nextScale)
                if (trialCost < curCost) {
                    for (k in 0 until count) rCur[k] = trialR[k]
                    logScale = nextScale
                    val improvement = (curCost - trialCost) / max(1e-9, curCost)
                    curCost = trialCost
                    lambda = max(1e-6, lambda * 0.3)
                    accepted = true
                    if (improvement < 1e-5) {
                        val finalRms = evalState(rCur, logScale).second
                        VeLog.d(TAG) {
                            "alignFrames: frames=$count edges=$matchedEdges matches=${allMatches.size} " +
                                "rms=${"%.3f".format(initialRmsDeg)}->${"%.3f".format(finalRms)}deg " +
                                "scale=${"%.4f".format(exp(logScale))}"
                        }
                        val fScale = exp(logScale).toFloat()
                        return frames.indices.map { k ->
                            PanoFrame(
                                frames[k].jpeg,
                                frames[k].width,
                                frames[k].height,
                                FloatArray(9) { rCur[k][it].toFloat() },
                                frames[k].tanX * fScale,
                                frames[k].tanY * fScale,
                            )
                        }
                    }
                    break
                } else {
                    lambda *= 5.0
                }
            }
            if (!accepted && lambda > 1e5) break
        }

        val finalRms = evalState(rCur, logScale).second
        VeLog.d(TAG) {
            "alignFrames: frames=$count edges=$matchedEdges matches=${allMatches.size} " +
                "rms=${"%.3f".format(initialRmsDeg)}->${"%.3f".format(finalRms)}deg " +
                "scale=${"%.4f".format(exp(logScale))}"
        }
        val fScale = exp(logScale).toFloat()
        return frames.indices.map { k ->
            PanoFrame(
                frames[k].jpeg,
                frames[k].width,
                frames[k].height,
                FloatArray(9) { rCur[k][it].toFloat() },
                frames[k].tanX * fScale,
                frames[k].tanY * fScale,
            )
        }
    }

    // ── Exposure / white-balance gains ───────────────────────────────────

    private class Overlap(val i: Int, val j: Int, val n: Int, val meanI: FloatArray, val meanJ: FloatArray)

    private fun estimateGains(geos: List<Geo>, small: List<Triple<IntArray, Int, Int>>): Array<FloatArray> {
        val count = geos.size
        val gains = Array(count) { floatArrayOf(1f, 1f, 1f) }
        if (count < 2) return gains

        val pairs = ArrayList<Overlap>()
        val grid = 16
        for (i in 0 until count) {
            val a = geos[i]
            for (j in i + 1 until count) {
                val b = geos[j]
                val dot = a.fx * b.fx + a.fy * b.fy + a.fz * b.fz
                if (dot < cos(a.radius + b.radius).toFloat()) continue
                var n = 0
                val si = DoubleArray(3)
                val sj = DoubleArray(3)
                val (pi, wi, hi) = small[i]
                val (pj, wj, hj) = small[j]
                for (gy in 0 until grid) {
                    for (gx in 0 until grid) {
                        val nxA = ((gx + 0.5f) / grid * 2f - 1f) * 0.9f
                        val nyA = ((gy + 0.5f) / grid * 2f - 1f) * 0.9f
                        val rx = nxA * a.tanX
                        val ry = nyA * a.tanY
                        val dx = a.rows[0] * rx + a.rows[1] * ry - a.rows[2]
                        val dy = a.rows[3] * rx + a.rows[4] * ry - a.rows[5]
                        val dz = a.rows[6] * rx + a.rows[7] * ry - a.rows[8]
                        val len = sqrt(dx * dx + dy * dy + dz * dz)
                        val ux = dx / len
                        val uy = dy / len
                        val uz = dz / len
                        val vz = b.rows[2] * ux + b.rows[5] * uy + b.rows[8] * uz
                        if (vz > -1e-3f) continue
                        val inv = -1f / vz
                        val nxB = (b.rows[0] * ux + b.rows[3] * uy + b.rows[6] * uz) * inv / b.tanX
                        val nyB = (b.rows[1] * ux + b.rows[4] * uy + b.rows[7] * uz) * inv / b.tanY
                        if (abs(nxB) > 0.9f || abs(nyB) > 0.9f) continue
                        val rowA = ((0.5f - nyA * 0.5f) * hi - 0.5f).roundToInt().coerceIn(0, hi - 1)
                        val colA = ((nxA * 0.5f + 0.5f) * wi - 0.5f).roundToInt().coerceIn(0, wi - 1)
                        val rowB = ((0.5f - nyB * 0.5f) * hj - 0.5f).roundToInt().coerceIn(0, hj - 1)
                        val colB = ((nxB * 0.5f + 0.5f) * wj - 0.5f).roundToInt().coerceIn(0, wj - 1)
                        val ca = pi[rowA * wi + colA]
                        val cb = pj[rowB * wj + colB]
                        val ra = ((ca shr 16) and 0xFF) / 255.0
                        val ga = ((ca shr 8) and 0xFF) / 255.0
                        val ba = (ca and 0xFF) / 255.0
                        val rb = ((cb shr 16) and 0xFF) / 255.0
                        val gb = ((cb shr 8) and 0xFF) / 255.0
                        val bb = (cb and 0xFF) / 255.0
                        if (max(abs(ra - rb), max(abs(ga - gb), abs(ba - bb))) > 0.30) continue
                        si[0] += ra; si[1] += ga; si[2] += ba
                        sj[0] += rb; sj[1] += gb; sj[2] += bb
                        n++
                    }
                }
                if (n < 20) continue
                pairs.add(
                    Overlap(
                        i, j, n,
                        floatArrayOf((si[0] / n).toFloat(), (si[1] / n).toFloat(), (si[2] / n).toFloat()),
                        floatArrayOf((sj[0] / n).toFloat(), (sj[1] / n).toFloat(), (sj[2] / n).toFloat()),
                    ),
                )
            }
        }
        if (pairs.isEmpty()) return gains

        val sn2 = 0.1 * 0.1
        val sg2 = 0.1 * 0.1
        for (c in 0 until 3) {
            val g = DoubleArray(count) { 1.0 }
            repeat(80) {
                for (k in 0 until count) {
                    var num = 1.0 / sg2
                    var den = 1.0 / sg2
                    for (p in pairs) {
                        val mine: Float
                        val other: Float
                        val otherIndex: Int
                        if (p.i == k) {
                            mine = p.meanI[c]; other = p.meanJ[c]; otherIndex = p.j
                        } else if (p.j == k) {
                            mine = p.meanJ[c]; other = p.meanI[c]; otherIndex = p.i
                        } else continue
                        num += p.n * g[otherIndex] * mine * other / sn2
                        den += p.n * mine * mine / sn2
                    }
                    g[k] = (num / den).coerceIn(0.5, 2.0)
                }
            }
            val mean = g.average()
            for (k in 0 until count) gains[k][c] = (g[k] / mean).toFloat()
        }
        return gains
    }

    // ── Graph-cut seam finding (alpha-expansion with Dinic max-flow) ─────

    private class SeamGrid(
        val step: Int,
        val w: Int,
        val h: Int,
        val owner: IntArray,
    )

    private class DinicGraph(maxNodes: Int, maxEdges: Int) {
        private val head = IntArray(maxNodes) { -1 }
        private val level = IntArray(maxNodes)
        private val cur = IntArray(maxNodes)
        private val queue = IntArray(maxNodes)
        private val to = IntArray(maxEdges)
        private val cap = FloatArray(maxEdges)
        private val next = IntArray(maxEdges)
        private var edgeCount = 0

        fun addEdge(u: Int, v: Int, c: Float) {
            if (c <= 1e-7f) return
            val e0 = edgeCount++
            to[e0] = v
            cap[e0] = c
            next[e0] = head[u]
            head[u] = e0

            val e1 = edgeCount++
            to[e1] = u
            cap[e1] = 0f
            next[e1] = head[v]
            head[v] = e1
        }

        private fun bfs(src: Int, snk: Int, nodeCount: Int): Boolean {
            for (i in 0 until nodeCount) level[i] = -1
            level[src] = 0
            var qh = 0
            var qt = 0
            queue[qt++] = src
            while (qh < qt) {
                val u = queue[qh++]
                var e = head[u]
                while (e != -1) {
                    if (cap[e] > 1e-7f) {
                        val v = to[e]
                        if (level[v] < 0) {
                            level[v] = level[u] + 1
                            queue[qt++] = v
                        }
                    }
                    e = next[e]
                }
            }
            return level[snk] >= 0
        }

        private fun dfs(u: Int, snk: Int, pushed: Float): Float {
            if (pushed <= 1e-7f || u == snk) return pushed
            var e = cur[u]
            while (e != -1) {
                cur[u] = e
                val v = to[e]
                if (level[v] == level[u] + 1 && cap[e] > 1e-7f) {
                    val tr = dfs(v, snk, min(pushed, cap[e]))
                    if (tr > 1e-7f) {
                        cap[e] -= tr
                        cap[e xor 1] += tr
                        return tr
                    }
                }
                e = next[e]
            }
            return 0f
        }

        fun runMaxFlow(src: Int, snk: Int, nodeCount: Int) {
            while (bfs(src, snk, nodeCount)) {
                for (i in 0 until nodeCount) cur[i] = head[i]
                while (dfs(src, snk, 1e9f) > 1e-7f) {
                    // push until blocking flow complete
                }
            }
            bfs(src, snk, nodeCount)
        }

        fun isSourceSide(node: Int): Boolean = level[node] >= 0
    }

    private fun sampleSmallFrame(
        f: Geo,
        dx: Float,
        dy: Float,
        dz: Float,
        small: Triple<IntArray, Int, Int>,
        gain: FloatArray,
    ): Int {
        if (dx * f.fx + dy * f.fy + dz * f.fz < f.cosRadius) return -1
        val m = f.rows
        val vz = m[2] * dx + m[5] * dy + m[8] * dz
        if (vz > -1e-4f) return -1
        val inv = -1f / vz
        val nx = (m[0] * dx + m[3] * dy + m[6] * dz) * inv / f.tanX
        val ny = (m[1] * dx + m[4] * dy + m[7] * dz) * inv / f.tanY
        if (abs(nx) > 0.996f || abs(ny) > 0.996f) return -1

        val (px, w, h) = small
        val sx = ((nx * 0.5f + 0.5f) * w - 0.5f).roundToInt().coerceIn(0, w - 1)
        val sy = ((0.5f - ny * 0.5f) * h - 0.5f).roundToInt().coerceIn(0, h - 1)
        val c = px[sy * w + sx]
        val r = (((c shr 16) and 0xFF) * gain[0]).roundToInt().coerceIn(0, 255)
        val g = (((c shr 8) and 0xFF) * gain[1]).roundToInt().coerceIn(0, 255)
        val b = ((c and 0xFF) * gain[2]).roundToInt().coerceIn(0, 255)
        return (r shl 16) or (g shl 8) or b
    }

    private fun frameFeather(f: Geo, dx: Float, dy: Float, dz: Float): Float {
        if (dx * f.fx + dy * f.fy + dz * f.fz < f.cosRadius) return 0f
        val m = f.rows
        val vz = m[2] * dx + m[5] * dy + m[8] * dz
        if (vz > -1e-4f) return 0f
        val inv = -1f / vz
        val nx = (m[0] * dx + m[3] * dy + m[6] * dz) * inv / f.tanX
        val ny = (m[1] * dx + m[4] * dy + m[7] * dz) * inv / f.tanY
        val wx = 1f - abs(nx)
        val wy = 1f - abs(ny)
        return if (wx > 0.004f && wy > 0.004f) wx * wy else 0f
    }

    private fun colorDiff(c1: Int, c2: Int): Float {
        if (c1 < 0 || c2 < 0) return 0f
        val dr = abs(((c1 shr 16) and 0xFF) - ((c2 shr 16) and 0xFF))
        val dg = abs(((c1 shr 8) and 0xFF) - ((c2 shr 8) and 0xFF))
        val db = abs((c1 and 0xFF) - (c2 and 0xFF))
        return (dr + dg + db) / (3f * 255f)
    }

    /** Directional L1 gradient difference across edge (p, q), preserving metric submodularity. */
    private fun edgeGradDiff(c1p: Int, c1q: Int, c2p: Int, c2q: Int): Float {
        if (c1p < 0 || c1q < 0 || c2p < 0 || c2q < 0) return 0f
        val dr = abs((((c1p shr 16) and 0xFF) - ((c1q shr 16) and 0xFF)) - (((c2p shr 16) and 0xFF) - ((c2q shr 16) and 0xFF)))
        val dg = abs((((c1p shr 8) and 0xFF) - ((c1q shr 8) and 0xFF)) - (((c2p shr 8) and 0xFF) - ((c2q shr 8) and 0xFF)))
        val db = abs(((c1p and 0xFF) - (c1q and 0xFF)) - ((c2p and 0xFF) - (c2q and 0xFF)))
        return (dr + dg + db) / (3f * 255f)
    }

    private fun findSeams(
        geos: List<Geo>,
        small: List<Triple<IntArray, Int, Int>>,
        gains: Array<FloatArray>,
        fullW: Int,
        fullH: Int,
        cropLeft: Int,
        cropTop: Int,
        cropW: Int,
        cropH: Int,
        sphere: Boolean,
    ): SeamGrid {
        val step = max(2, ceil(max(cropW, cropH) / 600.0).toInt())
        val sw = max(1, (cropW + step - 1) / step)
        val sh = max(1, (cropH + step - 1) / step)

        val dirX = FloatArray(sw * sh)
        val dirY = FloatArray(sw * sh)
        val dirZ = FloatArray(sw * sh)
        val seamSinLon = FloatArray(sw)
        val seamCosLon = FloatArray(sw)
        for (sx in 0 until sw) {
            val px = min(cropW - 1.0, sx * step + (step - 1) * 0.5)
            val lon = ((cropLeft + px + 0.5) / fullW) * 2.0 * PI - PI
            seamSinLon[sx] = sin(lon).toFloat()
            seamCosLon[sx] = cos(lon).toFloat()
        }
        for (sy in 0 until sh) {
            val py = min(cropH - 1.0, sy * step + (step - 1) * 0.5)
            val lat = PI / 2.0 - ((cropTop + py + 0.5) / fullH) * PI
            val cosLat = cos(lat).toFloat()
            val sinLat = sin(lat).toFloat()
            val row = sy * sw
            for (sx in 0 until sw) {
                val p = row + sx
                dirX[p] = cosLat * seamSinLon[sx]
                dirY[p] = sinLat
                dirZ[p] = -cosLat * seamCosLon[sx]
            }
        }

        val count = geos.size
        val owner = IntArray(sw * sh) { -1 }
        val ownerColor = IntArray(sw * sh) { -1 }

        for (p in 0 until sw * sh) {
            val dx = dirX[p]
            val dy = dirY[p]
            val dz = dirZ[p]
            var bestK = -1
            var maxF = 0f
            for (k in 0 until count) {
                val f = frameFeather(geos[k], dx, dy, dz)
                if (f > maxF) {
                    maxF = f
                    bestK = k
                }
            }
            if (bestK >= 0) {
                owner[p] = bestK
                ownerColor[p] = sampleSmallFrame(geos[bestK], dx, dy, dz, small[bestK], gains[bestK])
            }
        }

        if (count < 2) return SeamGrid(step, sw, sh, owner)

        val nodeId = IntArray(sw * sh) { -1 }
        val activePixels = IntArray(sw * sh)
        val alphaCol = IntArray(sw * sh) { -1 }
        val alphaFeather = FloatArray(sw * sh)

        val baseSeamCost = 0.012f
        val centerBias = 0.04f

        fun dataCost(feather: Float): Float = centerBias * (1f - feather)

        fun pairCost(l1: Int, l2: Int, c1p: Int, c1q: Int, c2p: Int, c2q: Int): Float {
            if (l1 == l2 || l1 < 0 || l2 < 0) return 0f
            if (c1p < 0 || c2p < 0 || c1q < 0 || c2q < 0) return baseSeamCost
            return 2f * baseSeamCost + colorDiff(c1p, c2p) + colorDiff(c1q, c2q) +
                0.6f * edgeGradDiff(c1p, c1q, c2p, c2q)
        }

        var swaps = 0
        for (sweep in 0 until 2) {
            var sweepChanges = 0
            for (alpha in 0 until count) {
                val ga = geos[alpha]
                var activeCount = 0
                for (p in 0 until sw * sh) {
                    val f = frameFeather(ga, dirX[p], dirY[p], dirZ[p])
                    if (f > 0f) {
                        val c = sampleSmallFrame(ga, dirX[p], dirY[p], dirZ[p], small[alpha], gains[alpha])
                        if (c >= 0) {
                            nodeId[p] = activeCount
                            activePixels[activeCount++] = p
                            alphaCol[p] = c
                            alphaFeather[p] = f
                        } else {
                            nodeId[p] = -1
                        }
                    } else {
                        nodeId[p] = -1
                    }
                }
                if (activeCount == 0) continue

                val src = activeCount
                val snk = activeCount + 1
                val nodeTotal = activeCount + 2
                val srcCap = FloatArray(activeCount)
                val snkCap = FloatArray(activeCount)
                val edgeU = IntArray(activeCount * 2)
                val edgeV = IntArray(activeCount * 2)
                val edgeC = FloatArray(activeCount * 2)
                var nEdges = 0

                fun addSource(n: Int, c: Float) { srcCap[n] += c }
                fun addSink(n: Int, c: Float) { snkCap[n] += c }

                for (n in 0 until activeCount) {
                    val p = activePixels[n]
                    val lp = owner[p]
                    if (lp == alpha) {
                        addSource(n, 1e6f)
                    } else if (lp < 0) {
                        addSink(n, 1e6f)
                        addSource(n, dataCost(alphaFeather[p]))
                    } else {
                        val fp = frameFeather(geos[lp], dirX[p], dirY[p], dirZ[p])
                        addSink(n, if (fp > 0f) dataCost(fp) else 1e5f)
                        addSource(n, dataCost(alphaFeather[p]))
                    }
                }

                fun processNeighbor(np: Int, p: Int, q: Int) {
                    val lp = owner[p]
                    val lq = owner[q]
                    val nq = nodeId[q]

                    val clpP = if (lp >= 0) ownerColor[p] else -1
                    val clqQ = if (lq >= 0) ownerColor[q] else -1
                    val calpP = alphaCol[p]

                    if (nq < 0) {
                        if (lp == alpha || lq < 0) return
                        val clpQ = if (lp >= 0) sampleSmallFrame(geos[lp], dirX[q], dirY[q], dirZ[q], small[lp], gains[lp]) else -1
                        val calpQ = sampleSmallFrame(ga, dirX[q], dirY[q], dirZ[q], small[alpha], gains[alpha])
                        val e00 = pairCost(lp, lq, clpP, clpQ, -1, clqQ)
                        val e10 = pairCost(alpha, lq, calpP, calpQ, -1, clqQ)
                        addSink(np, e00)
                        addSource(np, e10)
                        return
                    }

                    if (np > nq) return
                    val calpQ = alphaCol[q]

                    val clpQ = if (lp >= 0) sampleSmallFrame(geos[lp], dirX[q], dirY[q], dirZ[q], small[lp], gains[lp]) else -1
                    val clqP = if (lq >= 0) sampleSmallFrame(geos[lq], dirX[p], dirY[p], dirZ[p], small[lq], gains[lq]) else -1

                    val e00 = pairCost(lp, lq, clpP, clpQ, clqP, clqQ)
                    val e01 = pairCost(lp, alpha, clpP, clpQ, calpP, calpQ)
                    val e10 = pairCost(alpha, lq, calpP, calpQ, clqP, clqQ)

                    val aTerm = e10 - e00
                    val bTerm = -e10
                    val cTerm = max(0f, e01 + e10 - e00)

                    if (aTerm >= 0f) addSource(np, aTerm) else addSink(np, -aTerm)
                    if (bTerm >= 0f) addSource(nq, bTerm) else addSink(nq, -bTerm)
                    if (cTerm > 1e-6f) {
                        edgeU[nEdges] = np
                        edgeV[nEdges] = nq
                        edgeC[nEdges] = cTerm
                        nEdges++
                    }
                }

                for (n in 0 until activeCount) {
                    val p = activePixels[n]
                    val sx = p % sw
                    val sy = p / sw
                    if (sx + 1 < sw) {
                        processNeighbor(n, p, p + 1)
                    } else if (sphere && sw > 2) {
                        processNeighbor(n, p, sy * sw)
                    }
                    if (sx > 0) {
                        processNeighbor(n, p, p - 1)
                    } else if (sphere && sw > 2) {
                        processNeighbor(n, p, sy * sw + (sw - 1))
                    }
                    if (sy + 1 < sh) processNeighbor(n, p, p + sw)
                    if (sy > 0) processNeighbor(n, p, p - sw)
                }

                val graph = DinicGraph(nodeTotal, (activeCount * 2 + nEdges) * 2)
                for (n in 0 until activeCount) {
                    val m = min(srcCap[n], snkCap[n])
                    val s = srcCap[n] - m
                    val t = snkCap[n] - m
                    if (s > 1e-6f) graph.addEdge(src, n, s)
                    if (t > 1e-6f) graph.addEdge(n, snk, t)
                }
                for (e in 0 until nEdges) {
                    graph.addEdge(edgeU[e], edgeV[e], edgeC[e])
                }

                graph.runMaxFlow(src, snk, nodeTotal)

                for (n in 0 until activeCount) {
                    val p = activePixels[n]
                    if (!graph.isSourceSide(n) && owner[p] != alpha) {
                        owner[p] = alpha
                        ownerColor[p] = alphaCol[p]
                        sweepChanges++
                        swaps++
                    }
                }
            }
            if (sweepChanges == 0) break
        }
        VeLog.d(TAG) { "findSeams: grid=${sw}x$sh step=$step swaps=$swaps" }
        return SeamGrid(step, sw, sh, owner)
    }

    // ── Banded multi-band (Laplacian pyramid) blending ───────────────────

    private class PyramidLevel(val w: Int, val h: Int) {
        val r = FloatArray(w * h)
        val g = FloatArray(w * h)
        val b = FloatArray(w * h)
        val v = FloatArray(w * h)
    }

    private fun downsampleMasked(
        src: PyramidLevel,
        dst: PyramidLevel,
        wrapX: Boolean,
        tmpR: FloatArray,
        tmpG: FloatArray,
        tmpB: FloatArray,
        tmpV: FloatArray,
    ) {
        val sw = src.w
        val sh = src.h
        val dw = dst.w
        val dh = dst.h
        val ker = floatArrayOf(1f, 4f, 6f, 4f, 1f)

        for (y in 0 until sh) {
            val sRow = y * sw
            val tRow = y * dw
            for (x in 0 until dw) {
                val cx = x * 2
                var sr = 0f
                var sg = 0f
                var sb = 0f
                var wSum = 0f
                for (d in -2..2) {
                    var sx = cx + d
                    if (wrapX) {
                        sx = ((sx % sw) + sw) % sw
                    } else if (sx < 0 || sx >= sw) {
                        continue
                    }
                    val idx = sRow + sx
                    val v = src.v[idx]
                    if (v > 1e-6f) {
                        val kw = ker[d + 2] * v
                        sr += src.r[idx] * kw
                        sg += src.g[idx] * kw
                        sb += src.b[idx] * kw
                        wSum += kw
                    }
                }
                val outIdx = tRow + x
                if (wSum > 1e-6f) {
                    val inv = 1f / wSum
                    tmpR[outIdx] = sr * inv
                    tmpG[outIdx] = sg * inv
                    tmpB[outIdx] = sb * inv
                    tmpV[outIdx] = 1f
                } else {
                    tmpR[outIdx] = 0f
                    tmpG[outIdx] = 0f
                    tmpB[outIdx] = 0f
                    tmpV[outIdx] = 0f
                }
            }
        }

        for (y in 0 until dh) {
            val cy = y * 2
            val dRow = y * dw
            for (x in 0 until dw) {
                var sr = 0f
                var sg = 0f
                var sb = 0f
                var wSum = 0f
                for (d in -2..2) {
                    val sy = cy + d
                    if (sy < 0 || sy >= sh) continue
                    val idx = sy * dw + x
                    val v = tmpV[idx]
                    if (v > 1e-6f) {
                        val kw = ker[d + 2] * v
                        sr += tmpR[idx] * kw
                        sg += tmpG[idx] * kw
                        sb += tmpB[idx] * kw
                        wSum += kw
                    }
                }
                val outIdx = dRow + x
                if (wSum > 1e-6f) {
                    val inv = 1f / wSum
                    dst.r[outIdx] = sr * inv
                    dst.g[outIdx] = sg * inv
                    dst.b[outIdx] = sb * inv
                    dst.v[outIdx] = 1f
                } else {
                    dst.r[outIdx] = 0f
                    dst.g[outIdx] = 0f
                    dst.b[outIdx] = 0f
                    dst.v[outIdx] = 0f
                }
            }
        }
    }

    private fun downsampleMask(
        src: FloatArray,
        sw: Int,
        sh: Int,
        dst: FloatArray,
        dw: Int,
        dh: Int,
        wrapX: Boolean,
        tmp: FloatArray,
    ) {
        val ker = floatArrayOf(1f, 4f, 6f, 4f, 1f)
        for (y in 0 until sh) {
            val sRow = y * sw
            val tRow = y * dw
            for (x in 0 until dw) {
                val cx = x * 2
                var sum = 0f
                var kSum = 0f
                for (d in -2..2) {
                    var sx = cx + d
                    if (wrapX) {
                        sx = ((sx % sw) + sw) % sw
                    } else if (sx < 0 || sx >= sw) {
                        continue
                    }
                    val kw = ker[d + 2]
                    sum += src[sRow + sx] * kw
                    kSum += kw
                }
                tmp[tRow + x] = if (kSum > 0f) sum / kSum else 0f
            }
        }
        for (y in 0 until dh) {
            val cy = y * 2
            val dRow = y * dw
            for (x in 0 until dw) {
                var sum = 0f
                var kSum = 0f
                for (d in -2..2) {
                    val sy = cy + d
                    if (sy < 0 || sy >= sh) continue
                    val kw = ker[d + 2]
                    sum += tmp[sy * dw + x] * kw
                    kSum += kw
                }
                dst[dRow + x] = if (kSum > 0f) sum / kSum else 0f
            }
        }
    }

    private fun expandMasked(
        src: PyramidLevel,
        dstW: Int,
        dstH: Int,
        wrapX: Boolean,
        outR: FloatArray,
        outG: FloatArray,
        outB: FloatArray,
        tmpR: FloatArray,
        tmpG: FloatArray,
        tmpB: FloatArray,
        tmpV: FloatArray,
    ) {
        val sw = src.w
        val sh = src.h
        val ker = floatArrayOf(1f, 4f, 6f, 4f, 1f)

        for (y in 0 until sh) {
            val sRow = y * sw
            val tRow = y * dstW
            for (x in 0 until dstW) {
                var sr = 0f
                var sg = 0f
                var sb = 0f
                var wSum = 0f
                val parity = x and 1
                var d = -2 + parity
                while (d <= 2) {
                    val tx = x - d
                    var sx = tx shr 1
                    if (wrapX) {
                        sx = ((sx % sw) + sw) % sw
                    } else if (sx < 0 || sx >= sw) {
                        d += 2
                        continue
                    }
                    val idx = sRow + sx
                    val v = src.v[idx]
                    if (v > 1e-6f) {
                        val kw = ker[d + 2] * v
                        sr += src.r[idx] * kw
                        sg += src.g[idx] * kw
                        sb += src.b[idx] * kw
                        wSum += kw
                    }
                    d += 2
                }
                val outIdx = tRow + x
                if (wSum > 1e-6f) {
                    val inv = 1f / wSum
                    tmpR[outIdx] = sr * inv
                    tmpG[outIdx] = sg * inv
                    tmpB[outIdx] = sb * inv
                    tmpV[outIdx] = 1f
                } else {
                    tmpR[outIdx] = 0f
                    tmpG[outIdx] = 0f
                    tmpB[outIdx] = 0f
                    tmpV[outIdx] = 0f
                }
            }
        }

        for (y in 0 until dstH) {
            val oRow = y * dstW
            val parity = y and 1
            for (x in 0 until dstW) {
                var sr = 0f
                var sg = 0f
                var sb = 0f
                var wSum = 0f
                var d = -2 + parity
                while (d <= 2) {
                    val sy = (y - d) shr 1
                    if (sy < 0 || sy >= sh) {
                        d += 2
                        continue
                    }
                    val idx = sy * dstW + x
                    val v = tmpV[idx]
                    if (v > 1e-6f) {
                        val kw = ker[d + 2] * v
                        sr += tmpR[idx] * kw
                        sg += tmpG[idx] * kw
                        sb += tmpB[idx] * kw
                        wSum += kw
                    }
                    d += 2
                }
                val outIdx = oRow + x
                if (wSum > 1e-6f) {
                    val inv = 1f / wSum
                    outR[outIdx] = sr * inv
                    outG[outIdx] = sg * inv
                    outB[outIdx] = sb * inv
                } else {
                    outR[outIdx] = 0f
                    outG[outIdx] = 0f
                    outB[outIdx] = 0f
                }
            }
        }
    }

    private fun frameHorizontalPixelRange(
        f: Geo,
        fullW: Int,
        cropLeft: Int,
        cropW: Int,
        sphere: Boolean,
    ): Pair<Int, Int> {
        val sampleSteps = 5
        val lons = ArrayList<Double>(25)
        for (iy in 0 until sampleSteps) {
            val ny = -1f + iy * (2f / (sampleSteps - 1))
            for (ix in 0 until sampleSteps) {
                val nx = -1f + ix * (2f / (sampleSteps - 1))
                val rx = nx * f.tanX
                val ry = ny * f.tanY
                val wx = f.rows[0] * rx + f.rows[1] * ry - f.rows[2]
                val wy = f.rows[3] * rx + f.rows[4] * ry - f.rows[5]
                val wz = f.rows[6] * rx + f.rows[7] * ry - f.rows[8]
                val len = sqrt(wx * wx + wy * wy + wz * wz)
                val lat = asin((wy / len).toDouble().coerceIn(-1.0, 1.0))
                if (abs(lat) > PI / 2 - 0.15) return 0 to (cropW - 1)
                lons.add(atan2(wx.toDouble(), -wz.toDouble()))
            }
        }
        val ref = f.lon
        var minOff = Double.POSITIVE_INFINITY
        var maxOff = Double.NEGATIVE_INFINITY
        for (l in lons) {
            val d = wrapAngle(l - ref)
            if (d < minOff) minOff = d
            if (d > maxOff) maxOff = d
        }
        if (maxOff - minOff >= PI * 1.4) return 0 to (cropW - 1)
        val lon0 = ref + minOff
        val lon1 = ref + maxOff
        val x0 = floor(((lon0 + PI) / (2.0 * PI)) * fullW - cropLeft - 0.5).toInt() - 4
        val x1 = ceil(((lon1 + PI) / (2.0 * PI)) * fullW - cropLeft - 0.5).toInt() + 4
        return if (sphere) x0 to x1 else x0.coerceIn(0, cropW - 1) to x1.coerceIn(0, cropW - 1)
    }

  // ── Stitching ────────────────────────────────────────────────────────

    fun stitch(input: List<PanoFrame>, sphere: Boolean): StitchResult? {
        if (input.isEmpty()) return null
        val tStart = System.currentTimeMillis()
        val recentred = recentre(input, sphere)
        val aligned = alignFrames(recentred, sphere)
        val frames = recentre(aligned, sphere)
        val geos = frames.map { Geo(it) }

        val focalPx = geos.map { it.frame.width / (2.0 * it.tanX) }.average()
        var fullW = (2.0 * PI * focalPx).roundToInt()

        var lonMin = -PI
        var lonMax = PI
        var latTop = PI / 2
        var latBottom = -PI / 2
        if (!sphere) {
            lonMin = Double.MAX_VALUE
            lonMax = -Double.MAX_VALUE
            var inscribedTop = Double.MAX_VALUE
            var inscribedBottom = -Double.MAX_VALUE
            var unionTop = -Double.MAX_VALUE
            var unionBottom = Double.MAX_VALUE
            var meanVertical = 0.0
            for (g in geos) {
                val eX = atan(g.tanX.toDouble())
                val widen = eX / max(0.2, cos(g.lat))
                val half = min(PI, widen)
                lonMin = min(lonMin, g.lon - half)
                lonMax = max(lonMax, g.lon + half)

                var frameMinTop = Double.MAX_VALUE
                var frameMaxTop = -Double.MAX_VALUE
                var frameMaxBot = -Double.MAX_VALUE
                var frameMinBot = Double.MAX_VALUE
                for (s in 0..4) {
                    val nx = -1f + s * 0.5f
                    for (isTop in booleanArrayOf(true, false)) {
                        val ny = if (isTop) 1f else -1f
                        val rx = nx * g.tanX
                        val ry = ny * g.tanY
                        val wx = g.rows[0] * rx + g.rows[1] * ry - g.rows[2]
                        val wy = g.rows[3] * rx + g.rows[4] * ry - g.rows[5]
                        val wz = g.rows[6] * rx + g.rows[7] * ry - g.rows[8]
                        val len = sqrt(wx * wx + wy * wy + wz * wz)
                        val lat = asin((wy / len).toDouble().coerceIn(-1.0, 1.0))
                        if (isTop) {
                            frameMinTop = min(frameMinTop, lat)
                            frameMaxTop = max(frameMaxTop, lat)
                        } else {
                            frameMaxBot = max(frameMaxBot, lat)
                            frameMinBot = min(frameMinBot, lat)
                        }
                    }
                }
                inscribedTop = min(inscribedTop, frameMinTop)
                inscribedBottom = max(inscribedBottom, frameMaxBot)
                unionTop = max(unionTop, frameMaxTop)
                unionBottom = min(unionBottom, frameMinBot)
                meanVertical += (frameMaxTop - frameMinBot)
            }
            meanVertical /= geos.size
            lonMin = max(-PI, lonMin)
            lonMax = min(PI, lonMax)
            if (inscribedTop - inscribedBottom >= 0.45 * meanVertical) {
                latTop = inscribedTop
                latBottom = inscribedBottom
            } else {
                latTop = unionTop
                latBottom = unionBottom
            }
            latTop = min(PI / 2, latTop)
            latBottom = max(-PI / 2, latBottom)
        }

        fun cropPixelsAt(scale: Double): Double {
            val fw = fullW * scale
            return (lonMax - lonMin) / (2 * PI) * fw * ((latTop - latBottom) / PI * (fw / 2))
        }
        val scale = if (cropPixelsAt(1.0) > MAX_OUTPUT_PIXELS) {
            sqrt(MAX_OUTPUT_PIXELS / cropPixelsAt(1.0))
        } else {
            1.0
        }
        fullW = max(8, ((fullW * scale).roundToInt() / 8) * 8)
        val fullH = fullW / 2
        val cropLeft = if (sphere) 0 else ((lonMin + PI) / (2 * PI) * fullW).roundToInt().coerceIn(0, fullW - 1)
        val cropTop = if (sphere) 0 else ((PI / 2 - latTop) / PI * fullH).roundToInt().coerceIn(0, fullH - 1)
        val cropW = if (sphere) fullW else ((lonMax - lonMin) / (2 * PI) * fullW).roundToInt().coerceIn(1, fullW - cropLeft)
        val cropH = if (sphere) fullH else ((latTop - latBottom) / PI * fullH).roundToInt().coerceIn(1, fullH - cropTop)

        val small = geos.map { decodePixels(it.frame, SMALL_LONG_SIDE) }
        val gains = estimateGains(geos, small)
        val seamGrid = findSeams(geos, small, gains, fullW, fullH, cropLeft, cropTop, cropW, cropH, sphere)

        val bitmap = Bitmap.createBitmap(cropW, cropH, Bitmap.Config.ARGB_8888)

        fun lonOf(px: Int) = ((cropLeft + px + 0.5) / fullW) * 2 * PI - PI
        fun latOf(py: Int) = PI / 2 - ((cropTop + py + 0.5) / fullH) * PI
        val sinLon = FloatArray(cropW) { sin(lonOf(it)).toFloat() }
        val cosLon = FloatArray(cropW) { cos(lonOf(it)).toFloat() }

        val maxStripH = min(cropH, BAND_ROWS + 2 * HALO)
        val accumLevels = Array(PYRAMID_LEVELS) { l ->
            var lw = cropW
            var lh = maxStripH
            repeat(l) {
                lw = (lw + 1) / 2
                lh = (lh + 1) / 2
            }
            PyramidLevel(lw, lh)
        }
        val expandTmpR = FloatArray(cropW * maxStripH)
        val expandTmpG = FloatArray(cropW * maxStripH)
        val expandTmpB = FloatArray(cropW * maxStripH)
        val expandTmpV = FloatArray(cropW * maxStripH)
        val expOutR = FloatArray(cropW * maxStripH)
        val expOutG = FloatArray(cropW * maxStripH)
        val expOutB = FloatArray(cropW * maxStripH)

        val threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4)
        val pool = Executors.newFixedThreadPool(threads)
        val decoded = HashMap<Int, Triple<IntArray, Int, Int>>()

        try {
            var y0 = 0
            while (y0 < cropH) {
                val emitRows = min(BAND_ROWS, cropH - y0)
                val topY = max(0, y0 - HALO)
                val botY = min(cropH - 1, y0 + emitRows - 1 + HALO)
                val stripH = botY - topY + 1
                val emitOffset = y0 - topY

                val stripTopLat = latOf(topY)
                val stripBotLat = latOf(botY)
                val needed = ArrayList<Int>()
                for ((k, g) in geos.withIndex()) {
                    if (g.lat - g.radius <= stripTopLat && g.lat + g.radius >= stripBotLat) needed.add(k)
                }
                decoded.keys.retainAll(needed.toSet())
                for (k in needed) {
                    if (!decoded.containsKey(k)) decoded[k] = decodePixels(geos[k].frame, null)
                }

                for (l in 0 until PYRAMID_LEVELS) {
                    var lh = stripH
                    repeat(l) { lh = (lh + 1) / 2 }
                    val n = accumLevels[l].w * lh
                    accumLevels[l].r.fill(0f, 0, n)
                    accumLevels[l].g.fill(0f, 0, n)
                    accumLevels[l].b.fill(0f, 0, n)
                    accumLevels[l].v.fill(0f, 0, n)
                }

                val stripOwner = IntArray(cropW * stripH) { -1 }
                val ownerTasks = ArrayList<Callable<Unit>>()
                val oChunk = (stripH + threads - 1) / threads
                var or0 = 0
                while (or0 < stripH) {
                    val rs = or0
                    val re = min(stripH, or0 + oChunk)
                    ownerTasks.add(
                        Callable {
                            for (syLocal in rs until re) {
                                val gy = topY + syLocal
                                val lat = latOf(gy)
                                val cosLat = cos(lat).toFloat()
                                val sinLat = sin(lat).toFloat()
                                val seamRow = (gy / seamGrid.step).coerceIn(0, seamGrid.h - 1) * seamGrid.w
                                val outRow = syLocal * cropW
                                for (gx in 0 until cropW) {
                                    val seamCol = (gx / seamGrid.step).coerceIn(0, seamGrid.w - 1)
                                    var k = seamGrid.owner[seamRow + seamCol]
                                    val dx = cosLat * sinLon[gx]
                                    val dy = sinLat
                                    val dz = -cosLat * cosLon[gx]
                                    if (k >= 0 && frameFeather(geos[k], dx, dy, dz) <= 0f) {
                                        k = -1
                                    }
                                    if (k < 0) {
                                        var bestF = 0f
                                        for (cand in needed) {
                                            val f = frameFeather(geos[cand], dx, dy, dz)
                                            if (f > bestF) {
                                                bestF = f
                                                k = cand
                                            }
                                        }
                                    }
                                    stripOwner[outRow + gx] = k
                                }
                            }
                        },
                    )
                    or0 = re
                }
                for (f in pool.invokeAll(ownerTasks)) f.get()

                for (k in needed) {
                    val geo = geos[k]
                    val (pixels, fw, fh) = decoded[k] ?: continue
                    val gain = gains[k]

                    val (rawMinX, rawMaxX) = frameHorizontalPixelRange(
                        geo, fullW, cropLeft, cropW, sphere,
                    )
                    val spansAll = sphere && (rawMaxX - rawMinX >= cropW - 2 * HALO - 8)
                    val startX: Int
                    val localW: Int
                    val wrapInPlace: Boolean
                    if (spansAll) {
                        startX = 0
                        localW = cropW
                        wrapInPlace = true
                    } else if (sphere) {
                        val sx = floor((rawMinX - HALO) / 8.0).toInt() * 8
                        val ex = ceil((rawMaxX + HALO + 1) / 8.0).toInt() * 8
                        val span = ex - sx
                        if (span >= cropW) {
                            startX = 0
                            localW = cropW
                            wrapInPlace = true
                        } else {
                            startX = sx
                            localW = span.coerceAtLeast(8)
                            wrapInPlace = false
                        }
                    } else {
                        val sx = (max(0, rawMinX - HALO) / 8) * 8
                        val ex = min(cropW, ((rawMaxX + HALO + 8) / 8) * 8)
                        if (ex <= sx) continue
                        startX = sx
                        localW = ex - sx
                        wrapInPlace = false
                    }

                    val imgLevels = ArrayList<PyramidLevel>(PYRAMID_LEVELS)
                    val maskLevels = ArrayList<FloatArray>(PYRAMID_LEVELS)
                    var lw = localW
                    var lh = stripH
                    for (l in 0 until PYRAMID_LEVELS) {
                        imgLevels.add(PyramidLevel(lw, lh))
                        maskLevels.add(FloatArray(lw * lh))
                        lw = (lw + 1) / 2
                        lh = (lh + 1) / 2
                    }

                    val lvl0 = imgLevels[0]
                    val mask0 = maskLevels[0]
                    val warpTasks = ArrayList<Callable<Unit>>()
                    val wChunk = (stripH + threads - 1) / threads
                    var wr0 = 0
                    while (wr0 < stripH) {
                        val rs = wr0
                        val re = min(stripH, wr0 + wChunk)
                        warpTasks.add(
                            Callable {
                                val m = geo.rows
                                val tanX = geo.tanX
                                val tanY = geo.tanY
                                val g0 = gain[0]
                                val g1 = gain[1]
                                val g2 = gain[2]
                                for (syLocal in rs until re) {
                                    val gy = topY + syLocal
                                    val lat = latOf(gy)
                                    val cosLat = cos(lat).toFloat()
                                    val sinLat = sin(lat).toFloat()
                                    val rowOff = syLocal * localW
                                    val stripRow = syLocal * cropW
                                    for (lx in 0 until localW) {
                                        val gxRaw = startX + lx
                                        val gx = if (sphere) ((gxRaw % cropW) + cropW) % cropW else gxRaw
                                        if (gx < 0 || gx >= cropW) continue
                                        val idx = rowOff + lx
                                        val dx = cosLat * sinLon[gx]
                                        val dy = sinLat
                                        val dz = -cosLat * cosLon[gx]
                                        if (dx * geo.fx + dy * geo.fy + dz * geo.fz < geo.cosRadius) continue
                                        val vz = m[2] * dx + m[5] * dy + m[8] * dz
                                        if (vz > -1e-4f) continue
                                        val inv = -1f / vz
                                        val nx = (m[0] * dx + m[3] * dy + m[6] * dz) * inv / tanX
                                        val ny = (m[1] * dx + m[4] * dy + m[7] * dz) * inv / tanY
                                        if (abs(nx) >= 1f || abs(ny) >= 1f) continue

                                        val fxImg = ((nx * 0.5f + 0.5f) * fw - 0.5f).coerceIn(0f, (fw - 1).toFloat())
                                        val fyImg = ((0.5f - ny * 0.5f) * fh - 0.5f).coerceIn(0f, (fh - 1).toFloat())
                                        val x0i = fxImg.toInt()
                                        val y0i = fyImg.toInt()
                                        val x1i = min(x0i + 1, fw - 1)
                                        val y1i = min(y0i + 1, fh - 1)
                                        val fx = fxImg - x0i
                                        val fy = fyImg - y0i
                                        val p00 = pixels[y0i * fw + x0i]
                                        val p10 = pixels[y0i * fw + x1i]
                                        val p01 = pixels[y1i * fw + x0i]
                                        val p11 = pixels[y1i * fw + x1i]
                                        val w00 = (1f - fx) * (1f - fy)
                                        val w10 = fx * (1f - fy)
                                        val w01 = (1f - fx) * fy
                                        val w11 = fx * fy

                                        val cr = ((p00 shr 16) and 0xFF) * w00 + ((p10 shr 16) and 0xFF) * w10 +
                                            ((p01 shr 16) and 0xFF) * w01 + ((p11 shr 16) and 0xFF) * w11
                                        val cg = ((p00 shr 8) and 0xFF) * w00 + ((p10 shr 8) and 0xFF) * w10 +
                                            ((p01 shr 8) and 0xFF) * w01 + ((p11 shr 8) and 0xFF) * w11
                                        val cb = (p00 and 0xFF) * w00 + (p10 and 0xFF) * w10 +
                                            (p01 and 0xFF) * w01 + (p11 and 0xFF) * w11

                                        lvl0.r[idx] = cr * g0
                                        lvl0.g[idx] = cg * g1
                                        lvl0.b[idx] = cb * g2
                                        lvl0.v[idx] = 1f
                                        if (stripOwner[stripRow + gx] == k) {
                                            mask0[idx] = 1f
                                        }
                                    }
                                }
                            },
                        )
                        wr0 = re
                    }
                    for (f in pool.invokeAll(warpTasks)) f.get()

                    for (l in 0 until PYRAMID_LEVELS - 1) {
                        val cur = imgLevels[l]
                        val nxt = imgLevels[l + 1]
                        downsampleMasked(cur, nxt, wrapInPlace, expandTmpR, expandTmpG, expandTmpB, expandTmpV)
                        downsampleMask(
                            maskLevels[l], cur.w, cur.h,
                            maskLevels[l + 1], nxt.w, nxt.h,
                            wrapInPlace, expandTmpR,
                        )
                    }

                    for (l in 0 until PYRAMID_LEVELS) {
                        val cur = imgLevels[l]
                        val msk = maskLevels[l]
                        val acc = accumLevels[l]
                        if (l < PYRAMID_LEVELS - 1) {
                            expandMasked(
                                imgLevels[l + 1], cur.w, cur.h, wrapInPlace,
                                expOutR, expOutG, expOutB,
                                expandTmpR, expandTmpG, expandTmpB, expandTmpV,
                            )
                        }
                        val shiftStartX = startX shr l
                        for (ly in 0 until cur.h) {
                            val lRow = ly * cur.w
                            val aRow = ly * acc.w
                            for (lx in 0 until cur.w) {
                                val lIdx = lRow + lx
                                val wt = msk[lIdx] * cur.v[lIdx]
                                if (wt <= 1e-6f) continue
                                val gxRaw = shiftStartX + lx
                                val gx = if (sphere) ((gxRaw % acc.w) + acc.w) % acc.w else gxRaw
                                if (gx < 0 || gx >= acc.w) continue
                                val aIdx = aRow + gx
                                if (l < PYRAMID_LEVELS - 1) {
                                    acc.r[aIdx] += (cur.r[lIdx] - expOutR[lIdx]) * wt
                                    acc.g[aIdx] += (cur.g[lIdx] - expOutG[lIdx]) * wt
                                    acc.b[aIdx] += (cur.b[lIdx] - expOutB[lIdx]) * wt
                                } else {
                                    acc.r[aIdx] += cur.r[lIdx] * wt
                                    acc.g[aIdx] += cur.g[lIdx] * wt
                                    acc.b[aIdx] += cur.b[lIdx] * wt
                                }
                                acc.v[aIdx] += wt
                            }
                        }
                    }
                }

                for (l in 0 until PYRAMID_LEVELS) {
                    val acc = accumLevels[l]
                    var lh = stripH
                    repeat(l) { lh = (lh + 1) / 2 }
                    val n = acc.w * lh
                    for (idx in 0 until n) {
                        val w = acc.v[idx]
                        if (w > 1e-6f) {
                            val inv = 1f / w
                            acc.r[idx] *= inv
                            acc.g[idx] *= inv
                            acc.b[idx] *= inv
                            acc.v[idx] = 1f
                        } else {
                            acc.r[idx] = 0f
                            acc.g[idx] = 0f
                            acc.b[idx] = 0f
                            acc.v[idx] = 0f
                        }
                    }
                }

                for (l in PYRAMID_LEVELS - 2 downTo 0) {
                    val coarse = accumLevels[l + 1]
                    val fine = accumLevels[l]
                    var fineH = stripH
                    var coarseH = stripH
                    repeat(l) { fineH = (fineH + 1) / 2 }
                    repeat(l + 1) { coarseH = (coarseH + 1) / 2 }
                    val coarseLevel = PyramidLevel(coarse.w, coarseH)
                    val copyN = coarse.w * coarseH
                    System.arraycopy(coarse.r, 0, coarseLevel.r, 0, copyN)
                    System.arraycopy(coarse.g, 0, coarseLevel.g, 0, copyN)
                    System.arraycopy(coarse.b, 0, coarseLevel.b, 0, copyN)
                    System.arraycopy(coarse.v, 0, coarseLevel.v, 0, copyN)

                    expandMasked(
                        coarseLevel, fine.w, fineH, sphere,
                        expOutR, expOutG, expOutB,
                        expandTmpR, expandTmpG, expandTmpB, expandTmpV,
                    )
                    val fineN = fine.w * fineH
                    for (idx in 0 until fineN) {
                        if (fine.v[idx] > 0f) {
                            fine.r[idx] += expOutR[idx]
                            fine.g[idx] += expOutG[idx]
                            fine.b[idx] += expOutB[idx]
                        }
                    }
                }

                val outLvl = accumLevels[0]
                val band = IntArray(cropW * emitRows)
                for (row in 0 until emitRows) {
                    val srcRow = (emitOffset + row) * cropW
                    val dstRow = row * cropW
                    for (x in 0 until cropW) {
                        val idx = srcRow + x
                        if (outLvl.v[idx] <= 0f) {
                            band[dstRow + x] = 0xFF000000.toInt()
                        } else {
                            val ri = outLvl.r[idx].roundToInt().coerceIn(0, 255)
                            val gi = outLvl.g[idx].roundToInt().coerceIn(0, 255)
                            val bi = outLvl.b[idx].roundToInt().coerceIn(0, 255)
                            band[dstRow + x] = (0xFF shl 24) or (ri shl 16) or (gi shl 8) or bi
                        }
                    }
                }
                bitmap.setPixels(band, 0, cropW, 0, y0, cropW, emitRows)
                y0 += emitRows
            }
        } finally {
            pool.shutdownNow()
        }

        val jpegOut = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 92, jpegOut)
        val xmp = PanoramaXmp.build(fullW, fullH, cropW, cropH, cropLeft, cropTop)
        val jpeg = PanoramaXmp.inject(jpegOut.toByteArray(), xmp)

        val thumbW = 480
        val thumbH = (cropH * (thumbW.toFloat() / cropW)).roundToInt().coerceAtLeast(1)
        val thumb = Bitmap.createScaledBitmap(bitmap, thumbW, thumbH, true)
        val thumbOut = ByteArrayOutputStream()
        thumb.compress(Bitmap.CompressFormat.JPEG, 75, thumbOut)
        if (thumb !== bitmap) thumb.recycle()
        bitmap.recycle()

        VeLog.d(TAG) { "stitch: frames=${frames.size} sphere=$sphere out=${cropW}x$cropH ms=${System.currentTimeMillis() - tStart}" }
        return StitchResult(jpeg, thumbOut.toByteArray(), cropW, cropH)
    }
}