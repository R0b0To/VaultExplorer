package com.aeidolon.vaultexplorer.cancellation

import java.util.concurrent.ConcurrentHashMap

/**
 * Cancellation flags for copy/move [FileOperation][com.aeidolon.vaultexplorer]
 * opIds, checked from native code (see isCopyCancelled in jni_callbacks.h)
 * once per buffer iteration inside fatCopyFile/ntfsCopyFile/extCopyFile/
 * fsCopyFile -- same call site as CopyProgressBridge's progress reporting,
 * so a cancel lands within one chunk instead of only between whole files.
 * Mirrors [SplitJoinCancellation] exactly.
 */
object CopyCancellation {
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
