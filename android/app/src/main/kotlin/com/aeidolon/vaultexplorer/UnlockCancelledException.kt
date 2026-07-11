package com.aeidolon.vaultexplorer

/**
 * Thrown across the JNI boundary (see throwUnlockCancelledException() in
 * vaultexplorer.cpp) when an unlock attempt was aborted via
 * ContainerEngine.requestUnlockCancellation(volId) rather than failing for
 * a real reason (wrong password/keyfiles, corrupt container, ...).
 *
 * Kept distinct from a generic native error so MainActivity's
 * dispatchNativeError() can surface it to Dart as its own "CANCELLED"
 * result.error code instead of "AUTH_FAIL"/"C++_ERROR" — the unlock sheets
 * use that to skip showing an error banner for a cancellation the user
 * asked for themselves.
 *
 * Requires the explicit (message: String) constructor below — no default
 * value — so the compiled class exposes exactly the single-String
 * constructor signature (Ljava/lang/String;)V that JNI's ThrowNew() needs;
 * a default parameter would compile to an extra synthetic-marker overload
 * ThrowNew can't find.
 */
class UnlockCancelledException(message: String) : Exception(message)
