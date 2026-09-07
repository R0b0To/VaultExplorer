package com.aeidolon.vaultexplorer.container

interface VaultBackend {
    val format: ContainerFormat
    val skipsPerVolumeLock: Boolean
        get() = false

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
    /**
     * [singlePass] tells the chunk-progress reporter whether [opId]'s
     * byte budget covers just this one write (a plain writeback/import,
     * report the full delta) or is shared with a matching [extractFile]
     * call under the same opId (a cross-container copy's two-step
     * extract+writeback, report half from each side so together they add
     * up to one file instead of 200%). Defaults to the copy behavior
     * since that's every existing caller; only the standalone
     * writeBackFile MethodChannel handler passes true.
     */
    fun writeBackFile(virtualPath: String, sourcePath: String, opId: Int = 0, singlePass: Boolean = false): Boolean
    fun importStream(virtualPath: String, inputStream: java.io.InputStream, volId: Int): Boolean
    /** See [writeBackFile]'s [singlePass] doc -- same story, extract side. */
    fun extractFile(virtualPath: String, destinationPath: String, opId: Int = 0, singlePass: Boolean = false): Boolean
    fun beginBatchWrite() {}
    fun endBatchWrite() {}
    fun beginBatchDelete() {}
    fun endBatchDelete() {}
    fun invalidateCache(virtualPath: String = "") {}
    fun getSpaceInfo(): LongArray?

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
        if (session is com.aeidolon.vaultexplorer.cryptomator.CryptomatorSession) {
            session.volId = volId
        }
        if (session is com.aeidolon.vaultexplorer.gocryptfs.GocryptfsSession) {
            session.volId = volId
        }
    }
    fun get(volId: Int): VaultBackend? = sessions[volId]
    fun remove(volId: Int) {
        sessions.remove(volId)?.close()
    }
}