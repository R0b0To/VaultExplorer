package com.aeidolon.vaultexplorer

import android.net.Uri
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
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
    /** Looks up [uriString]'s volId, runs [block] on [executor] (default:
     *  the shared ioExecutor), and reports success/failure back via
     *  [result] on the UI thread. */
    fun <T> runNativeOp(
        uriString: String?,
        result: MethodChannel.Result,
        executor: ExecutorService = ioExecutor,
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
        executor.execute {
            try {
                val value = block(volId)
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                activity.runOnUiThread { dispatchNativeError(e, result) }
            }
        }
    }

    private fun isNotUnlockedException(e: Throwable): Boolean =
        e is IllegalStateException && e.message?.startsWith("NOT_UNLOCKED") == true
    private fun isReadOnlyException(e: Throwable): Boolean =
        e is IllegalStateException && e.message?.startsWith("READ_ONLY") == true

    fun dispatchNativeError(e: Exception, result: MethodChannel.Result) {
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
