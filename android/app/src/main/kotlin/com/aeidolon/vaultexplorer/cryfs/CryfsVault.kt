package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.RawFileResolver
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

    /**
     * Whether this vault's folder can really be read AND written through a
     * raw `java.io.File` path -- not merely whether the storage-permission
     * heuristics in [RawFileResolver.getRawFileFromUri] say so. When those
     * heuristics are wrong the first raw open fails with EACCES, so the
     * whole vault (config read, block store, mirror) must go through SAF /
     * the mirror instead. See [RawFileResolver.getVerifiedRawVaultRoot];
     * [probeWrite] is false for a read-only open, which must not touch the
     * vault folder.
     */
    private fun rawAccessVerified(context: Context, vaultRootUri: Uri, probeWrite: Boolean = true): Boolean =
        RawFileResolver.getVerifiedRawVaultRoot(context, vaultRootUri, CONFIG_FILE_NAME, probeWrite) != null

    private fun readConfigBytes(context: Context, root: DocumentFile, useRaw: Boolean): ByteArray? {
        val saf = SafDocumentOps(context, allowRaw = useRaw)
        val configDoc = saf.childOf(root, CONFIG_FILE_NAME) ?: return null
        return context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
    }

    private fun buildMirrorSync(
        context: Context,
        root: DocumentFile,
        useRaw: Boolean,
    ): com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator? {
        if (useRaw) return null
        // The mirror's view of the REAL tree must stay on SAF too: if raw
        // access was refused (or failed its probe) it must not sneak back in
        // through the pull/push of the real documents.
        val realOps = SafDocumentOps(context, allowRaw = false)
        return com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator(
            context = context,
            sessionTag = java.util.UUID.randomUUID().toString(),
            realOps = realOps,
        ).also { coordinator ->
            try {
                coordinator.reset(root)
            } catch (e: Exception) {
                // reset() may already have created the mirror folder, and
                // the coordinator escapes this function only through the
                // return value -- so tear it down here, then let the
                // caller handle the failure.
                runCatching { coordinator.teardown() }
                throw e
            }
        }
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): VaultOpenResult<CryfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: run {
                VeLog.e(TAG) { "open failed: Cannot access folder URI $vaultRootUri" }
                return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
            }

        val useRaw = rawAccessVerified(context, vaultRootUri, probeWrite = !readOnly)
        val configBytes = try {
            readConfigBytes(context, root, useRaw)
        } catch (e: Exception) {
            // Distinct from "missing": a file-backed document is opened with
            // a plain java.io open under the hood, so a permission problem
            // lands here -- don't report it as "no cryfs.config found".
            VeLog.e(TAG, e) { "open failed: Exception reading $CONFIG_FILE_NAME: ${e.message}" }
            return VaultOpenResult.InvalidVault("Could not read cryfs.config: ${e.message}")
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
            buildSession(context, vaultRootUri, root, config, readOnly, combinedKey, useRaw)
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

        val useRaw = rawAccessVerified(context, vaultRootUri, probeWrite = !readOnly)
        val configBytes = try {
            readConfigBytes(context, root, useRaw)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "openWithCombinedKey failed: Exception reading $CONFIG_FILE_NAME: ${e.message}" }
            return VaultOpenResult.InvalidVault("Could not read cryfs.config: ${e.message}")
        } ?: run {
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
            buildSession(context, vaultRootUri, root, config, readOnly, combinedKey, useRaw)
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
            // Decided only now: cryfs.config is the probe's sentinel file, so
            // it has to exist before raw access can be verified. Both the
            // block store below and the session built at the end follow it.
            val useRaw = rawAccessVerified(context, vaultRootUri)
            val nullParentId = CryfsBlockId(ByteArray(16))
            val cipherId = CryfsBlockCipher.cipherIdFor(config.blockCipherName)
            val blockStore = CryfsBlockStore(
                context, root, cipherId, config.encryptionKey, openIntegrityState(context, config),
                allowRaw = useRaw,
            )
            val virtualBlockSize = CryfsBlockStore.calculateVirtualBlockSize(config.blocksizeBytes, config.blockCipherName)
            val dataTree = CryfsDataTree(blockStore, virtualBlockSize, random)
            CryfsFsBlob.writeWhole(dataTree, config.rootBlobId, CryfsEntryType.DIR, nullParentId, CryfsDirBlob.serialize(emptyList()))
            buildSession(context, vaultRootUri, root, config, readOnly = false, useRaw = useRaw)
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
        val useRaw = rawAccessVerified(context, vaultRootUri)
        val configBytes = try {
            readConfigBytes(context, root, useRaw)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "changePassword failed: Exception reading $CONFIG_FILE_NAME: ${e.message}" }
            return VaultOpenResult.InvalidVault("Could not read cryfs.config: ${e.message}")
        } ?: return VaultOpenResult.InvalidVault("No cryfs.config found — this doesn't look like a CryFS vault.")
        val config = try {
            CryfsConfigFile.parse(configBytes, oldPassword)
        } catch (e: CryfsWrongPasswordException) {
            return VaultOpenResult.WrongPassword
        } catch (e: CryfsUnsupportedCipherException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        } catch (e: CryfsConfigException) {
            return VaultOpenResult.InvalidVault(e.message ?: "Malformed cryfs.config")
        }
        val saf = SafDocumentOps(context, allowRaw = useRaw)
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
        useRaw: Boolean,
    ): VaultOpenResult<CryfsSession> {
        val cipherId = try {
            CryfsBlockCipher.cipherIdFor(config.blockCipherName)
        } catch (e: CryfsUnsupportedCipherException) {
            VeLog.e(TAG, e) { "buildSession failed: Unsupported cipher '${config.blockCipherName}'" }
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        }
        val mirrorSync = buildMirrorSync(context, root, useRaw)
        try {
            val blockStore = CryfsBlockStore(
                context, root, cipherId, config.encryptionKey, openIntegrityState(context, config), mirrorSync,
                allowRaw = useRaw,
            )
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
        } catch (e: Exception) {
            // The mirror is created above and handed to the session only on
            // success, so nobody else can release it if anything below throws
            // (block store setup, the first block read, ...).
            runCatching { mirrorSync?.teardown() }
            throw e
        }
    }
}