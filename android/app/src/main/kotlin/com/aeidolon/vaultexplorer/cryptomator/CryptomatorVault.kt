package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafIOException
import java.security.SecureRandom
import java.util.UUID

/**
 * Entry point mirroring NativeEngine.unlockFile/create — opens or creates
 * a Cryptomator vault rooted at a SAF tree Uri (the folder containing
 * vault.cryptomator + masterkey.cryptomator + d/), given the user's
 * passphrase.
 */
object CryptomatorVault {

    private const val TAG = "CryptomatorVault"
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

    fun open(context: Context, vaultRootUri: Uri, passphrase: CharArray, readOnly: Boolean): VaultOpenResult<CryptomatorSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: run {
                VeLog.e(TAG) { "open failed: Cannot access folder URI $vaultRootUri" }
                return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
            }

        val masterkeyDoc = root.listFiles().firstOrNull { it.name == MASTERKEY_FILE_NAME }
            ?: run {
                VeLog.e(TAG) { "open failed: Missing $MASTERKEY_FILE_NAME in $vaultRootUri" }
                return VaultOpenResult.InvalidVault("No masterkey.cryptomator found — this doesn't look like a Cryptomator vault.")
            }

        val dataDir = root.listFiles().firstOrNull { it.name == DATA_DIR_NAME && it.isDirectory }
            ?: run {
                VeLog.e(TAG) { "open failed: Missing '$DATA_DIR_NAME' data directory in $vaultRootUri" }
                return VaultOpenResult.InvalidVault("Vault is missing its 'd' data directory.")
            }

        val masterkeyBytes = try {
            context.contentResolver.openInputStream(masterkeyDoc.uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "open failed: Exception reading $MASTERKEY_FILE_NAME at ${masterkeyDoc.uri}" }
            null
        } ?: run {
            VeLog.e(TAG) { "open failed: Could not read $MASTERKEY_FILE_NAME at ${masterkeyDoc.uri}" }
            return VaultOpenResult.InvalidVault("Could not read masterkey.cryptomator")
        }

        val parsed = try {
            CryptomatorMasterkeyFile.parse(masterkeyBytes)
        } catch (e: MasterkeyFileFormatException) {
            VeLog.e(TAG, e) { "open failed: Malformed $MASTERKEY_FILE_NAME: ${e.message}" }
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed masterkey.cryptomator")
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "open failed: Unexpected error parsing $MASTERKEY_FILE_NAME: ${e.message}" }
            return VaultOpenResult.InvalidVault("Failed to parse masterkey.cryptomator: ${e.message}")
        }

        val masterkey = try {
            CryptomatorMasterkeyFile.unlock(parsed, passphrase)
        } catch (e: InvalidPassphraseException) {
            VeLog.e(TAG, e) { "open failed: Incorrect passphrase for Cryptomator vault" }
            return VaultOpenResult.WrongPassword
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "open failed: Error unlocking masterkey: ${e.message}" }
            return VaultOpenResult.InvalidVault("Failed to unlock masterkey: ${e.message}")
        }

        val vaultConfigDoc = root.listFiles().firstOrNull { it.name == VAULT_FILE_NAME }
        val (vaultFormat, cipherCombo, shorteningThreshold) = if (vaultConfigDoc != null) {
            val jwt = try {
                context.contentResolver.openInputStream(vaultConfigDoc.uri)?.use { it.readBytes() }?.toString(Charsets.UTF_8)
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "open failed: Exception reading $VAULT_FILE_NAME at ${vaultConfigDoc.uri}" }
                null
            } ?: run {
                masterkey.destroy()
                VeLog.e(TAG) { "open failed: Could not read $VAULT_FILE_NAME at ${vaultConfigDoc.uri}" }
                return VaultOpenResult.InvalidVault("Could not read vault.cryptomator")
            }

            val config = try {
                CryptomatorVaultConfigParser.verify(jwt, masterkey)
            } catch (e: VaultConfigException) {
                masterkey.destroy()
                VeLog.e(TAG, e) { "open failed: $VAULT_FILE_NAME verification failed: ${e.message}" }
                return VaultOpenResult.InvalidVault(e.message ?: "vault.cryptomator verification failed")
            } catch (e: Exception) {
                masterkey.destroy()
                VeLog.e(TAG, e) { "open failed: Unexpected error verifying $VAULT_FILE_NAME: ${e.message}" }
                return VaultOpenResult.InvalidVault("vault.cryptomator verification error: ${e.message}")
            }
            Triple(config.vaultFormat, config.cipherCombo, config.shorteningThreshold)
        } else {
            Triple(7, "SIV_CTRMAC", DEFAULT_SHORTENING_THRESHOLD)
        }

        if (vaultFormat !in 7..8) {
            masterkey.destroy()
            VeLog.e(TAG) { "open failed: Unsupported vault format $vaultFormat" }
            return VaultOpenResult.InvalidVault("Vault format $vaultFormat is not supported (only 7 and 8 are).")
        }

        val session = try {
            CryptomatorSession(
                context = context,
                vaultRootUri = vaultRootUri,
                masterkey = masterkey,
                vaultFormat = vaultFormat,
                cipherCombo = cipherCombo,
                shorteningThreshold = shorteningThreshold,
                readOnly = readOnly,
            )
        } catch (e: Exception) {
            masterkey.destroy()
            VeLog.e(TAG, e) { "open failed: Could not initialize CryptomatorSession: ${e.message}" }
            return VaultOpenResult.InvalidVault("Could not open vault: ${e.message}")
        }

        val displayName = root.name ?: "Vault"
        return VaultOpenResult.Success(session, displayName)
    }

    fun changePassword(
        context: Context,
        vaultRootUri: Uri,
        oldPassphrase: CharArray,
        newPassphrase: CharArray,
    ): VaultOpenResult<Unit> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: run {
                VeLog.e(TAG) { "changePassword failed: Cannot access folder URI $vaultRootUri" }
                return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
            }

        val masterkeyDoc = root.listFiles().firstOrNull { it.name == MASTERKEY_FILE_NAME }
            ?: run {
                VeLog.e(TAG) { "changePassword failed: Missing $MASTERKEY_FILE_NAME" }
                return VaultOpenResult.InvalidVault("No masterkey.cryptomator found — this doesn't look like a Cryptomator vault.")
            }

        val masterkeyBytes = try {
            context.contentResolver.openInputStream(masterkeyDoc.uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            null
        } ?: run {
            VeLog.e(TAG) { "changePassword failed: Could not read $MASTERKEY_FILE_NAME" }
            return VaultOpenResult.InvalidVault("Could not read masterkey.cryptomator")
        }

        val parsed = try {
            CryptomatorMasterkeyFile.parse(masterkeyBytes)
        } catch (e: MasterkeyFileFormatException) {
            VeLog.e(TAG, e) { "changePassword failed: Malformed $MASTERKEY_FILE_NAME: ${e.message}" }
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed masterkey.cryptomator")
        }

        val masterkey = try {
            CryptomatorMasterkeyFile.unlock(parsed, oldPassphrase)
        } catch (e: InvalidPassphraseException) {
            VeLog.e(TAG, e) { "changePassword failed: Incorrect old passphrase" }
            return VaultOpenResult.WrongPassword
        }

        return try {
            val random = SecureRandom()
            val newMasterkeyJson = CryptomatorMasterkeyFile.lock(masterkey, newPassphrase, random, vaultVersion = parsed.version)
            try {
                SafDocumentOps(context).writeWhole(masterkeyDoc, newMasterkeyJson)
            } catch (e: SafIOException) {
                VeLog.e(TAG, e) { "changePassword failed: Could not write $MASTERKEY_FILE_NAME: ${e.message}" }
                return VaultOpenResult.InvalidVault(e.message ?: "Could not write masterkey.cryptomator")
            }
            VaultOpenResult.Success(Unit, root.name ?: "Vault")
        } finally {
            masterkey.destroy()
        }
    }

    fun create(context: Context, vaultRootUri: Uri, passphrase: CharArray): VaultOpenResult<CryptomatorSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return VaultOpenResult.InvalidVault("Cannot access the selected folder.")

        if (root.listFiles().isNotEmpty()) {
            return VaultOpenResult.InvalidVault("Selected folder is not empty.")
        }

        val random = SecureRandom()
        val masterkey = CryptomatorMasterkey.generate(random)

        val masterkeyJson = CryptomatorMasterkeyFile.lock(masterkey, passphrase, random, vaultVersion = 999)
        val masterkeyDoc = root.createFile("application/octet-stream", MASTERKEY_FILE_NAME)
            ?: return VaultOpenResult.InvalidVault("Could not create masterkey.cryptomator")
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
            ?: return VaultOpenResult.InvalidVault("Could not create vault.cryptomator")
        context.contentResolver.openOutputStream(vaultConfigDoc.uri, "wt")?.use { it.write(jwt.toByteArray(Charsets.UTF_8)) }

        val nameCryptor = CryptomatorFileNameCryptor(masterkey)
        val rootHash = nameCryptor.hashDirectoryId(ROOT_DIR_ID)
        val dataDir = root.createDirectory(DATA_DIR_NAME) ?: return VaultOpenResult.InvalidVault("Could not create 'd' directory")
        val lvl1 = dataDir.createDirectory(rootHash.substring(0, 2)) ?: return VaultOpenResult.InvalidVault("Could not create data subdirectory")
        lvl1.createDirectory(rootHash.substring(2)) ?: return VaultOpenResult.InvalidVault("Could not create data subdirectory")

        val session = CryptomatorSession(
            context = context,
            vaultRootUri = vaultRootUri,
            masterkey = masterkey,
            vaultFormat = CURRENT_VAULT_FORMAT,
            cipherCombo = CURRENT_CIPHER_COMBO,
            shorteningThreshold = DEFAULT_SHORTENING_THRESHOLD,
            readOnly = false,
        )
        return VaultOpenResult.Success(session, root.name ?: "Vault")
    }
}