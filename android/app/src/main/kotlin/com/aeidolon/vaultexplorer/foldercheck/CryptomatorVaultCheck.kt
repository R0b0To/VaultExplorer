package com.aeidolon.vaultexplorer.foldercheck

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafIOException
import java.util.UUID

import com.aeidolon.vaultexplorer.cryptomator.CryptomatorAuthenticationException
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorContentCryptor
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorFileNameCryptor
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorMasterkey
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorMasterkeyFile
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorSession
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorVaultConfigParser
import com.aeidolon.vaultexplorer.cryptomator.InvalidPassphraseException
import com.aeidolon.vaultexplorer.cryptomator.MasterkeyFileFormatException
import com.aeidolon.vaultexplorer.cryptomator.VaultConfigException

/**
 * Cryptomator half of the folder-vault Check & Repair tool -- see
 * GocryptfsVaultCheck's file doc for why this was split out of the former
 * single-file FolderVaultChecker and why checkCryptomator()/
 * repairCryptomator() are `internal` rather than `private`.
 */
internal object CryptomatorVaultCheck {

    private val WARNING = FolderVaultIssueSeverity.WARNING
    private val CRITICAL = FolderVaultIssueSeverity.CRITICAL

    internal fun checkCryptomator(
        context: Context, root: DocumentFile, password: CharArray?, session: CryptomatorSession?, log: (String) -> Unit,
    ): FolderVaultCheckOutcome {
        val saf = SafDocumentOps(context)
        val issues = mutableListOf<FolderVaultIssue>()

        log("Reading masterkey.cryptomator…")
        val masterkeyDoc = saf.childOf(root, "masterkey.cryptomator")
            ?: return FolderVaultCheckOutcome.InvalidVault("No masterkey.cryptomator found — this doesn't look like a Cryptomator vault.")
        val masterkeyBytes = context.contentResolver.openInputStream(masterkeyDoc.uri)?.use { it.readBytes() }
            ?: return FolderVaultCheckOutcome.InvalidVault("Could not read masterkey.cryptomator")
        val parsedMasterkey = try {
            CryptomatorMasterkeyFile.parse(masterkeyBytes)
        } catch (e: MasterkeyFileFormatException) {
            return FolderVaultCheckOutcome.InvalidVault(e.message ?: "Malformed masterkey.cryptomator")
        }
        log("masterkey.cryptomator OK.")

        val vaultConfigDoc = saf.childOf(root, "vault.cryptomator")
        val jwt = vaultConfigDoc?.let { doc ->
            context.contentResolver.openInputStream(doc.uri)?.use { it.readBytes() }?.toString(Charsets.UTF_8)
        }
        var cipherCombo = "SIV_CTRMAC"
        if (jwt != null) {
            try {
                val (_, formatFromJwt) = CryptomatorVaultConfigParser.decodeUnverified(jwt)
                log("vault.cryptomator OK (format $formatFromJwt, signature unverified until password given).")
            } catch (e: VaultConfigException) {
                return FolderVaultCheckOutcome.InvalidVault(e.message ?: "Malformed vault.cryptomator")
            }
        } else {
            issues += FolderVaultIssue(WARNING, "/", "No vault.cryptomator found — assuming format-7 vault.")
        }

        val dataDir = saf.childOf(root, "d")
            ?: return FolderVaultCheckOutcome.InvalidVault("Vault is missing its 'd' data directory.")

        if (session == null && password == null) {
            log("No password given — checking the physical storage layout only.")
            val physicalDirCount = checkCryptomatorDataDirShape(saf, dataDir, issues)
            return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("cryptomator", physicalDirCount, issues, false))
        }

        val masterkey: CryptomatorMasterkey
        val nameCryptor: CryptomatorFileNameCryptor
        val contentCryptor: CryptomatorContentCryptor
        if (session != null) {
            masterkey = session.masterkey
            nameCryptor = session.nameCryptor
            contentCryptor = session.contentCryptor
            log("Vault is already unlocked — scanning directory tree with session key…")
        } else {
            masterkey = try {
                CryptomatorMasterkeyFile.unlock(parsedMasterkey, password!!)
            } catch (e: InvalidPassphraseException) {
                return FolderVaultCheckOutcome.WrongPassword
            }
            if (jwt != null) {
                try {
                    val verified = CryptomatorVaultConfigParser.verify(jwt, masterkey)
                    cipherCombo = verified.cipherCombo
                } catch (e: VaultConfigException) {
                    issues += FolderVaultIssue(CRITICAL, "vault.cryptomator", e.message ?: "vault.cryptomator verification failed.")
                }
            }
            log("Password verified — walking directory tree…")
            nameCryptor = CryptomatorFileNameCryptor(masterkey)
            contentCryptor = try {
                CryptomatorContentCryptor.forCipherCombo(cipherCombo)
            } catch (e: VaultConfigException) {
                masterkey.destroy()
                return FolderVaultCheckOutcome.InvalidVault(e.message ?: "Unsupported cipherCombo")
            }
        }

        var filesScanned = 0
        val visitedDirIds = mutableSetOf<String>()

        fun physicalFolderForDirId(dirId: String): DocumentFile? {
            val hash = nameCryptor.hashDirectoryId(dirId)
            val lvl1 = saf.childOf(dataDir, hash.substring(0, 2)) ?: return null
            return saf.childOf(lvl1, hash.substring(2))
        }

        fun checkDirPointer(dirPointer: DocumentFile, virtualPath: String) {
            val size = dirPointer.length()
            if (size <= 0L) {
                issues += FolderVaultIssue(CRITICAL, "$virtualPath/dir.c9r", "dir.c9r is empty — the directory's identity is lost.")
            } else if (size > 1000) {
                issues += FolderVaultIssue(CRITICAL, "$virtualPath/dir.c9r", "dir.c9r is $size bytes, over Cryptomator's limit.")
            }
        }

        fun walkDir(dirId: String, virtualPath: String) {
            if (!visitedDirIds.add(dirId)) {
                issues += FolderVaultIssue(WARNING, virtualPath.ifEmpty { "/" }, "Directory ID cycle detected. Skipping.")
                return
            }
            val physicalFolder = physicalFolderForDirId(dirId)
            if (physicalFolder == null) {
                issues += FolderVaultIssue(CRITICAL, virtualPath.ifEmpty { "/" }, "Directory storage location missing on disk.")
                return
            }
            for (child in saf.listChildren(physicalFolder)) {
                val physName = child.name ?: continue
                try {
                    when {
                        physName == "dir.c9r" || physName == "dirid.c9r" || physName == "symlink.c9r" -> continue
                        physName.endsWith(".c9s") -> {
                            if (!child.isDirectory) {
                                issues += FolderVaultIssue(WARNING, "$virtualPath/$physName", ".c9s entry should be a folder.")
                                continue
                            }
                            val nameFile = saf.childOf(child, "name.c9s")
                            if (nameFile == null) {
                                issues += FolderVaultIssue(CRITICAL, "$virtualPath/$physName", "Shortened node missing name.c9s.")
                                continue
                            }
                            val longCipherName = saf.readWhole(nameFile).toString(Charsets.UTF_8).trim().trimEnd('\u0000', '\r', '\n', ' ').removeSuffix(".c9r").trim()
                            val cleartext = nameCryptor.decryptFilename(longCipherName, dirId.toByteArray(Charsets.UTF_8))
                            val childVirtual = "$virtualPath/$cleartext"
                            val dirPointer = saf.childOf(child, "dir.c9r")
                            if (dirPointer != null) {
                                checkDirPointer(dirPointer, childVirtual)
                                walkDir(saf.readWhole(dirPointer).toString(Charsets.UTF_8), childVirtual)
                            } else {
                                val contents = saf.childOf(child, "contents.c9r")
                                if (contents == null) {
                                    issues += FolderVaultIssue(WARNING, childVirtual, "Shortened file node is missing contents.c9r.")
                                } else {
                                    filesScanned++
                                    verifyCryptomatorFile(context, contents, contentCryptor, masterkey, childVirtual, issues)
                                }
                            }
                        }
                        physName.endsWith(".c9r") -> {
                            val cleartext = nameCryptor.decryptFilename(physName.removeSuffix(".c9r"), dirId.toByteArray(Charsets.UTF_8))
                            val childVirtual = "$virtualPath/$cleartext"
                            if (child.isDirectory) {
                                val dirPointer = saf.childOf(child, "dir.c9r")
                                if (dirPointer == null) {
                                    issues += FolderVaultIssue(CRITICAL, childVirtual, "Directory node is missing dir.c9r.")
                                } else {
                                    checkDirPointer(dirPointer, childVirtual)
                                    walkDir(saf.readWhole(dirPointer).toString(Charsets.UTF_8), childVirtual)
                                }
                            } else {
                                filesScanned++
                                verifyCryptomatorFile(context, child, contentCryptor, masterkey, childVirtual, issues)
                            }
                        }
                        else -> {
                            if (child.isDirectory) {
                                val dirPointer = saf.childOf(child, "dir.c9r")
                                if (dirPointer == null) {
                                    issues += FolderVaultIssue(WARNING, "$virtualPath/$physName", "Foreign directory node is missing dir.c9r.")
                                }
                            }
                        }
                    }
                } catch (e: CryptomatorAuthenticationException) {
                    issues += FolderVaultIssue(CRITICAL, "$virtualPath/$physName", "Filename fails to decrypt: ${e.message}")
                }
            }
        }

        walkDir("", "")
        if (session == null) masterkey.destroy()
        log("Scan complete: $filesScanned file(s) scanned, ${issues.size} issue(s) found.")
        return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("cryptomator", filesScanned, issues, true))
    }
    internal fun repairCryptomator(
        context: Context,
        root: DocumentFile,
        password: CharArray?,
        session: CryptomatorSession?,
        log: (String) -> Unit,
    ): FolderVaultRepairOutcome {
        val saf = SafDocumentOps(context)
        log("Starting Cryptomator Vault Repair & Recovery…")

        val masterkeyDoc = saf.childOf(root, "masterkey.cryptomator")
            ?: return FolderVaultRepairOutcome.InvalidVault("No masterkey.cryptomator found.")
        val masterkeyBytes = context.contentResolver.openInputStream(masterkeyDoc.uri)?.use { it.readBytes() }
            ?: return FolderVaultRepairOutcome.InvalidVault("Could not read masterkey.cryptomator")
        val parsedMasterkey = try {
            CryptomatorMasterkeyFile.parse(masterkeyBytes)
        } catch (e: Exception) {
            return FolderVaultRepairOutcome.InvalidVault("Malformed masterkey.cryptomator")
        }

        val masterkey: CryptomatorMasterkey
        val nameCryptor: CryptomatorFileNameCryptor
        val contentCryptor: CryptomatorContentCryptor

        if (session != null) {
            masterkey = session.masterkey
            nameCryptor = session.nameCryptor
            contentCryptor = session.contentCryptor
            log("Using active session key for recovery.")
        } else {
            if (password == null) {
                return FolderVaultRepairOutcome.WrongPassword
            }
            masterkey = try {
                CryptomatorMasterkeyFile.unlock(parsedMasterkey, password)
            } catch (e: InvalidPassphraseException) {
                return FolderVaultRepairOutcome.WrongPassword
            }
            nameCryptor = CryptomatorFileNameCryptor(masterkey)
            val vaultConfigDoc = saf.childOf(root, "vault.cryptomator")
            val jwt = vaultConfigDoc?.let { doc ->
                context.contentResolver.openInputStream(doc.uri)?.use { it.readBytes() }?.toString(Charsets.UTF_8)
            }
            var cipherCombo = "SIV_GCM"
            if (jwt != null) {
                try {
                    cipherCombo = CryptomatorVaultConfigParser.verify(jwt, masterkey).cipherCombo
                } catch (_: Exception) {}
            }
            contentCryptor = CryptomatorContentCryptor.forCipherCombo(cipherCombo)
        }

        val dataDir = saf.childOf(root, "d")
            ?: return FolderVaultRepairOutcome.InvalidVault("Vault missing 'd' data directory.")

        var fixedCount = 0
        var recoveredCount = 0
        var removedCount = 0

        fun physicalFolderForDirId(dirId: String): DocumentFile? {
            val hash = nameCryptor.hashDirectoryId(dirId)
            val lvl1 = saf.childOf(dataDir, hash.substring(0, 2)) ?: return null
            return saf.childOf(lvl1, hash.substring(2))
        }

        fun ensurePhysicalFolderForDirId(dirId: String): DocumentFile {
            val hash = nameCryptor.hashDirectoryId(dirId)
            val lvl1Name = hash.substring(0, 2)
            val lvl2Name = hash.substring(2)
            val lvl1 = saf.childOf(dataDir, lvl1Name) ?: saf.createDirectorySafe(dataDir, lvl1Name)
                ?: throw SafIOException("Cannot create $lvl1Name")
            return saf.childOf(lvl1, lvl2Name) ?: saf.createDirectorySafe(lvl1, lvl2Name)
                ?: throw SafIOException("Cannot create $lvl2Name")
        }

        val rootPhysical = ensurePhysicalFolderForDirId("")

        fun getOrCreateLostFoundFolder(): Pair<String, DocumentFile> {
            val rootChildren = saf.listChildren(rootPhysical)
            for (child in rootChildren) {
                val name = child.name ?: continue
                if (name.endsWith(".c9r") && child.isDirectory) {
                    try {
                        val clear = nameCryptor.decryptFilename(name.removeSuffix(".c9r"), "".toByteArray(Charsets.UTF_8))
                        if (clear == "LOST+FOUND") {
                            val dirPointer = saf.childOf(child, "dir.c9r")
                            if (dirPointer != null) {
                                val id = saf.readWhole(dirPointer).toString(Charsets.UTF_8)
                                val physical = physicalFolderForDirId(id)
                                if (physical != null) return id to physical
                            }
                        }
                    } catch (_: Exception) {}
                }
            }
            val lostFoundDirId = UUID.randomUUID().toString()
            val encName = nameCryptor.encryptFilename("LOST+FOUND", "".toByteArray(Charsets.UTF_8))
            val nodeFolder = saf.createDirectorySafe(rootPhysical, "$encName.c9r")
                ?: throw SafIOException("Could not create LOST+FOUND node folder")
            var dirFile = saf.createFileSafe(nodeFolder, "application/octet-stream", "dir.c9r")
                ?: throw SafIOException("Could not create dir.c9r")
            if (dirFile.name != "dir.c9r") dirFile = saf.renameDocumentAndGet(dirFile, "dir.c9r")
            saf.writeWhole(dirFile, lostFoundDirId.toByteArray(Charsets.UTF_8))
            val physical = ensurePhysicalFolderForDirId(lostFoundDirId)
            return lostFoundDirId to physical
        }

        val visitedDirIds = mutableSetOf<String>()
        val referencedDirHashes = mutableSetOf<String>()

        fun repairDir(dirId: String, virtualPath: String) {
            if (!visitedDirIds.add(dirId)) return
            val hash = nameCryptor.hashDirectoryId(dirId)
            referencedDirHashes.add(hash)

            val physicalFolder = physicalFolderForDirId(dirId) ?: ensurePhysicalFolderForDirId(dirId)
            val children = saf.listChildren(physicalFolder)

            for (child in children) {
                val physName = child.name ?: continue
                if (physName == "dir.c9r" || physName == "dirid.c9r" || physName == "symlink.c9r") continue

                if (child.isDirectory) {
                    var decryptedName: String? = null
                    var isCorruptName = false

                    if (physName.endsWith(".c9r")) {
                        try {
                            decryptedName = nameCryptor.decryptFilename(physName.removeSuffix(".c9r"), dirId.toByteArray(Charsets.UTF_8))
                        } catch (_: Exception) {
                            isCorruptName = true
                        }
                    } else if (physName.endsWith(".c9s")) {
                        val nameFile = saf.childOf(child, "name.c9s")
                        if (nameFile != null) {
                            try {
                                val longCipherName = saf.readWhole(nameFile).toString(Charsets.UTF_8).trim().removeSuffix(".c9r").trim()
                                decryptedName = nameCryptor.decryptFilename(longCipherName, dirId.toByteArray(Charsets.UTF_8))
                            } catch (_: Exception) {
                                isCorruptName = true
                            }
                        } else {
                            isCorruptName = true
                        }
                    } else {
                        decryptedName = physName
                    }

                    val dirPointer = saf.childOf(child, "dir.c9r")
                    val contentsFile = saf.childOf(child, "contents.c9r")

                    if (dirPointer != null) {
                        val ptrBytes = saf.readWhole(dirPointer)
                        val childDirId = String(ptrBytes, Charsets.UTF_8).trim()
                        if (childDirId.isEmpty() || ptrBytes.size > 1000) {
                            val newUuid = UUID.randomUUID().toString()
                            saf.writeWhole(dirPointer, newUuid.toByteArray(Charsets.UTF_8))
                            ensurePhysicalFolderForDirId(newUuid)
                            fixedCount++
                            log("Fixed corrupt dir.c9r in ${virtualPath}/$physName")
                            repairDir(newUuid, "$virtualPath/${decryptedName ?: "recovered_dir"}")
                        } else if (isCorruptName) {
                            val (lfId, lfFolder) = getOrCreateLostFoundFolder()
                            val newEncName = nameCryptor.encryptFilename("recovered_dir_${childDirId.take(8)}", lfId.toByteArray(Charsets.UTF_8))
                            val newFolder = saf.createDirectorySafe(lfFolder, "$newEncName.c9r")
                            if (newFolder != null) {
                                var newDirFile = saf.createFileSafe(newFolder, "application/octet-stream", "dir.c9r")
                                if (newDirFile != null) {
                                    if (newDirFile.name != "dir.c9r") newDirFile = saf.renameDocumentAndGet(newDirFile, "dir.c9r")
                                    saf.writeWhole(newDirFile, childDirId.toByteArray(Charsets.UTF_8))
                                }
                                saf.deleteRecursively(child)
                                recoveredCount++
                                log("Recovered directory with corrupted name to /LOST+FOUND/recovered_dir_${childDirId.take(8)}")
                            }
                            repairDir(childDirId, "/LOST+FOUND/recovered_dir_${childDirId.take(8)}")
                        } else {
                            repairDir(childDirId, "$virtualPath/${decryptedName ?: physName}")
                        }
                    } else if (contentsFile != null) {
                        if (isCorruptName) {
                            val (lfId, lfFolder) = getOrCreateLostFoundFolder()
                            val newEncName = nameCryptor.encryptFilename("recovered_file_${physName.take(8)}.bin", lfId.toByteArray(Charsets.UTF_8))
                            saf.copyDocumentRecursive(contentsFile, lfFolder)
                            saf.deleteRecursively(child)
                            recoveredCount++
                            log("Rescued shortened file with corrupted name to /LOST+FOUND")
                        }
                    } else {
                        val innerChildren = saf.listChildren(child)
                        if (innerChildren.isEmpty() || (innerChildren.size == 1 && innerChildren[0].name == "name.c9s")) {
                            saf.deleteRecursively(child)
                            removedCount++
                            log("Removed empty invalid directory node: ${virtualPath}/$physName")
                        } else {
                            val newUuid = UUID.randomUUID().toString()
                            var newDirDoc = saf.createFileSafe(child, "application/octet-stream", "dir.c9r")
                            if (newDirDoc != null) {
                                if (newDirDoc.name != "dir.c9r") newDirDoc = saf.renameDocumentAndGet(newDirDoc, "dir.c9r")
                                saf.writeWhole(newDirDoc, newUuid.toByteArray(Charsets.UTF_8))
                                ensurePhysicalFolderForDirId(newUuid)
                                fixedCount++
                                log("Restored missing dir.c9r for directory: ${virtualPath}/$physName")
                                repairDir(newUuid, "$virtualPath/${decryptedName ?: physName}")
                            }
                        }
                    }
                } else if (child.isFile) {
                    var isCorruptName = false
                    if (physName.endsWith(".c9r")) {
                        try {
                            nameCryptor.decryptFilename(physName.removeSuffix(".c9r"), dirId.toByteArray(Charsets.UTF_8))
                        } catch (_: Exception) {
                            isCorruptName = true
                        }
                    }
                    if (isCorruptName) {
                        val headerBytes = ByteArray(contentCryptor.headerSize)
                        val hasHeader = try {
                            context.contentResolver.openInputStream(child.uri)?.use { stream ->
                                var total = 0
                                while (total < headerBytes.size) {
                                    val count = stream.read(headerBytes, total, headerBytes.size - total)
                                    if (count < 0) break
                                    total += count
                                }
                                total == headerBytes.size
                            } == true
                        } catch (_: Exception) { false }

                        val isValidHeader = if (hasHeader) {
                            try {
                                contentCryptor.decryptHeader(headerBytes, masterkey)
                                true
                            } catch (_: Exception) { false }
                        } else false

                        if (isValidHeader) {
                            val (lfId, lfFolder) = getOrCreateLostFoundFolder()
                            val newEncName = nameCryptor.encryptFilename("recovered_file_${physName.take(8)}.bin", lfId.toByteArray(Charsets.UTF_8))
                            saf.copyDocumentRecursive(child, lfFolder)
                            saf.deleteRecursively(child)
                            recoveredCount++
                            log("Recovered file with damaged filename to /LOST+FOUND/recovered_file_${physName.take(8)}.bin")
                        } else if (child.length() == 0L) {
                            saf.deleteRecursively(child)
                            removedCount++
                            log("Removed 0-byte corrupt file: $physName")
                        }
                    }
                }
            }
        }

        log("Inspecting directory hierarchy…")
        repairDir("", "")

        log("Checking for orphaned data folders in storage…")
        for (lvl1 in saf.listChildren(dataDir)) {
            val lvl1Name = lvl1.name ?: continue
            if (!lvl1.isDirectory || lvl1Name.length != 2) continue
            for (lvl2 in saf.listChildren(lvl1)) {
                val lvl2Name = lvl2.name ?: continue
                if (!lvl2.isDirectory || lvl2Name.length != 30) continue
                val fullHash = (lvl1Name + lvl2Name).uppercase()
                if (!referencedDirHashes.contains(fullHash)) {
                    val contents = saf.listChildren(lvl2).filter {
                        val n = it.name
                        n != "dirid.c9r" && n != "dir.c9r" && n != "symlink.c9r"
                    }
                    if (contents.isNotEmpty()) {
                        val (lfId, lfFolder) = getOrCreateLostFoundFolder()
                        val orphanDirId = UUID.randomUUID().toString()
                        val encName = nameCryptor.encryptFilename("orphan_data_${fullHash.take(6)}", lfId.toByteArray(Charsets.UTF_8))
                        val orphanNode = saf.createDirectorySafe(lfFolder, "$encName.c9r")
                        if (orphanNode != null) {
                            var dirFile = saf.createFileSafe(orphanNode, "application/octet-stream", "dir.c9r")
                            if (dirFile != null) {
                                if (dirFile.name != "dir.c9r") dirFile = saf.renameDocumentAndGet(dirFile, "dir.c9r")
                                saf.writeWhole(dirFile, orphanDirId.toByteArray(Charsets.UTF_8))
                                val targetPhysical = ensurePhysicalFolderForDirId(orphanDirId)
                                for (item in contents) {
                                    saf.movePhysicalDocument(item, lvl2, targetPhysical)
                                }
                                recoveredCount++
                                log("Adopted orphaned storage directory into /LOST+FOUND/orphan_data_${fullHash.take(6)}")
                            }
                        }
                    } else {
                        saf.deleteRecursively(lvl2)
                        removedCount++
                    }
                }
            }
        }

        saf.invalidateAll()
        session?.invalidateCache("")

        log("Re-verifying vault after repairs…")
        val postCheck = checkCryptomator(context, root, password, session, {})
        val remaining = if (postCheck is FolderVaultCheckOutcome.Success) postCheck.report.issues else emptyList()

        if (session == null) masterkey.destroy()

        val report = FolderVaultRepairReport("cryptomator", fixedCount, recoveredCount, removedCount, remaining)
        log("Repair complete: $fixedCount fixed, $recoveredCount recovered to /LOST+FOUND, $removedCount cleaned up.")
        return FolderVaultRepairOutcome.Success(report)
    }
    private fun checkCryptomatorDataDirShape(saf: SafDocumentOps, dataDir: DocumentFile, issues: MutableList<FolderVaultIssue>): Int {
        var count = 0
        for (lvl1 in saf.listChildren(dataDir)) {
            val name1 = lvl1.name ?: continue
            if (!lvl1.isDirectory || name1.length != 2) continue
            for (lvl2 in saf.listChildren(lvl1)) {
                val name2 = lvl2.name ?: continue
                if (!lvl2.isDirectory || name2.length != 30) continue
                count++
            }
        }
        return count
    }
    private fun verifyCryptomatorFile(
        context: Context, file: DocumentFile, cryptor: CryptomatorContentCryptor, masterkey: CryptomatorMasterkey,
        virtualPath: String, issues: MutableList<FolderVaultIssue>,
    ) {
        try {
            context.contentResolver.openInputStream(file.uri)?.use { input ->
                val headerBuf = ByteArray(cryptor.headerSize)
                val headerRead = input.readFullyInto(headerBuf)
                if (headerRead == 0) return
                if (headerRead < headerBuf.size) {
                    issues += FolderVaultIssue(WARNING, virtualPath, "File shorter than header — truncated.")
                    return
                }
                val header = try {
                    cryptor.decryptHeader(headerBuf, masterkey)
                } catch (e: CryptomatorAuthenticationException) {
                    issues += FolderVaultIssue(CRITICAL, virtualPath, "File header fails authentication.")
                    return
                }
                var chunkNumber = 0L
                val chunkBuf = ByteArray(cryptor.ciphertextChunkSize)
                while (true) {
                    val n = input.readFullyInto(chunkBuf)
                    if (n <= 0) break
                    val chunk = if (n == chunkBuf.size) chunkBuf else chunkBuf.copyOf(n)
                    try {
                        cryptor.decryptChunk(chunk, chunkNumber, header, masterkey)
                    } catch (e: CryptomatorAuthenticationException) {
                        issues += FolderVaultIssue(CRITICAL, virtualPath, "Chunk $chunkNumber authentication failed.")
                        return
                    }
                    chunkNumber++
                }
            }
        } catch (e: Exception) {
            issues += FolderVaultIssue(WARNING, virtualPath, "Error: ${e.message}")
        }
    }
}
