package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.foldervault.FolderVaultOpener
import com.aeidolon.vaultexplorer.foldervault.NativeFolderVault

/**
 * Entry points for Cryptomator vaults (format 7 SIV_CTRMAC and format 8
 * SIV_GCM): probe, open, create, change password.
 *
 * The format itself (masterkey file, vault.cryptomator JWT, SIV file names,
 * .c9s shortening, GCM / CTR+HMAC content) lives in the native core
 * (cpp/foldervault/fv_cryptomator*.cpp).
 */
object CryptomatorVault {
    private const val MASTERKEY_FILE_NAME = "masterkey.cryptomator"
    const val CURRENT_VAULT_FORMAT = 8
    const val CURRENT_CIPHER_COMBO = "SIV_GCM"

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        return root.listFiles().any { it.name == MASTERKEY_FILE_NAME }
    }

    fun open(context: Context, vaultRootUri: Uri, passphrase: CharArray, readOnly: Boolean): VaultOpenResult<CryptomatorSession> =
        FolderVaultOpener.open(
            context, vaultRootUri, NativeFolderVault.CRYPTOMATOR, MASTERKEY_FILE_NAME, passphrase, null, readOnly,
        ) { handle, volRef -> CryptomatorSession(context, vaultRootUri, handle, readOnly, volRef) }

    fun create(
        context: Context,
        vaultRootUri: Uri,
        passphrase: CharArray,
        userEntropy: ByteArray? = null,
    ): VaultOpenResult<CryptomatorSession> =
        FolderVaultOpener.create(
            context, vaultRootUri, NativeFolderVault.CRYPTOMATOR, MASTERKEY_FILE_NAME, passphrase,
            IntArray(2), null, userEntropy,
        ) { handle, volRef -> CryptomatorSession(context, vaultRootUri, handle, false, volRef) }

    /** Format 7 -> 8, one way. See [FolderVaultOpener.migrateCryptomator]. */
    fun migrate(context: Context, vaultRootUri: Uri, passphrase: CharArray): VaultOpenResult<Unit> =
        FolderVaultOpener.migrateCryptomator(context, vaultRootUri, MASTERKEY_FILE_NAME, passphrase)

    fun changePassword(
        context: Context,
        vaultRootUri: Uri,
        oldPassphrase: CharArray,
        newPassphrase: CharArray,
    ): VaultOpenResult<Unit> =
        FolderVaultOpener.changePassword(context, vaultRootUri, NativeFolderVault.CRYPTOMATOR, MASTERKEY_FILE_NAME, oldPassphrase, newPassphrase)
}
