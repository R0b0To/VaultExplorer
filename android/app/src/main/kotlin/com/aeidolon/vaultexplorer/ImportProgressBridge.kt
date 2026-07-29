package com.aeidolon.vaultexplorer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

object ImportProgressBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportProgress(
        opId: Int,
        done: Int,
        total: Int,
        currentName: String,
        transferredBytes: Long = 0L,
        totalBytes: Long = 0L,
    ) {
        val ch = channel ?: return
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