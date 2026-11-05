package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.foldervault.FolderVaultOpener
import com.aeidolon.vaultexplorer.foldervault.NativeFolderVault
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import org.json.JSONArray
import org.json.JSONObject
import java.util.Base64

/**
 * Entry points for gocryptfs vaults: probe, open, create, change password.
 *
 * The format itself (config + scrypt/HKDF, EME file names, AES-256-GCM /
 * XChaCha20-Poly1305 / AES-SIV content, long names) lives in the native core
 * (cpp/foldervault/fv_gocryptfs*.cpp); [FolderVaultOpener] decides where the
 * vault's files are read from.
 */
object GocryptfsVault {
    private const val TAG = "GocryptfsVault"
    private const val CONFIG_FILE_NAME = "gocryptfs.conf"

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        val saf = SafDocumentOps(context)
        return saf.childOf(root, CONFIG_FILE_NAME) != null
    }

    /**
     * The parsed gocryptfs.conf, or null when it is missing, unreadable or
     * malformed. Used to find out BEFORE unlocking whether the vault wants a
     * password or a FIDO2 security key ([GocryptfsConfig.fido2]).
     */
    fun readConfig(context: Context, vaultRootUri: Uri): GocryptfsConfig? {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri) ?: return null
        val bytes = try {
            val configDoc = SafDocumentOps(context).childOf(root, CONFIG_FILE_NAME) ?: return null
            context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
        } catch (_: Exception) {
            null
        } ?: return null
        return try {
            GocryptfsConfig.parse(bytes)
        } catch (_: GocryptfsConfigException) {
            null
        }
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): VaultOpenResult<GocryptfsSession> {
        // A password can never open a security-key vault; say so instead of reporting "wrong password".
        if (readConfig(context, vaultRootUri)?.fido2 != null) {
            VeLog.e(TAG) { "open failed: vault needs a security key but a password was supplied" }
            return VaultOpenResult.InvalidVault(
                "This vault is protected by a security key. Unlock it with the key instead of a password."
            )
        }
        return FolderVaultOpener.open(
            context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, password, null, readOnly,
        ) { handle, volRef -> GocryptfsSession(context, vaultRootUri, handle, readOnly, volRef) }
    }

    /**
     * Opens a FIDO2-protected vault with the hmac-secret output obtained from
     * the security key. [secret] is the raw 32 bytes as upstream feeds them to
     * scrypt (the core receives them untouched -- no UTF-8 step); the caller
     * keeps ownership and should zero it afterwards.
     */
    fun openWithSecret(context: Context, vaultRootUri: Uri, secret: ByteArray, readOnly: Boolean): VaultOpenResult<GocryptfsSession> {
        if (readConfig(context, vaultRootUri)?.fido2 == null) {
            return VaultOpenResult.InvalidVault("This vault is not protected by a security key.")
        }
        return FolderVaultOpener.open(
            context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, null, null, readOnly, secret,
        ) { handle, volRef -> GocryptfsSession(context, vaultRootUri, handle, readOnly, volRef) }
    }

    fun create(
        context: Context,
        vaultRootUri: Uri,
        password: CharArray,
        cipher: GocryptfsCipher = GocryptfsCipher.AES_256_GCM,
        plaintextNames: Boolean = false,
        userEntropy: ByteArray? = null,
        // Security-key vault (`gocryptfs -init -fido2`): [rawSecret] is the hmac-secret output used
        // INSTEAD of [password], and [fido2] is recorded in gocryptfs.conf. The caller keeps ownership
        // of [rawSecret] and zeroes it.
        rawSecret: ByteArray? = null,
        fido2: GocryptfsFido2Params? = null,
    ): VaultOpenResult<GocryptfsSession> {
        // Same order as the native enum: 0 = AES-256-GCM, 1 = XChaCha20-Poly1305, 2 = AES-SIV.
        val cipherIndex = when (cipher) {
            GocryptfsCipher.AES_256_GCM -> 0
            GocryptfsCipher.XCHACHA20_POLY1305 -> 1
            GocryptfsCipher.AES_SIV -> 2
        }
        return FolderVaultOpener.create(
            context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, password,
            intArrayOf(cipherIndex, if (plaintextNames) 1 else 0), null, userEntropy,
            rawSecret = rawSecret, fido2Json = fido2?.let { fido2Json(it) },
        ) { handle, volRef -> GocryptfsSession(context, vaultRootUri, handle, false, volRef) }
    }

    /** The `FIDO2` object as the native core reads it (same field names upstream gocryptfs writes). */
    private fun fido2Json(p: GocryptfsFido2Params): String = JSONObject().apply {
        put("CredentialID", Base64.getEncoder().encodeToString(p.credentialId))
        put("HMACSalt", Base64.getEncoder().encodeToString(p.hmacSalt))
        if (p.assertOptions.isNotEmpty()) put("AssertOptions", JSONArray(p.assertOptions))
    }.toString()

    /** Refused for a security-key vault: there is no password to change (same as upstream gocryptfs). */
    fun changePassword(
        context: Context, vaultRootUri: Uri, oldPassword: CharArray, newPassword: CharArray,
    ): VaultOpenResult<Unit> =
        FolderVaultOpener.changePassword(context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, oldPassword, newPassword)
}
