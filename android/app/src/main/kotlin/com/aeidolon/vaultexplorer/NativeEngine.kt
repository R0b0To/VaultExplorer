package com.aeidolon.vaultexplorer

internal object NativeEngine {
    init {
        try {
            System.loadLibrary("vaultexplorer")
        } catch (e: UnsatisfiedLinkError) {
            // Ignore for desktop JVM unit tests
        }
    }

    @JvmStatic
    external fun encryptSingleFileNative(
        srcFd: Int, destFd: Int, cipherIndex: Int,
        password: String, keyfileFds: IntArray?, opId: Int
    ): Boolean

    @JvmStatic
    external fun decryptSingleFileNative(
        srcFd: Int, destFd: Int,
        password: String, keyfileFds: IntArray?, opId: Int
    ): Boolean

    @JvmStatic
    external fun getMaxVolumesNative(): Int

    @JvmStatic
    external fun deriveKeyMaterialNative(
        fd: Int, password: String, pim: Int,
        cipherId: Int = 255, hashId: Int = 255, keyfileFds: IntArray? = null
    ): ByteArray?

    @JvmStatic
    external fun getLastDerivedKeyMaterialNative(volId: Int): ByteArray?

    @JvmStatic
    external fun unlockAndListNative(
        fd: Int, password: String, pim: Int, volId: Int,
        cipherId: Int = 255, hashId: Int = 255, preservedKey: ByteArray? = null,
        keyfileFds: IntArray? = null, readOnly: Boolean = false,
        hiddenPassword: String? = null, hiddenPim: Int = 0,
        hiddenCipherId: Int = 255, hiddenHashId: Int = 255, hiddenKeyfileFds: IntArray? = null
    ): Array<String>?

    @JvmStatic external fun getAvifInfoNative(avifBytes: ByteArray): IntArray?
    @JvmStatic external fun decodeAvifFrameNative(avifBytes: ByteArray, frameIndex: Int): Map<String, Any>?
    @JvmStatic external fun decodeAvifNative(avifBytes: ByteArray): Map<String, Any>?

    @JvmStatic
    external fun createContainerNative(
        fd: Int, password: String, pim: Int, sizeBytes: Long, fileSystem: String,
        containerFormat: Int = 0, cipherId: Int = 255, hashId: Int = 255,
        keyfileFds: IntArray? = null
    ): Boolean

    @JvmStatic
    external fun createContainerWithHiddenNative(
        fd: Int, outerPassword: String, hiddenPassword: String,
        outerPim: Int, hiddenPim: Int, sizeBytes: Long,
        outerFileSystem: String, hiddenFileSystem: String,
        hiddenSizeBytes: Long,
        outerCipherId: Int = 255, outerHashId: Int = 255,
        hiddenCipherId: Int = 255, hiddenHashId: Int = 255,
        outerKeyfileFds: IntArray? = null, hiddenKeyfileFds: IntArray? = null
    ): Boolean

    @JvmStatic
    external fun changeContainerPasswordNative(
        fd: Int, oldPassword: String, newPassword: String,
        oldPim: Int, newPim: Int,
        cipherId: Int = 255, hashId: Int = 255,
        oldKeyfileFds: IntArray? = null, newKeyfileFds: IntArray? = null
    ): Boolean

    @JvmStatic
    external fun changeLuksContainerPasswordNative(
        fd: Int, oldPassword: String, newPassword: String,
        oldKeyfileFds: IntArray? = null, newKeyfileFds: IntArray? = null
    ): Int

    @JvmStatic
    external fun hashPasswordNative(
        password: String, salt: ByteArray, iterations: Int
    ): ByteArray?

    @JvmStatic
    external fun hashPasswordSha256Native(
        password: String, salt: ByteArray, iterations: Int, outputLen: Int
    ): ByteArray?

    @JvmStatic
    external fun aesGcmEncryptNative(
        key: ByteArray, iv: ByteArray, aad: ByteArray?, plaintext: ByteArray
    ): ByteArray?

    @JvmStatic
    external fun aesGcmDecryptNative(
        key: ByteArray, iv: ByteArray, aad: ByteArray?, ciphertextAndTag: ByteArray
    ): ByteArray?

    @JvmStatic
    external fun aesGcmEncryptFastNative(
        key: ByteArray, nonceLen: Int, aad: ByteArray?, plaintext: ByteArray
    ): ByteArray?

    @JvmStatic
    external fun aesGcmDecryptFastNative(
        key: ByteArray, nonceLen: Int, aad: ByteArray?, ciphertextAndNonce: ByteArray
    ): ByteArray?

    @JvmStatic
    external fun aesGcmEncryptStreamNative(
        key: ByteArray, nonceLen: Int, cleartextChunkSize: Int,
        fileIdOrHeaderNonce: ByteArray, startChunkNumber: Long, inputBuffer: ByteArray
    ): ByteArray?

    @JvmStatic
    external fun aesGcmDecryptStreamNative(
        key: ByteArray, nonceLen: Int, cleartextChunkSize: Int,
        fileIdOrHeaderNonce: ByteArray, startChunkNumber: Long, inputBuffer: ByteArray
    ): ByteArray?

    @JvmStatic
    external fun lockNative(volId: Int)

    @JvmStatic
    external fun requestCancelUnlockNative(volId: Int)

    @JvmStatic external fun getMatchedCipherId(volId: Int): Int
    @JvmStatic external fun getMatchedHashId(volId: Int): Int
    @JvmStatic external fun getContainerFormat(volId: Int): Int
    @JvmStatic external fun listDirectory(dirPath: String, volId: Int): Array<String>?
    @JvmStatic external fun getFileSize(fileName: String, volId: Int): Long
    @JvmStatic external fun getFolderSize(dirPath: String, volId: Int): Long
    @JvmStatic external fun readFileChunk(fileName: String, offset: Long, length: Int, volId: Int): ByteArray?
    @JvmStatic external fun writeFileChunk(fileName: String, offset: Long, data: ByteArray, volId: Int): Boolean
    @JvmStatic external fun writeBackFile(targetFileName: String, sourcePath: String, volId: Int): Boolean
    @JvmStatic external fun extractFile(targetFileName: String, destPath: String, volId: Int): Boolean
    @JvmStatic external fun deleteFile(targetFileName: String, volId: Int): Boolean
    @JvmStatic external fun createDirectory(dirPath: String, volId: Int): Boolean
    @JvmStatic external fun renameFile(oldPath: String, newPath: String, volId: Int): Boolean
    // opId <= 0 means "no progress reporting wanted" (same convention as
    // reportSplitJoinProgress) -- native no-ops the callback in that case.
    @JvmStatic external fun copyFile(srcPath: String, srcVolId: Int, destPath: String, destVolId: Int, opId: Int): Boolean
    @JvmStatic external fun setLastModifiedTime(path: String, epochSeconds: Long, volId: Int): Boolean
    @JvmStatic external fun getSpaceInfo(volId: Int): LongArray?
    @JvmStatic external fun getVaultInfo(volId: Int): Map<String, Any?>?

    @JvmStatic external fun unlockUsbAndListNative(
        password: String, pim: Int, volId: Int, deviceSizeBytes: Long,
        cipherId: Int = 255, hashId: Int = 255, preservedKey: ByteArray? = null,
        partitionOffsetHint: Long = -1L, keyfileFds: IntArray? = null, readOnly: Boolean = false,
        hiddenPassword: String? = null, hiddenPim: Int = 0,
        hiddenCipherId: Int = 255, hiddenHashId: Int = 255, hiddenKeyfileFds: IntArray? = null
    ): Array<String>?

    @JvmStatic
    external fun createUsbContainerNative(
        volId: Int, partitionScheme: String, password: String, pim: Int, sizeBytes: Long, fileSystem: String,
        containerFormat: Int = 0, cipherId: Int = 255, hashId: Int = 255,
        keyfileFds: IntArray? = null, quickFormat: Boolean = false
    ): Boolean

    @JvmStatic
    external fun scryptNative(
        passphrase: ByteArray, salt: ByteArray, N: Int, r: Int, p: Int, dkLen: Int
    ): ByteArray?

    @JvmStatic
    external fun gocryptfsEmeNative(
        key: ByteArray, tweak: ByteArray, data: ByteArray, encrypt: Boolean
    ): ByteArray?

    @JvmStatic
    external fun sivEncryptNative(
        encKey: ByteArray, macKey: ByteArray, plaintext: ByteArray, adList: Array<ByteArray>?
    ): ByteArray?

    @JvmStatic
    external fun sivDecryptNative(
        encKey: ByteArray, macKey: ByteArray, ciphertext: ByteArray, adList: Array<ByteArray>?
    ): ByteArray?

    @JvmStatic
    external fun xchacha20Poly1305SealNative(
        key: ByteArray, nonce: ByteArray, aad: ByteArray?, plaintext: ByteArray
    ): ByteArray?

    @JvmStatic
    external fun xchacha20Poly1305OpenNative(
        key: ByteArray, nonce: ByteArray, aad: ByteArray?, ciphertextAndTag: ByteArray
    ): ByteArray?

    @JvmStatic
    external fun createUsbContainerWithHiddenNative(
        volId: Int, partitionScheme: String,
        outerPassword: String, hiddenPassword: String,
        outerPim: Int, hiddenPim: Int, sizeBytes: Long,
        outerFileSystem: String, hiddenFileSystem: String,
        hiddenSizeBytes: Long,
        outerCipherId: Int = 255, outerHashId: Int = 255,
        hiddenCipherId: Int = 255, hiddenHashId: Int = 255,
        outerKeyfileFds: IntArray? = null, hiddenKeyfileFds: IntArray? = null,
        quickFormat: Boolean = false
    ): Boolean

    @JvmStatic external fun openStream(targetFileName: String, volId: Int): Long
    @JvmStatic external fun readStream(streamPtr: Long, offset: Long, outBuffer: ByteArray, length: Int, volId: Int): Int
    @JvmStatic external fun closeStream(streamPtr: Long, volId: Int)

    @JvmStatic external fun getCascadeFingerprint(cascadeId: Int): Int
    @JvmStatic external fun getCascadeIdCount(): Int
    @JvmStatic external fun getHashIdCount(): Int

    @JvmStatic external fun cryfsCipherIdNative(cipherName: String): Int
    @JvmStatic external fun cryfsEncryptBlockNative(cipherId: Int, key: ByteArray, plaintext: ByteArray): ByteArray?
    @JvmStatic external fun cryfsDecryptBlockNative(cipherId: Int, key: ByteArray, ciphertext: ByteArray): ByteArray?

    @JvmStatic
    external fun nativeDiagnoseContainerFile(fd: Int, opId: Int = -1): IntArray?

    @JvmStatic
    external fun nativeRestoreLuks2BackupHeaderFile(fd: Int, opId: Int = -1): Boolean

    @JvmStatic
    external fun nativeRestoreVeraCryptBackupHeaderFile(
        fd: Int, password: String, pim: Int, cipherId: Int, hashId: Int, opId: Int = -1
    ): Int

    @JvmStatic
    external fun nativeDiagnoseMountedVolumeFilesystem(volId: Int, opId: Int = -1): Int

    @JvmStatic
    external fun nativeRunMountedVolumeFilesystemCheck(volId: Int, opId: Int = -1): Boolean
}