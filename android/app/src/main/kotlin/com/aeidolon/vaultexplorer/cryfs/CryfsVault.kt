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

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): VaultOpenResult<CryfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val saf = SafDocumentOps(context)
        val configDoc = saf.childOf(root, CONFIG_FILE_NAME)
            ?: return VaultOpenResult.InvalidVault("No cryfs.config found — this doesn't look like a CryFS vault.")
        val configBytes = context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
            ?: return VaultOpenResult.InvalidVault("Could not read cryfs.config")
        val config = try {
            CryfsConfigFile.parse(configBytes, password)
        } catch (e: CryfsWrongPasswordException) {
            return VaultOpenResult.WrongPassword
        } catch (e: CryfsUnsupportedCipherException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        } catch (e: CryfsConfigException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed cryfs.config")
        }
        return try {
            buildSession(context, vaultRootUri, root, config, readOnly)
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
        return VaultOpenResult.Success(session, root.name ?: "Vault")
    }
}