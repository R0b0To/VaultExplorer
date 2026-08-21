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

    /** Cached from the most recent explicit reportProgress() call for this
     *  opId, so reportChunk() below -- fired from native mid-file, with
     *  only a byte delta to go on -- can still emit a full progress event. */
    private data class LastContext(
        val done: Int,
        val total: Int,
        val currentName: String,
        val totalBytes: Long,
    )
    private val lastContext = java.util.concurrent.ConcurrentHashMap<Int, LastContext>()

    /** Bytes transferred across every entry in this import *before* the
     *  file currently being written by a raw-path writeBackFile call --
     *  see beginFileChunks(). */
    private val chunkBaseline = java.util.concurrent.ConcurrentHashMap<Int, Long>()

    /** Bytes reported so far for the file currently being written -- see
     *  beginFileChunks() and reportChunk(). */
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

    /**
     * Called once, from Kotlin, right before a raw-file import starts the
     * single blocking native writeBackFile call for one entry -- see
     * importEntryRecursiveRaw. Establishes the byte baseline (bytes
     * transferred across every *previous* entry in this import) that
     * reportChunk() below layers each chunk's delta on top of. Callers
     * should already have called reportProgress() for this file's
     * done/total/currentName beforehand so reportChunk() has a
     * [LastContext] to reuse.
     */
    @JvmStatic
    fun beginFileChunks(opId: Int, baselineTransferredBytes: Long) {
        chunkBaseline[opId] = baselineTransferredBytes
        chunkAccumulated[opId] = java.util.concurrent.atomic.AtomicLong(0)
    }

    /**
     * Fired from native per 2 MB buffer chunk during a single writeBackFile
     * call (see reportImportChunkProgress in jni_callbacks.h) -- the
     * "spinning circle" fix for raw-path imports of large files, where
     * writeBackFile previously ran as one uninterrupted blocking call with
     * no signal until the whole file finished.
     *
     * Reuses whatever done/total/currentName/totalBytes context the most
     * recent reportProgress() call cached (see beginFileChunks' doc) and
     * adds bytesDelta on top of the baseline captured there, then just
     * calls reportProgress() again -- reusing its exact throttle/
     * terminal-flush logic rather than duplicating it here. This is purely
     * a UI-smoothing overlay: importEntryRecursiveRaw's own post-completion
     * reportProgress() call, driven by its authoritative transferredCounter
     * (not this scratch accumulator), is still what finalizes the true
     * total once the file completes -- so any drift here self-corrects.
     */
    @JvmStatic
    fun reportChunk(opId: Int, bytesDelta: Long) {
        if (bytesDelta <= 0) return
        val ctx = lastContext[opId] ?: return
        val accumulated = chunkAccumulated[opId]?.addAndGet(bytesDelta) ?: return
        val baseline = chunkBaseline[opId] ?: 0L
        reportProgress(opId, ctx.done, ctx.total, ctx.currentName, baseline + accumulated, ctx.totalBytes)
    }

    /** Drops all state for a finished/cancelled import -- see the `finally`
     *  blocks in ImportExportHandlers.kt, alongside ImportCancellation.clear(). */
    @JvmStatic
    fun clear(opId: Int) {
        lastReportTimes.remove(opId)
        lastContext.remove(opId)
        chunkBaseline.remove(opId)
        chunkAccumulated.remove(opId)
    }

    /**
     * Fired once per source entry whose name failed
     * [FilesystemNameValidator] validation for the destination container.
     * The entry is not written and its name is never mutated to "fix" it
     * (see docs/architecture.md ADR-002) -- this is the only record that it
     * was skipped, so the Dart side can summarize it for the user instead
     * of the entry silently vanishing from the import.
     *
     * Additive to the existing "onImportProgress" event stream: does not
     * change the `importFiles`/`importFolder` `Int`-count return contract.
     */
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
}