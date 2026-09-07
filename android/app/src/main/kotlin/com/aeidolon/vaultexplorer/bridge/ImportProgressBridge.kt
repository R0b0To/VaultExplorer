package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import com.aeidolon.vaultexplorer.FilesystemNameValidator

object ImportProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private val lastReportTimes = java.util.concurrent.ConcurrentHashMap<Int, Long>()

    /** Which opIds currently belong to a tracked import. */
    private val trackedIds = java.util.concurrent.ConcurrentHashMap.newKeySet<Int>()

    @JvmStatic
    fun begin(opId: Int) {
        if (opId > 0) trackedIds.add(opId)
    }

    @JvmStatic
    fun isTracking(opId: Int): Boolean = trackedIds.contains(opId)

    private data class LastContext(
        val done: Int,
        val total: Int,
        val currentName: String,
        val totalBytes: Long,
    )
    private val lastContext = java.util.concurrent.ConcurrentHashMap<Int, LastContext>()

    private val chunkBaseline = java.util.concurrent.ConcurrentHashMap<Int, Long>()
    private val chunkAccumulated = java.util.concurrent.ConcurrentHashMap<Int, java.util.concurrent.atomic.AtomicLong>()

    @JvmStatic
    fun reportProgress(
        opId: Int,
        done: Int,
        total: Int,
        currentName: String,
        transferredBytes: Long = 0L,
        totalBytes: Long = 0L,
    ) {
        lastContext[opId] = LastContext(done, total, currentName, totalBytes)

        val ch = channel ?: return
        val now = System.currentTimeMillis()
        val isTerminal = (done == total && total > 0) || (totalBytes > 0L && transferredBytes >= totalBytes)
        val lastTime = lastReportTimes[opId] ?: 0L

        if (!isTerminal && (now - lastTime < 50)) {
            return
        }
        lastReportTimes[opId] = now

        mainHandler.post {
            ch.invokeMethod(
                "onImportProgress",
                mapOf(
                    "opId" to opId,
                    "done" to done,
                    "total" to total,
                    "currentName" to currentName,
                    "transferredBytes" to transferredBytes,
                    "totalBytes" to totalBytes,
                ),
            )
        }
    }

    @JvmStatic
    fun beginFileChunks(opId: Int, baselineTransferredBytes: Long) {
        chunkBaseline[opId] = baselineTransferredBytes
        chunkAccumulated[opId] = java.util.concurrent.atomic.AtomicLong(0)
    }

    @JvmStatic
    fun reportChunk(opId: Int, bytesDelta: Long) {
        if (bytesDelta <= 0) return
        val ctx = lastContext[opId] ?: return
        val accumulated = chunkAccumulated[opId]?.addAndGet(bytesDelta) ?: return
        val baseline = chunkBaseline[opId] ?: 0L
        reportProgress(opId, ctx.done, ctx.total, ctx.currentName, baseline + accumulated, ctx.totalBytes)
    }

    @JvmStatic
    fun clear(opId: Int) {
        trackedIds.remove(opId)
        lastReportTimes.remove(opId)
        lastContext.remove(opId)
        chunkBaseline.remove(opId)
        chunkAccumulated.remove(opId)
    }

    @JvmStatic
    fun reportSkippedInvalidName(opId: Int, name: String, reasons: List<String>) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onImportItemSkipped",
                mapOf(
                    "opId" to opId,
                    "name" to name,
                    "reason" to reasons.joinToString("; "),
                ),
            )
        }
    }

    @JvmStatic
    fun reportItemFinished(
        opId: Int,
        sourceName: String,
        resolvedName: String,
        isDir: Boolean,
        success: Boolean,
    ) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onImportItemFinished",
                mapOf(
                    "opId" to opId,
                    "sourceName" to sourceName,
                    "resolvedName" to resolvedName,
                    "isDir" to isDir,
                    "success" to success,
                ),
            )
        }
    }
}