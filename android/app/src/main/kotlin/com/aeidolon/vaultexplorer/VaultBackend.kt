package com.aeidolon.vaultexplorer

interface VaultBackend {
    val format: ContainerFormat
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
    fun importStream(virtualPath: String, inputStream: java.io.InputStream, volId: Int): Boolean
    fun extractFile(virtualPath: String, destinationPath: String): Boolean
    fun beginBatchWrite() {}
    fun endBatchWrite() {}
    fun getSpaceInfo(): LongArray?
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