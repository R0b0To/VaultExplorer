package com.aeidolon.vaultexplorer

/**
 * Common Tier-2 (file/directory operations against an already-unlocked
 * volId) surface implemented by every pure-Kotlin vault backend —
 * currently [com.aeidolon.vaultexplorer.cryptomator.CryptomatorSession],
 * [com.aeidolon.vaultexplorer.gocryptfs.GocryptfsSession], and
 * [com.aeidolon.vaultexplorer.cryfs.CryfsSession].
 *
 * VeraCrypt/LUKS aren't included here: they have no session object at all
 * (native VolumeState slots instead), so they stay behind the
 * [NativeEngine] JNI shim — [ContainerEngine] falls back to it whenever
 * [vaultBackend] returns null for a volId.
 *
 * Method docs live on the call sites in ContainerEngine and on each
 * implementation; this interface only pins down the shared shape.
 */
interface VaultBackend {
    val format: ContainerFormat

    /**
     * Whether [ContainerFileSystem.getFileSize]/[ContainerFileSystem.readFileChunk]
     * may skip the per-volId ReentrantReadWriteLock for this backend.
     *
     * Defaults to false (locked, same as every native FAT/NTFS/ext-backed
     * volume) so a new backend is safe-by-default and must opt out
     * deliberately, in code, rather than by having its class name happen to
     * match a substring somewhere else -- see docs/tech-debt.md TD-6 for the
     * bug this replaced: the previous check ran `session.javaClass
     * .simpleName.contains("Cryptomator"/"Gocryptfs")`, but `session` there
     * was always a `ContainerSession` (the generic per-volId registry
     * entry), never a `CryptomatorSession`/`GocryptfsSession` -- so the
     * check was permanently false and the intended carve-out never fired.
     */
    val skipsPerVolumeLock: Boolean
        get() = false

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

    /** Releases any held resources (pending writes, cached keys, etc). Every
     *  backend must implement this so [VaultBackendRegistry.remove] can zero
     *  state without knowing which concrete backend it's holding. */
    fun close()
}

/** Process-wide registry of unlocked pure-Kotlin sessions. */
object VaultBackendRegistry {
    private val sessions = java.util.concurrent.ConcurrentHashMap<Int, VaultBackend>()

    fun put(volId: Int, session: VaultBackend) {
        sessions[volId] = session
    }

    fun get(volId: Int): VaultBackend? = sessions[volId]

    fun remove(volId: Int) {
        sessions.remove(volId)?.close()
    }
}