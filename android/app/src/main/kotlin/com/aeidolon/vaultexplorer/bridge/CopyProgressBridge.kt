package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * Pushes per-chunk copy/move byte progress from the native `copyFile` JNI
 * entry point (see reportCopyProgress in jni_callbacks.h) to Dart, mirroring
 * [ImportProgressBridge] / [SplitJoinProgressBridge]. Kept as its own event
 * (`"onCopyProgress"`) for the same reason [SplitJoinProgressBridge] is its
 * own: this carries only a byte delta, a different shape from either of
 * those, and belongs to the [FileOperation][com.aeidolon.vaultexplorer]
 * opId space (one native `copyFile` call per item, up to 4 items copying
 * concurrently under the same opId via `_CopySemaphore` on the Dart side).
 *
 * Each native chunk callback (one per 2 MB buffer iteration) reports a
 * *delta*, not a running total -- matches how `FileOperation._addTransferredBytes`
 * already accumulates for the old Dart-side chunked-copy fallback, so Dart
 * doesn't need per-file cursor bookkeeping to turn this into that.
 *
 * At native speed a single file can produce hundreds of these deltas per
 * second (and up to 4 files concurrently share one opId), so raw deltas are
 * accumulated here and flushed to the MethodChannel at most every
 * [FLUSH_INTERVAL_MS] -- posting every single chunk straight to Dart would
 * flood the platform channel for no visible UI benefit. [flushPending] must
 * be called once a file's native `copyFile` call returns (success or not)
 * so whatever's left in the accumulator when the call finishes -- up to one
 * flush interval's worth -- isn't lost.
 */
object CopyProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private const val FLUSH_INTERVAL_MS = 50L

    private val pendingBytes = ConcurrentHashMap<Int, AtomicLong>()
    private val lastFlushTimes = ConcurrentHashMap<Int, Long>()

    @JvmStatic
    fun reportProgress(opId: Int, bytesDelta: Long) {
        if (opId <= 0 || bytesDelta <= 0) return
        pendingBytes.getOrPut(opId) { AtomicLong(0) }.addAndGet(bytesDelta)
        maybeFlush(opId)
    }

    /**
     * Called from [FileOperationHandlers.handleCopyFile][com.aeidolon.vaultexplorer.handlers.FileOperationHandlers]
     * after each native `copyFile` call returns, so the tail of the file --
     * whatever hasn't hit a [FLUSH_INTERVAL_MS] flush yet -- still reaches
     * Dart instead of silently falling short of the file's total size.
     */
    @JvmStatic
    fun flushPending(opId: Int) {
        val remaining = pendingBytes[opId]?.getAndSet(0) ?: return
        if (remaining > 0) post(opId, remaining)
        // One file's tail flushed -- don't leak the entry across the
        // possibly-many other items still copying under this same opId.
        lastFlushTimes.remove(opId)
    }

    /** Drops all accumulator state for a finished/cancelled operation. */
    @JvmStatic
    fun clear(opId: Int) {
        pendingBytes.remove(opId)
        lastFlushTimes.remove(opId)
    }

    private fun maybeFlush(opId: Int) {
        val now = System.currentTimeMillis()
        val lastFlush = lastFlushTimes[opId] ?: 0L
        if (now - lastFlush < FLUSH_INTERVAL_MS) return
        lastFlushTimes[opId] = now
        val amount = pendingBytes[opId]?.getAndSet(0) ?: return
        if (amount > 0) post(opId, amount)
    }

    private fun post(opId: Int, bytesDelta: Long) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onCopyProgress",
                mapOf(
                    "opId" to opId,
                    "bytesDelta" to bytesDelta,
                ),
            )
        }
    }
}
