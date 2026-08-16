package com.aeidolon.vaultexplorer.foldercheck

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.io.File
import java.io.InputStream
import java.security.SecureRandom

import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsCipher
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsConfig
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsConfigException
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsContentAuthException
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsContentCryptor
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsFileNameCryptor
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsMasterkey
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsWrongPasswordException
import com.aeidolon.vaultexplorer.gocryptfs.Hkdf

import com.aeidolon.vaultexplorer.cryfs.CryfsBlockCipher
import com.aeidolon.vaultexplorer.cryfs.CryfsBlockId
import com.aeidolon.vaultexplorer.cryfs.CryfsBlockStore
import com.aeidolon.vaultexplorer.cryfs.CryfsConfigException
import com.aeidolon.vaultexplorer.cryfs.CryfsConfigFile
import com.aeidolon.vaultexplorer.cryfs.CryfsDataTree
import com.aeidolon.vaultexplorer.cryfs.CryfsDirBlob
import com.aeidolon.vaultexplorer.cryfs.CryfsEntryType
import com.aeidolon.vaultexplorer.cryfs.CryfsFsBlob
import com.aeidolon.vaultexplorer.cryfs.CryfsLocalIntegrityState
import com.aeidolon.vaultexplorer.cryfs.CryfsUnsupportedCipherException
import com.aeidolon.vaultexplorer.cryfs.CryfsWrongPasswordException

import com.aeidolon.vaultexplorer.cryptomator.CryptomatorAuthenticationException
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorContentCryptor
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorFileNameCryptor
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorMasterkey
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorMasterkeyFile
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorVaultConfigParser
import com.aeidolon.vaultexplorer.cryptomator.InvalidPassphraseException
import com.aeidolon.vaultexplorer.cryptomator.MasterkeyFileFormatException
import com.aeidolon.vaultexplorer.cryptomator.VaultConfigException

/**
 * Native engine backing the Flutter Check & Repair tool's folder-vault
 * support (see [ContainerToolService.checkFolderVault] on the Dart side).
 *
 * Unlike VeraCrypt/LUKS/BitLocker (container_repair.cpp/.h), gocryptfs,
 * CryFS, and Cryptomator vaults aren't a single container file wrapping a
 * block-device filesystem -- they're a *directory tree* of individually
 * encrypted files, so "check" here means something different: walk that
 * tree and, for every entry, verify whatever can be verified at that
 * layer (config envelope, on-disk block/file structure, and -- once a
 * password is supplied -- every file's own AEAD authentication tag).
 *
 * None of the three upstream projects ship an automatic *repair* for this
 * kind of corruption (see the doc comment on [FolderVaultCheckReport]),
 * so this only ever reports problems; it never rewrites anything.
 *
 * Two scan depths, mirroring the password-optional pattern
 * [ContainerToolService.diagnoseTarget]/[restoreBackupHeader] already use
 * for VeraCrypt:
 *  - No password: structural checks only -- config files parse, on-disk
 *    naming/magic bytes look right, ciphertext sizes line up with the
 *    format's block/chunk structure. Cheap, and doesn't require trusting
 *    this tool with the vault's password.
 *  - With password: everything above, plus decrypting and AEAD-verifying
 *    every file's header and every content chunk (exactly what upstream
 *    `gocryptfs -fsck` does), and -- for CryFS and Cryptomator, whose
 *    directory structure is itself encrypted -- walking the *decrypted*
 *    tree to find blocks/directories that are missing, corrupt, or
 *    unreachable.
 */
enum class FolderVaultIssueSeverity(val wire: Int) { INFO(0), WARNING(1), CRITICAL(2) }

data class FolderVaultIssue(
    val severity: FolderVaultIssueSeverity,
    /** Cleartext path when decryptable, otherwise the closest on-disk path we could resolve. */
    val path: String,
    val message: String,
)

/**
 * [filesScanned] is a rough per-format count of leaf entries examined
 * (ciphertext files for gocryptfs/Cryptomator, on-disk blocks for CryFS)
 * -- meant for the log panel's summary line, not as an exact inventory.
 * [deepScanPerformed] is true once a password was supplied and used, i.e.
 * every issue that *content* authentication could catch was actually
 * checked, not just structure.
 */
data class FolderVaultCheckReport(
    val formatWire: String,
    val filesScanned: Int,
    val issues: List<FolderVaultIssue>,
    val deepScanPerformed: Boolean,
) {
    val healthy: Boolean get() = issues.none { it.severity != FolderVaultIssueSeverity.INFO }
}

sealed class FolderVaultCheckOutcome {
    data class Success(val report: FolderVaultCheckReport) : FolderVaultCheckOutcome()
    data class InvalidVault(val message: String) : FolderVaultCheckOutcome()
    object WrongPassword : FolderVaultCheckOutcome()
}

object FolderVaultChecker {

    private val WARNING = FolderVaultIssueSeverity.WARNING
    private val CRITICAL = FolderVaultIssueSeverity.CRITICAL
    private val INFO = FolderVaultIssueSeverity.INFO

    fun check(
        context: Context,
        vaultRootUri: Uri,
        formatWire: String,
        password: CharArray?,
        log: (String) -> Unit = {},
    ): FolderVaultCheckOutcome {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return FolderVaultCheckOutcome.InvalidVault("Cannot access the selected folder.")
        return try {
            when (formatWire) {
                "gocryptfs" -> checkGocryptfs(context, root, password, log)
                "cryfs" -> checkCryfs(context, root, password, log)
                "cryptomator", "directory_vault" -> checkCryptomator(context, root, password, log)
                else -> FolderVaultCheckOutcome.InvalidVault("Unsupported folder vault format: $formatWire")
            }
        } finally {
            password?.fill(' ')
        }
    }

    // ── gocryptfs ────────────────────────────────────────────────────────

    private fun checkGocryptfs(
        context: Context, root: DocumentFile, password: CharArray?, log: (String) -> Unit,
    ): FolderVaultCheckOutcome {
        val saf = SafDocumentOps(context)
        val issues = mutableListOf<FolderVaultIssue>()

        log("Reading gocryptfs.conf…")
        val configDoc = saf.childOf(root, "gocryptfs.conf")
            ?: return FolderVaultCheckOutcome.InvalidVault("No gocryptfs.conf found — this doesn't look like a gocryptfs vault.")
        val configBytes = context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
            ?: return FolderVaultCheckOutcome.InvalidVault("Could not read gocryptfs.conf")
        val config = try {
            GocryptfsConfig.parse(configBytes)
        } catch (e: GocryptfsConfigException) {
            return FolderVaultCheckOutcome.InvalidVault(e.message ?: "Malformed gocryptfs.conf")
        }
        log("Config OK — cipher=${config.cipher}, plaintextNames=${config.plaintextNames}, dirIV=${config.hasDirIV}")

        var nameCryptor: GocryptfsFileNameCryptor? = null
        var contentCryptor: GocryptfsContentCryptor? = null
        if (password != null) {
            val masterkey = try {
                GocryptfsMasterkey.unlock(config, password)
            } catch (e: GocryptfsWrongPasswordException) {
                return FolderVaultCheckOutcome.WrongPassword
            }
            val nameKey = if (config.plaintextNames) ByteArray(0) else Hkdf.deriveSha256(masterkey, "EME filename encryption", 32)
            val hkdfInfo = when (config.cipher) {
                GocryptfsCipher.AES_256_GCM -> "AES-GCM file content encryption"
                GocryptfsCipher.XCHACHA20_POLY1305 -> "XChaCha20-Poly1305 file content encryption"
            }
            val contentKey = Hkdf.deriveSha256(masterkey, hkdfInfo, 32)
            masterkey.fill(0)
            nameCryptor = GocryptfsFileNameCryptor(nameKey, config.longNameMax, config.plaintextNames)
            contentCryptor = GocryptfsContentCryptor(contentKey, config.cipher)
            log("Password verified — scanning file contents too (this can take a while for large vaults)…")
        } else {
            log("No password given — checking structure only (sizes, gocryptfs.diriv presence). Provide a password for a full content scan.")
        }

        val nonceLen = when (config.cipher) {
            GocryptfsCipher.AES_256_GCM -> 16
            GocryptfsCipher.XCHACHA20_POLY1305 -> 24
        }
        val expectedChunkSize = nonceLen + GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE + 16
        val headerLen = GocryptfsContentCryptor.HEADER_LEN
        var filesScanned = 0

        fun walk(dir: DocumentFile, virtualPath: String) {
            val children = saf.listChildren(dir)
            var diriv: ByteArray? = null
            if (config.hasDirIV) {
                val dirivDoc = children.firstOrNull { it.name == GocryptfsFileNameCryptor.DIRIV_FILENAME }
                if (dirivDoc == null) {
                    issues += FolderVaultIssue(
                        CRITICAL, virtualPath.ifEmpty { "/" },
                        "Missing gocryptfs.diriv — every filename in this directory is unrecoverable without it.",
                    )
                } else {
                    val bytes = saf.readWhole(dirivDoc)
                    if (bytes.size != 16) {
                        issues += FolderVaultIssue(
                            CRITICAL, "$virtualPath/gocryptfs.diriv",
                            "gocryptfs.diriv is ${bytes.size} bytes, expected 16 — filenames here can't be decrypted.",
                        )
                    } else {
                        diriv = bytes
                    }
                }
            } else {
                diriv = ZERO_DIRIV
            }

            val byPhysicalName = children.associateBy { it.name }
            for (child in children) {
                val physName = child.name ?: continue
                if (physName == GocryptfsFileNameCryptor.DIRIV_FILENAME) continue
                if (physName.endsWith(GocryptfsFileNameCryptor.LONGNAME_SUFFIX)) continue // consumed via its sibling below

                var ciphertextName = physName
                if (physName.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX)) {
                    val nameFile = byPhysicalName[physName + GocryptfsFileNameCryptor.LONGNAME_SUFFIX]
                    if (nameFile == null) {
                        issues += FolderVaultIssue(WARNING, "$virtualPath/$physName", "Long-name file has no matching .name sidecar — orphaned, can't be resolved to a filename.")
                        continue
                    }
                    ciphertextName = saf.readWhole(nameFile).toString(Charsets.UTF_8)
                }

                var cleartextName = physName
                if (diriv != null && nameCryptor != null) {
                    try {
                        cleartextName = nameCryptor.decryptName(ciphertextName, diriv)
                    } catch (e: Exception) {
                        issues += FolderVaultIssue(CRITICAL, "$virtualPath/$physName", "Filename doesn't decrypt: ${e.message}")
                    }
                }
                val childVirtualPath = if (virtualPath.isEmpty()) cleartextName else "$virtualPath/$cleartextName"

                if (child.isDirectory) {
                    walk(child, childVirtualPath)
                } else {
                    filesScanned++
                    val size = child.length()
                    if (size in 1 until headerLen) {
                        issues += FolderVaultIssue(WARNING, childVirtualPath, "File is only $size byte(s) — shorter than gocryptfs's own $headerLen-byte header. Truncated.")
                    } else if (size > headerLen) {
                        val body = size - headerLen
                        val remainder = body % expectedChunkSize
                        if (remainder != 0L && remainder < nonceLen + 16) {
                            issues += FolderVaultIssue(WARNING, childVirtualPath, "Ciphertext size doesn't line up with gocryptfs's block structure — looks truncated mid-block.")
                        }
                    }
                    if (contentCryptor != null && size > 0) {
                        verifyGocryptfsFile(context, child, contentCryptor, childVirtualPath, issues)
                    }
                }
            }
        }

        log("Walking vault tree…")
        walk(root, "")
        log("Scan complete: $filesScanned file(s) scanned, ${issues.size} issue(s) found.")
        return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("gocryptfs", filesScanned, issues, contentCryptor != null))
    }

    private fun verifyGocryptfsFile(
        context: Context, file: DocumentFile, cryptor: GocryptfsContentCryptor,
        virtualPath: String, issues: MutableList<FolderVaultIssue>,
    ) {
        try {
            val opened = context.contentResolver.openInputStream(file.uri)
            if (opened == null) {
                issues += FolderVaultIssue(WARNING, virtualPath, "Could not open file for content verification.")
                return
            }
            opened.use { input ->
                val headerBuf = ByteArray(GocryptfsContentCryptor.HEADER_LEN)
                val headerRead = input.readFullyInto(headerBuf)
                if (headerRead < headerBuf.size) {
                    issues += FolderVaultIssue(WARNING, virtualPath, "File is shorter than the file header — truncated.")
                    return
                }
                val header = try {
                    cryptor.decodeHeader(headerBuf)
                } catch (e: GocryptfsContentAuthException) {
                    issues += FolderVaultIssue(CRITICAL, virtualPath, "Bad file header: ${e.message}")
                    return
                }
                var chunkNumber = 0L
                val chunkBuf = ByteArray(cryptor.ciphertextChunkSize)
                while (true) {
                    val n = input.readFullyInto(chunkBuf)
                    if (n <= 0) break
                    val chunk = if (n == chunkBuf.size) chunkBuf else chunkBuf.copyOf(n)
                    try {
                        cryptor.decryptChunk(chunk, chunkNumber, header)
                    } catch (e: GocryptfsContentAuthException) {
                        issues += FolderVaultIssue(CRITICAL, virtualPath, "Chunk $chunkNumber failed to authenticate — corrupted or tampered.")
                        return
                    }
                    chunkNumber++
                }
            }
        } catch (e: Exception) {
            issues += FolderVaultIssue(WARNING, virtualPath, "Error reading file: ${e.message}")
        }
    }

    // ── CryFS ────────────────────────────────────────────────────────────

    private fun checkCryfs(
        context: Context, root: DocumentFile, password: CharArray?, log: (String) -> Unit,
    ): FolderVaultCheckOutcome {
        val saf = SafDocumentOps(context)
        val issues = mutableListOf<FolderVaultIssue>()

        log("Reading cryfs.config…")
        val configDoc = saf.childOf(root, "cryfs.config")
            ?: return FolderVaultCheckOutcome.InvalidVault("No cryfs.config found — this doesn't look like a CryFS vault.")
        val configBytes = context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
            ?: return FolderVaultCheckOutcome.InvalidVault("Could not read cryfs.config")

        CryfsConfigFile.checkStructure(configBytes)?.let { problem ->
            return FolderVaultCheckOutcome.InvalidVault(problem)
        }
        log("cryfs.config envelope OK.")

        log("Scanning the block store for obviously invalid files…")
        var scanned = 0
        val onDiskIds = mutableSetOf<String>()
        for (shardDir in saf.listChildren(root)) {
            val shardName = shardDir.name ?: continue
            if (!shardDir.isDirectory || shardName.length != 3 || !shardName.all { it.isCryfsHex() }) continue
            for (blockFile in saf.listChildren(shardDir)) {
                val fileName = blockFile.name ?: continue
                if (fileName.length != 29 || !fileName.all { it.isCryfsHex() }) {
                    issues += FolderVaultIssue(WARNING, "$shardName/$fileName", "Doesn't look like a CryFS block ID — foreign file inside the block store.")
                    continue
                }
                scanned++
                onDiskIds += (shardName + fileName).lowercase()
                val prefix = readPrefix(context, blockFile, CryfsBlockStore.MAGIC_PREFIX.size)
                if (!prefix.contentEquals(CryfsBlockStore.MAGIC_PREFIX)) {
                    issues += FolderVaultIssue(CRITICAL, "$shardName/$fileName", "Block doesn't start with CryFS's block header — corrupted, truncated, or a foreign file.")
                }
            }
        }
        log("$scanned block file(s) found on disk.")

        if (password == null) {
            log("No password given — skipping the tree-connectivity check (it needs the vault key to read the directory index). Provide a password for a full scan.")
            return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("cryfs", scanned, issues, false))
        }

        val config = try {
            CryfsConfigFile.parse(configBytes, password)
        } catch (e: CryfsWrongPasswordException) {
            return FolderVaultCheckOutcome.WrongPassword
        } catch (e: CryfsUnsupportedCipherException) {
            return FolderVaultCheckOutcome.InvalidVault(e.message ?: "Unsupported cipher")
        } catch (e: CryfsConfigException) {
            return FolderVaultCheckOutcome.InvalidVault(e.message ?: "Malformed cryfs.config")
        }
        log("Password verified — walking the block tree from the root directory…")

        val cipherId = try {
            CryfsBlockCipher.cipherIdFor(config.blockCipherName)
        } catch (e: Exception) {
            config.encryptionKey.fill(0)
            return FolderVaultCheckOutcome.InvalidVault("Unsupported cipher ${config.blockCipherName}")
        }
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
                if (!loaded) {
                    ok = false
                    val violation = blockStore.lastIntegrityViolation
                    val detail = if (violation != null && violation.blockId == id) {
                        "looks like it was rolled back to an older version -- client ${violation.writerClientId} " +
                            "claims version ${violation.attemptedVersion}, but this device already recorded version " +
                            "${violation.knownVersion} for it. Likely cause: this vault was edited from another " +
                            "app/device whose own local version history is out of sync with this one."
                    } else {
                        "is missing or fails to authenticate."
                    }
                    issues += FolderVaultIssue(CRITICAL, virtualPath.ifEmpty { "/" }, "Block ${id.hex}, referenced from here, $detail")
                }
            }
            if (!ok) return
            val unwrapped = try {
                CryfsFsBlob.readWhole(dataTree, blobId)
            } catch (e: CryfsFsBlob.CorruptBlobException) {
                issues += FolderVaultIssue(CRITICAL, virtualPath.ifEmpty { "/" }, e.message ?: "Corrupt blob header.")
                return
            }
            val (header, payload) = unwrapped
            if (header.type != CryfsEntryType.DIR) return
            val entries = try {
                CryfsDirBlob.parse(payload)
            } catch (e: Exception) {
                issues += FolderVaultIssue(CRITICAL, virtualPath.ifEmpty { "/" }, "Directory entries are corrupt: ${e.message}")
                return
            }
            for (entry in entries) {
                val childPath = if (virtualPath.isEmpty()) entry.name else "$virtualPath/${entry.name}"
                visitBlob(entry.blobId, childPath)
            }
        }
        visitBlob(config.rootBlobId, "")

        val orphaned = onDiskIds - reachable
        if (orphaned.isNotEmpty()) {
            issues += FolderVaultIssue(
                INFO, "/",
                "${orphaned.size} block(s) on disk aren't reachable from the root directory — most likely leftovers from deleted files; harmless, but reclaimable.",
            )
        }
        config.encryptionKey.fill(0)

        log("Scan complete: ${visitedBlobs.size} blob(s) walked, ${reachable.size} block(s) reachable, ${issues.size} issue(s) found.")
        return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("cryfs", scanned, issues, true))
    }

    // ── Cryptomator ──────────────────────────────────────────────────────

    private fun checkCryptomator(
        context: Context, root: DocumentFile, password: CharArray?, log: (String) -> Unit,
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
        var cipherCombo = "SIV_CTRMAC" // pre-vault.cryptomator format-7 default
        if (jwt != null) {
            try {
                val (_, formatFromJwt) = CryptomatorVaultConfigParser.decodeUnverified(jwt)
                log("vault.cryptomator OK (format $formatFromJwt, signature unverified until password given).")
            } catch (e: VaultConfigException) {
                return FolderVaultCheckOutcome.InvalidVault(e.message ?: "Malformed vault.cryptomator")
            }
        } else {
            issues += FolderVaultIssue(WARNING, "/", "No vault.cryptomator found — assuming a very old format-7 vault.")
        }

        val dataDir = saf.childOf(root, "d")
            ?: return FolderVaultCheckOutcome.InvalidVault("Vault is missing its 'd' data directory.")

        if (password == null) {
            log("No password given — directory IDs and filenames are encrypted, so the tree walk needs a password too. Checking the physical storage layout only.")
            val physicalDirCount = checkCryptomatorDataDirShape(saf, dataDir, issues)
            return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("cryptomator", physicalDirCount, issues, false))
        }

        val masterkey = try {
            CryptomatorMasterkeyFile.unlock(parsedMasterkey, password)
        } catch (e: InvalidPassphraseException) {
            return FolderVaultCheckOutcome.WrongPassword
        }
        if (jwt != null) {
            try {
                val verified = CryptomatorVaultConfigParser.verify(jwt, masterkey)
                cipherCombo = verified.cipherCombo
            } catch (e: VaultConfigException) {
                issues += FolderVaultIssue(CRITICAL, "vault.cryptomator", e.message ?: "vault.cryptomator verification failed — wrong password or corrupted config.")
            }
        }
        log("Password verified — walking the directory tree…")

        val nameCryptor = CryptomatorFileNameCryptor(masterkey)
        val contentCryptor = try {
            CryptomatorContentCryptor.forCipherCombo(cipherCombo)
        } catch (e: VaultConfigException) {
            masterkey.destroy()
            return FolderVaultCheckOutcome.InvalidVault(e.message ?: "Unsupported cipherCombo")
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
                issues += FolderVaultIssue(CRITICAL, "$virtualPath/dir.c9r", "dir.c9r is $size bytes, over Cryptomator's 1000-byte limit — corrupted.")
            }
        }

        fun walkDir(dirId: String, virtualPath: String) {
            if (!visitedDirIds.add(dirId)) {
                issues += FolderVaultIssue(WARNING, virtualPath.ifEmpty { "/" }, "Directory ID cycle detected — a dir.c9r points back to an ancestor. Skipping to avoid an infinite loop.")
                return
            }
            val physicalFolder = physicalFolderForDirId(dirId)
            if (physicalFolder == null) {
                issues += FolderVaultIssue(CRITICAL, virtualPath.ifEmpty { "/" }, "dir.c9r points to a storage location that doesn't exist on disk — this directory's contents are lost.")
                return
            }
            for (child in saf.listChildren(physicalFolder)) {
                val physName = child.name ?: continue
                try {
                    when {
                        physName == "dir.c9r" -> continue
                        physName.endsWith(".c9s") -> {
                            if (!child.isDirectory) {
                                issues += FolderVaultIssue(WARNING, "$virtualPath/$physName", ".c9s entry should be a folder, but isn't.")
                                continue
                            }
                            val nameFile = saf.childOf(child, "name.c9r")
                            if (nameFile == null) {
                                issues += FolderVaultIssue(CRITICAL, "$virtualPath/$physName", "Shortened-name node is missing its name.c9r — original name is lost.")
                                continue
                            }
                            val longCipherName = saf.readWhole(nameFile).toString(Charsets.UTF_8).removeSuffix(".c9r")
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
                        else -> {} // unrelated/foreign file; ignore
                    }
                } catch (e: CryptomatorAuthenticationException) {
                    issues += FolderVaultIssue(CRITICAL, "$virtualPath/$physName", "Filename fails to decrypt: ${e.message}")
                }
            }
        }

        walkDir("", "")
        masterkey.destroy()
        log("Scan complete: $filesScanned file(s) scanned, ${issues.size} issue(s) found.")
        return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("cryptomator", filesScanned, issues, true))
    }

    /** No-password fallback: just checks the physical `d/xx/yyyy…` two-level fanout shape. */
    private fun checkCryptomatorDataDirShape(saf: SafDocumentOps, dataDir: DocumentFile, issues: MutableList<FolderVaultIssue>): Int {
        var count = 0
        for (lvl1 in saf.listChildren(dataDir)) {
            val name1 = lvl1.name ?: continue
            if (!lvl1.isDirectory || name1.length != 2) {
                issues += FolderVaultIssue(WARNING, "d/$name1", "Doesn't look like a Cryptomator level-1 storage directory (expected a 2-character name).")
                continue
            }
            for (lvl2 in saf.listChildren(lvl1)) {
                val name2 = lvl2.name ?: continue
                if (!lvl2.isDirectory || name2.length != 30) {
                    issues += FolderVaultIssue(WARNING, "d/$name1/$name2", "Doesn't look like a Cryptomator level-2 storage directory (expected a 30-character name).")
                    continue
                }
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
            val opened = context.contentResolver.openInputStream(file.uri)
            if (opened == null) {
                issues += FolderVaultIssue(WARNING, virtualPath, "Could not open file for content verification.")
                return
            }
            opened.use { input ->
                val headerBuf = ByteArray(cryptor.headerSize)
                val headerRead = input.readFullyInto(headerBuf)
                if (headerRead == 0) return // legitimate empty file
                if (headerRead < headerBuf.size) {
                    issues += FolderVaultIssue(WARNING, virtualPath, "File is shorter than Cryptomator's file header — truncated.")
                    return
                }
                val header = try {
                    cryptor.decryptHeader(headerBuf, masterkey)
                } catch (e: CryptomatorAuthenticationException) {
                    issues += FolderVaultIssue(CRITICAL, virtualPath, "File header fails to authenticate — wrong key or corrupted.")
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
                        issues += FolderVaultIssue(CRITICAL, virtualPath, "Chunk $chunkNumber fails to authenticate — corrupted or tampered.")
                        return
                    }
                    chunkNumber++
                }
            }
        } catch (e: Exception) {
            issues += FolderVaultIssue(WARNING, virtualPath, "Error reading file: ${e.message}")
        }
    }

    // ── shared helpers ───────────────────────────────────────────────────

    private val ZERO_DIRIV = ByteArray(16)

    private fun Char.isCryfsHex(): Boolean = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'

    private fun readPrefix(context: Context, file: DocumentFile, n: Int): ByteArray {
        return try {
            context.contentResolver.openInputStream(file.uri)?.use { input ->
                val buf = ByteArray(n)
                val read = input.readFullyInto(buf)
                buf.copyOf(read)
            } ?: ByteArray(0)
        } catch (e: Exception) {
            ByteArray(0)
        }
    }

    /** Fills [buf] completely (or up to EOF), unlike a single [InputStream.read] which may return short. */
    private fun InputStream.readFullyInto(buf: ByteArray): Int {
        var off = 0
        while (off < buf.size) {
            val r = read(buf, off, buf.size - off)
            if (r < 0) break
            off += r
        }
        return off
    }
}