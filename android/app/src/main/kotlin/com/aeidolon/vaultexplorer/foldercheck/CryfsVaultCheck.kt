package com.aeidolon.vaultexplorer.foldercheck

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.security.SecureRandom

import com.aeidolon.vaultexplorer.cryfs.CryfsBlockCipher
import com.aeidolon.vaultexplorer.cryfs.CryfsBlockId
import com.aeidolon.vaultexplorer.cryfs.CryfsBlockStore
import com.aeidolon.vaultexplorer.cryfs.CryfsConfig
import com.aeidolon.vaultexplorer.cryfs.CryfsConfigFile
import com.aeidolon.vaultexplorer.cryfs.CryfsDataTree
import com.aeidolon.vaultexplorer.cryfs.CryfsDirBlob
import com.aeidolon.vaultexplorer.cryfs.CryfsEntryType
import com.aeidolon.vaultexplorer.cryfs.CryfsFsBlob
import com.aeidolon.vaultexplorer.cryfs.CryfsLocalIntegrityState
import com.aeidolon.vaultexplorer.cryfs.CryfsSession
import com.aeidolon.vaultexplorer.cryfs.CryfsWrongPasswordException
import com.aeidolon.vaultexplorer.saf.SafDocumentOps

/**
 * CryFS half of the folder-vault Check & Repair tool -- see
 * GocryptfsVaultCheck's file doc for why this was split out of the former
 * single-file FolderVaultChecker and why checkCryfs() is `internal` rather
 * than `private`. CryFS has no automatic repair path (see
 * FolderVaultChecker.repair()'s dispatcher), so unlike the other two formats
 * this file only has a check side.
 */
internal object CryfsVaultCheck {

    internal fun checkCryfs(
        context: Context, root: DocumentFile, password: CharArray?, session: CryfsSession?, log: (String) -> Unit,
    ): FolderVaultCheckOutcome {
        val saf = SafDocumentOps(context)
        val issues = mutableListOf<FolderVaultIssue>()

        val configDoc = saf.childOf(root, "cryfs.config")
            ?: return FolderVaultCheckOutcome.InvalidVault("No cryfs.config found.")
        val configBytes = context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
            ?: return FolderVaultCheckOutcome.InvalidVault("Could not read cryfs.config")

        CryfsConfigFile.checkStructure(configBytes)?.let { problem ->
            return FolderVaultCheckOutcome.InvalidVault(problem)
        }

        var scanned = 0
        val onDiskIds = mutableSetOf<String>()
        for (shardDir in saf.listChildren(root)) {
            val shardName = shardDir.name ?: continue
            if (!shardDir.isDirectory || shardName.length != 3 || !shardName.all { it.isCryfsHex() }) continue
            for (blockFile in saf.listChildren(shardDir)) {
                val fileName = blockFile.name ?: continue
                if (fileName.length != 29 || !fileName.all { it.isCryfsHex() }) continue
                scanned++
                onDiskIds += (shardName + fileName).lowercase()
            }
        }

        val config: CryfsConfig
        if (session != null) {
            config = session.config
        } else if (password != null) {
            config = try {
                CryfsConfigFile.parse(configBytes, password)
            } catch (e: CryfsWrongPasswordException) {
                return FolderVaultCheckOutcome.WrongPassword
            } catch (e: Exception) {
                return FolderVaultCheckOutcome.InvalidVault(e.message ?: "cryfs.config error")
            }
        } else {
            return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("cryfs", scanned, issues, false))
        }

        val cipherId = CryfsBlockCipher.cipherIdFor(config.blockCipherName)
        val integrityState = CryfsLocalIntegrityState.open(File(context.filesDir, "cryfs_localstate"), config.filesystemId)
        val blockStore = CryfsBlockStore(context, root, cipherId, config.encryptionKey, integrityState)
        val virtualBlockSize = CryfsBlockStore.calculateVirtualBlockSize(config.blocksizeBytes, config.blockCipherName)
        val dataTree = CryfsDataTree(blockStore, virtualBlockSize, SecureRandom())

        val reachable = mutableSetOf<String>()
        val visitedBlobs = mutableSetOf<String>()

        fun visitBlob(blobId: CryfsBlockId, virtualPath: String) {
            if (!visitedBlobs.add(blobId.hex)) return
            var ok = true
            dataTree.walkBlockTree(blobId) { id, loaded ->
                reachable += id.hex
                if (!loaded) ok = false
            }
            if (!ok) return
            val header = try { CryfsFsBlob.readHeader(dataTree, blobId) } catch (_: Exception) { return }
            if (header.type != CryfsEntryType.DIR) return
            val payload = try { CryfsFsBlob.readWhole(dataTree, blobId).second } catch (_: Exception) { return }
            val entries = try { CryfsDirBlob.parse(payload) } catch (_: Exception) { return }
            for (entry in entries) {
                val childPath = if (virtualPath.isEmpty()) entry.name else "$virtualPath/${entry.name}"
                visitBlob(entry.blobId, childPath)
            }
        }
        visitBlob(config.rootBlobId, "")

        if (session == null) config.encryptionKey.fill(0)
        return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("cryfs", scanned, issues, true))
    }

    private fun Char.isCryfsHex(): Boolean = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
}
