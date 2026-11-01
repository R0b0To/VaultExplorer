package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import android.nfc.NfcAdapter
import android.os.ParcelFileDescriptor
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault
import com.aeidolon.vaultexplorer.securitykey.AssertPolicy
import com.aeidolon.vaultexplorer.securitykey.GocryptfsFido2Enrollment
import com.aeidolon.vaultexplorer.securitykey.Luks2Fido2Token
import com.aeidolon.vaultexplorer.securitykey.Luks2Fido2TokenReader
import com.aeidolon.vaultexplorer.securitykey.SecurityKeyError
import com.aeidolon.vaultexplorer.securitykey.SecurityKeyException
import com.aeidolon.vaultexplorer.securitykey.SecurityKeyService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService

/**
 * Hardware security key (FIDO2) support for the formats that have a shared,
 * interoperable scheme: gocryptfs (`-fido2`) and LUKS2 (systemd-cryptenroll's
 * `systemd-fido2` token). Cryptomator, CryFS, VeraCrypt and BitLocker have no
 * such scheme, so they are deliberately not handled here.
 *
 * This class answers "does this vault want a key?" ahead of time and turns a
 * presented key into the credential the existing unlock/create code expects.
 * The secret never leaves Kotlin: Dart only says "use the key" (plus an
 * optional PIN) and never sees the derived bytes.
 */
class SecurityKeyHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    private val service = SecurityKeyService(activity)

    /** Aborts a key wait in progress (user cancelled the unlock). */
    fun cancel() = service.cancel()

    private data class Probe(val required: Boolean, val pinRequired: Boolean)

    /**
     * Args: `filePath` (container file or vault folder URI) and `format`
     * (the Dart wire name; only gocryptfs and LUKS can be key-protected).
     * Replies `{required, pinRequired, nfcAvailable}`; anything unreadable
     * is reported as "not required" so the normal password flow stays
     * available and surfaces its own errors.
     */
    fun handleProbeSecurityKey(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val format = call.argument<String>("format") ?: ""
        if (uriString == null) {
            result.error("INVALID_ARGS", "filePath required", null)
            return
        }
        ioExecutor.execute {
            val probe = try {
                probe(Uri.parse(uriString), format)
            } catch (e: Exception) {
                VeLog.w(TAG) { "security key probe failed: ${e.message}" }
                Probe(required = false, pinRequired = false)
            }
            val nfc = NfcAdapter.getDefaultAdapter(activity) != null
            activity.runOnUiThread {
                result.success(
                    mapOf(
                        "required" to probe.required,
                        "pinRequired" to probe.pinRequired,
                        "nfcAvailable" to nfc,
                    )
                )
            }
        }
    }

    private fun probe(uri: Uri, format: String): Probe = when {
        format.startsWith("gocryptfs") -> {
            val fido2 = GocryptfsVault.readConfig(activity, uri)?.fido2
            Probe(
                required = fido2 != null,
                pinRequired = fido2 != null && AssertPolicy.fromGocryptfsOptions(fido2.assertOptions).pin,
            )
        }
        format.startsWith("luks") -> {
            val token = readLuksToken(uri)
            Probe(required = token != null, pinRequired = token?.policy?.pin == true)
        }
        else -> Probe(required = false, pinRequired = false)
    }

    private fun readLuksToken(uri: Uri): Luks2Fido2Token? {
        val pfd = activity.contentResolver.openFileDescriptor(uri, "r") ?: return null
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { Luks2Fido2TokenReader.read(it) }
    }

    /**
     * Waits for the key and returns the raw gocryptfs password bytes for the
     * vault at [uri]. BLOCKS (IO executor only). The caller zeroes the result.
     * @throws SecurityKeyException
     */
    fun resolveGocryptfsSecret(uri: Uri, pin: String?): ByteArray {
        val params = GocryptfsVault.readConfig(activity, uri)?.fido2
            ?: throw SecurityKeyException(
                SecurityKeyError.FAILED,
                "This vault isn't protected by a security key, or its gocryptfs.conf couldn't be read.",
            )
        val pinChars = pin?.takeIf { it.isNotEmpty() }?.toCharArray()
        try {
            return service.deriveGocryptfsSecret(params, pinChars)
        } finally {
            pinChars?.fill('\u0000')
        }
    }

    /**
     * Waits for the key and returns the LUKS passphrase for the container at
     * [uri] (base64 of the hmac-secret, exactly as systemd-cryptenroll
     * derives it). BLOCKS (IO executor only).
     * @throws SecurityKeyException
     */
    fun resolveLuksPassphrase(uri: Uri, pin: String?): String {
        val token = readLuksToken(uri)
            ?: throw SecurityKeyException(
                SecurityKeyError.FAILED,
                "This container has no security key (systemd-fido2) entry in its LUKS2 header.",
            )
        val pinChars = pin?.takeIf { it.isNotEmpty() }?.toCharArray()
        try {
            return service.deriveLuksPassphrase(token, pinChars)
        } finally {
            pinChars?.fill('\u0000')
        }
    }

    /** Creates a gocryptfs credential on the key. BLOCKS. The caller zeroes [GocryptfsFido2Enrollment.secret]. */
    fun enrollGocryptfs(userName: String, requirePin: Boolean, pin: String?): GocryptfsFido2Enrollment {
        val pinChars = pin?.takeIf { it.isNotEmpty() }?.toCharArray()
        try {
            return service.enrollGocryptfs(userName, requirePin, pinChars)
        } finally {
            pinChars?.fill('\u0000')
        }
    }

    private companion object {
        const val TAG = "VaultExplorer_SecurityKey"
    }
}
