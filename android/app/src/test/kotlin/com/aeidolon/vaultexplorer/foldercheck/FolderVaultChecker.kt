package com.aeidolon.vaultexplorer.foldercheck

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.crypto.LittleEndian
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafIOException
import java.io.File
import java.io.InputStream
import java.security.SecureRandom
import java.util.UUID

import com.aeidolon.vaultexplorer.container.VaultBackendRegistry

import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsCipher
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsConfig
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsConfigException
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsContentAuthException
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsContentCryptor
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsFileNameCryptor
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsMasterkey
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsSession
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsWrongPasswordException
import com.aeidolon.vaultexplorer.gocryptfs.Hkdf

import com.aeidolon.vaultexplorer.cryfs.CryfsBlockCipher
import com.aeidolon.vaultexplorer.cryfs.CryfsBlockId
import com.aeidolon.vaultexplorer.cryfs.CryfsBlockStore
import com.aeidolon.vaultexplorer.cryfs.CryfsConfig
import com.aeidolon.vaultexplorer.cryfs.CryfsConfigException
import com.aeidolon.vaultexplorer.cryfs.CryfsConfigFile
import com.aeidolon.vaultexplorer.cryfs.CryfsDataTree
import com.aeidolon.vaultexplorer.cryfs.CryfsDirBlob
import com.aeidolon.vaultexplorer.cryfs.CryfsEntryType
import com.aeidolon.vaultexplorer.cryfs.CryfsFsBlob
import com.aeidolon.vaultexplorer.cryfs.CryfsLocalIntegrityState
import com.aeidolon.vaultexplorer.cryfs.CryfsSession
import com.aeidolon.vaultexplorer.cryfs.CryfsUnsupportedCipherException
import com.aeidolon.vaultexplorer.cryfs.CryfsWrongPasswordException

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

enum class FolderVaultIssueSeverity(val wire: Int) { INFO(0), WARNING(1), CRITICAL(2) }

data class FolderVaultIssue(
    val severity: FolderVaultIssueSeverity,
    val path: String,
    val message: String,
)

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

data class FolderVaultRepairReport(
    val formatWire: String,
    val fixedCount: Int,
    val recoveredCount: Int,
    val removedCount: Int,
    val remainingIssues: List<FolderVaultIssue>,
) {
    val healthy: Boolean get() = remainingIssues.none { it.severity != FolderVaultIssueSeverity.INFO }
}

sealed class FolderVaultRepairOutcome {
    data class Success(val report: FolderVaultRepairReport) : FolderVaultRepairOutcome()
    data class InvalidVault(val message: String) : FolderVaultRepairOutcome()
    object WrongPassword : FolderVaultRepairOutcome()
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
        mountedVolId: Int? = null,
        log: (String) -> Unit = {},
    ): FolderVaultCheckOutcome {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return FolderVaultCheckOutcome.InvalidVault("Cannot access the selected folder.")
        val session = mountedVolId?.let { VaultBackendRegistry.get(it) }
        if (mountedVolId != null && session == null) {
            return FolderVaultCheckOutcome.InvalidVault(
                "This vault isn't open anymore -- pick it again and enter its password for a deep scan.",
            )
        }
        return try {
            when (formatWire) {
                "gocryptfs" -> checkGocryptfs(context, root, password, session as? GocryptfsSession, log)
                "cryfs" -> checkCryfs(context, root, password, session as? CryfsSession, log)
                "cryptomator", "directory_vault" -> checkCryptomator(context, root, password, session as? CryptomatorSession, log)
                else -> FolderVaultCheckOutcome.InvalidVault("Unsupported folder vault format: $formatWire")
            }
        } finally {
            password?.fill(' ')
        }
    }

    fun repair(
        context: Context,
        vaultRootUri: Uri,
        formatWire: String,
        password: CharArray?,
        mountedVolId: Int? = null,
        log: (String) -> Unit = {},
    ): FolderVaultRepairOutcome {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return FolderVaultRepairOutcome.InvalidVault("Cannot access the selected folder.")
        val session = mountedVolId?.let { VaultBackendRegistry.get(it) }
        if (mountedVolId != null && session == null) {
            return FolderVaultRepairOutcome.InvalidVault(
                "This vault isn't open anymore -- pick it again and enter its password to repair.",
            )
        }
        return try {
            when (formatWire) {
                "gocryptfs" -> repairGocryptfs(context, root, password, session as? GocryptfsSession, log)
                "cryptomator", "directory_vault" -> repairCryptomator(context, root, password, session as? CryptomatorSession, log)
                else -> FolderVaultRepairOutcome.InvalidVault("Automatic repair is currently supported for Cryptomator and gocryptfs vaults.")
            }
        } finally {
            password?.fill(' ')
        }
    }

    // ── gocryptfs Repair ───────────────────────────────────────────────────

    // internal rather than private: lets FolderVaultCheckerTest exercise this
    // directly with a DocumentFile.fromFile(...) fixture. check()/repair()'s
    // own DocumentFile.fromTreeUri(context, vaultRootUri) call needs a real
    // SAF tree-Uri provider that a plain temp folder can't satisfy -- every
    // other DocumentFile-based test in this project (ChunkedFileEngineTest,
    // MirrorSyncCoordinatorTest, SafDocumentOpsTest) works around the same
    // constraint by testing one layer below the Uri entry point. Visibility
    // only -- no behavior change.
    internal fun repairGocryptfs(
        context: Context,
        root: DocumentFile,
        password: CharArray?,
        session: GocryptfsSession?,
        log: (String) -> Unit,
    ): FolderVaultRepairOutcome {
        val saf = SafDocumentOps(context)
        log("Starting gocryptfs Vault Repair & Recovery…")

        var fixedCount = 0
        var recoveredCount = 0
        var removedCount = 0

        // 1. Resolve / Restore gocryptfs.conf
        var configDoc = saf.childOf(root, "gocryptfs.conf")
        if (configDoc == null) {
            val bakDoc = saf.childOf(root, "gocryptfs.conf.bak")
            if (bakDoc != null) {
                log("gocryptfs.conf missing; restoring from gocryptfs.conf.bak…")
                val bakBytes = context.contentResolver.openInputStream(bakDoc.uri)?.use { it.readBytes() }
                if (bakBytes != null) {
                    val restored = saf.createFileSafe(root, "application/octet-stream", "gocryptfs.conf")
                    if (restored != null) {
                        saf.writeWhole(restored, bakBytes)
                        configDoc = restored
                        fixedCount++
                        log("Restored gocryptfs.conf from backup.")
                    }
                }
            }
        }

        if (configDoc == null) {
            return FolderVaultRepairOutcome.InvalidVault("Missing gocryptfs.conf and no backup found.")
        }

        val configBytes = context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
            ?: return FolderVaultRepairOutcome.InvalidVault("Could not read gocryptfs.conf")
        val config = try {
            GocryptfsConfig.parse(configBytes)
        } catch (e: GocryptfsConfigException) {
            return FolderVaultRepairOutcome.InvalidVault(e.message ?: "Malformed gocryptfs.conf")
        }

        val nameCryptor: GocryptfsFileNameCryptor
        val contentCryptor: GocryptfsContentCryptor

        if (session != null) {
            nameCryptor = session.nameCryptor
            contentCryptor = session.contentCryptor
            log("Using active session keys for repair.")
        } else {
            if (password == null) {
                return FolderVaultRepairOutcome.WrongPassword
            }
            val masterkey = try {
                GocryptfsMasterkey.unlock(config, password)
            } catch (e: GocryptfsWrongPasswordException) {
                return FolderVaultRepairOutcome.WrongPassword
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
        }

        // 2. Validate / Repair root gocryptfs.diriv
        var rootDiriv: ByteArray = ZERO_DIRIV
        if (config.hasDirIV) {
            val rootDirivDoc = saf.childOf(root, GocryptfsFileNameCryptor.DIRIV_FILENAME)
            val bytes = if (rootDirivDoc != null) try { saf.readWhole(rootDirivDoc) } catch (_: Exception) { null } else null
            if (bytes != null && bytes.size == 16) {
                rootDiriv = bytes
            } else {
                val fresh = ByteArray(16).also { SecureRandom().nextBytes(it) }
                val targetDoc = rootDirivDoc ?: saf.createFileSafe(root, "application/octet-stream", GocryptfsFileNameCryptor.DIRIV_FILENAME)
                if (targetDoc != null) {
                    saf.writeWhole(targetDoc, fresh)
                    rootDiriv = fresh
                    fixedCount++
                    log("Restored missing/corrupted root gocryptfs.diriv.")
                }
            }
        }

        // 3. Locate / Create /LOST+FOUND directory in vault
        fun getOrCreateLostFoundFolder(): Pair<DocumentFile, ByteArray> {
            val encName = if (config.plaintextNames) "LOST+FOUND" else nameCryptor.encryptName("LOST+FOUND", rootDiriv)
            val existing = saf.childOf(root, encName)
            if (existing != null && existing.isDirectory) {
                val dirivDoc = if (config.hasDirIV) saf.childOf(existing, GocryptfsFileNameCryptor.DIRIV_FILENAME) else null
                val ivBytes = if (dirivDoc != null) try { saf.readWhole(dirivDoc) } catch (_: Exception) { null } else null
                val iv = if (ivBytes != null && ivBytes.size == 16) ivBytes else {
                    val fresh = ByteArray(16).also { SecureRandom().nextBytes(it) }
                    val dDoc = dirivDoc ?: saf.createFileSafe(existing, "application/octet-stream", GocryptfsFileNameCryptor.DIRIV_FILENAME)
                    if (dDoc != null) saf.writeWhole(dDoc, fresh)
                    fresh
                }
                return existing to iv
            }
            val created = saf.createDirectorySafe(root, encName) ?: throw SafIOException("Could not create LOST+FOUND folder")
            val lfIv = ByteArray(16).also { SecureRandom().nextBytes(it) }
            if (config.hasDirIV) {
                val dDoc = saf.createFileSafe(created, "application/octet-stream", GocryptfsFileNameCryptor.DIRIV_FILENAME)
                if (dDoc != null) saf.writeWhole(dDoc, lfIv)
            }
            return created to lfIv
        }

        val visitedDocs = mutableSetOf<String>()

        fun repairDirectory(dirDoc: DocumentFile, virtualPath: String, currentDirIv: ByteArray) {
            val dirKey = dirDoc.uri.toString()
            if (!visitedDocs.add(dirKey)) return

            var effectiveDirIv = currentDirIv
            if (config.hasDirIV && dirDoc.uri != root.uri) {
                val dirivDoc = saf.childOf(dirDoc, GocryptfsFileNameCryptor.DIRIV_FILENAME)
                val ivBytes = if (dirivDoc != null) try { saf.readWhole(dirivDoc) } catch (_: Exception) { null } else null
                if (ivBytes != null && ivBytes.size == 16) {
                    effectiveDirIv = ivBytes
                } else {
                    val fresh = ByteArray(16).also { SecureRandom().nextBytes(it) }
                    val dDoc = dirivDoc ?: saf.createFileSafe(dirDoc, "application/octet-stream", GocryptfsFileNameCryptor.DIRIV_FILENAME)
                    if (dDoc != null) {
                        saf.writeWhole(dDoc, fresh)
                        effectiveDirIv = fresh
                        fixedCount++
                        log("Restored missing gocryptfs.diriv in $virtualPath")
                    }
                }
            }

            val children = saf.listChildren(dirDoc)
            val byName = children.associateBy { it.name }

            for (child in children) {
                val physName = child.name ?: continue
                if (physName == GocryptfsFileNameCryptor.DIRIV_FILENAME ||
                    physName == "gocryptfs.conf" ||
                    physName == "gocryptfs.conf.bak") continue

                if (physName.endsWith(GocryptfsFileNameCryptor.LONGNAME_SUFFIX)) {
                    val baseLongName = physName.removeSuffix(GocryptfsFileNameCryptor.LONGNAME_SUFFIX)
                    if (!byName.containsKey(baseLongName)) {
                        saf.deleteRecursively(child)
                        removedCount++
                        log("Removed orphaned .name sidecar: $physName in $virtualPath")
                    }
                    continue
                }

                val isLongName = physName.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX)
                var ciphertextName = physName
                var missingSidecar = false

                if (isLongName) {
                    val sidecar = byName[physName + GocryptfsFileNameCryptor.LONGNAME_SUFFIX]
                    if (sidecar == null) {
                        missingSidecar = true
                    } else {
                        val sidecarContent = try { saf.readWhole(sidecar).toString(Charsets.UTF_8).trim() } catch (_: Exception) { null }
                        if (sidecarContent.isNullOrEmpty()) {
                            missingSidecar = true
                        } else {
                            ciphertextName = sidecarContent
                        }
                    }
                }

                var cleartextName: String? = null
                var nameCorrupted = missingSidecar
                if (!nameCorrupted) {
                    try {
                        cleartextName = nameCryptor.decryptName(ciphertextName, effectiveDirIv)
                    } catch (_: Exception) {
                        nameCorrupted = true
                    }
                }

                if (child.isDirectory) {
                    if (nameCorrupted) {
                        val innerChildren = saf.listChildren(child).filter {
                            it.name != GocryptfsFileNameCryptor.DIRIV_FILENAME
                        }
                        if (innerChildren.isEmpty()) {
                            saf.deleteRecursively(child)
                            if (isLongName) byName[physName + GocryptfsFileNameCryptor.LONGNAME_SUFFIX]?.let { saf.deleteRecursively(it) }
                            removedCount++
                            log("Removed empty unreadable directory: $physName in $virtualPath")
                        } else {
                            val (lfFolder, lfIv) = getOrCreateLostFoundFolder()
                            val safeName = "recovered_dir_${physName.take(8)}"
                            val encSafeName = if (config.plaintextNames) safeName else nameCryptor.encryptName(safeName, lfIv)
                            val rescuedDir = saf.createDirectorySafe(lfFolder, encSafeName)
                            if (rescuedDir != null) {
                                for (innerItem in saf.listChildren(child)) {
                                    saf.movePhysicalDocument(innerItem, child, rescuedDir)
                                }
                                saf.deleteRecursively(child)
                                if (isLongName) byName[physName + GocryptfsFileNameCryptor.LONGNAME_SUFFIX]?.let { saf.deleteRecursively(it) }
                                recoveredCount++
                                log("Rescued directory with damaged name to /LOST+FOUND/$safeName")
                                repairDirectory(rescuedDir, "/LOST+FOUND/$safeName", effectiveDirIv)
                            }
                        }
                    } else {
                        repairDirectory(child, if (virtualPath.isEmpty()) cleartextName!! else "$virtualPath/$cleartextName", effectiveDirIv)
                    }
                } else if (child.isFile) {
                    val length = child.length()
                    if (length == 0L) {
                        if (nameCorrupted) {
                            saf.deleteRecursively(child)
                            if (isLongName) byName[physName + GocryptfsFileNameCryptor.LONGNAME_SUFFIX]?.let { saf.deleteRecursively(it) }
                            removedCount++
                            log("Removed 0-byte corrupt file with unreadable name in $virtualPath")
                        } else {
                            val freshHeader = contentCryptor.encodeHeader(contentCryptor.createHeader())
                            saf.writeWhole(child, freshHeader)
                            fixedCount++
                            log("Fixed 0-byte file: $virtualPath/$cleartextName (written valid 18-byte empty header)")
                        }
                        continue
                    }

                    if (length in 1 until GocryptfsContentCryptor.HEADER_LEN) {
                        if (nameCorrupted) {
                            saf.deleteRecursively(child)
                            if (isLongName) byName[physName + GocryptfsFileNameCryptor.LONGNAME_SUFFIX]?.let { saf.deleteRecursively(it) }
                            removedCount++
                            log("Removed truncated file (< 18 bytes) with corrupt name in $virtualPath")
                        } else {
                            val freshHeader = contentCryptor.encodeHeader(contentCryptor.createHeader())
                            saf.writeWhole(child, freshHeader)
                            fixedCount++
                            log("Reset truncated file (< 18 bytes) to empty: $virtualPath/$cleartextName")
                        }
                        continue
                    }

                    var headerBytes = ByteArray(GocryptfsContentCryptor.HEADER_LEN)
                    var headerReadOk = false
                    try {
                        context.contentResolver.openInputStream(child.uri)?.use {
                            headerReadOk = it.read(headerBytes) == headerBytes.size
                        }
                    } catch (_: Exception) {}

                    if (!headerReadOk) {
                        log("Could not read header for $physName in $virtualPath")
                        continue
                    }

                    val version = ((headerBytes[0].toInt() and 0xFF) shl 8) or (headerBytes[1].toInt() and 0xFF)
                    val headerValid = (version == 2)

                    if (!headerValid) {
                        val (lfFolder, lfIv) = getOrCreateLostFoundFolder()
                        val safeName = "corrupt_version_${version}_${physName.take(8)}.bin"
                        val encSafeName = if (config.plaintextNames) safeName else nameCryptor.encryptName(safeName, lfIv)
                        saf.copyDocumentRecursive(child, lfFolder)
                        saf.deleteRecursively(child)
                        if (isLongName) byName[physName + GocryptfsFileNameCryptor.LONGNAME_SUFFIX]?.let { saf.deleteRecursively(it) }
                        recoveredCount++
                        log("Rescued file with unsupported version ($version) to /LOST+FOUND/$safeName")
                        continue
                    }

                    val fileHeader = try {
                        contentCryptor.decodeHeader(headerBytes)
                    } catch (_: Exception) { null }

                    if (nameCorrupted && fileHeader != null) {
                        val (lfFolder, lfIv) = getOrCreateLostFoundFolder()
                        val safeName = "recovered_file_${LittleEndian.bytesToHex(fileHeader.fileId.take(4).toByteArray())}.bin"
                        val encSafeName = if (config.plaintextNames) safeName else nameCryptor.encryptName(safeName, lfIv)
                        saf.copyDocumentRecursive(child, lfFolder)
                        saf.deleteRecursively(child)
                        if (isLongName) byName[physName + GocryptfsFileNameCryptor.LONGNAME_SUFFIX]?.let { saf.deleteRecursively(it) }
                        recoveredCount++
                        log("Rescued file with damaged name to /LOST+FOUND/$safeName")
                    }
                }
            }
        }

        log("Scanning directory tree and repairing corruptions…")
        repairDirectory(root, "", rootDiriv)

        saf.invalidateAll()
        session?.invalidateCache("")

        log("Re-verifying vault consistency…")
        val postCheck = checkGocryptfs(context, root, password, session, {})
        val remaining = if (postCheck is FolderVaultCheckOutcome.Success) postCheck.report.issues else emptyList()

        val report = FolderVaultRepairReport("gocryptfs", fixedCount, recoveredCount, removedCount, remaining)
        log("gocryptfs repair complete: $fixedCount fixed, $recoveredCount recovered to /LOST+FOUND, $removedCount cleaned up.")
        return FolderVaultRepairOutcome.Success(report)
    }

    // ── Cryptomator Check & Repair ──────────────────────────────────────────

    // internal, not private -- see the comment on repairGocryptfs above.
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

    // internal, not private -- see the comment on repairGocryptfs above.
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
                    val contents = saf.listChildren(lvl2)
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

    // ── gocryptfs & CryFS Checkers ──────────────────────────────────────────

    // internal, not private -- see the comment on repairGocryptfs above.
    internal fun checkGocryptfs(
        context: Context, root: DocumentFile, password: CharArray?, session: GocryptfsSession?, log: (String) -> Unit,
    ): FolderVaultCheckOutcome {
        val saf = SafDocumentOps(context)
        val issues = mutableListOf<FolderVaultIssue>()

        log("Reading gocryptfs.conf…")
        val configDoc = saf.childOf(root, "gocryptfs.conf")
            ?: return FolderVaultCheckOutcome.InvalidVault("No gocryptfs.conf found.")
        val configBytes = context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
            ?: return FolderVaultCheckOutcome.InvalidVault("Could not read gocryptfs.conf")
        val config = try {
            GocryptfsConfig.parse(configBytes)
        } catch (e: GocryptfsConfigException) {
            return FolderVaultCheckOutcome.InvalidVault(e.message ?: "Malformed gocryptfs.conf")
        }

        var nameCryptor: GocryptfsFileNameCryptor? = null
        var contentCryptor: GocryptfsContentCryptor? = null
        if (session != null) {
            nameCryptor = session.nameCryptor
            contentCryptor = session.contentCryptor
            log("Scanning file contents with session key…")
        } else if (password != null) {
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
            log("Password verified — scanning file contents…")
        } else {
            log("No password given — checking structure only.")
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
                    issues += FolderVaultIssue(CRITICAL, virtualPath.ifEmpty { "/" }, "Missing gocryptfs.diriv.")
                } else {
                    val bytes = saf.readWhole(dirivDoc)
                    if (bytes.size != 16) {
                        issues += FolderVaultIssue(CRITICAL, "$virtualPath/gocryptfs.diriv", "gocryptfs.diriv size invalid.")
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
                if (physName == GocryptfsFileNameCryptor.DIRIV_FILENAME ||
                    physName == "gocryptfs.conf" ||
                    physName == "gocryptfs.conf.bak") continue
                if (physName.endsWith(GocryptfsFileNameCryptor.LONGNAME_SUFFIX)) continue

                var ciphertextName = physName
                if (physName.startsWith(GocryptfsFileNameCryptor.LONGNAME_PREFIX)) {
                    val nameFile = byPhysicalName[physName + GocryptfsFileNameCryptor.LONGNAME_SUFFIX]
                    if (nameFile == null) {
                        issues += FolderVaultIssue(WARNING, "$virtualPath/$physName", "Long-name file missing .name sidecar.")
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
                    if (size == 0L) {
                        issues += FolderVaultIssue(WARNING, childVirtualPath, "0-byte file (missing 18-byte header).")
                    } else if (size in 1 until headerLen) {
                        issues += FolderVaultIssue(WARNING, childVirtualPath, "File shorter than header ($size bytes).")
                    } else if (size > headerLen) {
                        val body = size - headerLen
                        val remainder = body % expectedChunkSize
                        if (remainder != 0L && remainder < nonceLen + 16) {
                            issues += FolderVaultIssue(WARNING, childVirtualPath, "Ciphertext size misaligned with block structure.")
                        }
                    }
                    if (contentCryptor != null && size >= headerLen) {
                        verifyGocryptfsFile(context, child, contentCryptor, childVirtualPath, issues)
                    }
                }
            }
        }

        walk(root, "")
        return FolderVaultCheckOutcome.Success(FolderVaultCheckReport("gocryptfs", filesScanned, issues, contentCryptor != null))
    }

    private fun verifyGocryptfsFile(
        context: Context, file: DocumentFile, cryptor: GocryptfsContentCryptor,
        virtualPath: String, issues: MutableList<FolderVaultIssue>,
    ) {
        try {
            context.contentResolver.openInputStream(file.uri)?.use { input ->
                val headerBuf = ByteArray(GocryptfsContentCryptor.HEADER_LEN)
                val headerRead = input.readFullyInto(headerBuf)
                if (headerRead < headerBuf.size) {
                    issues += FolderVaultIssue(WARNING, virtualPath, "File truncated (shorter than header).")
                    return
                }
                val version = ((headerBuf[0].toInt() and 0xFF) shl 8) or (headerBuf[1].toInt() and 0xFF)
                if (version != 2) {
                    issues += FolderVaultIssue(CRITICAL, virtualPath, "Unsupported file format version $version (expected version 2).")
                    return
                }
                val header = try {
                    cryptor.decodeHeader(headerBuf)
                } catch (e: Exception) {
                    issues += FolderVaultIssue(CRITICAL, virtualPath, "File header corrupted: ${e.message}")
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
                        issues += FolderVaultIssue(CRITICAL, virtualPath, "Chunk $chunkNumber authentication failed: ${e.message}")
                        return
                    }
                    chunkNumber++
                }
            }
        } catch (e: Exception) {
            issues += FolderVaultIssue(WARNING, virtualPath, "Content error: ${e.message}")
        }
    }

    // internal, not private -- see the comment on repairGocryptfs above.
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

    private val ZERO_DIRIV = ByteArray(16)
    private fun Char.isCryfsHex(): Boolean = this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
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