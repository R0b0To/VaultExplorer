package com.aeidolon.vaultexplorer.container
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.VaultStreamRegistry
import com.aeidolon.vaultexplorer.VeLog

object ContainerEngine {
    fun maxVolumes(): Int = NativeEngine.getMaxVolumesNative()

    fun deriveKeyMaterial(
        fd: Int, password: String, pim: Int, cipherId: Int = 255,
        hashId: Int = 255, keyfileFds: IntArray? = null,
    ): ByteArray? = NativeEngine.deriveKeyMaterialNative(fd, password, pim, cipherId, hashId, keyfileFds)

    fun lastDerivedKeyMaterial(volId: Int): ByteArray? =
        NativeEngine.getLastDerivedKeyMaterialNative(volId)

    fun unlockFile(
        fd: Int, password: String, pim: Int, volId: Int, cipherId: Int = 255,
        hashId: Int = 255, preservedKey: ByteArray? = null, keyfileFds: IntArray? = null,
        readOnly: Boolean = false,
        hiddenPassword: String? = null, hiddenPim: Int = 0, hiddenCipherId: Int = 255,
        hiddenHashId: Int = 255, hiddenKeyfileFds: IntArray? = null,
    ): Array<String>? = NativeEngine.unlockAndListNative(
        fd, password, pim, volId, cipherId, hashId, preservedKey, keyfileFds, readOnly,
        hiddenPassword, hiddenPim, hiddenCipherId, hiddenHashId, hiddenKeyfileFds,
    )

    fun unlockUsb(
        password: String, pim: Int, volId: Int, deviceSizeBytes: Long, cipherId: Int = 255,
        hashId: Int = 255, preservedKey: ByteArray? = null, partitionOffsetHint: Long = -1L,
        keyfileFds: IntArray? = null, readOnly: Boolean = false,
        hiddenPassword: String? = null, hiddenPim: Int = 0, hiddenCipherId: Int = 255,
        hiddenHashId: Int = 255, hiddenKeyfileFds: IntArray? = null,
    ): Array<String>? = NativeEngine.unlockUsbAndListNative(
        password, pim, volId, deviceSizeBytes, cipherId, hashId, preservedKey,
        partitionOffsetHint, keyfileFds, readOnly,
        hiddenPassword, hiddenPim, hiddenCipherId, hiddenHashId, hiddenKeyfileFds,
    )

    fun create(
        fd: Int, password: String, pim: Int, sizeBytes: Long, fileSystem: String,
        containerFormat: Int = 0, cipherId: Int = 255, hashId: Int = 255,
        keyfileFds: IntArray? = null,
    ): Boolean = NativeEngine.createContainerNative(
        fd, password, pim, sizeBytes, fileSystem, containerFormat, cipherId, hashId, keyfileFds
    )

    fun createUsb(
        volId: Int, partitionScheme: String, password: String, pim: Int, sizeBytes: Long, fileSystem: String,
        containerFormat: Int = 0, cipherId: Int = 255, hashId: Int = 255,
        keyfileFds: IntArray? = null, quickFormat: Boolean = false
    ): Boolean = NativeEngine.createUsbContainerNative(
        volId, partitionScheme, password, pim, sizeBytes, fileSystem, containerFormat, cipherId, hashId, keyfileFds, quickFormat
    )

    fun createWithHidden(
        fd: Int, outerPassword: String, hiddenPassword: String,
        outerPim: Int, hiddenPim: Int, sizeBytes: Long,
        outerFileSystem: String, hiddenFileSystem: String,
        hiddenSizeBytes: Long,
        outerCipherId: Int = 255, outerHashId: Int = 255,
        hiddenCipherId: Int = 255, hiddenHashId: Int = 255,
        outerKeyfileFds: IntArray? = null, hiddenKeyfileFds: IntArray? = null,
    ): Boolean = NativeEngine.createContainerWithHiddenNative(
        fd, outerPassword, hiddenPassword, outerPim, hiddenPim, sizeBytes,
        outerFileSystem, hiddenFileSystem, hiddenSizeBytes,
        outerCipherId, outerHashId, hiddenCipherId, hiddenHashId,
        outerKeyfileFds, hiddenKeyfileFds
    )
    
    fun createUsbWithHidden(
        volId: Int, partitionScheme: String,
        outerPassword: String, hiddenPassword: String,
        outerPim: Int, hiddenPim: Int, sizeBytes: Long,
        outerFileSystem: String, hiddenFileSystem: String,
        hiddenSizeBytes: Long,
        outerCipherId: Int = 255, outerHashId: Int = 255,
        hiddenCipherId: Int = 255, hiddenHashId: Int = 255,
        outerKeyfileFds: IntArray? = null, hiddenKeyfileFds: IntArray? = null,
        quickFormat: Boolean = false
    ): Boolean = NativeEngine.createUsbContainerWithHiddenNative(
        volId, partitionScheme, outerPassword, hiddenPassword, outerPim, hiddenPim, sizeBytes,
        outerFileSystem, hiddenFileSystem, hiddenSizeBytes, outerCipherId, outerHashId,
        hiddenCipherId, hiddenHashId, outerKeyfileFds, hiddenKeyfileFds, quickFormat
    )

    fun changePassword(
        fd: Int, oldPassword: String, newPassword: String,
        oldPim: Int, newPim: Int,
        cipherId: Int = 255, hashId: Int = 255,
        oldKeyfileFds: IntArray? = null, newKeyfileFds: IntArray? = null,
    ): Boolean = NativeEngine.changeContainerPasswordNative(
        fd, oldPassword, newPassword, oldPim, newPim, cipherId, hashId,
        oldKeyfileFds, newKeyfileFds
    )

    fun changeLuksPassword(
        fd: Int, oldPassword: String, newPassword: String,
        oldKeyfileFds: IntArray? = null, newKeyfileFds: IntArray? = null,
    ): Int = NativeEngine.changeLuksContainerPasswordNative(
        fd, oldPassword, newPassword, oldKeyfileFds, newKeyfileFds
    )

    fun lock(volId: Int) {
        val session = VaultBackendRegistry.get(volId)
        if (session != null) VaultBackendRegistry.remove(volId) else NativeEngine.lockNative(volId)
    }
    
    fun requestUnlockCancellation(volId: Int) = NativeEngine.requestCancelUnlockNative(volId)
    
    fun hashPassword(password: String, salt: ByteArray, iterations: Int): ByteArray? =
        NativeEngine.hashPasswordNative(password, salt, iterations)

    fun matchedCipherId(volId: Int): Int = NativeEngine.getMatchedCipherId(volId)
    fun matchedHashId(volId: Int): Int = NativeEngine.getMatchedHashId(volId)

    fun format(volId: Int): ContainerFormat =
        VaultBackendRegistry.get(volId)?.format ?: ContainerFormat.fromNative(NativeEngine.getContainerFormat(volId))

    fun listDirectory(path: String, volId: Int): Array<String>? {
        VaultBackendRegistry.get(volId)?.let { return it.listDirectory(path) }
        return NativeEngine.listDirectory(path, volId)
    }

    fun invalidateCache(path: String, volId: Int) {
        VaultBackendRegistry.get(volId)?.invalidateCache(path)
    }

    fun createDirectory(path: String, volId: Int): Boolean {
        VaultBackendRegistry.get(volId)?.let { return it.createDirectory(path) }
        return NativeEngine.createDirectory(path, volId)
    }

    fun renameFile(oldPath: String, newPath: String, volId: Int): Boolean {
        val ok = VaultBackendRegistry.get(volId)?.let { it.renameFile(oldPath, newPath) }
            ?: NativeEngine.renameFile(oldPath, newPath, volId)
        return ok
    }

    fun setLastModifiedTime(path: String, epochSeconds: Long, volId: Int): Boolean {
        VaultBackendRegistry.get(volId)?.let { return it.setLastModifiedTime(path, epochSeconds) }
        return NativeEngine.setLastModifiedTime(path, epochSeconds, volId)
    }

    fun deleteFile(path: String, volId: Int): Boolean {
        val ok = VaultBackendRegistry.get(volId)?.let { it.deleteFile(path) }
            ?: NativeEngine.deleteFile(path, volId)
        return ok
    }

    fun getFileSize(path: String, volId: Int): Long {
        VaultBackendRegistry.get(volId)?.let { return it.getFileSize(path) }
        return NativeEngine.getFileSize(path, volId)
    }

    fun getFolderSize(path: String, volId: Int): Long {
        VaultBackendRegistry.get(volId)?.let { return it.getFolderSize(path) }
        return NativeEngine.getFolderSize(path, volId)
    }

    fun readFileChunk(path: String, offset: Long, length: Int, volId: Int): ByteArray? {
        VaultBackendRegistry.get(volId)?.let { return it.readFileChunk(path, offset, length) }
        return NativeEngine.readFileChunk(path, offset, length, volId)
    }

    fun writeFileChunk(path: String, offset: Long, data: ByteArray, volId: Int): Boolean {
        VaultBackendRegistry.get(volId)?.let { return it.writeFileChunk(path, offset, data) }
        return NativeEngine.writeFileChunk(path, offset, data, volId)
    }

    fun finishWrite(path: String, volId: Int): Boolean {
        return VaultBackendRegistry.get(volId)?.let { it.finishWrite(path) } ?: true
    }

    fun writeBackFile(path: String, sourcePath: String, volId: Int, opId: Int = 0): Boolean {
        return VaultBackendRegistry.get(volId)?.let { it.writeBackFile(path, sourcePath, opId) }
            ?: NativeEngine.writeBackFile(path, sourcePath, volId, opId)
    }

    fun extractFile(path: String, destinationPath: String, volId: Int, opId: Int = 0): Boolean {
        VaultBackendRegistry.get(volId)?.let { return it.extractFile(path, destinationPath, opId) }
        return NativeEngine.extractFile(path, destinationPath, volId)
    }

    fun getSpaceInfo(volId: Int): LongArray? {
        VaultBackendRegistry.get(volId)?.let { return it.getSpaceInfo() }
        return NativeEngine.getSpaceInfo(volId)
    }

    fun getVaultInfo(volId: Int): Map<String, Any?>? {
        VaultBackendRegistry.get(volId)?.let { return it.getVaultInfo() }
        return NativeEngine.getVaultInfo(volId)
    }

    fun openStream(path: String, volId: Int): Long {
        if (VaultBackendRegistry.get(volId) != null) return VaultStreamRegistry.open(volId, path)
        return NativeEngine.openStream(path, volId)
    }

   fun copyFile(srcVolId: Int, srcPath: String, destVolId: Int, destPath: String, opId: Int = 0): Boolean {
        val srcIsBackend = VaultBackendRegistry.get(srcVolId) != null
        val destIsBackend = VaultBackendRegistry.get(destVolId) != null
        if (!srcIsBackend && !destIsBackend) {
            return NativeEngine.copyFile(srcPath, srcVolId, destPath, destVolId, opId)
        }
        // At least one side is a folder-vault session (gocryptfs/cryptomator/cryfs).
        // Callers should go through ContainerFileSystem.copyFile instead of this
        // function directly for that case -- it applies the correct per-backend
        // locking around each half (skipsPerVolumeLock-aware extract,
        // managesOwnWriteLocking-aware write-back) via copyFileViaBackend below,
        // rather than this function's own unwrapped extractFile/writeBackFile
        // calls. See copyFileViaBackend's doc comment for why that split exists.
        return copyFileViaBackend(srcVolId, srcPath, destVolId, destPath, opId,
            extract = { path, dest -> extractFile(path, dest, srcVolId, opId) },
            writeBack = { path, source -> writeBackFile(path, source, destVolId, opId) })
    }

    /**
     * The folder-vault half of [copyFile]: extract [srcPath] to a plaintext
     * temp file via [extract], then hand that temp file to [writeBack] for
     * [destPath]. Exists as its own function -- rather than inlined in
     * [copyFile] -- so [ContainerFileSystem.copyFile] can drive it with
     * [extract]/[writeBack] implementations that apply the correct
     * per-backend Kotlin lock around each call (see that function's doc
     * comment for why holding one lock across both steps, the way the
     * disk-image branch above safely does, isn't safe here: there's no
     * per-chunk yield point in a two-call extract-then-writeback sequence
     * the way there is in NativeEngine.copyFile's chunked loop).
     * [copyFile] above still calls this directly for callers that bypass
     * ContainerFileSystem, with [extract]/[writeBack] plugged in unwrapped --
     * exactly the previous behavior, preserved for anything that doesn't
     * need the lock-safety fix (there are none in this codebase today, but
     * this keeps the two call shapes symmetric rather than only reachable
     * one way).
     *
     * No native cross-container stream-copy primitive exists for folder
     * vaults, so unlike the disk-image formats we can't hand this straight
     * to NativeEngine. Bridge through a single plaintext temp file instead
     * of falling back to Dart's chunked readFileChunk/writeFileChunk loop:
     * that loop pays a full platform-channel round trip per 2MB chunk in
     * both directions, which is the actual source of the slowdown, not
     * crypto or disk throughput. extractFile and writeBackFile already
     * stream the whole file in one native/backend call each (same
     * primitives export/import use), so this keeps intra-vault copy off
     * the channel entirely except for these two calls.
     *
     * opId flows into both calls so a folder-vault session can report
     * progress through CopyProgressBridge the same way NativeEngine
     * .copyFile's JNI path already does for the disk-image branch above.
     * Coverage is asymmetric right now: writeBackFile's NativeEngine
     * fallback takes opId too, so a disk-image destination reports
     * progress same as a folder-vault one -- but extractFile's NativeEngine
     * fallback still doesn't, so a disk-image *source* stays silent for
     * the extract half of the copy until that entry point gets the same
     * treatment.
     */
    fun copyFileViaBackend(
        srcVolId: Int, srcPath: String, destVolId: Int, destPath: String, opId: Int = 0,
        extract: (path: String, destinationPath: String) -> Boolean,
        writeBack: (path: String, sourcePath: String) -> Boolean,
    ): Boolean {
        val tempFile = java.io.File.createTempFile("ve_copy_", ".tmp")
        return try {
            val t0 = System.currentTimeMillis()
            val extracted = extract(srcPath, tempFile.absolutePath)
            val extractMs = System.currentTimeMillis() - t0
            if (!extracted || !tempFile.exists()) return false
            val bytes = tempFile.length()

            val t1 = System.currentTimeMillis()
            val written = writeBack(destPath, tempFile.absolutePath)
            val writeBackMs = System.currentTimeMillis() - t1

            val t2 = System.currentTimeMillis()
            SecureFileWipe.secureDeleteFile(tempFile)
            val wipeMs = System.currentTimeMillis() - t2

            val totalMs = extractMs + writeBackMs + wipeMs
            val mb = bytes / (1024.0 * 1024.0)
            val mbps = if (totalMs > 0) mb / (totalMs / 1000.0) else 0.0
            VeLog.i("VaultProfiling") {
                String.format(
                    """
                    ========== INTRA_VAULT COPY_FILE PROFILING ==========
                    File Size                    : %.2f MB (%d bytes)
                    Total Time                   : %d ms (Overall Throughput: %.2f MB/s)
                    -------------------------------------------------
                    1. Extract (decrypt) Time    : %d ms
                    2. Write-back (encrypt) Time : %d ms
                    3. Secure Wipe of Temp Time  : %d ms
                    ===================================================
                    """.trimIndent(),
                    mb, bytes, totalMs, mbps, extractMs, writeBackMs, wipeMs
                )
            }
            written
        } finally {
            if (tempFile.exists()) SecureFileWipe.secureDeleteFile(tempFile)
        }
    }

    fun importStream(path: String, inputStream: java.io.InputStream, volId: Int): Boolean {
        VaultBackendRegistry.get(volId)?.let { session ->
            return session.importStream(path, inputStream, volId)
        }
        val tempFile = java.io.File.createTempFile("vc_import_", ".tmp")
        return try {
            tempFile.outputStream().use { out -> inputStream.copyTo(out) }
            // opId 0: this path already gets full byte-level progress from
            // ProgressInputStream on the read side (see ImportExportHandlers.kt)
            // before the fully-buffered temp file ever reaches here, so no
            // native progress/cancellation reporting is needed for the write.
            NativeEngine.writeBackFile(path, tempFile.absolutePath, volId, 0)
        } finally {
            tempFile.delete()
        }
    }

    fun readStream(stream: Long, offset: Long, out: ByteArray, length: Int, volId: Int): Int {
        if (VaultBackendRegistry.get(volId) != null) {
            return VaultStreamRegistry.read(volId, stream, offset, out, length)
        }
        return NativeEngine.readStream(stream, offset, out, length, volId)
    }

    fun beginBatchWrite(volId: Int) {
        VaultBackendRegistry.get(volId)?.beginBatchWrite()
    }

    fun endBatchWrite(volId: Int) {
        VaultBackendRegistry.get(volId)?.endBatchWrite()
    }

    fun closeStream(stream: Long, volId: Int) {
        if (VaultBackendRegistry.get(volId) != null) {
            VaultStreamRegistry.close(volId, stream)
        } else {
            NativeEngine.closeStream(stream, volId)
        }
    }
}

enum class ContainerFormat {
    VERACRYPT, LUKS1, LUKS2, CRYPTOMATOR, GOCRYPTFS, CRYFS, BITLOCKER, UNKNOWN;
    val wireName: String get() = when (this) {
        VERACRYPT -> "veracrypt"; LUKS1 -> "luks1"; LUKS2 -> "luks2"
        CRYPTOMATOR -> "cryptomator"; GOCRYPTFS -> "gocryptfs"; CRYFS -> "cryfs"
        BITLOCKER -> "bitlocker"; UNKNOWN -> "unknown"
    }

    companion object {
        fun fromNative(value: Int): ContainerFormat = when (value) {
            0 -> VERACRYPT
            1 -> LUKS1
            2 -> LUKS2
            3 -> BITLOCKER
            else -> UNKNOWN
        }
    }
}