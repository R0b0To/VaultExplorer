package com.aeidolon.vaultexplorer

import com.aeidolon.vaultexplorer.cryptomator.CryptomatorSessionRegistry
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorStreamRegistry
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsSessionRegistry
import com.aeidolon.vaultexplorer.gocryptfs.GocryptfsStreamRegistry

/**
 * Format-neutral native engine boundary.
 *
 * Tier-1 (unlock/create/change-password) operations remain VeraCrypt/LUKS-
 * specific — Cryptomator and Gocryptfs vaults are opened via their respective
 * vault classes directly from MainActivity, not through this facade's unlock* methods,
 * since they have no block-device/FUSE layer for VeraCryptEngine to drive.
 *
 * Tier-2 (file/directory operations against an unlocked volId) dispatch
 * here: if [CryptomatorSessionRegistry] or [GocryptfsSessionRegistry] holds a session
 * for the given volId, the call goes to that pure-Kotlin session; otherwise it falls
 * through to the ABI-compatible JNI shim [VeraCryptEngine], unchanged from
 * before. This keeps every existing call site (ContainerFileSystem,
 * ContainerDocumentsProvider, file_operation_service.dart, etc.) working
 * unmodified for all container families — callers key everything off
 * volId and never need to know which backend is actually serving it.
 */
object ContainerEngine {
    fun maxVolumes(): Int = VeraCryptEngine.getMaxVolumesNative()

    fun deriveKeyMaterial(
        fd: Int, password: String, pim: Int, cipherId: Int = 255,
        hashId: Int = 255, keyfileFds: IntArray? = null,
    ): ByteArray? = VeraCryptEngine.deriveKeyMaterialNative(fd, password, pim, cipherId, hashId, keyfileFds)

    fun lastDerivedKeyMaterial(volId: Int): ByteArray? =
        VeraCryptEngine.getLastDerivedKeyMaterialNative(volId)

    fun unlockFile(
        fd: Int, password: String, pim: Int, volId: Int, cipherId: Int = 255,
        hashId: Int = 255, preservedKey: ByteArray? = null, keyfileFds: IntArray? = null,
        readOnly: Boolean = false,
    ): Array<String>? = VeraCryptEngine.unlockAndListNative(
        fd, password, pim, volId, cipherId, hashId, preservedKey, keyfileFds, readOnly
    )

    fun unlockUsb(
        password: String, pim: Int, volId: Int, deviceSizeBytes: Long, cipherId: Int = 255,
        hashId: Int = 255, preservedKey: ByteArray? = null, partitionOffsetHint: Long = -1L,
        keyfileFds: IntArray? = null, readOnly: Boolean = false,
    ): Array<String>? = VeraCryptEngine.unlockUsbAndListNative(
        password, pim, volId, deviceSizeBytes, cipherId, hashId, preservedKey,
        partitionOffsetHint, keyfileFds, readOnly
    )

    /** containerFormat: 0 = VeraCrypt, 1 = LUKS1, 2 = LUKS2. See
     *  createContainerNative's doc comment in [VeraCryptEngine] for the
     *  cipherId/hashId/keyfileFds semantics, which differ by format. */
    fun create(
        fd: Int, password: String, pim: Int, sizeBytes: Long, fileSystem: String,
        containerFormat: Int = 0, cipherId: Int = 255, hashId: Int = 255,
        keyfileFds: IntArray? = null,
    ): Boolean = VeraCryptEngine.createContainerNative(
        fd, password, pim, sizeBytes, fileSystem, containerFormat, cipherId, hashId, keyfileFds
    )

    fun createUsb(
        volId: Int, partitionScheme: String, password: String, pim: Int, sizeBytes: Long, fileSystem: String,
        containerFormat: Int = 0, cipherId: Int = 255, hashId: Int = 255,
        keyfileFds: IntArray? = null, quickFormat: Boolean = false
    ): Boolean = VeraCryptEngine.createUsbContainerNative(
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
    ): Boolean = VeraCryptEngine.createContainerWithHiddenNative(
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
    ): Boolean = VeraCryptEngine.createUsbContainerWithHiddenNative(
        volId, partitionScheme, outerPassword, hiddenPassword, outerPim, hiddenPim, sizeBytes,
        outerFileSystem, hiddenFileSystem, hiddenSizeBytes, outerCipherId, outerHashId,
        hiddenCipherId, hiddenHashId, outerKeyfileFds, hiddenKeyfileFds, quickFormat
    )

    fun changePassword(
        fd: Int, oldPassword: String, newPassword: String,
        oldPim: Int, newPim: Int,
        cipherId: Int = 255, hashId: Int = 255,
        oldKeyfileFds: IntArray? = null, newKeyfileFds: IntArray? = null,
    ): Boolean = VeraCryptEngine.changeContainerPasswordNative(
        fd, oldPassword, newPassword, oldPim, newPim, cipherId, hashId,
        oldKeyfileFds, newKeyfileFds
    )

    /** Locks/closes volId's session regardless of backend: zeroes the Cryptomator/Gocryptfs masterkey if it's a pure-Kotlin session, otherwise unmounts the native VeraCrypt/LUKS volume as before. */
    fun lock(volId: Int) = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.remove(volId)
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.remove(volId)
        else                                            -> VeraCryptEngine.lockNative(volId)
    }
    
    fun requestUnlockCancellation(volId: Int) = VeraCryptEngine.requestCancelUnlockNative(volId)
    
    fun hashPassword(password: String, salt: ByteArray, iterations: Int): ByteArray? =
        VeraCryptEngine.hashPasswordNative(password, salt, iterations)

    fun matchedCipherId(volId: Int): Int = VeraCryptEngine.getMatchedCipherId(volId)
    fun matchedHashId(volId: Int): Int = VeraCryptEngine.getMatchedHashId(volId)

    fun format(volId: Int): ContainerFormat = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> ContainerFormat.CRYPTOMATOR
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> ContainerFormat.GOCRYPTFS
        else                                            -> ContainerFormat.fromNative(VeraCryptEngine.getContainerFormat(volId))
    }

    fun listDirectory(path: String, volId: Int): Array<String>? = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.listDirectory(path)
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.listDirectory(path)
        else                                            -> VeraCryptEngine.listDirectory(path, volId)
    }

    fun createDirectory(path: String, volId: Int): Boolean = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.createDirectory(path) ?: false
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.createDirectory(path) ?: false
        else                                            -> VeraCryptEngine.createDirectory(path, volId)
    }

    fun renameFile(oldPath: String, newPath: String, volId: Int): Boolean = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.renameFile(oldPath, newPath) ?: false
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.renameFile(oldPath, newPath) ?: false
        else                                            -> VeraCryptEngine.renameFile(oldPath, newPath, volId)
    }

    fun setLastModifiedTime(path: String, epochSeconds: Long, volId: Int): Boolean = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.setLastModifiedTime(path, epochSeconds) ?: false
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.setLastModifiedTime(path, epochSeconds) ?: false
        else                                            -> VeraCryptEngine.setLastModifiedTime(path, epochSeconds, volId)
    }

    fun deleteFile(path: String, volId: Int): Boolean = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.deleteFile(path) ?: false
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.deleteFile(path) ?: false
        else                                            -> VeraCryptEngine.deleteFile(path, volId)
    }

    fun getFileSize(path: String, volId: Int): Long = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.getFileSize(path) ?: -1L
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.getFileSize(path) ?: -1L
        else                                            -> VeraCryptEngine.getFileSize(path, volId)
    }

    fun getFolderSize(path: String, volId: Int): Long = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.getFolderSize(path) ?: -1L
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.getFolderSize(path) ?: -1L
        else                                            -> VeraCryptEngine.getFolderSize(path, volId)
    }

    fun readFileChunk(path: String, offset: Long, length: Int, volId: Int): ByteArray? = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.readFileChunk(path, offset, length)
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.readFileChunk(path, offset, length)
        else                                            -> VeraCryptEngine.readFileChunk(path, offset, length, volId)
    }

    /** For Cryptomator/Gocryptfs sessions, callers MUST invoke [finishWrite] once after their final writeFileChunk() call for a given path to flush the last (possibly partial) chunk and materialize the file. */
    fun writeFileChunk(path: String, offset: Long, data: ByteArray, volId: Int): Boolean = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.writeFileChunk(path, offset, data) ?: false
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.writeFileChunk(path, offset, data) ?: false
        else                                            -> VeraCryptEngine.writeFileChunk(path, offset, data, volId)
    }

    /** No-op for VeraCrypt/LUKS (whose writeFileChunk is already durable per-call); required for Cryptomator and Gocryptfs to flush their write buffers. Safe to call unconditionally after any writeFileChunk() sequence completes. */
    fun finishWrite(path: String, volId: Int): Boolean = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.finishWrite(path) ?: false
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.finishWrite(path) ?: false
        else                                            -> true
    }

    fun writeBackFile(path: String, sourcePath: String, volId: Int): Boolean = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.writeBackFile(path, sourcePath) ?: false
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.writeBackFile(path, sourcePath) ?: false
        else                                            -> VeraCryptEngine.writeBackFile(path, sourcePath, volId)
    }

    fun extractFile(path: String, destination: String, volId: Int): Boolean = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.extractFile(path, destination) ?: false
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.extractFile(path, destination) ?: false
        else                                            -> VeraCryptEngine.extractFile(path, destination, volId)
    }

    fun getSpaceInfo(volId: Int): LongArray? = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorSessionRegistry.get(volId)?.getSpaceInfo()
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsSessionRegistry.get(volId)?.getSpaceInfo()
        else                                            -> VeraCryptEngine.getSpaceInfo(volId)
    }

    fun openStream(path: String, volId: Int): Long = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorStreamRegistry.open(volId, path)
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsStreamRegistry.open(volId, path)
        else                                            -> VeraCryptEngine.openStream(path, volId)
    }

    fun readStream(stream: Long, offset: Long, out: ByteArray, length: Int, volId: Int): Int = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorStreamRegistry.read(volId, stream, offset, out, length)
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsStreamRegistry.read(volId, stream, offset, out, length)
        else                                            -> VeraCryptEngine.readStream(stream, offset, out, length, volId)
    }

    fun closeStream(stream: Long, volId: Int) = when {
        CryptomatorSessionRegistry.isCryptomator(volId) -> CryptomatorStreamRegistry.close(volId, stream)
        GocryptfsSessionRegistry.isGocryptfs(volId)     -> GocryptfsStreamRegistry.close(volId, stream)
        else                                            -> VeraCryptEngine.closeStream(stream, volId)
    }
}

enum class ContainerFormat {
    VERACRYPT, LUKS1, LUKS2, CRYPTOMATOR, GOCRYPTFS, UNKNOWN;
    val wireName: String get() = when (this) {
        VERACRYPT -> "veracrypt"; LUKS1 -> "luks1"; LUKS2 -> "luks2"
        CRYPTOMATOR -> "cryptomator"; GOCRYPTFS -> "gocryptfs"; UNKNOWN -> "unknown"
    }

    companion object {
        fun fromNative(value: Int): ContainerFormat = when (value) {
            0 -> VERACRYPT
            1 -> LUKS1
            2 -> LUKS2
            else -> UNKNOWN
        }
    }
}