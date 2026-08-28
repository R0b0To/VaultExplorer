package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Export-side counterpart to [ImportProgressBridge]. Reports progress for
 * exportFilesToFolder (see ImportExportHandlers.kt) back to Dart so bulk or
 * large exports get the same "still working, not frozen" feedback that
 * import already has, instead of the UI just blocking on a single opaque
 * native call with no signal until it returns.
 *
 * One real difference from import: a folder-vault (Cryptomator/gocryptfs/
 * cryFS) extractFile call already reports its own chunk-level progress to
 * [CopyProgressBridge], because that code path is shared with
 * cross-container copy's extract half. Copy halves every reported chunk
 * (see the comment in ChunkedFileEngine.writeBackFile/extractFile) since a
 * copy's byte budget covers two passes -- but export is a single pass, so
 * halved chunks would stall its progress at 50%. [isTracking] lets
 * ChunkedFileEngine.extractFile tell, from the opId alone, whether a given
 * call belongs to a tracked export (route the *full* chunk here via
 * [reportChunk]) or an ordinary copy (route to CopyProgressBridge,
 * unchanged). For the native block-device formats (VeraCrypt/LUKS/
 * BitLocker/VHD), NativeEngine.extractFile has no such per-chunk hook at
 * all -- those only get the coarser per-file progress this bridge also
 * reports via [reportProgress]/[reportItemFinished].
 */
object ExportProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private val lastReportTimes = java.util.concurrent.ConcurrentHashMap<Int, Long>()

    /** Which opIds currently belong to a running export -- see [isTracking]. */
    private val trackedIds = java.util.concurrent.ConcurrentHashMap.newKeySet<Int>()

    /** Cached from the most recent explicit reportProgress() call for this
     *  opId, so reportChunk() below -- fired mid-file, with only a byte
     *  delta to go on -- can still emit a full progress event. */
    private data class LastContext(
        val done: Int,
        val total: Int,
        val currentName: String,
        val totalBytes: Long,
    )
    private val lastContext = java.util.concurrent.ConcurrentHashMap<Int, LastContext>()

    /** Bytes transferred across every entry in this export *before* the
     *  file currently being extracted -- see beginFileChunks(). */
    private val chunkBaseline = java.util.concurrent.ConcurrentHashMap<Int, Long>()

    /** Bytes reported so far for the file currently being extracted -- see
     *  beginFileChunks() and reportChunk(). */
    private val chunkAccumulated = java.util.concurrent.ConcurrentHashMap<Int, java.util.concurrent.atomic.AtomicLong>()

    /** Marks opId as a tracked export -- called once when
     *  handleExportFilesFolder starts working through its item list. */
    @JvmStatic
    fun begin(opId: Int) {
        trackedIds.add(opId)
    }

    @JvmStatic
    fun isTracking(opId: Int): Boolean = trackedIds.contains(opId)

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
                "onExportProgress",
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
     * Called once, from Kotlin, right before extracting one entry --
     * establishes the byte baseline (bytes transferred across every
     * *previous* entry in this export) that reportChunk() below layers
     * each chunk's delta on top of. Callers should already have called
     * reportProgress() for this file's done/total/currentName beforehand
     * so reportChunk() has a [LastContext] to reuse.
     */
    @JvmStatic
    fun beginFileChunks(opId: Int, baselineTransferredBytes: Long) {
        chunkBaseline[opId] = baselineTransferredBytes
        chunkAccumulated[opId] = java.util.concurrent.atomic.AtomicLong(0)
    }

    /**
     * Fired from ChunkedFileEngine.extractFile per buffer batch when
     * [isTracking] says the opId belongs to an export, with the *full*
     * decrypted batch size (unlike CopyProgressBridge's halved amount --
     * export is a single decrypt-only pass, not decrypt-then-encrypt).
     *
     * Reuses whatever done/total/currentName/totalBytes context the most
     * recent reportProgress() call cached and adds bytesDelta on top of
     * the baseline captured there, then just calls reportProgress() again.
     * Purely a UI-smoothing overlay for folder-vault formats: the
     * post-completion reportProgress() call for each entry, driven by its
     * own known file size, is still what finalizes the true total once
     * that entry completes -- so any drift here self-corrects.
     */
    @JvmStatic
    fun reportChunk(opId: Int, bytesDelta: Long) {
        if (bytesDelta <= 0) return
        val ctx = lastContext[opId] ?: return
        val accumulated = chunkAccumulated[opId]?.addAndGet(bytesDelta) ?: return
        val baseline = chunkBaseline[opId] ?: 0L
        reportProgress(opId, ctx.done, ctx.total, ctx.currentName, baseline + accumulated, ctx.totalBytes)
    }

    /** Drops all state for a finished/cancelled export -- see the `finally`
     *  blocks in ImportExportHandlers.kt, alongside ExportCancellation.clear(). */
    @JvmStatic
    fun clear(opId: Int) {
        trackedIds.remove(opId)
        lastReportTimes.remove(opId)
        lastContext.remove(opId)
        chunkBaseline.remove(opId)
        chunkAccumulated.remove(opId)
    }

    /**
     * Fired when a single top-level entry in an export operation finishes
     * writing to device storage (or fails). Lets the Dart side mark that
     * item done/failed immediately rather than waiting for the whole
     * export call to return.
     */
    @JvmStatic
    fun reportItemFinished(
        opId: Int,
        sourceName: String,
        isDir: Boolean,
        success: Boolean,
    ) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onExportItemFinished",
                mapOf(
                    "opId" to opId,
                    "sourceName" to sourceName,
                    "isDir" to isDir,
                    "success" to success,
                ),
            )
        }
    }
}
