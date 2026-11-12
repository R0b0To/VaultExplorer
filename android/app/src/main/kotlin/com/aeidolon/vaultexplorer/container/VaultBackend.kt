package com.aeidolon.vaultexplorer.container

interface VaultBackend {
    val format: ContainerFormat
    val skipsPerVolumeLock: Boolean
        get() = false

    val managesOwnWriteLocking: Boolean
        get() = false

    fun listDirectory(virtualPath: String): Array<String>?
    /** Symlinks of one folder, wire kind "L" (see DirEntryWire); never part of [listDirectory]. */
    fun listSymlinks(virtualPath: String): Array<String>? = emptyArray()
    /** The target of the symlink at [virtualPath], or null if it is not a (readable) symlink. */
    fun readSymlink(virtualPath: String): String? = null
    fun createSymlink(virtualPath: String, target: String): Boolean = false
    /** Entries present on disk but not listed (conflict copies etc.); -1 when the backend cannot tell. */
    fun hiddenEntryCount(virtualPath: String): Int = -1
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
        // Folder vaults run natively; the session needs its volume id to label mirror-pull progress.
        if (session is com.aeidolon.vaultexplorer.foldervault.NativeVaultSession) {
            session.volId = volId
        }
    }
    fun get(volId: Int): VaultBackend? = sessions[volId]
    fun remove(volId: Int) {
        sessions.remove(volId)?.close()
    }
}