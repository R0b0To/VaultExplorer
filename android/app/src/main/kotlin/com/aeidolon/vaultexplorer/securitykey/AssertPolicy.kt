package com.aeidolon.vaultexplorer.securitykey

/**
 * How a vault expects its hmac-secret assertion to be performed.
 *
 * This matters for correctness, not just UX: an authenticator derives a
 * DIFFERENT hmac-secret output depending on whether the assertion was
 * user-verified (PIN/UV) or not (CTAP2.1 "CredRandomWithUV" vs
 * "CredRandomWithoutUV"). The secret only matches the one that was used when
 * the vault was created if the assertion is made the same way, so the PIN is
 * sent if and only if the vault's own metadata says so -- never merely
 * because the key happens to have a PIN set.
 *
 * - [pin]: send the PIN (user-verified assertion).
 * - [up]: explicit user-presence option; null = leave at the authenticator
 *   default (required).
 * - [uv]: the vault asked for built-in user verification (e.g. a fingerprint
 *   key). Only PIN-based verification is supported here.
 */
data class AssertPolicy(
    val pin: Boolean = false,
    val up: Boolean? = null,
    val uv: Boolean? = null,
) {
    companion object {
        /**
         * gocryptfs stores the options it passes to `fido2-assert -t` as
         * "name=value" strings (`pin=true`, `up=false`, `uv=true`).
         * Unknown options are ignored.
         */
        fun fromGocryptfsOptions(options: List<String>): AssertPolicy {
            var pin = false
            var up: Boolean? = null
            var uv: Boolean? = null
            for (opt in options) {
                val i = opt.indexOf('=')
                if (i <= 0) continue
                val value = opt.substring(i + 1).trim().lowercase()
                val flag = when (value) {
                    "true" -> true
                    "false" -> false
                    else -> continue
                }
                when (opt.substring(0, i).trim().lowercase()) {
                    "pin" -> pin = flag
                    "up" -> up = flag
                    "uv" -> uv = flag
                }
            }
            return AssertPolicy(pin = pin, up = up, uv = uv)
        }
    }
}
