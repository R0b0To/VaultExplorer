package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.security.SecureRandom

object CryfsVault {
    private const val CONFIG_FILE_NAME = "cryfs.config"

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        val saf = SafDocumentOps(context)
        return saf.childOf(root, CONFIG_FILE_NAME) != null
    }

    private fun readConfigBytes(context: Context, root: DocumentFile): ByteArray? {
        val saf = SafDocumentOps(context)
        val configDoc = saf.childOf(root, CONFIG_FILE_NAME) ?: return null
        return context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): VaultOpenResult<CryfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val configBytes = readConfigBytes(context, root)
            ?: return VaultOpenResult.InvalidVault("No cryfs.config found — this doesn't look like a CryFS vault.")
        val combinedKey = try {
            CryfsConfigFile.deriveCombinedKey(configBytes, password)
        } catch (e: CryfsConfigException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed cryfs.config")
        }
        val config = try {
            CryfsConfigFile.parseWithCombinedKey(configBytes, combinedKey)
        } catch (e: CryfsWrongPasswordException) {
            combinedKey.fill(0)
            return VaultOpenResult.WrongPassword
        } catch (e: CryfsUnsupportedCipherException) {
            combinedKey.fill(0)
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        } catch (e: CryfsConfigException) {
            combinedKey.fill(0)
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed cryfs.config")
        }
        return try {
            buildSession(context, vaultRootUri, root, config, readOnly, combinedKey)
        } catch (e: Exception) {
            combinedKey.fill(0)
            VaultOpenResult.InvalidVault("Could not open vault: ${e.message}")
        }
    }

    /**
     * Fast-path counterpart of [open]: reopens the vault with a previously
     * cached `combinedKey` (see [VaultOpenResult.Success.derivedKey]),
     * skipping cryfs's scrypt KDF entirely — the same trick DroidFS's native
     * cryfs/gocryptfs JNI layer plays via its `givenHash` parameter. A stale
     * or wrong cached key surfaces as [VaultOpenResult.WrongPassword], same
     * as a wrong password, so the caller can fall back to a password prompt.
     */
    fun openWithCombinedKey(
        context: Context, vaultRootUri: Uri, combinedKey: ByteArray, readOnly: Boolean,
    ): VaultOpenResult<CryfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val configBytes = readConfigBytes(context, root)
            ?: return VaultOpenResult.InvalidVault("No cryfs.config found — this doesn't look like a CryFS vault.")
        val config = try {
            CryfsConfigFile.parseWithCombinedKey(configBytes, combinedKey)
        } catch (e: CryfsWrongPasswordException) {
            return VaultOpenResult.WrongPassword
        } catch (e: CryfsUnsupportedCipherException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        } catch (e: CryfsConfigException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed cryfs.config")
        }
        return try {
            buildSession(context, vaultRootUri, root, config, readOnly, combinedKey)
        } catch (e: Exception) {
            VaultOpenResult.InvalidVault("Could not open vault: ${e.message}")
        }
    }

    fun create(context: Context, vaultRootUri: Uri, password: CharArray): VaultOpenResult<CryfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val saf = SafDocumentOps(context)
        if (saf.listChildren(root).isNotEmpty()) {
            return VaultOpenResult.InvalidVault("Selected folder is not empty.")
        }
        val random = SecureRandom()
        return try {
            val config = CryfsConfigFile.newVaultConfig(random)
            val configBytes = CryfsConfigFile.build(config, password, random)
            val configDoc = root.createFile("application/octet-stream", CONFIG_FILE_NAME)
                ?: return VaultOpenResult.InvalidVault("Could not create cryfs.config")
            context.contentResolver.openOutputStream(configDoc.uri, "wt")?.use { it.write(configBytes) }
                ?: return VaultOpenResult.InvalidVault("Could not write cryfs.config")
            val nullParentId = CryfsBlockId(ByteArray(16))
            val cipherId = CryfsBlockCipher.cipherIdFor(config.blockCipherName)
            val blockStore = CryfsBlockStore(context, root, cipherId, config.encryptionKey, config.exclusiveClientId ?: 1L)
            val virtualBlockSize = CryfsBlockStore.calculateVirtualBlockSize(config.blocksizeBytes, config.blockCipherName)
            val dataTree = CryfsDataTree(blockStore, virtualBlockSize, random)
            CryfsFsBlob.writeWhole(dataTree, config.rootBlobId, CryfsEntryType.DIR, nullParentId, CryfsDirBlob.serialize(emptyList()))
            buildSession(context, vaultRootUri, root, config, readOnly = false)
        } catch (e: Exception) {
            VaultOpenResult.InvalidVault("Vault creation failed: ${e.message}")
        }
    }

    private fun buildSession(
        context: Context, vaultRootUri: Uri, root: DocumentFile, config: CryfsConfig, readOnly: Boolean,
        derivedKey: ByteArray? = null,
    ): VaultOpenResult<CryfsSession> {
        val cipherId = try {
            CryfsBlockCipher.cipherIdFor(config.blockCipherName)
        } catch (e: CryfsUnsupportedCipherException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        }
        val blockStore = CryfsBlockStore(context, root, cipherId, config.encryptionKey, config.exclusiveClientId ?: 1L)
        if (blockStore.load(config.rootBlobId) == null) {
            return VaultOpenResult.InvalidVault("Vault's root directory block is missing or unreadable.")
        }
        val virtualBlockSize = CryfsBlockStore.calculateVirtualBlockSize(config.blocksizeBytes, config.blockCipherName)
        val dataTree = CryfsDataTree(blockStore, virtualBlockSize, SecureRandom())
        val tree = CryfsVaultTree(dataTree, config.rootBlobId)
        val session = CryfsSession(context, vaultRootUri, config, dataTree, tree, readOnly)
        return VaultOpenResult.Success(session, root.name ?: "Vault", derivedKey)
    }
}