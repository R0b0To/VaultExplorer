package com.aeidolon.vaultexplorer

/**
 * Format-neutral native engine boundary.
 *
 * Tier-1 (unlock/create/change-password) operations remain VeraCrypt/LUKS-
 * specific — Cryptomator, Gocryptfs, and Cryfs vaults are opened via their
 * respective vault classes directly from MainActivity, not through this
 * facade's unlock* methods, since they have no block-device/FUSE layer for
 * NativeEngine to drive.
 *
 * Tier-2 (file/directory operations against an unlocked volId) dispatch
 * here: if [VaultBackendRegistry] holds a session for the given volId, the
 * call goes to that pure-Kotlin session; otherwise it falls through to the
 * ABI-compatible JNI shim [NativeEngine], unchanged from before. This
 * keeps every existing call site (ContainerFileSystem,
 * ContainerDocumentsProvider, file_operation_service.dart, etc.) working
 * unmodified for all container families — callers key everything off
 * volId and never need to know which backend is actually serving it.
 */
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

    /** containerFormat: 0 = VeraCrypt, 1 = LUKS1, 2 = LUKS2. See
     *  createContainerNative's doc comment in [NativeEngine] for the
     *  cipherId/hashId/keyfileFds semantics, which differ by format. */
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

    /** 0 = success, 1 = wrong old password/keyfile, 2 = other error. See
     *  NativeEngine.changeLuksContainerPasswordNative's doc comment. */
    fun changeLuksPassword(
        fd: Int, oldPassword: String, newPassword: String,
        oldKeyfileFds: IntArray? = null, newKeyfileFds: IntArray? = null,
    ): Int = NativeEngine.changeLuksContainerPasswordNative(
        fd, oldPassword, newPassword, oldKeyfileFds, newKeyfileFds
    )

    /** Locks/closes volId's session regardless of backend: zeroes the Cryptomator/Gocryptfs masterkey if it's a pure-Kotlin session, otherwise unmounts the native VeraCrypt/LUKS volume as before. */
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

    /** For Cryptomator/Gocryptfs sessions, callers MUST invoke [finishWrite] once after their final writeFileChunk() call for a given path to flush the last (possibly partial) chunk and materialize the file. */
    fun writeFileChunk(path: String, offset: Long, data: ByteArray, volId: Int): Boolean {
        VaultBackendRegistry.get(volId)?.let { return it.writeFileChunk(path, offset, data) }
        return NativeEngine.writeFileChunk(path, offset, data, volId)
    }

    /** No-op for VeraCrypt/LUKS (whose writeFileChunk is already durable per-call); required for Cryptomator and Gocryptfs to flush their write buffers. Safe to call unconditionally after any writeFileChunk() sequence completes. */
    fun finishWrite(path: String, volId: Int): Boolean {
        return VaultBackendRegistry.get(volId)?.let { it.finishWrite(path) } ?: true
    }

    fun writeBackFile(path: String, sourcePath: String, volId: Int): Boolean {
        return VaultBackendRegistry.get(volId)?.let { it.writeBackFile(path, sourcePath) }
            ?: NativeEngine.writeBackFile(path, sourcePath, volId)
    }

    fun extractFile(path: String, destination: String, volId: Int): Boolean {
        VaultBackendRegistry.get(volId)?.let { return it.extractFile(path, destination) }
        return NativeEngine.extractFile(path, destination, volId)
    }

    fun getSpaceInfo(volId: Int): LongArray? {
        VaultBackendRegistry.get(volId)?.let { return it.getSpaceInfo() }
        return NativeEngine.getSpaceInfo(volId)
    }

    fun openStream(path: String, volId: Int): Long {
        if (VaultBackendRegistry.get(volId) != null) return VaultStreamRegistry.open(volId, path)
        return NativeEngine.openStream(path, volId)
    }

    fun importStream(path: String, inputStream: java.io.InputStream, volId: Int): Boolean {
        VaultBackendRegistry.get(volId)?.let { session ->
            return session.importStream(path, inputStream)
        }
        // Category D (see docs/temp-file-audit.md, finding TF-07): NativeEngine
        // (the VeraCrypt/LUKS/BitLocker C++ engine) only accepts a real source
        // path for writeBackFile, so the imported plaintext has to be staged
        // on host disk here -- there's no stream/pipe entry point into it.
        // Always zero-fill + delete afterward rather than a plain delete().
        //
        // NOTE: unlike every other temp file in this codebase, this one is
        // NOT created under an explicit context.cacheDir -- ContainerEngine
        // is a plain singleton object with no Context reference threaded
        // into it, and importStream's callers (ImportExportHandlers) are a
        // few frames further up. File.createTempFile(prefix, suffix) without
        // an explicit directory falls back to the `java.io.tmpdir` system
        // property, which the Android runtime is not guaranteed to set to a
        // private, writable location on every OS version/OEM. This has
        // worked in testing but is a latent portability/security gap --
        // threading a Context (or a pre-resolved private dir) through
        // ImportExportHandlers -> ContainerFileSystem -> here so this can
        // use context.cacheDir explicitly, like every other temp file in
        // the app, is tracked as follow-up work rather than guessed at here.
        val tempFile = java.io.File.createTempFile("vc_import_", ".tmp")
        return try {
            tempFile.outputStream().use { out -> inputStream.copyTo(out) }
            NativeEngine.writeBackFile(path, tempFile.absolutePath, volId)
        } finally {
            SecureFileWipe.secureDeleteFile(tempFile)
        }
    }

    fun readStream(stream: Long, offset: Long, out: ByteArray, length: Int, volId: Int): Int {
        if (VaultBackendRegistry.get(volId) != null) {
            return VaultStreamRegistry.read(volId, stream, offset, out, length)
        }
        return NativeEngine.readStream(stream, offset, out, length, volId)
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