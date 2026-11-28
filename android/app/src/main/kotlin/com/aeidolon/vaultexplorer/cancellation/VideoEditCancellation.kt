package com.aeidolon.vaultexplorer.cancellation

import java.util.concurrent.ConcurrentHashMap

/**
 * Cancellation flags for Video Editor exports, keyed by the opId Dart passes
 * with `videoEditExport`. Same shape as [HashCancellation]; kept as its own
 * registry so the opId spaces of unrelated long-running operations can never
 * collide.
 */
object VideoEditCancellation {
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
