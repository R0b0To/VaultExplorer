package com.aeidolon.vaultexplorer

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecureStorageHandlers(
    private val activity: MainActivity,
) {
    private val KEY_ALIAS = "vaultexplorer_app_secure_storage_key"
    private val PREFS_NAME = "vaultexplorer_app_secure_storage"

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

    private fun encrypt(plainText: String): String? {
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val key = getOrCreateMasterKey()
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val iv = cipher.iv
            val encryptedBytes = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
            val combined = ByteArray(iv.size + encryptedBytes.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(encryptedBytes, 0, combined, iv.size, encryptedBytes.size)
            Base64.encodeToString(combined, Base64.NO_WRAP)
        } catch (_: Exception) {
            null
        }
    }

    private fun decrypt(encryptedBase64: String): String? {
        return try {
            val combined = Base64.decode(encryptedBase64, Base64.NO_WRAP)
            if (combined.size <= 12) return null
            val iv = combined.copyOfRange(0, 12)
            val payload = combined.copyOfRange(12, combined.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val key = getOrCreateMasterKey()
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            val decryptedBytes = cipher.doFinal(payload)
            String(decryptedBytes, Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private val prefs by lazy {
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun handleRead(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        if (key == null) {
            result.error("INVALID_ARGS", "key required", null)
            return
        }
        val encrypted = prefs.getString(key, null)
        if (encrypted == null) {
            result.success(null)
            return
        }
        val decrypted = decrypt(encrypted)
        result.success(decrypted)
    }

    fun handleWrite(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        val value = call.argument<String>("value")
        if (key == null) {
            result.error("INVALID_ARGS", "key required", null)
            return
        }
        if (value == null) {
            handleDelete(call, result)
            return
        }
        val encrypted = encrypt(value)
        if (encrypted == null) {
            result.success(false)
            return
        }
        val ok = prefs.edit().putString(key, encrypted).commit()
        result.success(ok)
    }

    fun handleDelete(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        if (key == null) {
            result.error("INVALID_ARGS", "key required", null)
            return
        }
        val ok = prefs.edit().remove(key).commit()
        result.success(ok)
    }

    fun handleDeleteAll(call: MethodCall, result: MethodChannel.Result) {
        val ok = prefs.edit().clear().commit()
        result.success(ok)
    }

    fun handleReadAll(call: MethodCall, result: MethodChannel.Result) {
        val allEntries = prefs.all
        val resultMap = HashMap<String, String>()
        for ((key, value) in allEntries) {
            if (value is String) {
                val decrypted = decrypt(value)
                if (decrypted != null) {
                    resultMap[key] = decrypted
                }
            }
        }
        result.success(resultMap)
    }

    fun handleContainsKey(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        if (key == null) {
            result.error("INVALID_ARGS", "key required", null)
            return
        }
        result.success(prefs.contains(key))
    }
}
