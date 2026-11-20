package com.aeidolon.vaultexplorer

import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * Lightweight timing aggregation for the native side of the app, the
 * counterpart of Dart's `PerfTrace` (lib/core/utils/perf_trace.dart).
 *
 * Active only while [VeLog.enabled] is true -- the same "Debug logging"
 * setting that drives all other logging, so one switch turns on both the Dart
 * and the Kotlin measurements. When it is off, [begin] returns 0 and every
 * other call returns immediately.
 *
 * ```
 * val t0 = PerfLog.begin()
 * doWork()
 * PerfLog.end("thumb.img.decode", t0)
 * ```
 *
 * Samples are aggregated per name (count / total / max) and a summary is
 * written to logcat under the tag `VE_PERF` roughly every [FLUSH_INTERVAL_MS]
 * -- piggybacked on whichever thread records next, so there is no timer or
 * extra thread. Rows are sorted by total time so the biggest cost is first.
 */
object PerfLog {
    private const val TAG = "VE_PERF"
    private const val FLUSH_INTERVAL_MS = 10_000L
    private const val MAX_ROWS = 40

    private class Stat {
        val count = AtomicLong()
        val totalUs = AtomicLong()
        val maxUs = AtomicLong()
    }

    private val stats = ConcurrentHashMap<String, Stat>()
    private val windowStartMs = AtomicLong(System.currentTimeMillis())

    /** Returns a start token, or 0 when tracing is off. */
    fun begin(): Long = if (VeLog.enabled) System.nanoTime() or 1L else 0L

    /** Records the time since [startToken] under [name]; a no-op for token 0. */
    fun end(name: String, startToken: Long) {
        if (startToken == 0L) return
        record(name, (System.nanoTime() - startToken) / 1_000L)
    }

    /** Adds one sample of [micros] microseconds under [name]. */
    fun record(name: String, micros: Long) {
        if (!VeLog.enabled) return
        val stat = stats.getOrPut(name) { Stat() }
        stat.count.incrementAndGet()
        stat.totalUs.addAndGet(micros)
        var seen = stat.maxUs.get()
        while (micros > seen && !stat.maxUs.compareAndSet(seen, micros)) {
            seen = stat.maxUs.get()
        }
        maybeFlush()
    }

    private fun maybeFlush() {
        val now = System.currentTimeMillis()
        val start = windowStartMs.get()
        if (now - start < FLUSH_INTERVAL_MS) return
        // Exactly one thread wins the right to print this window.
        if (!windowStartMs.compareAndSet(start, now)) return

        val rows = ArrayList<Pair<String, LongArray>>(stats.size)
        for ((name, stat) in stats) {
            val count = stat.count.getAndSet(0)
            if (count == 0L) continue
            rows.add(name to longArrayOf(count, stat.totalUs.getAndSet(0), stat.maxUs.getAndSet(0)))
        }
        if (rows.isEmpty()) return
        rows.sortByDescending { it.second[1] }

        val windowSeconds = (now - start) / 1000.0
        VeLog.i(TAG) { "[native] -- window ${"%.1f".format(Locale.ROOT, windowSeconds)}s --" }
        for ((name, v) in rows.take(MAX_ROWS)) {
            val count = v[0]
            val total = v[1]
            val max = v[2]
            VeLog.i(TAG) {
                "[native] ${name.padEnd(28)} n=$count total=${fmt(total)} avg=${fmt(total / count)} max=${fmt(max)}"
            }
        }
    }

    private fun fmt(us: Long): String = when {
        us >= 1_000_000L -> "%.2fs".format(Locale.ROOT, us / 1_000_000.0)
        us >= 10_000L -> "${us / 1_000L}ms"
        us >= 1_000L -> "%.1fms".format(Locale.ROOT, us / 1_000.0)
        else -> "${us}us"
    }
}
