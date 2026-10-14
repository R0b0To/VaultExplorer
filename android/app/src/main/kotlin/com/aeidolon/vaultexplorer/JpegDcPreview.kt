package com.aeidolon.vaultexplorer

import java.io.InputStream

/**
 * Low-memory preview of a progressive JPEG, decoded from its first scan only.
 *
 * A normal decode of a progressive JPEG has to hold every DCT coefficient of
 * the whole image (6 bytes per pixel for 4:4:4), so a very large one -- an
 * 857 megapixel photo needs ~5 GB -- cannot be decoded at all on a phone, even
 * when only a small preview is wanted. But the first scan of a progressive
 * file carries the DC coefficient of every 8x8 block, and a block's DC
 * coefficient is exactly its average colour. Decoding just that scan yields
 * the image at 1/8 scale (an 857 MP photo becomes ~13 MP) from a small
 * fraction of the file, with memory proportional to the *output*.
 *
 * The decoder is streaming: each MCU row is converted to RGB and folded into
 * a box-filtered result as soon as it is decoded, so the 1/8-scale image is
 * never held whole either. The result is at least [decode]'s `targetSize` on
 * its longer side whenever the source is big enough (it is never upscaled).
 *
 * Supported: progressive (SOF2) 8-bit JPEG, 1 or 3 components, any chroma
 * subsampling, restart intervals, whose first scan is an interleaved DC scan
 * over all components (what libjpeg, mozjpeg and Pillow all write). Anything
 * else returns null and the caller falls back to refusing the image.
 */
object JpegDcPreview {
    class Preview(val argb: IntArray, val width: Int, val height: Int)

    private class Component(val id: Int, val h: Int, val v: Int, val quantId: Int)

    /** Canonical Huffman table with a 16-bit lookup of (length shl 8) or symbol. */
    private class Huffman(counts: IntArray, symbols: IntArray) {
        val lookup = ShortArray(1 shl 16)

        init {
            var code = 0
            var k = 0
            for (length in 1..16) {
                repeat(counts[length - 1]) {
                    if (k >= symbols.size || code >= (1 shl length)) throw FormatException("bad DHT")
                    val first = code shl (16 - length)
                    val last = (code + 1) shl (16 - length)
                    val entry = ((length shl 8) or symbols[k]).toShort()
                    for (i in first until last) lookup[i] = entry
                    code++
                    k++
                }
                code = code shl 1
            }
        }
    }

    private class FormatException(message: String) : Exception(message)

    private class Source(private val stream: InputStream) {
        private val buffer = ByteArray(64 * 1024)
        private var pos = 0
        private var limit = 0

        fun read(): Int {
            if (pos >= limit) {
                limit = stream.read(buffer, 0, buffer.size)
                pos = 0
                if (limit <= 0) {
                    limit = 0
                    return -1
                }
            }
            return buffer[pos++].toInt() and 0xFF
        }

        fun readFully(n: Int): ByteArray {
            val out = ByteArray(n)
            for (i in 0 until n) {
                val b = read()
                if (b < 0) throw FormatException("truncated segment")
                out[i] = b.toByte()
            }
            return out
        }
    }

    /** Entropy-coded-data bit reader: handles 0xFF00 stuffing and stops at markers. */
    private class Bits(private val src: Source) {
        private var acc = 0
        private var count = 0
        // Zero bits appended after the data ran out (marker / EOF). The
        // lookahead in [decode] routinely reads past the last real bit, so
        // "a marker was seen" doesn't mean the scan is short -- only
        // actually consuming these padding bits does.
        private var padBits = 0
        var marker = 0
            private set

        private fun fill() {
            if (marker != 0) {
                acc = acc shl 8
                count += 8
                padBits += 8
                return
            }
            val b = src.read()
            if (b < 0) {
                marker = 0xD9
                acc = acc shl 8
                count += 8
                padBits += 8
                return
            }
            if (b == 0xFF) {
                var b2 = src.read()
                while (b2 == 0xFF) b2 = src.read() // fill bytes
                if (b2 != 0) {
                    marker = if (b2 < 0) 0xD9 else b2
                    acc = acc shl 8
                    count += 8
                    padBits += 8
                    return
                }
                // 0xFF00: a literal 0xFF data byte
            }
            acc = (acc shl 8) or b
            count += 8
        }

        fun receive(n: Int): Int {
            if (n == 0) return 0
            while (count < n) fill()
            val v = (acc shr (count - n)) and ((1 shl n) - 1)
            count -= n
            acc = acc and ((1 shl count) - 1)
            return v
        }

        fun decode(table: Huffman): Int {
            while (count < 16) fill()
            val entry = table.lookup[(acc shr (count - 16)) and 0xFFFF].toInt() and 0xFFFF
            val length = entry shr 8
            if (length == 0) throw FormatException("bad Huffman code")
            count -= length
            acc = acc and ((1 shl count) - 1)
            return entry and 0xFF
        }

        /** True if decoding has consumed bits that were not in the file. */
        fun overran(): Boolean = count < padBits

        /** Skips to and consumes the RSTn marker that follows a restart interval. */
        fun restart() {
            acc = 0
            count = 0
            padBits = 0
            if (marker == 0) {
                // Padding bits already consumed with the last byte; scan to the marker.
                var b = src.read()
                while (b >= 0) {
                    if (b == 0xFF) {
                        var b2 = src.read()
                        while (b2 == 0xFF) b2 = src.read()
                        if (b2 != 0) {
                            marker = if (b2 < 0) 0xD9 else b2
                            break
                        }
                    }
                    b = src.read()
                }
            }
            if (marker in 0xD0..0xD7) marker = 0 else throw FormatException("missing restart marker")
        }
    }

    /**
     * Decodes [stream] (positioned at the file's first byte) to an ARGB
     * preview, or returns null if it isn't a progressive JPEG this decoder
     * handles. [targetSize] is the longer edge the caller ultimately wants;
     * the result is the 1/8-scale image box-filtered down while it stays at
     * least that big.
     */
    fun decode(stream: InputStream, targetSize: Int): Preview? = try {
        decodeInternal(Source(stream), targetSize.coerceAtLeast(1))
    } catch (e: FormatException) {
        null
    } catch (e: java.io.IOException) {
        null
    } catch (e: IndexOutOfBoundsException) {
        null // malformed tables / segment lengths
    }

    private fun decodeInternal(src: Source, targetSize: Int): Preview? {
        if (src.read() != 0xFF || src.read() != 0xD8) return null

        val quantDc = IntArray(4) // DC quantiser (first value) per table id
        val huffDc = arrayOfNulls<Huffman>(4)
        var restartInterval = 0
        var adobeTransform = -1
        var width = 0
        var height = 0
        var components: Array<Component>? = null
        var scanComponents: IntArray? = null // component indices in scan order
        var scanTables: IntArray? = null
        var pointTransform = 0

        segments@ while (true) {
            var b = src.read()
            while (b != 0xFF) {
                if (b < 0) return null
                b = src.read()
            }
            var marker = src.read()
            while (marker == 0xFF) marker = src.read()
            if (marker < 0) return null
            if (marker == 0 || marker == 0xD8 || marker == 0x01 || marker in 0xD0..0xD7) continue

            val length = (src.read() shl 8) or src.read()
            if (length < 2) return null
            val seg = src.readFully(length - 2)

            when (marker) {
                0xDB -> { // DQT
                    var j = 0
                    while (j < seg.size) {
                        val precision = (seg[j].toInt() and 0xFF) shr 4
                        val id = seg[j].toInt() and 0x0F
                        j++
                        if (id > 3) return null
                        if (precision == 0) {
                            if (j + 64 > seg.size) return null
                            quantDc[id] = seg[j].toInt() and 0xFF
                            j += 64
                        } else {
                            if (j + 128 > seg.size) return null
                            quantDc[id] = ((seg[j].toInt() and 0xFF) shl 8) or (seg[j + 1].toInt() and 0xFF)
                            j += 128
                        }
                    }
                }
                0xC4 -> { // DHT
                    var j = 0
                    while (j < seg.size) {
                        if (j + 17 > seg.size) return null
                        val tableClass = (seg[j].toInt() and 0xFF) shr 4
                        val id = seg[j].toInt() and 0x0F
                        j++
                        val counts = IntArray(16) { seg[j + it].toInt() and 0xFF }
                        j += 16
                        val total = counts.sum()
                        if (j + total > seg.size) return null
                        val symbols = IntArray(total) { seg[j + it].toInt() and 0xFF }
                        j += total
                        if (tableClass == 0 && id <= 3) huffDc[id] = Huffman(counts, symbols)
                    }
                }
                0xDD -> { // DRI
                    if (seg.size < 2) return null
                    restartInterval = ((seg[0].toInt() and 0xFF) shl 8) or (seg[1].toInt() and 0xFF)
                }
                0xEE -> { // APP14 Adobe
                    if (seg.size >= 12 && seg[0].toInt() == 0x41 && seg[1].toInt() == 0x64) { // "Ad"obe
                        adobeTransform = seg[11].toInt() and 0xFF
                    }
                }
                0xC2 -> { // SOF2: progressive, Huffman
                    if (seg.size < 6 || seg[0].toInt() != 8) return null
                    height = ((seg[1].toInt() and 0xFF) shl 8) or (seg[2].toInt() and 0xFF)
                    width = ((seg[3].toInt() and 0xFF) shl 8) or (seg[4].toInt() and 0xFF)
                    val count = seg[5].toInt() and 0xFF
                    if ((count != 1 && count != 3) || seg.size < 6 + 3 * count) return null
                    components = Array(count) { c ->
                        val hv = seg[7 + 3 * c].toInt() and 0xFF
                        Component(
                            id = seg[6 + 3 * c].toInt() and 0xFF,
                            h = hv shr 4,
                            v = hv and 0x0F,
                            quantId = seg[8 + 3 * c].toInt() and 0xFF,
                        )
                    }
                }
                0xC0, 0xC1, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF -> return null
                0xDA -> { // SOS: the first scan is the one we decode
                    val frame = components ?: return null
                    if (seg.isEmpty()) return null
                    val ns = seg[0].toInt() and 0xFF
                    if (ns != frame.size || seg.size < 4 + 2 * ns) return null
                    val order = IntArray(ns)
                    val tables = IntArray(ns)
                    for (c in 0 until ns) {
                        val id = seg[1 + 2 * c].toInt() and 0xFF
                        val index = frame.indexOfFirst { it.id == id }
                        if (index < 0) return null
                        order[c] = index
                        tables[c] = (seg[2 + 2 * c].toInt() and 0xFF) shr 4
                        if (tables[c] > 3) return null
                    }
                    val ss = seg[1 + 2 * ns].toInt() and 0xFF
                    val se = seg[2 + 2 * ns].toInt() and 0xFF
                    val approx = seg[3 + 2 * ns].toInt() and 0xFF
                    // Only a first (Ah = 0) DC scan over every component.
                    if (ss != 0 || se != 0 || (approx shr 4) != 0) return null
                    pointTransform = approx and 0x0F
                    scanComponents = order
                    scanTables = tables
                    break@segments
                }
            }
        }

        val frame = components ?: return null
        val order = scanComponents ?: return null
        val tables = scanTables ?: return null
        if (width <= 0 || height <= 0) return null
        for (c in frame) if (c.h !in 1..4 || c.v !in 1..4 || c.quantId > 3) return null
        val dcTables = ArrayList<Huffman>(order.size)
        for (n in order.indices) dcTables.add(huffDc[tables[n]] ?: return null)

        val hMax = frame.maxOf { it.h }
        val vMax = frame.maxOf { it.v }
        val mcuCols = (width + 8 * hMax - 1) / (8 * hMax)
        val mcuRows = (height + 8 * vMax - 1) / (8 * vMax)
        val w8 = (width + 7) / 8
        val h8 = (height + 7) / 8

        // Integer box factor: keep the result at least targetSize on its long side.
        val k = maxOf(1, maxOf(w8, h8) / targetSize)
        val outW = (w8 + k - 1) / k
        val outH = (h8 + k - 1) / k
        val sumR = IntArray(outW * outH)
        val sumG = IntArray(outW * outH)
        val sumB = IntArray(outW * outH)

        val bits = Bits(src)
        val pred = IntArray(frame.size)
        val samples = Array(frame.size) { IntArray(frame[it].h * frame[it].v) }
        val isYcc = frame.size == 3 && adobeTransform != 0
        val vals = IntArray(3)

        var mcuIndex = 0
        for (my in 0 until mcuRows) {
            for (mx in 0 until mcuCols) {
                if (restartInterval > 0 && mcuIndex > 0 && mcuIndex % restartInterval == 0) {
                    bits.restart()
                    pred.fill(0)
                }
                mcuIndex++

                for (n in order.indices) {
                    val ci = order[n]
                    val comp = frame[ci]
                    val q = quantDc[comp.quantId]
                    for (blk in 0 until comp.h * comp.v) {
                        val t = bits.decode(dcTables[n])
                        if (t > 16) throw FormatException("bad DC category")
                        var diff = 0
                        if (t > 0) {
                            diff = bits.receive(t)
                            if (diff < (1 shl (t - 1))) diff += (-1 shl t) + 1
                        }
                        pred[ci] += diff
                        // IDCT of a DC-only block: every sample is DC / 8, level-shifted.
                        samples[ci][blk] = (((pred[ci] shl pointTransform) * q + 4) shr 3) + 128
                    }
                }
                if (bits.overran()) return null // scan ended before every MCU was decoded

                for (py in 0 until vMax) {
                    val y8 = my * vMax + py
                    if (y8 >= h8) break
                    for (px in 0 until hMax) {
                        val x8 = mx * hMax + px
                        if (x8 >= w8) break
                        for (ci in frame.indices) {
                            val comp = frame[ci]
                            vals[ci] = samples[ci][(py * comp.v / vMax) * comp.h + (px * comp.h / hMax)]
                        }
                        var r: Int
                        var g: Int
                        var b: Int
                        if (frame.size == 1) {
                            r = vals[0]; g = r; b = r
                        } else if (isYcc) {
                            val cb = vals[1] - 128
                            val cr = vals[2] - 128
                            r = vals[0] + ((91881 * cr) shr 16)
                            g = vals[0] - ((22554 * cb + 46802 * cr) shr 16)
                            b = vals[0] + ((116130 * cb) shr 16)
                        } else {
                            r = vals[0]; g = vals[1]; b = vals[2]
                        }
                        val o = (y8 / k) * outW + (x8 / k)
                        sumR[o] += r.coerceIn(0, 255)
                        sumG[o] += g.coerceIn(0, 255)
                        sumB[o] += b.coerceIn(0, 255)
                    }
                }
            }
        }

        val argb = IntArray(outW * outH)
        for (oy in 0 until outH) {
            val rows = minOf(k, h8 - oy * k)
            for (ox in 0 until outW) {
                val n = rows * minOf(k, w8 - ox * k)
                val o = oy * outW + ox
                argb[o] = (0xFF shl 24) or
                    ((sumR[o] / n) shl 16) or
                    ((sumG[o] / n) shl 8) or
                    (sumB[o] / n)
            }
        }
        return Preview(argb, outW, outH)
    }
}
