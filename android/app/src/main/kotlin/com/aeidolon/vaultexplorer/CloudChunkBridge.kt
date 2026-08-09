package com.aeidolon.vaultexplorer

import com.aeidolon.vaultexplorer.cloudbridge.VaultCloudBridgeClient

/**
 * Upcall target for native disk_read/disk_write when a volume's backing
 * store is [VolumeState.isCloudChunkedSource] rather than a local file or
 * USB device — see chunked_block_device.h's header comment for this
 * transport's current integration status. jni_runtime.cpp resolves this
 * class + these two @JvmStatic methods once in JNI_OnLoad and calls them
 * directly from cloudChunkReadRange/cloudChunkWriteRange
 * (jni/jni_callbacks.cpp) — this class never calls into native itself.
 *
 * Each registered volume is backed by a [VaultCloudBridgeClient] session
 * bound to VaultSync Bridge (see that class and Phase 3's
 * ChunkCacheManager on the Bridge side for where the actual network I/O
 * and caching happens) plus the identity — accountId/remoteVaultPath —
 * needed to address it. Register/unregister are owned by the remote-vault
 * mount/lock flow, same as UsbBlockBridge's are owned by the USB
 * unlock/lock flow; native code never opens or closes the underlying AIDL
 * session.
 */
object CloudChunkBridge {

    class Session(
        val client: VaultCloudBridgeClient,
        val accountId: String,
        val remoteVaultPath: String,
        val chunkSizeBytes: Int,
    )

    // ConcurrentHashMap for the same reason UsbBlockBridge's `devices` map
    // is one: register()/unregister() run on the mount/lock flow's thread
    // while readChunk()/writeChunkRange() are called from whichever JNI/
    // ioExecutor thread is doing native I/O for one of potentially several
    // concurrently-mounted remote-chunked volumes.
    private val sessions = java.util.concurrent.ConcurrentHashMap<Int, Session>()

    fun register(volId: Int, session: Session) {
        sessions[volId] = session
    }

    fun unregister(volId: Int) {
        sessions.remove(volId)
    }

    /**
     * Always returns exactly [Session.chunkSizeBytes] bytes on success —
     * a legitimately absent (sparse) remote chunk is zero-filled here,
     * not represented as null, so native's cloudChunkReadRange never has
     * to special-case "not found" versus "present and zero" (mirrors
     * IVaultCloudBridgeService.openRemoteChunkForRead's own contract).
     * Returns null only on a hard failure (no session registered, or the
     * underlying AIDL call itself failed/disconnected).
     */
    @JvmStatic
    fun readChunk(volId: Int, chunkIndex: Long): ByteArray? {
        val session = sessions[volId] ?: return null
        return session.client.readChunk(session.accountId, session.remoteVaultPath, chunkIndex, session.chunkSizeBytes)
    }

    /**
     * Read-modify-write against the full chunk: fetches the current chunk
     * (via the same path [readChunk] uses, so it benefits from
     * ChunkCacheManager's cache on the Bridge side), splices [data] in at
     * [offsetInChunk], and writes the whole chunk back through
     * VaultCloudBridgeClient's staged openRemoteChunkForWrite/
     * finalizeRemoteChunkWrite pair. Deliberately not delegated to native
     * (see chunked_block_device.cpp's pwrite doc comment) — this is a
     * caching/staleness decision, the same category of decision
     * ChunkCacheManager already owns on the other side of the AIDL call.
     */
    @JvmStatic
    fun writeChunkRange(volId: Int, chunkIndex: Long, offsetInChunk: Int, data: ByteArray): Boolean {
        val session = sessions[volId] ?: return false
        val current = session.client.readChunk(session.accountId, session.remoteVaultPath, chunkIndex, session.chunkSizeBytes)
            ?: return false
        if (offsetInChunk + data.size > current.size) return false
        System.arraycopy(data, 0, current, offsetInChunk, data.size)
        return session.client.writeChunk(session.accountId, session.remoteVaultPath, chunkIndex, current)
    }
}
