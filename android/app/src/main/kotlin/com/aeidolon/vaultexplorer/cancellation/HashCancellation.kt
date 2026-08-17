package com.aeidolon.vaultexplorer.cancellation

import java.util.concurrent.ConcurrentHashMap
import com.aeidolon.vaultexplorer.handlers.HashVerifierHandlers

/**
 * opId-keyed cancellation flags for [HashVerifierHandlers.handleComputeExternalFileHash].
 * Mirrors [SplitJoinCancellation]'s shape exactly, kept as its own id space
 * for the same reason that file's doc comment gives: independent tools
 * shouldn't share a cancellation namespace just because the pattern looks
 * the same.
 */
object HashCancellation {
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
