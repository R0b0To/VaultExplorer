package com.aeidolon.vaultexplorer.handlers

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import java.security.UnrecoverableKeyException
import java.util.concurrent.ExecutorService
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog

/**
 * "Sentinel" keys that let the app notice when the device's biometrics change.
 *
 * Biometric unlock in the app is a `local_auth` prompt in front of credentials
 * that live in Keystore-backed storage; none of those storage keys are bound to
 * the user's biometrics, so Android has nothing to invalidate when someone
 * enrolls a new fingerprint or face. A sentinel is a Keystore AES key that
 * exists only for that purpose:
 *
 *  - it requires user authentication for every use, with BIOMETRIC_STRONG only
 *    (the part that makes Android honor the next flag), and
 *  - it is created with `setInvalidatedByBiometricEnrollment(true)`, so the OS
 *    permanently invalidates it the moment a biometric is enrolled (and when
 *    the last one is removed or the secure lock screen is disabled).
 *
 * One sentinel per biometric-protected thing (the master lock, each vault), each
 * under its own alias. They are independent on purpose: re-enabling biometrics
 * for one of them replaces only its own sentinel, so it can never make another
 * thing that was enabled before the enrollment look valid again.
 *
 * The key is never used to encrypt anything. [handleStatus] only opens a cipher
 * operation with it: for a per-use-auth key that succeeds while the key is
 * valid (the operation just waits for an authentication that never comes) and
 * throws [KeyPermanentlyInvalidatedException] once the key has been
 * invalidated. That is the check Android documents for this purpose.
 *
 * Aliases start with [ALIAS_PREFIX]; `KeystorePurge` deletes every alias this
 * app owns on a panic wipe, so they need no handling there.
 */
class BiometricKeyHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    private val androidKeyStore: KeyStore by lazy {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    }

    /** The caller's opaque [id] ("master", "vault:<uri>") is hashed so no
     *  vault location ends up readable in the alias list. */
    private fun aliasFor(id: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(id.toByteArray(Charsets.UTF_8))
        val hex = digest.joinToString("") { "%02x".format(it) }
        return ALIAS_PREFIX + hex
    }

    /**
     * Replaces any existing sentinel for [alias] with a fresh one that trusts
     * the biometrics enrolled right now. Returns false (leaving no key behind)
     * when Android refuses to create it -- typically because no biometric is
     * enrolled or there is no secure lock screen -- in which case the caller
     * must not turn biometric unlock on.
     */
    private fun createSentinel(alias: String): Boolean {
        return try {
            if (androidKeyStore.containsAlias(alias)) androidKeyStore.deleteEntry(alias)
            val builder = KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Timeout 0 = authentication for every use; BIOMETRIC_STRONG
                // alone, so a device PIN/pattern can't stand in for a biometric.
                builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
            }
            // Below API 30, requiring authentication without a validity
            // duration already means "every use" (the default is -1).
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(builder.build())
            generator.generateKey()
            true
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Could not create biometric sentinel key" }
            try {
                if (androidKeyStore.containsAlias(alias)) androidKeyStore.deleteEntry(alias)
            } catch (cleanup: Exception) {
            }
            false
        }
    }

    /**
     * One of:
     *  - [STATUS_VALID]: the key exists and no biometric change has happened since it was created;
     *  - [STATUS_INVALIDATED]: Android invalidated it (enrollment change) or it can no longer be recovered;
     *  - [STATUS_MISSING]: there is no key under that alias (never created on this device, cleared, or
     *    settings restored from a backup made elsewhere);
     *  - [STATUS_ERROR]: the Keystore could not answer. Callers refuse the current attempt but must not
     *    treat this as proof of a change.
     */
    private fun sentinelStatus(alias: String): String {
        return try {
            if (!androidKeyStore.containsAlias(alias)) return STATUS_MISSING
            val key = androidKeyStore.getKey(alias, null) as? SecretKey ?: return STATUS_MISSING
            Cipher.getInstance("AES/GCM/NoPadding").init(Cipher.ENCRYPT_MODE, key)
            STATUS_VALID
        } catch (e: KeyPermanentlyInvalidatedException) {
            STATUS_INVALIDATED
        } catch (e: UnrecoverableKeyException) {
            STATUS_INVALIDATED
        } catch (e: UserNotAuthenticatedException) {
            // Only raised for a still-usable key that needs authentication.
            STATUS_VALID
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Biometric sentinel status check failed" }
            STATUS_ERROR
        }
    }

    private fun deleteSentinel(alias: String): Boolean {
        return try {
            if (androidKeyStore.containsAlias(alias)) androidKeyStore.deleteEntry(alias)
            true
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Failed to delete biometric sentinel key" }
            false
        }
    }

    fun handleCreate(call: MethodCall, result: MethodChannel.Result) =
        runKeystore(call, result) { createSentinel(aliasFor(it)) }

    fun handleStatus(call: MethodCall, result: MethodChannel.Result) =
        runKeystore(call, result) { sentinelStatus(aliasFor(it)) }

    fun handleDelete(call: MethodCall, result: MethodChannel.Result) =
        runKeystore(call, result) { deleteSentinel(aliasFor(it)) }

    /** Keystore round trips stay off the platform thread, like the sibling
     *  derived-key handlers. */
    private fun runKeystore(call: MethodCall, result: MethodChannel.Result, block: (String) -> Any) {
        val id = call.argument<String>("id")
        if (id.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "id required", null)
            return
        }
        ioExecutor.execute {
            try {
                val value = block(id)
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("BIOMETRIC_KEY_ERROR", e.message, null) }
            }
        }
    }

    companion object {
        private const val TAG = "BiometricKeyHandlers"
        const val ALIAS_PREFIX = "ve_biometric_sentinel_"
        const val STATUS_VALID = "valid"
        const val STATUS_INVALIDATED = "invalidated"
        const val STATUS_MISSING = "missing"
        const val STATUS_ERROR = "error"
    }
}
