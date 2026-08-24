package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.io.File
import java.security.SecureRandom

object CryfsVault {
    private const val CONFIG_FILE_NAME = "cryfs.config"

    /** Where this app's own per-vault CryFS client ID and known-block-version
     *  history live -- private, per-install, per-vault (keyed by filesystemId),
     *  and deliberately *not* part of the vault itself. See
     *  [CryfsLocalIntegrityState]'s KDoc for why this needs to be durable and
     *  is the actual fix for vaults eventually tripping DroidFS/cryfs's error
     *  24/25 after being edited from this app. */
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

    /**
     * Builds the [com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator] a
     * CryfsBlockStore should mirror block I/O through, or null when
     * vaultRootUri already resolves to a path we have direct POSIX access
     * to -- same policy as CryptomatorSession/GocryptfsVault (see
     * MirrorSyncCoordinator's doc comment). Only used for the long-lived
     * blockStore built in [buildSession]: the short-lived one [create]
     * builds just to write the vault's initial empty root directory blob
     * is discarded immediately after, so mirroring it would only add a
     * mirror directory to immediately tear down for no benefit -- that one
     * deliberately stays unmirrored, same as Cryptomator/gocryptfs's
     * create() writing their own initial files straight to the real tree.
     */
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
            VaultOpenResult.InvalidVault("Vault creation failed: ${e.message}")
        }
    }

    /**
     * Rewraps cryfs.config under [newPassword]: decrypts with [oldPassword]
     * exactly like [open] does, then re-serializes the same (unchanged)
     * config payload -- cipher, key, root blob ID, etc. -- with a fresh
     * scrypt salt under the new password, overwriting cryfs.config in
     * place. The encrypted block store itself is untouched, since the
     * underlying encryption key never changes.
     */
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
            context.contentResolver.openOutputStream(configDoc.uri, "wt")?.use { it.write(newConfigBytes) }
                ?: return VaultOpenResult.InvalidVault("Could not write cryfs.config")
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
            return VaultOpenResult.InvalidVault(e.message ?: "Unsupported cipher")
        }
        val mirrorSync = buildMirrorSync(context, vaultRootUri, root)
        val blockStore = CryfsBlockStore(context, root, cipherId, config.encryptionKey, openIntegrityState(context, config), mirrorSync)
        if (blockStore.load(config.rootBlobId) == null) {
            val violation = blockStore.lastIntegrityViolation
            mirrorSync?.teardown()
            return if (violation != null) {
                VaultOpenResult.InvalidVault(
                    "This vault's root directory looks like it was rolled back to an older version " +
                        "(client ${violation.writerClientId}: saw version ${violation.attemptedVersion}, but this " +
                        "device already recorded version ${violation.knownVersion}). Refusing to open it to avoid " +
                        "masking possible data loss or tampering -- this is the same protection CryFS's own error " +
                        "24/25 gives you."
                )
            } else {
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