package com.aeidolon.vaultexplorer

import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks which import operations (identified by the FileOperation.id that
 * Dart passes through as "opId" into importFile/importFolder) have been
 * asked to cancel, so importEntryRecursive() can notice between files and
 * unwind via ImportCancelledException.
 *
 * Unlike unlock cancellation — which aborts a single native auto-detect
 * keyed by volId — imports run entirely on the Kotlin side (SAF reads +
 * ContainerFileSystem writes), so a plain in-memory flag per opId is
 * enough; no JNI/C++ involvement needed.
 *
 * Purely in-memory and process-lifetime. Entries are removed via clear()
 * once an import finishes (success, failure, or cancellation — see the
 * `finally` blocks in MainActivity's import launchers) so the set doesn't
 * grow without bound across a long session.
 */
object ImportCancellation {
    private val cancelledIds = ConcurrentHashMap.newKeySet<Int>()

    fun cancel(opId: Int) {
        cancelledIds.add(opId)
    }

    fun isCancelled(opId: Int): Boolean = cancelledIds.contains(opId)

    fun clear(opId: Int) {
        cancelledIds.remove(opId)
    }
}
