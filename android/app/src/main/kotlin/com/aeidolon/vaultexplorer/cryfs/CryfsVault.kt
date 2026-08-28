package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafIOException
import java.io.File
import java.security.SecureRandom

object CryfsVault {
    private const val TAG = "CryfsVault"
    private const val CONFIG_FILE_NAME = "cryfs.config"

    private fun localIntegrityStateBaseDir(context: Context) = File(context.filesDir, "cryfs_localstate")

    private fun openIntegrityState(context: Context, config: CryfsConfig) =
        CryfsLocalIntegrityState.open(localIntegrityStateBaseDir(context), config.filesystemId)

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

    private fun buildMirrorSync(
        context: Context,
        vaultRootUri: Uri,
        root: DocumentFile,
    ): com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator? {
        if (com.aeidolon.vaultexplorer.RawFileResolver.getRawFileFromUri(context, vaultRootUri) != null) return null
        val realOps = SafDocumentOps(context)
        return com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator(
            context = context,
            sessionTag = java.util.UUID.randomUUID().toString(),
            realOps = realOps,
        ).also { it.reset(root) }
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): VaultOpenResult<CryfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: run {
                VeLog.e(TAG) { "open failed: Cannot access folder URI $vaultRootUri" }
                return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
            }

        val configBytes = try {
            readConfigBytes(context, root)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "open failed: Exception reading $CONFIG_FILE_NAME" }
            null
        } ?: run {
            VeLog.e(TAG) { "open failed: Missing or unreadable $CONFIG_FILE_NAME in $vaultRootUri" }
            return VaultOpenResult.InvalidVault("No cryfs.config found — this doesn't look like a CryFS vault.")
        }

        val combinedKey = try {
            CryfsConfigFile.deriveCombinedKey(configBytes, password)
        } catch (e: CryfsConfigException) {
            VeLog.e(TAG, e) { "open failed: Malformed $CONFIG_FILE_NAME during key derivation: ${e.message}" }
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed cryfs.config")
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "open failed: Unexpected error during key derivation: ${e.message}" }
            return VaultOpenResult.InvalidVault("Key derivation error: ${e.message}")
        }

        val config = try {
            CryfsConfigFile.parseWithCombinedKey(configBytes, combinedKey)
        } catch (e: CryfsWrongPasswordException) {
            combinedKey.fill(0)
            VeLog.e(TAG, e) { "open failed: Incorrect password for CryFS vault" }
            return VaultOpenResult.WrongPassword
        } catch (e: CryfsUnsupportedCipherException) {
            combinedKey.fill(0)
            VeLog.e(TAG, e) { "open failed: Unsupported cipher: ${e.message}" }
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        } catch (e: CryfsConfigException) {
            combinedKey.fill(0)
            VeLog.e(TAG, e) { "open failed: Malformed $CONFIG_FILE_NAME: ${e.message}" }
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed cryfs.config")
        }

        return try {
            buildSession(context, vaultRootUri, root, config, readOnly, combinedKey)
        } catch (e: Exception) {
            combinedKey.fill(0)
            VeLog.e(TAG, e) { "open failed: Could not initialize CryfsSession: ${e.message}" }
            VaultOpenResult.InvalidVault("Could not open vault: ${e.message}")
        }
    }

    fun openWithCombinedKey(
        context: Context, vaultRootUri: Uri, combinedKey: ByteArray, readOnly: Boolean,
    ): VaultOpenResult<CryfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: run {
                VeLog.e(TAG) { "openWithCombinedKey failed: Cannot access folder URI $vaultRootUri" }
                return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
            }

        val configBytes = readConfigBytes(context, root)
            ?: run {
                VeLog.e(TAG) { "openWithCombinedKey failed: Missing $CONFIG_FILE_NAME in $vaultRootUri" }
                return VaultOpenResult.InvalidVault("No cryfs.config found — this doesn't look like a CryFS vault.")
            }

        val config = try {
            CryfsConfigFile.parseWithCombinedKey(configBytes, combinedKey)
        } catch (e: CryfsWrongPasswordException) {
            VeLog.e(TAG, e) { "openWithCombinedKey failed: Stale or incorrect combined key" }
            return VaultOpenResult.WrongPassword
        } catch (e: CryfsUnsupportedCipherException) {
            VeLog.e(TAG, e) { "openWithCombinedKey failed: Unsupported cipher: ${e.message}" }
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        } catch (e: CryfsConfigException) {
            VeLog.e(TAG, e) { "openWithCombinedKey failed: Malformed $CONFIG_FILE_NAME: ${e.message}" }
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed cryfs.config")
        }

        return try {
            buildSession(context, vaultRootUri, root, config, readOnly, combinedKey)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "openWithCombinedKey failed: Error in buildSession: ${e.message}" }
            VaultOpenResult.InvalidVault("Could not open vault: ${e.message}")
        }
    }

    fun create(
        context: Context,
        vaultRootUri: Uri,
        password: CharArray,
        cipher: String = CryfsConfigFile.DEFAULT_BLOCK_CIPHER,
        blocksizeBytes: Int = CryfsConfigFile.DEFAULT_BLOCKSIZE,
    ): VaultOpenResult<CryfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val saf = SafDocumentOps(context)
        if (saf.listChildren(root).isNotEmpty()) {
            return VaultOpenResult.InvalidVault("Selected folder is not empty.")
        }
        val random = SecureRandom()
        return try {
            val config = CryfsConfigFile.newVaultConfig(random, cipher, blocksizeBytes)
            val configBytes = CryfsConfigFile.build(config, password, random)
            val configDoc = root.createFile("application/octet-stream", CONFIG_FILE_NAME)
                ?: return VaultOpenResult.InvalidVault("Could not create cryfs.config")
            context.contentResolver.openOutputStream(configDoc.uri, "wt")?.use { it.write(configBytes) }
                ?: return VaultOpenResult.InvalidVault("Could not write cryfs.config")
            val nullParentId = CryfsBlockId(ByteArray(16))
            val cipherId = CryfsBlockCipher.cipherIdFor(config.blockCipherName)
            val blockStore = CryfsBlockStore(context, root, cipherId, config.encryptionKey, openIntegrityState(context, config))
            val virtualBlockSize = CryfsBlockStore.calculateVirtualBlockSize(config.blocksizeBytes, config.blockCipherName)
            val dataTree = CryfsDataTree(blockStore, virtualBlockSize, random)
            CryfsFsBlob.writeWhole(dataTree, config.rootBlobId, CryfsEntryType.DIR, nullParentId, CryfsDirBlob.serialize(emptyList()))
            buildSession(context, vaultRootUri, root, config, readOnly = false)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "create failed: ${e.message}" }
            VaultOpenResult.InvalidVault("Vault creation failed: ${e.message}")
        }
    }

    fun changePassword(
        context: Context, vaultRootUri: Uri, oldPassword: CharArray, newPassword: CharArray,
    ): VaultOpenResult<Unit> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val configBytes = readConfigBytes(context, root)
            ?: return VaultOpenResult.InvalidVault("No cryfs.config found — this doesn't look like a CryFS vault.")
        val config = try {
            CryfsConfigFile.parse(configBytes, oldPassword)
        } catch (e: CryfsWrongPasswordException) {
            return VaultOpenResult.WrongPassword
        } catch (e: CryfsUnsupportedCipherException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        } catch (e: CryfsConfigException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed cryfs.config")
        }
        val saf = SafDocumentOps(context)
        val configDoc = saf.childOf(root, CONFIG_FILE_NAME)
            ?: return VaultOpenResult.InvalidVault("No cryfs.config found — this doesn't look like a CryFS vault.")
        return try {
            val random = SecureRandom()
            val newConfigBytes = CryfsConfigFile.build(config, newPassword, random)
            try {
                saf.writeWhole(configDoc, newConfigBytes)
            } catch (e: SafIOException) {
                VeLog.e(TAG, e) { "changePassword failed to write cryfs.config: ${e.message}" }
                return VaultOpenResult.InvalidVault(e.message ?: "Could not write cryfs.config")
            }
            VaultOpenResult.Success(Unit, root.name ?: "Vault")
        } finally {
            config.encryptionKey.fill(0)
        }
    }

    private fun buildSession(
        context: Context, vaultRootUri: Uri, root: DocumentFile, config: CryfsConfig, readOnly: Boolean,
        derivedKey: ByteArray? = null,
    ): VaultOpenResult<CryfsSession> {
        val cipherId = try {
            CryfsBlockCipher.cipherIdFor(config.blockCipherName)
        } catch (e: CryfsUnsupportedCipherException) {
            VeLog.e(TAG, e) { "buildSession failed: Unsupported cipher '${config.blockCipherName}'" }
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        }
        val mirrorSync = buildMirrorSync(context, vaultRootUri, root)
        val blockStore = CryfsBlockStore(context, root, cipherId, config.encryptionKey, openIntegrityState(context, config), mirrorSync)
        if (blockStore.load(config.rootBlobId) == null) {
            val violation = blockStore.lastIntegrityViolation
            mirrorSync?.teardown()
            return if (violation != null) {
                val errorMsg = "Rollback detected on root directory block (${config.rootBlobId.hex}): client ${violation.writerClientId} claims version ${violation.attemptedVersion}, known version ${violation.knownVersion}"
                VeLog.e(TAG) { errorMsg }
                VaultOpenResult.InvalidVault(
                    "This vault's root directory looks like it was rolled back to an older version " +
                        "(client ${violation.writerClientId}: saw version ${violation.attemptedVersion}, but this " +
                        "device already recorded version ${violation.knownVersion}). Refusing to open it to avoid " +
                        "masking possible data loss or tampering -- this is the same protection CryFS's own error " +
                        "24/25 gives you."
                )
            } else {
                VeLog.e(TAG) { "buildSession failed: Root directory block '${config.rootBlobId.hex}' missing or unreadable" }
                VaultOpenResult.InvalidVault("Vault's root directory block is missing or unreadable.")
            }
        }
        val virtualBlockSize = CryfsBlockStore.calculateVirtualBlockSize(config.blocksizeBytes, config.blockCipherName)
        val dataTree = CryfsDataTree(blockStore, virtualBlockSize, SecureRandom())
        val tree = CryfsVaultTree(dataTree, config.rootBlobId)
        val session = CryfsSession(context, vaultRootUri, config, dataTree, tree, readOnly, blockStore)
        return VaultOpenResult.Success(session, root.name ?: "Vault", derivedKey)
    }
}