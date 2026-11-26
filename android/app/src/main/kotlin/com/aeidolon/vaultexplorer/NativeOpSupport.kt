package com.aeidolon.vaultexplorer

import android.net.Uri
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.atomic.AtomicInteger
import com.aeidolon.vaultexplorer.cancellation.ExportCancelledException
import com.aeidolon.vaultexplorer.cancellation.ImportCancelledException
import com.aeidolon.vaultexplorer.cancellation.UnlockCancelledException
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry

/**
 * Shared plumbing used by nearly every MethodChannel handler group:
 * running a Tier-2 native op on a background executor and reporting the
 * result back on the UI thread, translating C++/session exceptions into
 * the Flutter-side error codes the Dart layer expects, and opening keyfile
 * URIs into raw fds for the JNI keyfile-mixing contract (see
 * NativeEngine's doc comment for fd ownership).
 *
 * Holds a reference to [activity] rather than a pre-resolved
 * ContentResolver/executor snapshot. This class is constructed as an eager
 * MainActivity field, which runs *before* Activity.attachBaseContext() —
 * touching contentResolver (or getSystemService, cacheDir, etc.) that
 * early throws a NullPointerException. Everything here is only ever
 * invoked from a MethodChannel handler, well after attach(), so resolving
 * activity.contentResolver lazily inside each method is safe.
 */
class NativeOpSupport(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    private companion object {
        const val TAG = "NativeOpSupport"
    }

    // Rate limiters for the always-on boundary lines (see logWriteReturnedFalse and
    // dispatchNativeError): a loop of failing calls (a folder of unreadable
    // thumbnails, a failing import) must not flood logcat.
    private val falseResultLogs = AtomicInteger(0)
    private val errorLogs = AtomicInteger(0)

    /** Looks up [uriString]'s volId, runs [block] on [executor] (default:
     *  the shared ioExecutor), and reports success/failure back via
     *  [result] on the UI thread.
     *
     *  [op] names a *write* operation. When such an op returns plain `false`
     *  (an I/O failure below the JNI layer, as opposed to a READ_ONLY /
     *  NOT_UNLOCKED exception) nothing else logs it, and the UI can only say
     *  "check the container is still mounted"; see [logWriteReturnedFalse]. */
    fun <T> runNativeOp(
        uriString: String?,
        result: MethodChannel.Result,
        executor: ExecutorService = ioExecutor,
        label: String? = null,
        op: String? = null,
        block: (volId: Int) -> T,
    ) {
        if (uriString == null) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container not mounted", null)
            return
        }
        // With a [label], PerfLog reports how long the op waited for a free
        // thread on [executor] ("native.<label>.queue_wait") and how long it
        // then ran ("native.<label>.run"). Both are 0-cost when logging is off.
        val enqueuedAt = if (label != null) PerfLog.begin() else 0L
        executor.execute {
            try {
                var runStart = 0L
                if (enqueuedAt != 0L) {
                    PerfLog.end("native.$label.queue_wait", enqueuedAt)
                    runStart = PerfLog.begin()
                }
                val value = block(volId)
                if (runStart != 0L) PerfLog.end("native.$label.run", runStart)
                if (op != null && value is Boolean && !value) logWriteReturnedFalse(op, volId)
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                activity.runOnUiThread { dispatchNativeError(e, result) }
            }
        }
    }

    /**
     * One always-on line when a write op fails without throwing. The cause is in
     * the preceding "pwrite64 failed" / "SplitFuseCallback" lines (errno, offset,
     * fd access mode); this line ties it to the user-visible operation and states
     * whether the session was flagged read-only. No paths or names.
     */
    private fun logWriteReturnedFalse(op: String, volId: Int) {
        if (!OpenDiagnostics.shouldLogOccurrence(falseResultLogs)) return
        val session = ContainerSessionRegistry.activeSessions[volId]
        VeLog.diagW(TAG) {
            "write op '$op' returned false: volId=$volId sessionReadOnly=${session?.readOnly ?: "no-session"}"
        }
    }

    private fun isNotUnlockedException(e: Throwable): Boolean =
        e is IllegalStateException && e.message?.startsWith("NOT_UNLOCKED") == true
    private fun isReadOnlyException(e: Throwable): Boolean =
        e is IllegalStateException && e.message?.startsWith("READ_ONLY") == true

    fun dispatchNativeError(e: Exception, result: MethodChannel.Result) {
        // Cancellations are user actions. Everything else used to be handed to
        // Dart without a trace on this side; log the code and the exception
        // class/errno only (messages carry paths).
        val cancelled = e is UnlockCancelledException || e is ImportCancelledException || e is ExportCancelledException
        if (!cancelled && OpenDiagnostics.shouldLogOccurrence(errorLogs)) {
            val code = when {
                isNotUnlockedException(e) -> "NOT_UNLOCKED"
                isReadOnlyException(e) -> "READ_ONLY"
                else -> "C++_ERROR"
            }
            VeLog.diagW(TAG) { "native op failed: code=$code cause=${OpenDiagnostics.failureTag(e)}" }
        }
        if (e is UnlockCancelledException || e is ImportCancelledException || e is ExportCancelledException) {
            result.error("CANCELLED", e.message, null)
        } else if (isNotUnlockedException(e)) {
            result.error("NOT_UNLOCKED", e.message, null)
        } else if (isReadOnlyException(e)) {
            result.error("READ_ONLY", e.message, null)
        } else {
            result.error("C++_ERROR", e.message, null)
        }
    }

    /** Opens each keyfile path as a raw fd for the JNI keyfile-mixing calls.
     *  The native side takes ownership of every returned fd (see
     *  NativeEngine's deriveKeyMaterialNative doc comment). On failure, any
     *  fds already opened in this batch are closed before rethrowing. */
    fun openKeyfileFds(paths: List<String>?): IntArray? {
        if (paths.isNullOrEmpty()) return null
        val opened = mutableListOf<ParcelFileDescriptor>()
        try {
            for (path in paths) {
                val pfd = activity.contentResolver.openFileDescriptor(Uri.parse(path), "r")
                    ?: throw Exception("Could not open keyfile: $path")
                opened.add(pfd)
            }
            return IntArray(opened.size) { i -> opened[i].detachFd() }
        } catch (e: Exception) {
            for (pfd in opened) {
                try { pfd.close() } catch (_: Exception) {}
            }
            throw e
        }
    }
}
