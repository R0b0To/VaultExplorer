package com.aeidolon.vaultexplorer.container

import android.content.Context
import android.util.Base64
import com.aeidolon.vaultexplorer.NativeEngine
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Read-only access, from the SAF pipeline, to the on-disk `appCache` tier
 * the Dart-side `ThumbnailCacheService` already maintains.
 *
 * Previously the SAF pipeline (`ContainerDocumentsProvider`) had no cache
 * of its own and no way to reach Dart's -- it fully re-decrypted,
 * re-decoded, and re-compressed on every single request, even for a file
 * the user had just viewed in-app a moment earlier.
 *
 * This is intentionally **read-only**: it never writes into Dart's cache
 * directory. Two different language runtimes writing into the same
 * AES-GCM-encrypted files without coordinating would need real concurrency
 * design (partial writes, key-rotation timing, etc.); reading what's
 * already there safely needs none of that, and it's where nearly all the
 * value is anyway -- the common case this helps is "the user already
 * looked at this file in-app," not "an external app is the first ever
 * viewer." If Dart hasn't cached this file (or hasn't run yet on a fresh
 * install), every lookup here is just a cache miss and the SAF pipeline
 * falls back to its normal full-generation path exactly as before.
 *
 * Also intentionally simplified: Dart's own lookup tries a quality-
 * qualified key first and falls back to a quality-agnostic "base" key
 * (`md5(filePath)`, with no size/quality suffix) that `put()` always keeps
 * up to date regardless of which quality was active when it was written
 * (see `ThumbnailCacheService._putInternal`'s `file.copy(baseFile.path)`).
 * This only ever checks that base key -- it deliberately doesn't try to
 * learn the user's current in-app `ThumbnailQuality` setting, since the
 * base key alone already covers "was this file cached at all," which is
 * the only question that matters here.
 *
 * Every step below fails soft: a missing key, a missing file, a corrupt
 * blob, or an AES-GCM authentication-tag mismatch (e.g. from a path/key
 * assumption that doesn't quite match Dart's) all just return `null`, the
 * same as a normal cache miss -- never an exception, never wrong bytes,
 * since GCM's own tag verification rejects anything that doesn't decrypt
 * to exactly what was encrypted under this exact key.
 */
object SafThumbnailCache {

    // Mirrors AppSecureStorage/SecureStorageHandlers.kt exactly -- same
    // SharedPreferences file, same entry key, same AndroidKeyStore alias
    // and AES-GCM scheme, so this reads the identical key Dart already
    // generated and persisted. Duplicated rather than shared because
    // SecureStorageHandlers is constructed with a MainActivity, which
    // this ContentProvider-context caller doesn't have and shouldn't need.
    private const val SECURE_PREFS_NAME = "vaultexplorer_app_secure_storage"
    private const val SECURE_PREFS_KEY_ALIAS = "vaultexplorer_app_secure_storage_key"
    private const val APP_CACHE_KEY_PREF_NAME = "app_cache_aes_key"

    private const val GCM_NONCE_SIZE = 12
    private const val GCM_TAG_SIZE = 16

    /** Returns the cached, already-thumbnail-sized JPEG bytes for
     * [virtualPath] in container [volId], or null on any miss/failure. */
    fun tryRead(context: Context, volId: Int, virtualPath: String): ByteArray? {
        return try {
            val containerUri = ContainerSessionRegistry.activeSessions[volId]?.uri ?: return null
            val appCacheKey = readAppCacheKey(context) ?: return null

            val dirName = md5Hex(containerUri)
            val fileName = md5Hex(virtualPath)
            val file = File(File(File(context.cacheDir, "thumbs"), dirName), fileName)
            if (!file.isFile) return null

            val raw = file.readBytes()
            if (raw.size <= GCM_NONCE_SIZE + GCM_TAG_SIZE) return null

            val iv = raw.copyOfRange(0, GCM_NONCE_SIZE)
            val ciphertextAndTag = raw.copyOfRange(GCM_NONCE_SIZE, raw.size)
            val plaintext = NativeEngine.aesGcmDecryptNative(appCacheKey, iv, null, ciphertextAndTag)
                ?: return null

            if (!isJpegSignature(plaintext)) return null
            plaintext
        } catch (e: Exception) {
            null
        }
    }

    // internal (not private) so JVM unit tests can exercise this pure,
    // native-free logic directly -- see SafThumbnailCacheTest. tryRead()
    // itself isn't unit-testable in a plain JVM/Robolectric run: it calls
    // NativeEngine.aesGcmDecryptNative, a genuine JNI binding to the
    // compiled C++ library, which only loads on a real device/emulator
    // (or an instrumented test), not in a desktop JVM test process --
    // NativeEngine's own init{} block already anticipates this
    // (UnsatisfiedLinkError -> "Ignore for desktop JVM unit tests"). The
    // fail-soft-to-null design on every step of tryRead() means a broken
    // key/native call just produces a permanent cache miss, never a crash
    // or wrong data, regardless of what unit tests can reach -- but the
    // end-to-end integration (in-app cache write -> SAF read hits it)
    // still needs verifying by hand on a device before relying on it.
    internal fun isJpegSignature(bytes: ByteArray): Boolean =
        bytes.size >= 3 &&
            (bytes[0].toInt() and 0xFF) == 0xFF &&
            (bytes[1].toInt() and 0xFF) == 0xD8 &&
            (bytes[2].toInt() and 0xFF) == 0xFF

    internal fun md5Hex(value: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(value.toByteArray(Charsets.UTF_8))
        val sb = StringBuilder(digest.size * 2)
        for (b in digest) sb.append(String.format("%02x", b))
        return sb.toString()
    }

    /** Reads and decrypts the 32-byte app-cache AES key Dart generated via
     * AppCacheEncryption.getEncryptionKey(), or null if it doesn't exist
     * yet (nothing has ever been written to the appCache tier) or can't be
     * read for any reason. */
    private fun readAppCacheKey(context: Context): ByteArray? {
        val prefs = context.getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE)
        val encryptedBase64 = prefs.getString(APP_CACHE_KEY_PREF_NAME, null) ?: return null

        val decryptedBase64 = decryptSecurePrefsValue(encryptedBase64) ?: return null
        return try {
            Base64.decode(decryptedBase64, Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }

    private fun decryptSecurePrefsValue(encryptedBase64: String): String? {
        return try {
            val combined = Base64.decode(encryptedBase64, Base64.NO_WRAP)
            if (combined.size <= GCM_NONCE_SIZE) return null
            val iv = combined.copyOfRange(0, GCM_NONCE_SIZE)
            val payload = combined.copyOfRange(GCM_NONCE_SIZE, combined.size)

            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val entry = keyStore.getEntry(SECURE_PREFS_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
                ?: return null
            val key: SecretKey = entry.secretKey

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            val decryptedBytes = cipher.doFinal(payload)
            String(decryptedBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }
}
