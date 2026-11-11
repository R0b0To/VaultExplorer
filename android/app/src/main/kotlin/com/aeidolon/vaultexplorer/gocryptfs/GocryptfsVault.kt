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
    private const val CONFIG_FILE_NAME = "gocryptfs.conf"

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        val saf = SafDocumentOps(context)
        return saf.childOf(root, CONFIG_FILE_NAME) != null
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): VaultOpenResult<GocryptfsSession> =
        FolderVaultOpener.open(
            context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, password, null, readOnly,
        ) { handle, volRef -> GocryptfsSession(context, vaultRootUri, handle, readOnly, volRef) }

    fun create(
        context: Context,
        vaultRootUri: Uri,
        password: CharArray,
        cipher: GocryptfsCipher = GocryptfsCipher.AES_256_GCM,
        plaintextNames: Boolean = false,
        userEntropy: ByteArray? = null,
        // gocryptfs -deterministic-names: no gocryptfs.diriv files, so two devices that create the same
        // folder offline produce the same ciphertext (the right choice for a synchronised folder).
        deterministicNames: Boolean = false,
        // gocryptfs -longnamemax: 0 = default (255), otherwise 62..255.
        longNameMax: Int = 0,
    ): VaultOpenResult<GocryptfsSession> {
        // Same order as the native enum: 0 = AES-256-GCM, 1 = XChaCha20-Poly1305, 2 = AES-SIV.
        val cipherIndex = when (cipher) {
            GocryptfsCipher.AES_256_GCM -> 0
            GocryptfsCipher.XCHACHA20_POLY1305 -> 1
            GocryptfsCipher.AES_SIV -> 2
        }
        return FolderVaultOpener.create(
            context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, password,
            intArrayOf(cipherIndex, if (plaintextNames) 1 else 0, if (deterministicNames) 1 else 0, longNameMax),
            null, userEntropy,
        ) { handle, volRef -> GocryptfsSession(context, vaultRootUri, handle, false, volRef) }
    }

    fun changePassword(
        context: Context, vaultRootUri: Uri, oldPassword: CharArray, newPassword: CharArray,
    ): VaultOpenResult<Unit> =
        FolderVaultOpener.changePassword(context, vaultRootUri, NativeFolderVault.GOCRYPTFS, CONFIG_FILE_NAME, oldPassword, newPassword)
}
