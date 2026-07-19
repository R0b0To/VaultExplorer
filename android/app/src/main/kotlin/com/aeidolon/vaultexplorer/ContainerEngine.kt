package com.aeidolon.vaultexplorer

import com.aeidolon.vaultexplorer.cryptomator.CryptomatorSessionRegistry
import com.aeidolon.vaultexplorer.cryptomator.CryptomatorStreamRegistry

/**
 * Format-neutral native engine boundary.
 *
 * Tier-1 (unlock/create/change-password) operations remain VeraCrypt/LUKS-
 * specific — Cryptomator vaults are opened via CryptomatorVault.open/create
 * directly from MainActivity, not through this facade's unlock* methods,
 * since Cryptomator has no block-device/FUSE layer for VeraCryptEngine to
 * drive.
 *
 * Tier-2 (file/directory operations against an unlocked volId) dispatch
 * here: if [CryptomatorSessionRegistry] holds a session for the given
 * volId, the call goes to that pure-Kotlin session; otherwise it falls
 * through to the ABI-compatible JNI shim [VeraCryptEngine], unchanged from
 * before. This keeps every existing call site (ContainerFileSystem,
 * ContainerDocumentsProvider, file_operation_service.dart, etc.) working
 * unmodified for both container families — callers key everything off
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

    /** Locks/closes volId's session regardless of backend: zeroes the Cryptomator masterkey if it's a Cryptomator session, otherwise unmounts the native VeraCrypt/LUKS volume as before. */
    fun lock(volId: Int) {
        if (CryptomatorSessionRegistry.isCryptomator(volId)) {
            CryptomatorSessionRegistry.remove(volId)
        } else {
            VeraCryptEngine.lockNative(volId)
        }
    }
    fun requestUnlockCancellation(volId: Int) = VeraCryptEngine.requestCancelUnlockNative(volId)
    fun hashPassword(password: String, salt: ByteArray, iterations: Int): ByteArray? =
        VeraCryptEngine.hashPasswordNative(password, salt, iterations)

    fun matchedCipherId(volId: Int): Int = VeraCryptEngine.getMatchedCipherId(volId)
    fun matchedHashId(volId: Int): Int = VeraCryptEngine.getMatchedHashId(volId)

    fun format(volId: Int): ContainerFormat {
        if (CryptomatorSessionRegistry.isCryptomator(volId)) return ContainerFormat.CRYPTOMATOR
        return ContainerFormat.fromNative(VeraCryptEngine.getContainerFormat(volId))
    }

fun listDirectory(path: String, volId: Int): Array<String>? =
    if (CryptomatorSessionRegistry.isCryptomator(volId))
        CryptomatorSessionRegistry.get(volId)?.listDirectory(path)
    else
        VeraCryptEngine.listDirectory(path, volId)

    fun createDirectory(path: String, volId: Int): Boolean =
        CryptomatorSessionRegistry.get(volId)?.createDirectory(path) ?: VeraCryptEngine.createDirectory(path, volId)

    fun renameFile(oldPath: String, newPath: String, volId: Int): Boolean =
        CryptomatorSessionRegistry.get(volId)?.renameFile(oldPath, newPath) ?: VeraCryptEngine.renameFile(oldPath, newPath, volId)

    fun setLastModifiedTime(path: String, epochSeconds: Long, volId: Int): Boolean =
        CryptomatorSessionRegistry.get(volId)?.setLastModifiedTime(path, epochSeconds) ?: VeraCryptEngine.setLastModifiedTime(path, epochSeconds, volId)

    fun deleteFile(path: String, volId: Int): Boolean =
        CryptomatorSessionRegistry.get(volId)?.deleteFile(path) ?: VeraCryptEngine.deleteFile(path, volId)

    fun getFileSize(path: String, volId: Int): Long =
        CryptomatorSessionRegistry.get(volId)?.getFileSize(path) ?: VeraCryptEngine.getFileSize(path, volId)

    fun getFolderSize(path: String, volId: Int): Long =
        CryptomatorSessionRegistry.get(volId)?.getFolderSize(path) ?: VeraCryptEngine.getFolderSize(path, volId)

    fun readFileChunk(path: String, offset: Long, length: Int, volId: Int): ByteArray? =
        CryptomatorSessionRegistry.get(volId)?.readFileChunk(path, offset, length) ?: VeraCryptEngine.readFileChunk(path, offset, length, volId)

    /** For Cryptomator sessions, callers MUST invoke [finishWriteIfCryptomator] once after their final writeFileChunk() call for a given path to flush the last (possibly partial) chunk and materialize the file. */
    fun writeFileChunk(path: String, offset: Long, data: ByteArray, volId: Int): Boolean =
        CryptomatorSessionRegistry.get(volId)?.writeFileChunk(path, offset, data) ?: VeraCryptEngine.writeFileChunk(path, offset, data, volId)

    /** No-op for VeraCrypt/LUKS (whose writeFileChunk is already durable per-call); required for Cryptomator to flush its write buffer. Safe to call unconditionally after any writeFileChunk() sequence completes. */
    fun finishWriteIfCryptomator(path: String, volId: Int): Boolean =
        CryptomatorSessionRegistry.get(volId)?.finishWrite(path) ?: true

    fun writeBackFile(path: String, sourcePath: String, volId: Int): Boolean =
        CryptomatorSessionRegistry.get(volId)?.writeBackFile(path, sourcePath) ?: VeraCryptEngine.writeBackFile(path, sourcePath, volId)

    fun extractFile(path: String, destination: String, volId: Int): Boolean =
        CryptomatorSessionRegistry.get(volId)?.extractFile(path, destination) ?: VeraCryptEngine.extractFile(path, destination, volId)

fun getSpaceInfo(volId: Int): LongArray? =
    if (CryptomatorSessionRegistry.isCryptomator(volId))
        CryptomatorSessionRegistry.get(volId)?.getSpaceInfo()
    else
        VeraCryptEngine.getSpaceInfo(volId)

    fun openStream(path: String, volId: Int): Long =
        if (CryptomatorSessionRegistry.isCryptomator(volId)) CryptomatorStreamRegistry.open(volId, path)
        else VeraCryptEngine.openStream(path, volId)

    fun readStream(stream: Long, offset: Long, out: ByteArray, length: Int, volId: Int): Int =
        if (CryptomatorSessionRegistry.isCryptomator(volId)) CryptomatorStreamRegistry.read(volId, stream, offset, out, length)
        else VeraCryptEngine.readStream(stream, offset, out, length, volId)

    fun closeStream(stream: Long, volId: Int) {
        if (CryptomatorSessionRegistry.isCryptomator(volId)) CryptomatorStreamRegistry.close(volId, stream)
        else VeraCryptEngine.closeStream(stream, volId)
    }
}

enum class ContainerFormat {
    VERACRYPT,
    LUKS1,
    LUKS2,
    CRYPTOMATOR,
    UNKNOWN;

    val wireName: String
        get() = when (this) {
            VERACRYPT -> "veracrypt"
            LUKS1 -> "luks1"
            LUKS2 -> "luks2"
            CRYPTOMATOR -> "cryptomator"
            UNKNOWN -> "unknown"
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