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
    fun importStream(virtualPath: String, inputStream: java.io.InputStream): Boolean
    fun extractFile(virtualPath: String, destinationPath: String): Boolean
    fun getSpaceInfo(): LongArray?
}

/** Process-wide registry of unlocked pure-Kotlin sessions. */
object VaultBackendRegistry {
    private val sessions = java.util.concurrent.ConcurrentHashMap<Int, VaultBackend>()

    fun put(volId: Int, session: VaultBackend) {
        sessions[volId] = session
    }

    fun get(volId: Int): VaultBackend? = sessions[volId]

    fun remove(volId: Int) {
        // VaultBackend doesn't have close(), but we need to zero keys.
        // For now, let's cast if we know it needs closing.
        val session = sessions.remove(volId)
        if (session is com.aeidolon.vaultexplorer.cryptomator.CryptomatorSession) {
            session.close()
        } else if (session is com.aeidolon.vaultexplorer.gocryptfs.GocryptfsSession) {
            session.close()
        } else if (session is com.aeidolon.vaultexplorer.cryfs.CryfsSession) {
            session.close()
        }
    }
}