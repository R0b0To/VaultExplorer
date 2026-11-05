package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.foldervault.FolderVaultOpener
import com.aeidolon.vaultexplorer.foldervault.NativeFolderVault
import com.aeidolon.vaultexplorer.saf.SafDocumentOps

/**
 * Entry points for CryFS vaults: probe, open (password or remembered derived
 * key), create, change password.
 *
 * The format itself (cryfs.config, block store with its local integrity
 * state, blob data tree, directory blobs) lives in the native core
 * (cpp/foldervault/fv_cryfs*.cpp). The per-install integrity bookkeeping is
 * kept in filesDir/cryfs_localstate exactly as before.
 */
object CryfsVault {
    private const val CONFIG_FILE_NAME = "cryfs.config"

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        val saf = SafDocumentOps(context)
        return saf.childOf(root, CONFIG_FILE_NAME) != null
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): VaultOpenResult<CryfsSession> =
        FolderVaultOpener.open(
            context, vaultRootUri, NativeFolderVault.CRYFS, CONFIG_FILE_NAME, password, null, readOnly,
        ) { handle, volRef -> CryfsSession(context, vaultRootUri, handle, readOnly, volRef) }

    /** Fast path: reopen with the scrypt output a previous [open] returned as `derivedKey`. */
    fun openWithCombinedKey(
        context: Context, vaultRootUri: Uri, combinedKey: ByteArray, readOnly: Boolean,
    ): VaultOpenResult<CryfsSession> =
        FolderVaultOpener.open(
            context, vaultRootUri, NativeFolderVault.CRYFS, CONFIG_FILE_NAME, null, combinedKey, readOnly,
        ) { handle, volRef -> CryfsSession(context, vaultRootUri, handle, readOnly, volRef) }

    fun create(
        context: Context,
        vaultRootUri: Uri,
        password: CharArray,
        cipher: String = CryfsConfigFile.DEFAULT_BLOCK_CIPHER,
        blocksizeBytes: Int = CryfsConfigFile.DEFAULT_BLOCKSIZE,
        userEntropy: ByteArray? = null,
    ): VaultOpenResult<CryfsSession> =
        FolderVaultOpener.create(
            context, vaultRootUri, NativeFolderVault.CRYFS, CONFIG_FILE_NAME, password,
            intArrayOf(blocksizeBytes, 0), cipher, userEntropy,
        ) { handle, volRef -> CryfsSession(context, vaultRootUri, handle, false, volRef) }

    fun changePassword(
        context: Context, vaultRootUri: Uri, oldPassword: CharArray, newPassword: CharArray,
    ): VaultOpenResult<Unit> =
        FolderVaultOpener.changePassword(context, vaultRootUri, NativeFolderVault.CRYFS, CONFIG_FILE_NAME, oldPassword, newPassword)
}
