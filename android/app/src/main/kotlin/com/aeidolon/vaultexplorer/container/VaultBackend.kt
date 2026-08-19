package com.aeidolon.vaultexplorer.container

interface VaultBackend {
    val format: ContainerFormat
    val skipsPerVolumeLock: Boolean
        get() = false

    /**
     * Whether this backend takes [ContainerFileSystem.withWriteLock] itself,
     * in short internal critical sections, for [finishWrite]/[writeBackFile]/
     * [deleteFile] -- so [ContainerFileSystem] should skip its own whole-call
     * lock for those three too, the same way it already does for
     * [importStream] via [skipsPerVolumeLock].
     *
     * Only `cryfs.CryfsSession` sets this true: its blob-tree writes and
     * deletes are split into a short locked "publish"/"detach" step plus
     * unlocked work on content nothing else can reach yet (see
     * `cryfs.CryfsDataTree`), so wrapping the whole call in one outer lock
     * would make those internal acquisitions redundant re-entrant no-ops
     * that never actually release to a waiting reader on another thread.
     *
     * Gocryptfs and Cryptomator have no equivalent internal locking for
     * these three calls (only [importStream] streams through
     * [engine.ChunkedFileEngine.writeBackStream]'s per-batch lock), so they
     * leave this false and keep relying on the outer lock to protect them.
     */
    val managesOwnWriteLocking: Boolean
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
    fun importStream(virtualPath: String, inputStream: java.io.InputStream, volId: Int): Boolean
    fun extractFile(virtualPath: String, destinationPath: String): Boolean
    fun beginBatchWrite() {}
    fun endBatchWrite() {}
    fun getSpaceInfo(): LongArray?

    /** Backs Vault Settings' "Vault Information" screen -- see
     *  ContainerEngine.getVaultInfo()'s doc comment for the native-format
     *  equivalent and the overall key-naming convention. */
    fun getVaultInfo(): Map<String, Any?>
    fun close()
}

object VaultBackendRegistry {
    private val sessions = java.util.concurrent.ConcurrentHashMap<Int, VaultBackend>()
    fun put(volId: Int, session: VaultBackend) {
        sessions[volId] = session
        if (session is com.aeidolon.vaultexplorer.cryfs.CryfsSession) {
            session.volId = volId
            session.dataTree.volId = volId
        }
    }
    fun get(volId: Int): VaultBackend? = sessions[volId]
    fun remove(volId: Int) {
        sessions.remove(volId)?.close()
    }
}