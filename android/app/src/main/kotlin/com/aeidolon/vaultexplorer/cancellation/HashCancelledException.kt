package com.aeidolon.vaultexplorer.cancellation
import com.aeidolon.vaultexplorer.handlers.HashVerifierHandlers

/**
 * Thrown from [HashVerifierHandlers.handleComputeExternalFileHash] when
 * [HashCancellation.isCancelled] notices the op was cancelled via
 * `VaultExplorerApi.cancelHashCompute()` rather than a real I/O failure.
 * Mirrors [SplitJoinCancelledException].
 */
class HashCancelledException(message: String) : Exception(message)
