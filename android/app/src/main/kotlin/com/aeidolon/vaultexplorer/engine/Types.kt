package com.aeidolon.vaultexplorer.engine

/**
 * Common exceptions for all vault backends.
 */
open class VaultIOException(message: String, cause: Throwable? = null) : Exception(message, cause)
class VaultPathNotFoundException(path: String) : VaultIOException("Path not found: $path")

/**
 * Common tree node interface.
 */
interface VaultTreeNode {
    val cleartextName: String
}

/**
 * Common result type for vault opening operations.
 */
sealed class VaultOpenResult<out S> {
    /** [derivedKey], when non-null, is the raw KDF output used to unlock this
     *  vault (e.g. cryfs's scrypt `combinedKey`). Callers that want a "skip
     *  password entry next time" cache can stash it and later reopen via the
     *  backend's `openWithCombinedKey`/equivalent fast path. */
    data class Success<out S>(
        val session: S,
        val vaultDisplayName: String,
        val derivedKey: ByteArray? = null,
    ) : VaultOpenResult<S>()
    object WrongPassword : VaultOpenResult<Nothing>()
    data class InvalidVault(val reason: String) : VaultOpenResult<Nothing>()
}