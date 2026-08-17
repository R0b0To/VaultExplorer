package com.aeidolon.vaultexplorer.cancellation
import com.aeidolon.vaultexplorer.handlers.SplitJoinHandlers

/**
 * Thrown from [SplitJoinHandlers]'s split/join loops when
 * [SplitJoinCancellation.isCancelled] notices the operation was cancelled
 * via [SplitJoinCancellation.cancel] (fired from Dart's
 * `FileOperation.requestCancel()` -> `VaultExplorerApi.cancelSplitJoin()`)
 * rather than a real I/O failure.
 *
 * Kept distinct from a generic I/O error, mirroring
 * [ImportCancelledException], so [SplitJoinHandlers] can surface it to
 * Dart as its own `"CANCELLED"` `result.error` code instead of
 * `"IO_ERROR"`.
 */
class SplitJoinCancelledException(message: String) : Exception(message)
