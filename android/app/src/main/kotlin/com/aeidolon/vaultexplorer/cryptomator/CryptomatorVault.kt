package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import java.security.SecureRandom
import java.util.UUID

sealed class CryptomatorOpenResult {
    data class Success(val session: CryptomatorSession, val vaultDisplayName: String) : CryptomatorOpenResult()
    object WrongPassword : CryptomatorOpenResult()
    data class InvalidVault(val reason: String) : CryptomatorOpenResult()
}

/**
 * Entry point mirroring VeraCryptEngine.unlockFile/create — opens or creates
 * a Cryptomator vault rooted at a SAF tree Uri (the folder containing
 * vault.cryptomator + masterkey.cryptomator + d/), given the user's
 * passphrase.
 */
object CryptomatorVault {

    private const val VAULT_FILE_NAME = "vault.cryptomator"
    private const val MASTERKEY_FILE_NAME = "masterkey.cryptomator"
    private const val DATA_DIR_NAME = "d"
    private const val ROOT_DIR_ID = ""
    private const val DEFAULT_SHORTENING_THRESHOLD = 220
    const val CURRENT_VAULT_FORMAT = 8
    const val CURRENT_CIPHER_COMBO = "SIV_GCM"

    /** Quick, cheap check the user picked a folder that looks like a Cryptomator vault (used right after ACTION_OPEN_DOCUMENT_TREE returns, before asking for a password). */
    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        val hasMasterkey = root.listFiles().any { it.name == MASTERKEY_FILE_NAME }
        return hasMasterkey
    }

    fun open(context: Context, vaultRootUri: Uri, passphrase: CharArray, readOnly: Boolean): CryptomatorOpenResult {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return CryptomatorOpenResult.InvalidVault("Cannot access the selected folder.")

        val masterkeyDoc = root.listFiles().firstOrNull { it.name == MASTERKEY_FILE_NAME }
            ?: return CryptomatorOpenResult.InvalidVault("No masterkey.cryptomator found — this doesn't look like a Cryptomator vault.")
        val dataDir = root.listFiles().firstOrNull { it.name == DATA_DIR_NAME && it.isDirectory }
            ?: return CryptomatorOpenResult.InvalidVault("Vault is missing its 'd' data directory.")

        val masterkeyBytes = context.contentResolver.openInputStream(masterkeyDoc.uri)?.use { it.readBytes() }
            ?: return CryptomatorOpenResult.InvalidVault("Could not read masterkey.cryptomator")

        val parsed = try {
            CryptomatorMasterkeyFile.parse(masterkeyBytes)
        } catch (e: MasterkeyFileFormatException) {
            return CryptomatorOpenResult.InvalidVault(e.message ?: "Malformed masterkey.cryptomator")
        }

        val masterkey = try {
            CryptomatorMasterkeyFile.unlock(parsed, passphrase)
        } catch (e: InvalidPassphraseException) {
            return CryptomatorOpenResult.WrongPassword
        }

        val vaultConfigDoc = root.listFiles().firstOrNull { it.name == VAULT_FILE_NAME }
        val (vaultFormat, cipherCombo, shorteningThreshold) = if (vaultConfigDoc != null) {
            val jwt = context.contentResolver.openInputStream(vaultConfigDoc.uri)?.use { it.readBytes() }
                ?.toString(Charsets.UTF_8)
                ?: return CryptomatorOpenResult.InvalidVault("Could not read vault.cryptomator")
            val config = try {
                CryptomatorVaultConfigParser.verify(jwt, masterkey)
            } catch (e: VaultConfigException) {
                masterkey.destroy()
                return CryptomatorOpenResult.InvalidVault(e.message ?: "vault.cryptomator verification failed")
            }
            Triple(config.vaultFormat, config.cipherCombo, config.shorteningThreshold)
        } else {
            // Format 7 vaults created before vault.cryptomator existed (very old
            // Cryptomator versions) fall back to masterkey.json's own "version"
            // field and the legacy SIV_CTRMAC scheme. Out of scope per the
            // agreed plan (format 7+8 only, both of which normally carry
            // vault.cryptomator) — but format 7 *can* legally lack it if it
            // predates that field's introduction, so we accept it defensively
            // rather than hard-failing.
            Triple(7, "SIV_CTRMAC", DEFAULT_SHORTENING_THRESHOLD)
        }

        if (vaultFormat !in 7..8) {
            masterkey.destroy()
            return CryptomatorOpenResult.InvalidVault("Vault format $vaultFormat is not supported (only 7 and 8 are).")
        }

        val session = CryptomatorSession(
            context = context,
            vaultRootUri = vaultRootUri,
            masterkey = masterkey,
            vaultFormat = vaultFormat,
            cipherCombo = cipherCombo,
            shorteningThreshold = shorteningThreshold,
            readOnly = readOnly,
        )
        val displayName = root.name ?: "Vault"
        return CryptomatorOpenResult.Success(session, displayName)
    }

    /**
     * Creates a brand-new vault in an empty (or non-existent-but-creatable)
     * SAF tree: writes masterkey.cryptomator, vault.cryptomator, and the
     * initial empty 'd/<hash(rootDirId="")>' two-level directory. Always
     * uses [CURRENT_VAULT_FORMAT]/[CURRENT_CIPHER_COMBO] (format 8, SIV_GCM)
     * per the agreed scope — this app never creates format-7 vaults, only
     * opens them.
     */
    fun create(context: Context, vaultRootUri: Uri, passphrase: CharArray): CryptomatorOpenResult {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return CryptomatorOpenResult.InvalidVault("Cannot access the selected folder.")

        if (root.listFiles().isNotEmpty()) {
            return CryptomatorOpenResult.InvalidVault("Selected folder is not empty.")
        }

        val random = SecureRandom()
        val masterkey = CryptomatorMasterkey.generate(random)

        val masterkeyJson = CryptomatorMasterkeyFile.lock(masterkey, passphrase, random, vaultVersion = 999)
        val masterkeyDoc = root.createFile("application/octet-stream", MASTERKEY_FILE_NAME)
            ?: return CryptomatorOpenResult.InvalidVault("Could not create masterkey.cryptomator")
        context.contentResolver.openOutputStream(masterkeyDoc.uri, "wt")?.use { it.write(masterkeyJson) }

        val vaultId = UUID.randomUUID().toString()
        val jwt = CryptomatorVaultConfigParser.create(
            vaultFormat = CURRENT_VAULT_FORMAT,
            cipherCombo = CURRENT_CIPHER_COMBO,
            shorteningThreshold = DEFAULT_SHORTENING_THRESHOLD,
            masterkey = masterkey,
            vaultId = vaultId,
        )
        val vaultConfigDoc = root.createFile("application/octet-stream", VAULT_FILE_NAME)
            ?: return CryptomatorOpenResult.InvalidVault("Could not create vault.cryptomator")
        context.contentResolver.openOutputStream(vaultConfigDoc.uri, "wt")?.use { it.write(jwt.toByteArray(Charsets.UTF_8)) }

        // Root directory's physical storage: d/<hash("")[0:2]>/<hash("")[2:]>
        val nameCryptor = CryptomatorFileNameCryptor(masterkey)
        val rootHash = nameCryptor.hashDirectoryId(ROOT_DIR_ID)
        val dataDir = root.createDirectory(DATA_DIR_NAME) ?: return CryptomatorOpenResult.InvalidVault("Could not create 'd' directory")
        val lvl1 = dataDir.createDirectory(rootHash.substring(0, 2)) ?: return CryptomatorOpenResult.InvalidVault("Could not create data subdirectory")
        lvl1.createDirectory(rootHash.substring(2)) ?: return CryptomatorOpenResult.InvalidVault("Could not create data subdirectory")

        val session = CryptomatorSession(
            context = context,
            vaultRootUri = vaultRootUri,
            masterkey = masterkey,
            vaultFormat = CURRENT_VAULT_FORMAT,
            cipherCombo = CURRENT_CIPHER_COMBO,
            shorteningThreshold = DEFAULT_SHORTENING_THRESHOLD,
            readOnly = false,
        )
        return CryptomatorOpenResult.Success(session, root.name ?: "Vault")
    }
}