package com.aeidolon.vaultexplorer

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import com.aeidolon.vaultexplorer.container.VaultBackend
import com.aeidolon.vaultexplorer.container.VaultBackendRegistry

/**
 * Handle-based read stream registry for pure-Kotlin vault backends.
 *
 * Replaces the former CryfsStreamRegistry / CryptomatorStreamRegistry /
 * GocryptfsStreamRegistry, which were three copies of this exact logic
 * differing only in which concrete session type they cast [VaultBackend] to.
 * Since [VaultBackend] already exposes [VaultBackend.readFileChunk], no
 * per-format cast is needed at all — this dispatches through the interface,
 * so a new backend gets streaming support for free.
 */
object VaultStreamRegistry {
    private val streams = ConcurrentHashMap<Long, Pair<Int, String>>() // handle -> (volId, path)
    private val nextHandle = AtomicLong(1)

    fun open(volId: Int, path: String): Long {
        val handle = nextHandle.getAndIncrement()
        streams[handle] = volId to path
        return handle
    }

    fun read(volId: Int, handle: Long, offset: Long, out: ByteArray, length: Int): Int {
        val (ownerVolId, path) = streams[handle] ?: return -1
        if (ownerVolId != volId) return -1
        val session = VaultBackendRegistry.get(volId) ?: return -1
        val chunk = session.readFileChunk(path, offset, length) ?: return -1
        if (chunk.isEmpty()) return 0
        System.arraycopy(chunk, 0, out, 0, chunk.size)
        return chunk.size
    }

    fun close(volId: Int, handle: Long) { streams.remove(handle) }
}
