package com.aeidolon.vaultexplorer.securitykey

/**
 * Failure categories for hardware security key (FIDO2) operations. [wire] is
 * the MethodChannel error code Dart maps to a localized message.
 *
 * [retryOnNextKey]: the failure is specific to the key that was just
 * presented (wrong key for this vault, or not a FIDO key at all), so the
 * transport keeps waiting for another key instead of failing the operation.
 */
enum class SecurityKeyError(val wire: String, val retryOnNextKey: Boolean = false) {
    TIMEOUT("SECURITY_KEY_TIMEOUT"),
    CANCELLED("SECURITY_KEY_CANCELLED"),
    PIN_REQUIRED("SECURITY_KEY_PIN_REQUIRED"),
    PIN_INVALID("SECURITY_KEY_PIN_INVALID"),
    PIN_BLOCKED("SECURITY_KEY_PIN_BLOCKED"),
    PIN_NOT_SET("SECURITY_KEY_PIN_NOT_SET"),
    NO_CREDENTIAL("SECURITY_KEY_NO_CREDENTIAL", retryOnNextKey = true),
    UNSUPPORTED("SECURITY_KEY_UNSUPPORTED"),
    USER_ACTION("SECURITY_KEY_USER_ACTION"),
    FAILED("SECURITY_KEY_FAILED"),
}

class SecurityKeyException(
    val error: SecurityKeyError,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)
