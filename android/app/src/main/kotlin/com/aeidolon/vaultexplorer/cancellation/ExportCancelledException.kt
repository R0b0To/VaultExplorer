package com.aeidolon.vaultexplorer.cancellation
import com.aeidolon.vaultexplorer.MainActivity

/**
 * Thrown from exportEntryRecursive()/exportEntryRecursiveRaw() when
 * ExportCancellation.isCancelled() notices the operation was cancelled via
 * ExportCancellation.cancel(opId) (see MainActivity's CANCEL_EXPORT
 * handler, fired from Dart's FileOperation.requestCancel() ->
 * VaultExplorerApi.cancelExport()) — rather than a real I/O failure.
 *
 * Kept distinct from a generic native error, mirroring
 * [ImportCancelledException], so NativeOpSupport.dispatchNativeError() can
 * surface it to Dart as its own "CANCELLED" result.error code instead of
 * "C++_ERROR" — FileOperationService uses that to set the operation's
 * status to cancelled instead of failed.
 */
class ExportCancelledException(message: String) : Exception(message)
