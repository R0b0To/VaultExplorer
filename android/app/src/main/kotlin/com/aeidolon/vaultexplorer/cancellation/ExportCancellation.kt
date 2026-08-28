package com.aeidolon.vaultexplorer.cancellation

import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks which export operations (identified by the FileOperation.id that
 * Dart passes through as "opId" into exportFilesToFolder) have been asked
 * to cancel, so the export loop in ImportExportHandlers.kt can notice
 * between entries and stop early.
 *
 * Checked only between files/folders in Kotlin (exportEntryRecursive /
 * exportEntryRecursiveRaw / the top-level item loop in
 * handleExportFilesFolder) -- there is no mid-file check inside a single
 * extractFile call, same limitation the cross-container copy path already
 * has for its own extract half (see the doc comment on
 * ContainerEngine.copyFileViaBackend).
 *
 * Purely in-memory and process-lifetime. Entries are removed via clear()
 * once an export finishes (success, failure, or cancellation) so the set
 * doesn't grow without bound across a long session. Mirrors
 * [ImportCancellation] / [CopyCancellation] exactly.
 */
object ExportCancellation {
    private val cancelledIds = ConcurrentHashMap.newKeySet<Int>()

    @JvmStatic
    fun cancel(opId: Int) {
        cancelledIds.add(opId)
    }

    @JvmStatic
    fun isCancelled(opId: Int): Boolean = cancelledIds.contains(opId)

    @JvmStatic
    fun clear(opId: Int) {
        cancelledIds.remove(opId)
    }
}
