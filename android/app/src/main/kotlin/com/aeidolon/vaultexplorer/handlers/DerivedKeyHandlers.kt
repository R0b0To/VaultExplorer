package com.aeidolon.vaultexplorer.handlers

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import com.aeidolon.vaultexplorer.container.ContainerEngine
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.VeLog

/**
 * The Keystore-backed "remembered password" feature: derives a container's
 * raw key material once via [ContainerEngine.deriveKeyMaterial] (or an
 * unlock call caches it directly), then encrypts and stores it under an
 * AndroidKeyStore-backed AES key so a later unlock can skip password entry
 * (and, for VeraCrypt/LUKS, skip the expensive PBKDF2/Argon2id run). Also
 * hosts the plain PBKDF2 password-hashing call used by the Dart-side
 * "remember this password" verification flow.
 *
 * The storage key is derived from a content-hash fingerprint of the
 * container file itself (falling back to a hash of the path string), not
 * the path, so a renamed/moved container still finds its cached key.
 *
 * A cached key can optionally be given a lifetime: an absolute expiry the
 * user sets per container (see [DerivedKeyExpiryStore]). Once it has passed
 * the key is removed -- from the prefs file and from the AndroidKeyStore --
 * either the next time it would be loaded ([loadDerivedKeyBytes]) or during
 * the sweep the app runs on launch ([purgeExpiredKeys]), whichever is first.
 *
 * Holds [activity] rather than a pre-resolved Context/ContentResolver
 * snapshot; see [NativeOpSupport]'s doc comment for why.
 */
class DerivedKeyHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    /** Marker/config file names checked, in order, when [filePath] turns out
     *  to be a folder-vault tree URI rather than a single document. Their
     *  contents are small and unique per vault (they embed the KDF salt
     *  and/or wrapped keys), so hashing them gives folder vaults the same
     *  "survives rename/move" fingerprinting that single-file containers get
     *  from hashing their own header bytes. */
    private val FOLDER_VAULT_MARKER_FILES = listOf(
        "cryfs.config",       // CryFS
        "gocryptfs.conf",     // gocryptfs
        "vault.cryptomator",  // Cryptomator (legacy vault format marker)
        "masterkey.cryptomator",
    )

    private fun folderVaultFingerprint(treeUri: Uri): String? {
        return try {
            val root = androidx.documentfile.provider.DocumentFile.fromTreeUri(activity, treeUri) ?: return null
            val saf = com.aeidolon.vaultexplorer.saf.SafDocumentOps(activity)
            for (markerName in FOLDER_VAULT_MARKER_FILES) {
                val markerDoc = saf.childOf(root, markerName) ?: continue
                return activity.contentResolver.openInputStream(markerDoc.uri)?.use { stream ->
                    val digest = MessageDigest.getInstance("SHA-256")
                    val buffer = ByteArray(8192)
                    while (true) {
                        val read = stream.read(buffer)
                        if (read <= 0) break
                        digest.update(buffer, 0, read)
                    }
                    android.util.Base64.encodeToString(digest.digest(), android.util.Base64.NO_WRAP)
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun containerFingerprint(filePath: String): String? {
        return try {
            val uri = Uri.parse(filePath)
            if (android.provider.DocumentsContract.isTreeUri(uri)) {
                return folderVaultFingerprint(uri)
            }
            when (uri.scheme) {
                "content" -> {
                    activity.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                        val digest = MessageDigest.getInstance("SHA-256")
                        val buffer = ByteArray(8192)
                        var totalRead = 0
                        ParcelFileDescriptor.AutoCloseInputStream(pfd).use { stream ->
                            while (true) {
                                val read = stream.read(buffer)
                                if (read <= 0) break
                                digest.update(buffer, 0, read)
                                totalRead += read
                                if (totalRead >= 8192) break
                            }
                        }
                        android.util.Base64.encodeToString(digest.digest(), android.util.Base64.NO_WRAP)
                    }
                }
                "file" -> {
                    val file = java.io.File(uri.path ?: return null)
                    file.inputStream().use { stream ->
                        val digest = MessageDigest.getInstance("SHA-256")
                        val buffer = ByteArray(8192)
                        var totalRead = 0
                        while (true) {
                            val read = stream.read(buffer)
                            if (read <= 0) break
                            digest.update(buffer, 0, read)
                            totalRead += read
                            if (totalRead >= 8192) break
                        }
                        android.util.Base64.encodeToString(digest.digest(), android.util.Base64.NO_WRAP)
                    }
                }
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun derivedKeyAlias(filePath: String): String {
        val root = containerFingerprint(filePath)
            ?: android.util.Base64.encodeToString(
                MessageDigest.getInstance("SHA-256").digest(filePath.toByteArray(Charsets.UTF_8)),
                android.util.Base64.NO_WRAP,
            )
        return "vc2_derived_${root}"
    }

    private val androidKeyStore: KeyStore by lazy {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    }

    /** Same file `StorageShredder` / `PanicPurgeRegistry` clear on a panic
     *  wipe, so blobs and their expiry bookkeeping go together. */
    private val derivedPrefs by lazy {
        activity.getSharedPreferences(DERIVED_KEYS_PREFS, Context.MODE_PRIVATE)
    }

    private val expiry by lazy { DerivedKeyExpiryStore(derivedPrefs) }

    private fun getOrCreateDerivedKey(alias: String): SecretKey {
        val existing = androidKeyStore.getEntry(alias, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun encryptDerivedKey(plain: ByteArray, alias: String): ByteArray? {
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val key = getOrCreateDerivedKey(alias)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val iv = cipher.iv
            val encrypted = cipher.doFinal(plain)
            val out = ByteArray(iv.size + encrypted.size)
            System.arraycopy(iv, 0, out, 0, iv.size)
            System.arraycopy(encrypted, 0, out, iv.size, encrypted.size)
            out
        } catch (_: Exception) {
            null
        }
    }

    private fun decryptDerivedKey(blob: ByteArray, alias: String): ByteArray? {
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val key = getOrCreateDerivedKey(alias)
            val iv = blob.copyOfRange(0, 12)
            val payload = blob.copyOfRange(12, blob.size)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            cipher.doFinal(payload)
        } catch (_: Exception) {
            null
        }
    }

    fun handleGetAvifInfo(call: MethodCall, result: MethodChannel.Result) {
        val avifBytes = call.argument<ByteArray>("avifBytes")
        if (avifBytes == null || avifBytes.isEmpty()) {
            result.error("INVALID_ARGS", "avifBytes required", null)
            return
        }
        ioExecutor.execute {
            try {
                val info = NativeEngine.getAvifInfoNative(avifBytes)
                activity.runOnUiThread {
                    if (info != null) result.success(info)
                    else result.error("AVIF_ERROR", "Failed to parse AVIF info", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleDecodeAvifFrame(call: MethodCall, result: MethodChannel.Result) {
        val avifBytes = call.argument<ByteArray>("avifBytes")
        val frameIndex = call.argument<Int>("frameIndex") ?: 0
        if (avifBytes == null || avifBytes.isEmpty()) {
            result.error("INVALID_ARGS", "avifBytes required", null)
            return
        }
        ioExecutor.execute {
            try {
                val frameMap = NativeEngine.decodeAvifFrameNative(avifBytes, frameIndex)
                activity.runOnUiThread {
                    if (frameMap != null) result.success(frameMap)
                    else result.error("AVIF_ERROR", "Failed to decode AVIF frame $frameIndex", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleDecodeAvif(call: MethodCall, result: MethodChannel.Result) {
        val avifBytes = call.argument<ByteArray>("avifBytes")
        if (avifBytes == null || avifBytes.isEmpty()) {
            result.error("INVALID_ARGS", "avifBytes required", null)
            return
        }
        ioExecutor.execute {
            try {
                val decoded = NativeEngine.decodeAvifNative(avifBytes)
                activity.runOnUiThread {
                    if (decoded != null) result.success(decoded)
                    else result.error("AVIF_ERROR", "Failed to decode AVIF", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    /** Called cross-domain by [VaultUnlockHandlers] and [UsbContainerHandlers]
     *  right after a successful unlock when the caller asked to cache the
     *  freshly-derived key, in addition to being exposed as its own
     *  MethodChannel call ([handleStoreDerivedKey]). */
    fun storeDerivedKeyBytes(filePath: String, derivedKey: ByteArray): Boolean {
        val alias = derivedKeyAlias(filePath)
        VeLog.i("VaultExplorer_C++") { "Storing derived key" }
        val encrypted = encryptDerivedKey(derivedKey, alias) ?: return false
        val encoded = android.util.Base64.encodeToString(encrypted, android.util.Base64.NO_WRAP)
        val editor = derivedPrefs.edit().putString(alias, encoded)
        expiry.recordStored(editor, filePath, alias)
        editor.apply()
        return true
    }

    private fun loadDerivedKeyBytes(filePath: String): ByteArray? {
        // An expired key is removed instead of returned, so a stale cache can
        // never unlock a vault even if the launch-time sweep has not run yet.
        if (purgeIfExpired(filePath)) return null
        val alias = derivedKeyAlias(filePath)
        val encoded = derivedPrefs.getString(alias, null) ?: return null
        val encrypted = android.util.Base64.decode(encoded, android.util.Base64.NO_WRAP)
        val decrypted = decryptDerivedKey(encrypted, alias)
        if (decrypted != null) {
            VeLog.i("VaultExplorer_C++") { "Loaded derived key from Keystore-backed storage" }
        }
        return decrypted
    }

    /**
     * Drops the cached blob for [filePath]. The configured expiry survives by
     * default: this is also what runs when a cached key turns out to be stale
     * (wrong after a password change), and that must not silently turn a
     * "remove after 7 days" vault into "keep forever". Pass [removeExpiry]
     * when the vault itself goes away or caching is being switched off, which
     * also deletes the now-useless AndroidKeyStore entry.
     */
    private fun clearDerivedKeyBytes(filePath: String, removeExpiry: Boolean = false): Boolean {
        val alias = derivedKeyAlias(filePath)
        val ok = derivedPrefs.edit().remove(alias).commit()
        if (removeExpiry) {
            deleteKeystoreAlias(alias)
            expiry.forget(filePath)
        }
        return ok
    }

    private fun deleteKeystoreAlias(alias: String) {
        try {
            if (androidKeyStore.containsAlias(alias)) androidKeyStore.deleteEntry(alias)
        } catch (e: Exception) {
            VeLog.w("VaultExplorer_C++", e) { "Failed to delete derived-key Keystore alias" }
        }
    }

    /** Removes one expired cache: blob, Keystore entry and (unless
     *  [keepExpiry], see [DerivedKeyExpiryStore.markPurged]) expiry state. */
    private fun purge(due: DerivedKeyExpiryStore.Due, keepExpiry: Boolean = false) {
        val alias = due.alias ?: due.path?.let { derivedKeyAlias(it) }
        if (alias != null) deleteKeystoreAlias(alias)
        expiry.markPurged(due, alias, keepExpiry)
        VeLog.i("VaultExplorer_C++") { "Cached derived key reached its lifetime and was removed" }
    }

    /** Unlock-path purge. Keeps the elapsed expiry so that a key cached
     *  again later in this session is removed again rather than living on;
     *  the next launch sweep clears it for good. */
    private fun purgeIfExpired(filePath: String): Boolean {
        val due = expiry.dueFor(filePath) ?: return false
        purge(due, keepExpiry = true)
        return true
    }

    /**
     * Launch-time sweep: removes every cached key whose lifetime has run
     * out, without needing access to any container file. Returns the paths
     * (as originally passed to store/load) of every vault purged since the
     * last call -- including ones [loadDerivedKeyBytes] purged mid-session --
     * so the Dart side can switch key caching off for them.
     */
    fun purgeExpiredKeys(): List<String> {
        for (due in expiry.due()) purge(due)
        return expiry.takePurgedPaths()
    }

    fun handleDeriveDerivedKey(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        val password = call.argument<String>("password")
        val pim = call.argument<Number>("pim")?.toInt() ?: 0
        val cipherId = call.argument<Number>("cipherId")?.toInt() ?: 255
        val hashId = call.argument<Number>("hashId")?.toInt() ?: 255
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")

        if (filePath == null || password == null) {
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }

        ioExecutor.execute {
            var pfd: ParcelFileDescriptor? = null
            try {
                pfd = activity.contentResolver.openFileDescriptor(Uri.parse(filePath), "r")
                    ?: throw Exception("Could not open file descriptor")
                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)
                val fd = pfd.detachFd()
                val derived = ContainerEngine.deriveKeyMaterial(fd, password, pim, cipherId, hashId, keyfileFds)
                val encoded = derived?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
                activity.runOnUiThread { result.success(encoded) }
            } catch (e: Exception) {
                try { pfd?.close() } catch (_: Exception) {}
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleStoreDerivedKey(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        val derivedKeyBase64 = call.argument<String>("derivedKey")
        val derived = derivedKeyBase64?.let { Base64.decode(it, Base64.NO_WRAP) }
        if (filePath == null || derived == null) {
            result.success(false)
            return
        }
        result.success(storeDerivedKeyBytes(filePath, derived))
    }

    fun handleLoadDerivedKey(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath == null) {
            result.success(null)
            return
        }
        val derivedKey = loadDerivedKeyBytes(filePath)
        result.success(derivedKey?.let { Base64.encodeToString(it, Base64.NO_WRAP) })
    }

    fun handleClearDerivedKey(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath == null) {
            result.success(false)
            return
        }
        val removeExpiry = call.argument<Boolean>("removeExpiry") ?: false
        result.success(clearDerivedKeyBytes(filePath, removeExpiry))
    }

    /** Sets (or, with no `expiresAtMs`, removes) the lifetime of [filePath]'s
     *  cached key. Off the main thread because finding the blob's alias for
     *  the mapping can read the container header. */
    fun handleSetDerivedKeyExpiry(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath == null) {
            result.error("INVALID_ARGS", "filePath required", null)
            return
        }
        val expiresAtMs = call.argument<Number>("expiresAtMs")?.toLong()
        ioExecutor.execute {
            try {
                val blobAlias = if (expiresAtMs != null) {
                    derivedKeyAlias(filePath).takeIf { derivedPrefs.contains(it) }
                } else {
                    null
                }
                expiry.setExpiry(filePath, expiresAtMs, blobAlias)
                activity.runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleGetDerivedKeyExpiry(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath == null) {
            result.success(null)
            return
        }
        result.success(expiry.expiryOf(filePath))
    }

    fun handlePurgeExpiredDerivedKeys(@Suppress("UNUSED_PARAMETER") call: MethodCall, result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val purged = purgeExpiredKeys()
                activity.runOnUiThread { result.success(purged) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleHashPassword(call: MethodCall, result: MethodChannel.Result) {
        val password   = call.argument<String>("password")
        val saltBytes  = call.argument<ByteArray>("salt")
        val iterations = call.argument<Int>("iterations") ?: 200_000

        if (password == null || saltBytes == null || saltBytes.isEmpty()) {
            result.error("INVALID_ARGS", "password and non-empty salt required", null)
            return
        }

        ioExecutor.execute {
            try {
                val hash = ContainerEngine.hashPassword(password, saltBytes, iterations)
                activity.runOnUiThread {
                    if (hash != null) result.success(hash)
                    else result.error("KDF_FAILED", "PBKDF2 derivation failed", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleHashPasswordSha256(call: MethodCall, result: MethodChannel.Result) {
        val password   = call.argument<String>("password")
        val saltBytes  = call.argument<ByteArray>("salt")
        val iterations = call.argument<Int>("iterations") ?: 50_000
        val outputLen  = call.argument<Int>("outputLen") ?: 32

        if (password == null || saltBytes == null || saltBytes.isEmpty()) {
            result.error("INVALID_ARGS", "password and non-empty salt required", null)
            return
        }

        ioExecutor.execute {
            try {
                val hash = NativeEngine.hashPasswordSha256Native(password, saltBytes, iterations, outputLen)
                activity.runOnUiThread {
                    if (hash != null) result.success(hash)
                    else result.error("KDF_FAILED", "PBKDF2 SHA-256 derivation failed", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleAesGcmEncrypt(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<ByteArray>("key")
        val iv = call.argument<ByteArray>("iv")
        val aad = call.argument<ByteArray>("aad")
        val plaintext = call.argument<ByteArray>("plaintext")

        if (key == null || iv == null || plaintext == null) {
            result.error("INVALID_ARGS", "key, iv, and plaintext required", null)
            return
        }

        ioExecutor.execute {
            try {
                val encrypted = NativeEngine.aesGcmEncryptNative(key, iv, aad, plaintext)
                activity.runOnUiThread {
                    if (encrypted != null) result.success(encrypted)
                    else result.error("CRYPTO_FAILED", "AES-GCM encryption failed", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleAesGcmDecrypt(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<ByteArray>("key")
        val iv = call.argument<ByteArray>("iv")
        val aad = call.argument<ByteArray>("aad")
        val ciphertextAndTag = call.argument<ByteArray>("ciphertextAndTag")

        if (key == null || iv == null || ciphertextAndTag == null) {
            result.error("INVALID_ARGS", "key, iv, and ciphertextAndTag required", null)
            return
        }

        ioExecutor.execute {
            try {
                val decrypted = NativeEngine.aesGcmDecryptNative(key, iv, aad, ciphertextAndTag)
                activity.runOnUiThread {
                    if (decrypted != null) result.success(decrypted)
                    else result.error("CRYPTO_FAILED", "AES-GCM decryption failed", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    private companion object {
        const val DERIVED_KEYS_PREFS = "vc2_derived_keys"
    }
}
