package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.foldervault.FolderVaultOpener
import com.aeidolon.vaultexplorer.foldervault.NativeFolderVault
import com.aeidolon.vaultexplorer.saf.SafDocumentOps

/**
 * Entry points for gocryptfs vaults: probe, open, create, change password.
 *
 * The format itself (config + scrypt/HKDF, EME file names, AES-256-GCM /
 * XChaCha20-Poly1305 / AES-SIV content, long names) lives in the native core
 * (cpp/foldervault/fv_gocryptfs*.cpp); [FolderVaultOpener] decides where the
 * vault's files are read from.
 */
object GocryptfsVault {
    private val CONFIG_FILE_NAME: String get() = NativeFolderVault.configFileName(NativeFolderVault.GOCRYPTFS)

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        val saf = SafDocumentOps(context)
        val name = CONFIG_FILE_NAME
        return name.isNotEmpty() && saf.childOf(root, name) != null
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): VaultOpenResult<GocryptfsSession> =
        FolderVaultOpener.open(
            context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, password, null, readOnly,
        ) { handle, volRef -> GocryptfsSession(context, vaultRootUri, handle, readOnly, volRef) }

    fun create(
        context: Context,
        vaultRootUri: Uri,
        password: CharArray,
        // "aes-256-gcm", "xchacha20-poly1305" or "aes-siv"; anything else (or empty) = the native default, AES-256-GCM.
        cipher: String = "",
        plaintextNames: Boolean = false,
        userEntropy: ByteArray? = null,
        // gocryptfs -deterministic-names: no gocryptfs.diriv files, so two devices that create the same
        // folder offline produce the same ciphertext (the right choice for a synchronised folder).
        deterministicNames: Boolean = false,
        // gocryptfs -longnamemax: 0 = default (255), otherwise 62..255.
        longNameMax: Int = 0,
    ): VaultOpenResult<GocryptfsSession> {
        return FolderVaultOpener.create(
            context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, password,
            intArrayOf(0, if (plaintextNames) 1 else 0, if (deterministicNames) 1 else 0, longNameMax),
            cipher, userEntropy,
        ) { handle, volRef -> GocryptfsSession(context, vaultRootUri, handle, false, volRef) }
    }

    fun changePassword(
        context: Context, vaultRootUri: Uri, oldPassword: CharArray, newPassword: CharArray,
    ): VaultOpenResult<Unit> =
        FolderVaultOpener.changePassword(context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, oldPassword, newPassword)
}
