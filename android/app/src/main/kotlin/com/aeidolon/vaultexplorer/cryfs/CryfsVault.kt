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
    private val CONFIG_FILE_NAME: String get() = NativeFolderVault.configFileName(NativeFolderVault.CRYFS)

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        val saf = SafDocumentOps(context)
        val name = CONFIG_FILE_NAME
        return name.isNotEmpty() && saf.childOf(root, name) != null
    }

    fun open(
        context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean,
        disableSingleClientMode: Boolean = false,
    ): VaultOpenResult<CryfsSession> =
        FolderVaultOpener.open(
            context, vaultRootUri, NativeFolderVault.CRYFS, CONFIG_FILE_NAME, password, null, readOnly,
            disableSingleClientMode = disableSingleClientMode,
        ) { handle, volRef -> CryfsSession(context, vaultRootUri, handle, readOnly, volRef) }

    /** Fast path: reopen with the scrypt output a previous [open] returned as `derivedKey`. */
    fun openWithCombinedKey(
        context: Context, vaultRootUri: Uri, combinedKey: ByteArray, readOnly: Boolean,
        disableSingleClientMode: Boolean = false,
    ): VaultOpenResult<CryfsSession> =
        FolderVaultOpener.open(
            context, vaultRootUri, NativeFolderVault.CRYFS, CONFIG_FILE_NAME, null, combinedKey, readOnly,
            disableSingleClientMode = disableSingleClientMode,
        ) { handle, volRef -> CryfsSession(context, vaultRootUri, handle, readOnly, volRef) }

    fun create(
        context: Context,
        vaultRootUri: Uri,
        password: CharArray,
        // Empty cipher / 0 block size = the native defaults; anything unsupported or out of range falls back to
        // them too (cpp/foldervault/fv_formats.h, normalizeCryfsCreateOptions).
        cipher: String = "",
        blocksizeBytes: Int = 0,
        userEntropy: ByteArray? = null,
        scryptLogN: Int = 0,
    ): VaultOpenResult<CryfsSession> =
        FolderVaultOpener.create(
            context, vaultRootUri, NativeFolderVault.CRYFS, CONFIG_FILE_NAME, password,
            intArrayOf(blocksizeBytes, scryptLogN), cipher, userEntropy,
        ) { handle, volRef -> CryfsSession(context, vaultRootUri, handle, false, volRef) }

    fun changePassword(
        context: Context, vaultRootUri: Uri, oldPassword: CharArray, newPassword: CharArray,
    ): VaultOpenResult<Unit> =
        FolderVaultOpener.changePassword(context, vaultRootUri, NativeFolderVault.CRYFS, CONFIG_FILE_NAME, oldPassword, newPassword)
}
