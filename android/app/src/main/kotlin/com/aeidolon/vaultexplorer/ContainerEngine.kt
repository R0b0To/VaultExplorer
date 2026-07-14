package com.aeidolon.vaultexplorer

/**
 * Format-neutral native engine boundary.
 *
 * The implementation currently delegates to the ABI-compatible JNI shim
 * [VeraCryptEngine]. New formats belong behind this API; callers must not
 * select a native implementation by its container brand.
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
    ): Array<String>? = VeraCryptEngine.unlockAndListNative(
        fd, password, pim, volId, cipherId, hashId, preservedKey, keyfileFds
    )

    fun unlockUsb(
        password: String, pim: Int, volId: Int, deviceSizeBytes: Long, cipherId: Int = 255,
        hashId: Int = 255, preservedKey: ByteArray? = null, partitionOffsetHint: Long = -1L,
        keyfileFds: IntArray? = null,
    ): Array<String>? = VeraCryptEngine.unlockUsbAndListNative(
        password, pim, volId, deviceSizeBytes, cipherId, hashId, preservedKey,
        partitionOffsetHint, keyfileFds
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

    fun changePassword(
        fd: Int, oldPassword: String, newPassword: String,
        oldPim: Int, newPim: Int,
        cipherId: Int = 255, hashId: Int = 255,
        oldKeyfileFds: IntArray? = null, newKeyfileFds: IntArray? = null,
    ): Boolean = VeraCryptEngine.changeContainerPasswordNative(
        fd, oldPassword, newPassword, oldPim, newPim, cipherId, hashId,
        oldKeyfileFds, newKeyfileFds
    )

    fun lock(volId: Int) = VeraCryptEngine.lockNative(volId)
    fun requestUnlockCancellation(volId: Int) = VeraCryptEngine.requestCancelUnlockNative(volId)
    fun hashPassword(password: String, salt: ByteArray, iterations: Int): ByteArray? =
        VeraCryptEngine.hashPasswordNative(password, salt, iterations)

    fun matchedCipherId(volId: Int): Int = VeraCryptEngine.getMatchedCipherId(volId)
    fun matchedHashId(volId: Int): Int = VeraCryptEngine.getMatchedHashId(volId)
    fun format(volId: Int): ContainerFormat = ContainerFormat.fromNative(VeraCryptEngine.getContainerFormat(volId))

    fun listDirectory(path: String, volId: Int): Array<String>? = VeraCryptEngine.listDirectory(path, volId)
    fun createDirectory(path: String, volId: Int): Boolean = VeraCryptEngine.createDirectory(path, volId)
    fun renameFile(oldPath: String, newPath: String, volId: Int): Boolean = VeraCryptEngine.renameFile(oldPath, newPath, volId)
    fun setLastModifiedTime(path: String, epochSeconds: Long, volId: Int): Boolean = VeraCryptEngine.setLastModifiedTime(path, epochSeconds, volId)
    fun deleteFile(path: String, volId: Int): Boolean = VeraCryptEngine.deleteFile(path, volId)
    fun getFileSize(path: String, volId: Int): Long = VeraCryptEngine.getFileSize(path, volId)
    fun getFolderSize(path: String, volId: Int): Long = VeraCryptEngine.getFolderSize(path, volId)
    fun readFileChunk(path: String, offset: Long, length: Int, volId: Int): ByteArray? = VeraCryptEngine.readFileChunk(path, offset, length, volId)
    fun writeFileChunk(path: String, offset: Long, data: ByteArray, volId: Int): Boolean = VeraCryptEngine.writeFileChunk(path, offset, data, volId)
    fun writeBackFile(path: String, sourcePath: String, volId: Int): Boolean = VeraCryptEngine.writeBackFile(path, sourcePath, volId)
    fun extractFile(path: String, destination: String, volId: Int): Boolean = VeraCryptEngine.extractFile(path, destination, volId)
    fun getSpaceInfo(volId: Int): LongArray? = VeraCryptEngine.getSpaceInfo(volId)
    fun openStream(path: String, volId: Int): Long = VeraCryptEngine.openStream(path, volId)
    fun readStream(stream: Long, offset: Long, out: ByteArray, length: Int, volId: Int): Int =
        VeraCryptEngine.readStream(stream, offset, out, length, volId)
    fun closeStream(stream: Long, volId: Int) = VeraCryptEngine.closeStream(stream, volId)
}

enum class ContainerFormat {
    VERACRYPT,
    LUKS1,
    LUKS2,
    UNKNOWN;

    val wireName: String
        get() = when (this) {
            VERACRYPT -> "veracrypt"
            LUKS1 -> "luks1"
            LUKS2 -> "luks2"
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