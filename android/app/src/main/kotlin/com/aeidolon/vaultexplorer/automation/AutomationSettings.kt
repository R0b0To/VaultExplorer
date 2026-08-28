package com.aeidolon.vaultexplorer.automation

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.aeidolon.vaultexplorer.container.ContainerLifecycleCore.DirectoryVaultFormat
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keystore-backed settings for the automation broadcast receiver:
 * the shared API token, and, per vault (keyed by the same container URI
 * string ContainerSessionRegistry already keys sessions by), which tier
 * of automation is opted in and the automation-only stored password.
 *
 * Deliberately separate from SecureStorageHandlers' general-purpose
 * key-value store, which Dart can read/write by key over the
 * MethodChannel -- this file, its Keystore alias, and everything in it
 * are never exposed to the Dart layer or to any MethodChannel. The
 * automation password is also deliberately NOT the same store
 * DerivedKeyHandlers uses for the biometric-gated fast-unlock cache:
 * automation unlocks are unattended by definition, so what they can
 * reach is kept narrow and separate on purpose (see
 * ContainerLifecycleCore.unlockContainer's doc comment for the matching
 * reasoning on why hidden volumes are excluded entirely).
 *
 * Crypto approach mirrors SecureStorageHandlers (AES/GCM over an
 * AndroidKeyStore-backed key) with its own alias and prefs file, so nothing
 * here can surface through a bug in, or a future export-all feature on,
 * the general secure-storage path.
 */
object AutomationSettings {

    private const val KEY_ALIAS = "vaultexplorer_automation_key"
    private const val PREFS_NAME = "vaultexplorer_automation_settings"
    private const val PREF_TOKEN = "automation_api_token"
    private const val PREF_TIER_PREFIX = "tier:"        // + container URI -> AutomationTier.name
    private const val PREF_PASSWORD_PREFIX = "pwd:"     // + container URI -> encrypted password
    private const val PREF_KEYFILE_PREFIX = "kf:"       // + container URI -> encrypted pipe-delimited keyfile paths
    private const val PREF_PIM_PREFIX = "pim:"          // + container URI -> encrypted PIM integer
    private const val PREF_FORMAT_PREFIX = "fmt:"       // + container URI -> DirectoryVaultFormat.name; absent = standard container
    private const val PREF_CAPTURE_PREFIX = "cap:"      // + container URI -> "true" if TAKE_PHOTO/START_RECORDING are opted in

    enum class AutomationTier {
        /** Automation cannot touch this vault at all. This is the default for every vault. */
        NONE,

        /** Automation may send UNLOCK_VAULT / LOCK_VAULT for this vault. */
        LIFECYCLE,

        /** LIFECYCLE, plus IMPORT_FILE / EXPORT_FILE / IMPORT_FOLDER / EXPORT_FOLDER for this vault. */
        FULL,
    }

    private val androidKeyStore: KeyStore by lazy {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    }

    private fun getOrCreateMasterKey(): SecretKey {
        val existing = androidKeyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun encrypt(plainText: String): String? = try {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateMasterKey())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        val combined = ByteArray(iv.size + encrypted.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(encrypted, 0, combined, iv.size, encrypted.size)
        Base64.encodeToString(combined, Base64.NO_WRAP)
    } catch (_: Exception) {
        null
    }

    private fun decrypt(encryptedBase64: String): String? = try {
        val combined = Base64.decode(encryptedBase64, Base64.NO_WRAP)
        if (combined.size <= 12) {
            null
        } else {
            val iv = combined.copyOfRange(0, 12)
            val payload = combined.copyOfRange(12, combined.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateMasterKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(payload), Charsets.UTF_8)
        }
    } catch (_: Exception) {
        null
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // --- API token -----------------------------------------------------

    /** True once a token has ever been generated, i.e. automation has been turned on at least once. */
    fun isConfigured(context: Context): Boolean = prefs(context).contains(PREF_TOKEN)

    /**
     * Returns the current token, generating one on first call. A settings
     * screen should show this exactly once with a copy button plus a
     * separate, explicit "regenerate" action -- there's no legitimate
     * reason to re-display an existing token outside that one moment.
     */
    fun getOrCreateToken(context: Context): String {
        val existing = prefs(context).getString(PREF_TOKEN, null)?.let { decrypt(it) }
        return existing ?: regenerateToken(context)
    }

    fun regenerateToken(context: Context): String {
        val randomBytes = ByteArray(24)
        SecureRandom().nextBytes(randomBytes)
        val token = Base64.encodeToString(randomBytes, Base64.NO_WRAP or Base64.URL_SAFE).trimEnd('=')
        encrypt(token)?.let { prefs(context).edit().putString(PREF_TOKEN, it).commit() }
        return token
    }

    fun isTokenValid(context: Context, providedToken: String?): Boolean {
        if (providedToken.isNullOrEmpty()) return false
        val stored = prefs(context).getString(PREF_TOKEN, null)?.let { decrypt(it) } ?: return false
        return MessageDigest.isEqual(
            stored.toByteArray(Charsets.UTF_8),
            providedToken.toByteArray(Charsets.UTF_8),
        )
    }

    // --- Per-vault tier --------------------------------------------------

    fun getTier(context: Context, containerUri: String): AutomationTier {
        val raw = prefs(context).getString(PREF_TIER_PREFIX + containerUri, null) ?: return AutomationTier.NONE
        return try {
            AutomationTier.valueOf(raw)
        } catch (_: Exception) {
            AutomationTier.NONE
        }
    }

    /**
     * [format] should always be passed explicitly by a settings screen: the
     * vault's format is already known wherever it's listed on the
     * dashboard, so there's no good reason to leave this unset. Pass null
     * for a standard block-device container (VeraCrypt/LUKS/BitLocker/
     * VHD-VHDX); pass the actual format for a Cryptomator/gocryptfs/CryFS
     * vault. Setting tier to NONE clears the stored format too.
     */
    fun setTier(context: Context, containerUri: String, tier: AutomationTier, format: DirectoryVaultFormat? = null) {
        val editor = prefs(context).edit()
        if (tier == AutomationTier.NONE) {
            editor.remove(PREF_TIER_PREFIX + containerUri)
            editor.remove(PREF_FORMAT_PREFIX + containerUri)
            editor.remove(PREF_CAPTURE_PREFIX + containerUri)
        } else {
            editor.putString(PREF_TIER_PREFIX + containerUri, tier.name)
            if (format != null) {
                editor.putString(PREF_FORMAT_PREFIX + containerUri, format.name)
            } else {
                editor.remove(PREF_FORMAT_PREFIX + containerUri)
            }
            // Dropping from FULL back to LIFECYCLE also clears the capture
            // opt-in, not just NONE -- otherwise re-promoting to FULL later
            // would silently restore a camera opt-in the user never
            // re-confirmed at that moment. canCapture() below already gates
            // on tier == FULL, so this isn't needed for correctness right
            // now, but it keeps the stored state from quietly outliving the
            // decision that granted it.
            if (tier != AutomationTier.FULL) {
                editor.remove(PREF_CAPTURE_PREFIX + containerUri)
            }
        }
        editor.commit()
    }

    fun canUnlockLock(context: Context, containerUri: String): Boolean =
        getTier(context, containerUri) != AutomationTier.NONE

    fun canImportExport(context: Context, containerUri: String): Boolean =
        getTier(context, containerUri) == AutomationTier.FULL

    // --- Per-vault camera-capture opt-in -----------------------------------

    /** Whether TAKE_PHOTO / START_RECORDING are opted in for this vault. */
    fun getCaptureEnabled(context: Context, containerUri: String): Boolean =
        prefs(context).getBoolean(PREF_CAPTURE_PREFIX + containerUri, false)

    fun setCaptureEnabled(context: Context, containerUri: String, enabled: Boolean) {
        prefs(context).edit().putBoolean(PREF_CAPTURE_PREFIX + containerUri, enabled).commit()
    }

    /**
     * FULL tier alone does not grant camera capture. IMPORT_FILE/EXPORT_FILE
     * only ever touch a path the caller already named; TAKE_PHOTO and
     * START_RECORDING *generate new content* from a live camera/mic with no
     * on-screen indication at all for a still photo (no foreground-service
     * notification is needed for a capture that fast -- see
     * VaultAutomationReceiver.handleTakePhoto), which is a bigger silent-
     * capture risk than anything else this receiver can do. So capture
     * needs FULL *and* this separate, explicit switch -- the same
     * "two opt-ins for a materially bigger trust jump" reasoning already
     * used to split LIFECYCLE from FULL itself.
     */
    fun canCapture(context: Context, containerUri: String): Boolean =
        getTier(context, containerUri) == AutomationTier.FULL && getCaptureEnabled(context, containerUri)

    /** Null means "standard block-device container" -- see setTier's doc comment. */
    fun getFormat(context: Context, containerUri: String): DirectoryVaultFormat? {
        val raw = prefs(context).getString(PREF_FORMAT_PREFIX + containerUri, null) ?: return null
        return try {
            DirectoryVaultFormat.valueOf(raw)
        } catch (_: Exception) {
            null
        }
    }

    // --- Per-vault stored password ---------------------------------------

    fun getStoredPassword(context: Context, containerUri: String): String? =
        prefs(context).getString(PREF_PASSWORD_PREFIX + containerUri, null)?.let { decrypt(it) }

    fun setStoredPassword(context: Context, containerUri: String, password: String?) {
        val editor = prefs(context).edit()
        if (password.isNullOrEmpty()) {
            editor.remove(PREF_PASSWORD_PREFIX + containerUri)
        } else {
            val encrypted = encrypt(password) ?: return
            editor.putString(PREF_PASSWORD_PREFIX + containerUri, encrypted)
        }
        editor.commit()
    }

    // --- Per-vault stored keyfiles ---------------------------------------

    fun getStoredKeyfiles(context: Context, containerUri: String): List<String>? {
        val raw = prefs(context).getString(PREF_KEYFILE_PREFIX + containerUri, null)?.let { decrypt(it) }
            ?: return null
        return raw.split("|").filter { it.isNotEmpty() }
    }

    fun setStoredKeyfiles(context: Context, containerUri: String, paths: List<String>?) {
        val editor = prefs(context).edit()
        if (paths.isNullOrEmpty()) {
            editor.remove(PREF_KEYFILE_PREFIX + containerUri)
        } else {
            val encrypted = encrypt(paths.joinToString("|")) ?: return
            editor.putString(PREF_KEYFILE_PREFIX + containerUri, encrypted)
        }
        editor.commit()
    }

    // --- Per-vault stored PIM --------------------------------------------

    fun getStoredPim(context: Context, containerUri: String): Int? {
        val raw = prefs(context).getString(PREF_PIM_PREFIX + containerUri, null)?.let { decrypt(it) }
            ?: return null
        return raw.toIntOrNull()
    }

    fun setStoredPim(context: Context, containerUri: String, pim: Int?) {
        val editor = prefs(context).edit()
        if (pim == null || pim <= 0) {
            editor.remove(PREF_PIM_PREFIX + containerUri)
        } else {
            val encrypted = encrypt(pim.toString()) ?: return
            editor.putString(PREF_PIM_PREFIX + containerUri, encrypted)
        }
        editor.commit()
    }

    /** Call when a vault is removed from the app so stray automation config doesn't linger. */
    fun clearVault(context: Context, containerUri: String) {
        prefs(context).edit()
            .remove(PREF_TIER_PREFIX + containerUri)
            .remove(PREF_PASSWORD_PREFIX + containerUri)
            .remove(PREF_KEYFILE_PREFIX + containerUri)
            .remove(PREF_PIM_PREFIX + containerUri)
            .remove(PREF_FORMAT_PREFIX + containerUri)
            .remove(PREF_CAPTURE_PREFIX + containerUri)
            .apply()
    }
}
