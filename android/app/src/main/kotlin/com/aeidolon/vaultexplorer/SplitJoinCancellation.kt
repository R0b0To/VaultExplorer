package com.aeidolon.vaultexplorer

import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks which Container Splitter/Joiner operations (identified by the
 * same `opId` convention as [ImportCancellation] — Dart's
 * `FileOperation.id`, passed through into `splitContainer`/`joinContainer`)
 * have been asked to cancel, so [SplitJoinHandlers] can notice between
 * buffer-sized read/write steps and unwind via [SplitJoinCancelledException].
 *
 * Deliberately a separate id space from [ImportCancellation] rather than
 * reusing it: split/join runs entirely outside the mounted-container/volId
 * world (see [SplitJoinHandlers]'s doc comment), and a stray cross-cancel
 * between an in-flight import and an in-flight split/join that happened to
 * land on the same opId would be a confusing bug to chase down. Purely
 * in-memory and process-lifetime, same as [ImportCancellation]; entries are
 * removed via [clear] once an operation finishes (success, failure, or
 * cancellation) so the set doesn't grow without bound across a session.
 */
object SplitJoinCancellation {
    private val cancelledIds = ConcurrentHashMap.newKeySet<Int>()

    fun cancel(opId: Int) {
        cancelledIds.add(opId)
    }

    fun isCancelled(opId: Int): Boolean = cancelledIds.contains(opId)

    fun clear(opId: Int) {
        cancelledIds.remove(opId)
    }
}
