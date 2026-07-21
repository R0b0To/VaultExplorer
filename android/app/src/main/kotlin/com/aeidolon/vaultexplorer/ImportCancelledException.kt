package com.aeidolon.vaultexplorer

/**
 * Thrown from importEntryRecursive() when ImportCancellation.isCancelled()
 * notices the operation was cancelled via ImportCancellation.cancel(opId)
 * (see MainActivity's CANCEL_IMPORT handler, fired from Dart's
 * FileOperation.requestCancel() -> VaultExplorerApi.cancelImport()) —
 * rather than a real I/O failure.
 *
 * Kept distinct from a generic native error, mirroring
 * UnlockCancelledException, so MainActivity's dispatchNativeError() can
 * surface it to Dart as its own "CANCELLED" result.error code instead of
 * "C++_ERROR" — FileOperationService uses that to set the operation's
 * status to cancelled instead of failed.
 *
 * Requires the explicit (message: String) constructor below, matching
 * UnlockCancelledException's shape for consistency — though unlike that
 * one, this never crosses the JNI boundary; it's thrown and caught
 * entirely within Kotlin.
 */
class ImportCancelledException(message: String) : Exception(message)
