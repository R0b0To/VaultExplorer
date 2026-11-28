package com.aeidolon.vaultexplorer.handlers

import android.content.Context
import android.os.PowerManager
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Arguments shared by `videoEditExport` and `audioEditExport`: `volId`,
 * `filePath`, `isLocalStorage`, `segments` (list of `[startUs, endUs]`),
 * `merge` (one output holding every segment vs. one output per segment),
 * `outputPaths` (exactly 1 when merging, else one per segment --
 * container-relative for a vault, absolute for local storage; Dart has already
 * made them unique) and `opId`.
 */
internal class EditExportArgs(
    val volId: Int,
    val filePath: String,
    val isLocal: Boolean,
    val opId: Int,
    val outputPaths: List<String>,
    private val merge: Boolean,
    private val segmentsUs: List<Pair<Long, Long>>,
) {
    /** The segments grouped per output file: one group when merging, otherwise one per segment. */
    fun <R> groups(makeRange: (startUs: Long, endUs: Long) -> R): List<List<R>> {
        val ranges = segmentsUs.map { makeRange(it.first, it.second) }
        return if (merge) listOf(ranges) else ranges.map { listOf(it) }
    }
}

/**
 * Reads and validates the shared export arguments. On a bad request it replies
 * `INVALID_ARGS` on [result] itself and returns null, so callers just `?: return`.
 */
internal fun parseEditExportArgs(call: MethodCall, result: MethodChannel.Result): EditExportArgs? {
    val volId = call.argument<Number>("volId")?.toInt()
    val filePath = call.argument<String>("filePath")
    val isLocal = call.argument<Boolean>("isLocalStorage") ?: false
    val merge = call.argument<Boolean>("merge") ?: false
    val opId = call.argument<Number>("opId")?.toInt() ?: 0
    val rawSegments = call.argument<List<List<Number>>>("segments")
    val outputPaths = call.argument<List<String>>("outputPaths")

    if (volId == null || filePath.isNullOrEmpty() || rawSegments.isNullOrEmpty() || outputPaths.isNullOrEmpty()) {
        result.error("INVALID_ARGS", "volId, filePath, segments and outputPaths are required", null)
        return null
    }
    val segments = rawSegments.map { it[0].toLong() to it[1].toLong() }
    if (segments.any { it.second <= it.first }) {
        result.error("INVALID_ARGS", "Every segment needs an end after its start", null)
        return null
    }
    val groupCount = if (merge) 1 else segments.size
    if (outputPaths.size != groupCount) {
        result.error("INVALID_ARGS", "Expected $groupCount output path(s), got ${outputPaths.size}", null)
        return null
    }
    return EditExportArgs(volId, filePath, isLocal, opId, outputPaths, merge, segments)
}

/** Plumbing shared by the Video and Audio editors' export paths. */
internal object EditExportSupport {
    private const val COPY_BUFFER = 256 * 1024
    private const val MB = 1024 * 1024L

    /** Acquires a partial wake lock for a long export; null when the power service is unavailable. */
    fun acquireWakeLock(context: Context, tag: String, timeoutMs: Long): PowerManager.WakeLock? {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, tag)
        wakeLock?.acquire(timeoutMs)
        return wakeLock
    }

    fun releaseWakeLock(wakeLock: PowerManager.WakeLock?) {
        if (wakeLock?.isHeld == true) {
            runCatching { wakeLock.release() }
        }
    }

    /**
     * Free-space preflight: the output is never larger than the source, so the
     * estimate is sized on it. Checks the app cache (where each output is muxed
     * first) and then the destination -- the local folder or the vault.
     *
     * @throws IOException when a location is known to be too small.
     */
    fun checkFreeSpace(cacheDir: File, args: EditExportArgs) {
        val sourceSize = if (args.isLocal) {
            File(args.filePath).length().coerceAtLeast(1L)
        } else {
            ContainerFileSystem.getFileSize(args.volId, args.filePath).coerceAtLeast(1L)
        }
        val estimatedBytes = ((sourceSize * 1.2).toLong() + 5 * MB).coerceAtLeast(10 * MB)

        fun failIfTooSmall(freeBytes: Long?, where: String) {
            if (freeBytes != null && freeBytes in 1 until estimatedBytes) {
                throw IOException(
                    "Not enough free space $where (need ${estimatedBytes / MB} MB, only ${freeBytes / MB} MB available)"
                )
            }
        }

        failIfTooSmall(cacheDir.usableSpace, "in app cache")
        if (args.isLocal) {
            val destDir = File(args.outputPaths[0]).parentFile ?: File(args.outputPaths[0])
            failIfTooSmall(destDir.usableSpace, "on storage")
        } else {
            failIfTooSmall(
                ContainerFileSystem.getSpaceInfo(args.volId)?.let { if (it.size > 1) it[1] else null },
                "in vault",
            )
        }
    }

    /** Moves the finished plaintext [temp] file to [dest] (a local path, or container-relative for a vault). */
    fun saveOutput(args: EditExportArgs, temp: File, dest: String, tag: String): Boolean =
        if (args.isLocal) {
            copyToLocal(temp, File(dest), tag)
        } else {
            val written = ContainerFileSystem.writeBackFile(args.volId, dest, temp.absolutePath)
            written && ContainerFileSystem.finishWrite(args.volId, dest)
        }

    private fun copyToLocal(src: File, dest: File, tag: String): Boolean = try {
        dest.parentFile?.mkdirs()
        src.inputStream().use { input ->
            dest.outputStream().use { output -> input.copyTo(output, COPY_BUFFER) }
        }
        true
    } catch (e: Exception) {
        VeLog.w(tag, e) { "copyToLocal failed" }
        false
    }

    /** Removes outputs this call created, so a failed/cancelled export leaves nothing half-written behind. */
    fun rollBack(args: EditExportArgs, created: List<String>) {
        for (path in created) {
            runCatching {
                if (args.isLocal) File(path).delete() else ContainerFileSystem.deleteFile(args.volId, path)
            }
        }
    }

    /** Replies `CANCELLED` or `EXPORT_FAILED` (logging only genuine failures) on the UI thread. */
    fun replyFailure(
        activity: MainActivity,
        result: MethodChannel.Result,
        error: Exception,
        cancelled: Boolean,
        tag: String,
        logMessage: String,
    ) {
        if (!cancelled) VeLog.w(tag, error) { logMessage }
        activity.runOnUiThread {
            if (cancelled) {
                result.error("CANCELLED", "Export cancelled", null)
            } else {
                result.error("EXPORT_FAILED", error.message ?: "Export failed", null)
            }
        }
    }
}
