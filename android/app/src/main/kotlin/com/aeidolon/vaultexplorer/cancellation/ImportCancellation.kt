package com.aeidolon.vaultexplorer.cancellation

import java.util.concurrent.ConcurrentHashMap
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.MainActivity

/**
 * Tracks which import operations (identified by the FileOperation.id that
 * Dart passes through as "opId" into importFile/importFolder) have been
 * asked to cancel, so importEntryRecursive() can notice between files and
 * unwind via ImportCancelledException.
 *
 * SAF-sourced imports run entirely on the Kotlin side (SAF reads +
 * ContainerFileSystem writes), so a between-files check here is enough for
 * those. Raw-file imports (a local path copied straight into the container
 * via a single blocking native writeBackFile call) also check this
 * mid-file now -- see isImportCancelled in jni_callbacks.h, called once
 * per buffer iteration from fatWriteBackFile/ntfsWriteBackFile/
 * extWriteBackFile/fsWriteBackFile -- so isCancelled needs to stay
 * @JvmStatic even though most callers are still plain Kotlin.
 *
 * Purely in-memory and process-lifetime. Entries are removed via clear()
 * once an import finishes (success, failure, or cancellation — see the
 * `finally` blocks in MainActivity's import launchers) so the set doesn't
 * grow without bound across a long session.
 */
object ImportCancellation {
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
