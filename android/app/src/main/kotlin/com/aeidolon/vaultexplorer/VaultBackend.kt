package com.aeidolon.vaultexplorer

/**
 * Common Tier-2 (file/directory operations against an already-unlocked
 * volId) surface implemented by every pure-Kotlin vault backend —
 * currently [com.aeidolon.vaultexplorer.cryptomator.CryptomatorSession] and
 * [com.aeidolon.vaultexplorer.gocryptfs.GocryptfsSession].
 *
 * VeraCrypt/LUKS aren't included here: they have no session object at all
 * (native VolumeState slots instead), so they stay behind the
 * [VeraCryptEngine] JNI shim — [ContainerEngine] falls back to it whenever
 * [vaultBackend] returns null for a volId.
 *
 * Method docs live on the call sites in ContainerEngine and on each
 * implementation; this interface only pins down the shared shape.
 */
interface VaultBackend {
    val format: ContainerFormat

    fun listDirectory(virtualPath: String): Array<String>?
    fun createDirectory(virtualPath: String): Boolean
    fun renameFile(oldVirtualPath: String, newVirtualPath: String): Boolean
    fun setLastModifiedTime(virtualPath: String, epochSeconds: Long): Boolean
    fun deleteFile(virtualPath: String): Boolean
    fun getFileSize(virtualPath: String): Long
    fun getFolderSize(virtualPath: String): Long
    fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray?
    fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean
    fun finishWrite(virtualPath: String): Boolean
    fun writeBackFile(virtualPath: String, sourcePath: String): Boolean
    fun extractFile(virtualPath: String, destinationPath: String): Boolean
    fun getSpaceInfo(): LongArray?
}
