package com.aeidolon.vaultexplorer.foldercheck

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.crypto.LittleEndian
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafIOException
import java.security.SecureRandom

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

/**
 * gocryptfs half of the folder-vault Check & Repair tool. Split out of the
 * former single-file FolderVaultChecker (~1250 lines covering three
 * unrelated vault formats in one object) so this format's check/repair logic
 * lives in its own file, the way every other format-specific concern in this
 * codebase already does (see the cryptomator/, gocryptfs/, cryfs/ session
 * packages). FolderVaultChecker.kt is now a thin dispatcher over this object
 * plus CryptomatorVaultCheck and CryfsVaultCheck.
 *
 * checkGocryptfs()/repairGocryptfs() are `internal` -- needed so
 * FolderVaultChecker.kt (a different file) can dispatch into them, and as a
 * side effect this is also what lets FolderVaultCheckerGocryptfsTest call
 * them directly with a DocumentFile.fromFile(...) fixture rather than the
 * public FolderVaultChecker.check()/repair() entry points, which need a real
 * SAF tree-Uri provider a plain temp folder can't satisfy. Everything else
 * here stays private to this file, same as before the split.
 */
internal object GocryptfsVaultCheck {

    private val WARNING = FolderVaultIssueSeverity.WARNING
    private val CRITICAL = FolderVaultIssueSeverity.CRITICAL
    private val ZERO_DIRIV = ByteArray(16)

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

}
