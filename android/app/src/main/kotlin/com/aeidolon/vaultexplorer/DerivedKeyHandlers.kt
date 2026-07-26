package com.aeidolon.vaultexplorer

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

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

    /** Called cross-domain by [VaultUnlockHandlers] and [UsbContainerHandlers]
     *  right after a successful unlock when the caller asked to cache the
     *  freshly-derived key, in addition to being exposed as its own
     *  MethodChannel call ([handleStoreDerivedKey]). */
    fun storeDerivedKeyBytes(filePath: String, derivedKey: ByteArray): Boolean {
        val alias = derivedKeyAlias(filePath)
        Log.i("VaultExplorer_C++", "Storing derived key for ${filePath} (${derivedKey.size} bytes)")
        val encrypted = encryptDerivedKey(derivedKey, alias) ?: return false
        val encoded = android.util.Base64.encodeToString(encrypted, android.util.Base64.NO_WRAP)
        activity.getSharedPreferences("vc2_derived_keys", Context.MODE_PRIVATE)
            .edit()
            .putString(alias, encoded)
            .apply()
        return true
    }

    private fun loadDerivedKeyBytes(filePath: String): ByteArray? {
        val alias = derivedKeyAlias(filePath)
        val encoded = activity.getSharedPreferences("vc2_derived_keys", Context.MODE_PRIVATE)
            .getString(alias, null) ?: return null
        val encrypted = android.util.Base64.decode(encoded, android.util.Base64.NO_WRAP)
        val decrypted = decryptDerivedKey(encrypted, alias)
        if (decrypted != null) {
            Log.i("VaultExplorer_C++", "Loaded derived key for ${filePath} from Keystore-backed storage (${decrypted.size} bytes)")
        }
        return decrypted
    }

    private fun clearDerivedKeyBytes(filePath: String): Boolean {
        return activity.getSharedPreferences("vc2_derived_keys", Context.MODE_PRIVATE)
            .edit()
            .remove(derivedKeyAlias(filePath))
            .commit()
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
        result.success(clearDerivedKeyBytes(filePath))
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
}