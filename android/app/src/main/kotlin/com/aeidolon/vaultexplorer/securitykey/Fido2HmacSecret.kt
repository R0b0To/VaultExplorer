package com.aeidolon.vaultexplorer.securitykey

import com.yubico.yubikit.core.application.CommandException
import com.yubico.yubikit.core.fido.CtapException
import com.yubico.yubikit.fido.ctap.ClientPin
import com.yubico.yubikit.fido.ctap.Ctap2Session
import com.yubico.yubikit.fido.ctap.PinUvAuthProtocol
import com.yubico.yubikit.fido.ctap.PinUvAuthProtocolV1
import com.yubico.yubikit.fido.ctap.PinUvAuthProtocolV2
import com.yubico.yubikit.fido.webauthn.AuthenticatorData
import java.nio.ByteBuffer
import java.security.SecureRandom

/**
 * Raw CTAP2 `hmac-secret` operations.
 *
 * Why this drives [Ctap2Session] directly instead of using yubikit's
 * HmacSecretExtension: that class always hashes the caller's salt as
 * SHA-256("WebAuthn PRF" || 0x00 || salt) (the WebAuthn PRF convention).
 * gocryptfs and systemd-cryptenroll hand the authenticator their stored salt
 * unchanged, so going through the PRF layer would silently derive a
 * different secret and nothing could be unlocked. The extension input is
 * built here by hand: {1: keyAgreement, 2: encrypt(sharedSecret, salt),
 * 3: authenticate(sharedSecret, saltEnc), 4: pinUvAuthProtocol}.
 *
 * Callers own the returned secret and must zero it after use.
 */
object Fido2HmacSecret {
    private const val EXT = "hmac-secret"
    const val SALT_LEN = 32
    const val SECRET_LEN = 32
    private val random = SecureRandom()

    /**
     * Derives the 32-byte hmac-secret output for [credentialId] and [salt]
     * (the salt is sent as-is). [pin] is only used when [policy] (or an
     * always-UV authenticator) requires user verification; see
     * [AssertPolicy] for why that decision must come from the vault.
     */
    fun deriveSecret(
        session: Ctap2Session,
        rpId: String,
        credentialId: ByteArray,
        salt: ByteArray,
        policy: AssertPolicy,
        pin: CharArray?,
    ): ByteArray = ctap {
        if (salt.size != SALT_LEN) {
            throw SecurityKeyException(
                SecurityKeyError.FAILED,
                "Unexpected hmac-secret salt length ${salt.size} (expected $SALT_LEN).",
            )
        }
        val info = requireSupport(session)
        if (policy.uv == true && !policy.pin) {
            throw SecurityKeyException(
                SecurityKeyError.UNSUPPORTED,
                "This vault requires built-in user verification (for example a fingerprint), " +
                    "which isn't supported. Only PIN verification is.",
            )
        }
        val needPin = policy.pin || alwaysUv(info)
        if (needPin && !hasPin(info)) {
            throw SecurityKeyException(SecurityKeyError.PIN_NOT_SET, "This security key has no PIN set.")
        }

        val protocol = protocolFor(info)
        val clientPin = ClientPin(session, protocol)
        var pinToken: ByteArray? = null
        var sharedSecret: ByteArray? = null
        try {
            if (needPin) {
                pinToken = clientPin.getPinToken(requirePin(pin), ClientPin.PIN_PERMISSION_GA, rpId)
            }
            val agreement = clientPin.sharedSecret
            val keyAgreement = agreement.first
            val secretKey = agreement.second
            sharedSecret = secretKey

            val saltEnc = protocol.encrypt(secretKey, salt)
            val saltAuth = protocol.authenticate(secretKey, saltEnc)
            val hmacInput = mapOf<Int, Any>(
                1 to keyAgreement,
                2 to saltEnc,
                3 to saltAuth,
                4 to protocol.version,
            )

            val clientDataHash = random32()
            val allowList = listOf(mapOf("type" to "public-key", "id" to credentialId))
            val options: Map<String, Any>? = if (policy.up == false) mapOf("up" to false) else null
            val assertions = session.getAssertions(
                rpId,
                clientDataHash,
                allowList,
                mapOf(EXT to hmacInput),
                options,
                pinToken?.let { protocol.authenticate(it, clientDataHash) },
                if (pinToken != null) protocol.version else null,
                null,
            )
            val assertion = assertions.firstOrNull()
                ?: throw SecurityKeyException(SecurityKeyError.FAILED, "The security key returned no assertion.")
            val authData = parseAuthData(assertion.authenticatorData)
            val encrypted = authData.extensions?.get(EXT) as? ByteArray
                ?: throw SecurityKeyException(
                    SecurityKeyError.FAILED,
                    "The security key did not return an hmac-secret value.",
                )
            val plain = protocol.decrypt(secretKey, encrypted)
            // Same sanity checks upstream gocryptfs applies to the output.
            if (plain.size != SECRET_LEN || plain.all { it == 0.toByte() }) {
                plain.fill(0)
                throw SecurityKeyException(SecurityKeyError.FAILED, "The security key returned an invalid hmac-secret value.")
            }
            plain
        } finally {
            pinToken?.fill(0)
            sharedSecret?.fill(0)
        }
    }

    /**
     * Creates a non-discoverable credential with hmac-secret enabled and
     * returns its credential ID. [pin] is needed whenever the key has a PIN
     * set (makeCredential requires it then); [policy].pin only records
     * whether LATER assertions will be user-verified and is checked here so
     * a "require PIN" vault can't be created on a key with no PIN.
     */
    fun createCredential(
        session: Ctap2Session,
        rpId: String,
        rpName: String,
        userName: String,
        policy: AssertPolicy,
        pin: CharArray?,
    ): ByteArray = ctap {
        val info = requireSupport(session)
        if (policy.pin && !hasPin(info)) {
            throw SecurityKeyException(SecurityKeyError.PIN_NOT_SET, "This security key has no PIN set.")
        }
        val needPin = hasPin(info) || alwaysUv(info)
        val protocol = protocolFor(info)
        val clientPin = ClientPin(session, protocol)
        var pinToken: ByteArray? = null
        try {
            if (needPin) {
                pinToken = clientPin.getPinToken(requirePin(pin), ClientPin.PIN_PERMISSION_MC, rpId)
            }
            val clientDataHash = random32()
            val credential = session.makeCredential(
                clientDataHash,
                mapOf("id" to rpId, "name" to rpName),
                mapOf("id" to random32(), "name" to userName),
                listOf(mapOf("type" to "public-key", "alg" to -7)), // ES256, libfido2's default
                null,
                mapOf(EXT to true),
                null,
                pinToken?.let { protocol.authenticate(it, clientDataHash) },
                if (pinToken != null) protocol.version else null,
                null,
                null,
            )
            val authData = parseAuthData(credential.authenticatorData)
            if (authData.extensions?.get(EXT) != true) {
                throw SecurityKeyException(
                    SecurityKeyError.UNSUPPORTED,
                    "The security key did not enable the hmac-secret extension for the new credential.",
                )
            }
            authData.attestedCredentialData?.credentialId
                ?: throw SecurityKeyException(SecurityKeyError.FAILED, "The security key returned no credential ID.")
        } finally {
            pinToken?.fill(0)
        }
    }

    private fun requireSupport(session: Ctap2Session): Ctap2Session.InfoData {
        val info = session.cachedInfo
        if (!info.extensions.contains(EXT) || !ClientPin.isSupported(info)) {
            throw SecurityKeyException(
                SecurityKeyError.UNSUPPORTED,
                "This security key does not support the FIDO2 hmac-secret extension.",
            )
        }
        return info
    }

    private fun protocolFor(info: Ctap2Session.InfoData): PinUvAuthProtocol =
        if (info.pinUvAuthProtocols.contains(2)) PinUvAuthProtocolV2() else PinUvAuthProtocolV1()

    private fun hasPin(info: Ctap2Session.InfoData): Boolean = info.options["clientPin"] == true

    private fun alwaysUv(info: Ctap2Session.InfoData): Boolean = info.options["alwaysUv"] == true

    private fun requirePin(pin: CharArray?): CharArray {
        if (pin == null || pin.isEmpty()) {
            throw SecurityKeyException(SecurityKeyError.PIN_REQUIRED, "A security key PIN is required.")
        }
        return pin
    }

    private fun parseAuthData(bytes: ByteArray): AuthenticatorData = try {
        AuthenticatorData.parseFrom(ByteBuffer.wrap(bytes))
    } catch (e: RuntimeException) {
        throw SecurityKeyException(SecurityKeyError.FAILED, "The security key returned malformed data.", e)
    }

    private fun random32(): ByteArray = ByteArray(32).also { random.nextBytes(it) }

    private inline fun <T> ctap(block: () -> T): T = try {
        block()
    } catch (e: CtapException) {
        throw e.toSecurityKeyException()
    } catch (e: CommandException) {
        throw SecurityKeyException(SecurityKeyError.FAILED, e.message ?: "Security key command failed.", e)
    }

    private fun CtapException.toSecurityKeyException(): SecurityKeyException {
        val (error, message) = when (ctapError) {
            CtapException.ERR_NO_CREDENTIALS, CtapException.ERR_INVALID_CREDENTIAL ->
                SecurityKeyError.NO_CREDENTIAL to "This security key does not hold the credential for this vault."
            CtapException.ERR_PIN_INVALID, CtapException.ERR_PIN_AUTH_INVALID ->
                SecurityKeyError.PIN_INVALID to "Incorrect security key PIN."
            CtapException.ERR_PIN_BLOCKED, CtapException.ERR_PIN_AUTH_BLOCKED, CtapException.ERR_UV_BLOCKED ->
                SecurityKeyError.PIN_BLOCKED to "The security key PIN is blocked. Unplug and reconnect the key, or reset its PIN."
            CtapException.ERR_PIN_NOT_SET ->
                SecurityKeyError.PIN_NOT_SET to "This security key has no PIN set."
            CtapException.ERR_PUAT_REQUIRED ->
                SecurityKeyError.PIN_REQUIRED to "A security key PIN is required."
            CtapException.ERR_USER_ACTION_TIMEOUT, CtapException.ERR_ACTION_TIMEOUT,
            CtapException.ERR_OPERATION_DENIED, CtapException.ERR_UP_REQUIRED ->
                SecurityKeyError.USER_ACTION to "The security key was not touched in time."
            CtapException.ERR_KEEPALIVE_CANCEL ->
                SecurityKeyError.CANCELLED to "Cancelled."
            CtapException.ERR_UNSUPPORTED_EXTENSION ->
                SecurityKeyError.UNSUPPORTED to "This security key does not support the FIDO2 hmac-secret extension."
            else ->
                SecurityKeyError.FAILED to (message ?: "Security key error.")
        }
        return SecurityKeyException(error, message, this)
    }
}
