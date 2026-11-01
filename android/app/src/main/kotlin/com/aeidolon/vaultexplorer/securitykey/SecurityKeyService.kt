package com.aeidolon.vaultexplorer.securitykey

import android.app.Activity
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsFido2Params
import com.yubico.yubikit.fido.ctap.Ctap2Session
import java.security.SecureRandom

/**
 * A freshly enrolled gocryptfs security-key credential: what goes into the
 * new vault's gocryptfs.conf ([params]) and the secret the masterkey is
 * wrapped under ([secret], raw 32 bytes -- the caller zeroes it).
 */
class GocryptfsFido2Enrollment(val params: GocryptfsFido2Params, val secret: ByteArray)

/**
 * High-level security-key operations for the formats that have a shared,
 * interoperable scheme: gocryptfs (`-fido2`) and LUKS2 (`systemd-cryptenroll`).
 * Every call blocks until a key is presented -- IO executor only.
 */
class SecurityKeyService(private val activity: Activity) {

    @Volatile private var active: SecurityKeyTransport? = null

    /** Aborts the key wait in progress, if any. Safe to call from any thread. */
    fun cancel() {
        active?.cancel()
    }

    private fun <T> withKey(block: (Ctap2Session) -> T): T {
        val transport = SecurityKeyTransport(activity)
        active = transport
        try {
            return transport.run(block = block)
        } finally {
            active = null
        }
    }

    /** The raw 32-byte hmac-secret gocryptfs uses as the vault password. Caller zeroes it. */
    fun deriveGocryptfsSecret(params: GocryptfsFido2Params, pin: CharArray?): ByteArray = withKey { session ->
        Fido2HmacSecret.deriveSecret(
            session = session,
            rpId = GocryptfsFido2Params.RP_ID,
            credentialId = params.credentialId,
            salt = params.hmacSalt,
            policy = AssertPolicy.fromGocryptfsOptions(params.assertOptions),
            pin = pin,
        )
    }

    /**
     * Creates the credential and derives its first secret in ONE session, so
     * over NFC the key only has to stay on the phone once. Mirrors
     * `gocryptfs -init -fido2`: relying party "gocryptfs", non-resident
     * credential, a random 32-byte salt, and `pin=true` recorded as an assert
     * option when the user asked for PIN protection.
     */
    fun enrollGocryptfs(userName: String, requirePin: Boolean, pin: CharArray?): GocryptfsFido2Enrollment =
        withKey { session ->
            val policy = AssertPolicy(pin = requirePin)
            val credentialId = Fido2HmacSecret.createCredential(
                session, GocryptfsFido2Params.RP_ID, GocryptfsFido2Params.RP_ID, userName, policy, pin,
            )
            val salt = ByteArray(Fido2HmacSecret.SALT_LEN).also { SecureRandom().nextBytes(it) }
            val secret = Fido2HmacSecret.deriveSecret(
                session, GocryptfsFido2Params.RP_ID, credentialId, salt, policy, pin,
            )
            GocryptfsFido2Enrollment(
                params = GocryptfsFido2Params(
                    credentialId = credentialId,
                    hmacSalt = salt,
                    assertOptions = if (requirePin) listOf("pin=true") else emptyList(),
                ),
                secret = secret,
            )
        }

    /** The LUKS passphrase systemd-cryptenroll derives for [token]: base64 of the hmac-secret. */
    fun deriveLuksPassphrase(token: Luks2Fido2Token, pin: CharArray?): String {
        val secret = withKey { session ->
            Fido2HmacSecret.deriveSecret(session, token.rpId, token.credentialId, token.salt, token.policy, pin)
        }
        try {
            return Luks2Fido2Token.passphraseFor(secret)
        } finally {
            secret.fill(0)
        }
    }
}
