package com.aeidolon.vaultexplorer.cryfs

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/** Mirrors GocryptfsStreamRegistry — see its doc comment; same volId+path handle
 *  scheme, just resolving against a [CryfsSession] instead. */
object CryfsStreamRegistry {
    private val streams = ConcurrentHashMap<Long, Pair<Int, String>>()
    private val nextHandle = AtomicLong(1)

    fun open(volId: Int, path: String): Long {
        val handle = nextHandle.getAndIncrement()
        streams[handle] = volId to path
        return handle
    }

    fun read(volId: Int, handle: Long, offset: Long, out: ByteArray, length: Int): Int {
        val (ownerVolId, path) = streams[handle] ?: return -1
        if (ownerVolId != volId) return -1
        val session = com.aeidolon.vaultexplorer.VaultBackendRegistry.get(volId) as? CryfsSession ?: return -1
        val chunk = session.readFileChunk(path, offset, length) ?: return -1
        if (chunk.isEmpty()) return 0
        System.arraycopy(chunk, 0, out, 0, chunk.size)
        return chunk.size
    }

    fun close(volId: Int, handle: Long) { streams.remove(handle) }
}
