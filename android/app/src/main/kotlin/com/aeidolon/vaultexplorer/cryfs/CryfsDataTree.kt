package com.aeidolon.vaultexplorer.cryfs

import com.aeidolon.vaultexplorer.ContainerFileSystem
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.security.SecureRandom
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicInteger

class CryfsDataTree(
    private val blockStore: CryfsBlockStorage,
    private val nodeBlockSize: Int,
    private val random: SecureRandom,
) {
    var volId: Int = -1

    inline fun <T> runRead(block: () -> T): T {
        return if (volId >= 0) ContainerFileSystem.withReadLock(volId, block) else block()
    }

    inline fun <T> runWrite(block: () -> T): T {
        return if (volId >= 0) ContainerFileSystem.withWriteLock(volId, block) else block()
    }

    private val maxLeafPayload = (nodeBlockSize - NODE_HEADER_SIZE).coerceAtLeast(1)
    private val maxChildren = (maxLeafPayload / CryfsBlockId.SIZE_BYTES).coerceAtLeast(2)

    private data class Node(val depth: Int, val leafPayload: ByteArray?, val children: List<CryfsBlockId>?)

    private fun loadNode(id: CryfsBlockId): Node? {
        val raw = blockStore.load(id) ?: return null
        if (raw.size < NODE_HEADER_SIZE) return null
        val formatVersion = readU16LE(raw, 0)
        if (formatVersion != NODE_FORMAT_VERSION_HEADER) return null
        val depth = raw[3].toInt() and 0xFF
        val size = readU32LE(raw, 4)
        return if (depth == 0) {
            val end = (NODE_HEADER_SIZE + size).coerceAtMost(raw.size)
            Node(0, raw.copyOfRange(NODE_HEADER_SIZE, end), null)
        } else {
            val children = ArrayList<CryfsBlockId>(size)
            for (i in 0 until size) {
                val off = NODE_HEADER_SIZE + i * 16
                if (off + 16 > raw.size) break
                children.add(CryfsBlockId(raw.copyOfRange(off, off + 16)))
            }
            Node(depth, null, children)
        }
    }

    private fun capacity(depth: Int): Long {
        var cap = maxLeafPayload.toLong()
        repeat(depth) { cap *= maxChildren }
        return cap
    }

    fun size(rootId: CryfsBlockId): Long {
        val node = runRead { loadNode(rootId) } ?: return 0L
        return nodeSize(node)
    }

    private fun nodeSize(node: Node): Long {
        if (node.depth == 0) return node.leafPayload!!.size.toLong()
        val children = node.children!!
        if (children.isEmpty()) return 0L
        val childCap = capacity(node.depth - 1)
        val lastNode = runRead { loadNode(children.last()) } ?: return (children.size - 1).toLong() * childCap
        return (children.size - 1).toLong() * childCap + nodeSize(lastNode)
    }

    fun readAll(rootId: CryfsBlockId): ByteArray {
        val total = size(rootId)
        return read(rootId, 0, total.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
    }

    fun read(rootId: CryfsBlockId, offset: Long, length: Int): ByteArray {
        if (length <= 0) return ByteArray(0)
        val node = runRead { loadNode(rootId) } ?: return ByteArray(0)
        val out = ByteArrayOutputStream(length.coerceAtMost(nodeBlockSize.coerceAtLeast(1)))
        readInto(node, offset, length, out)
        return out.toByteArray()
    }

    private fun readInto(node: Node, offset: Long, length: Int, out: ByteArrayOutputStream) {
        if (length <= 0 || offset < 0) return
        if (node.depth == 0) {
            val payload = node.leafPayload!!
            if (offset >= payload.size) return
            val end = minOf(payload.size.toLong(), offset + length).toInt()
            out.write(payload, offset.toInt(), end - offset.toInt())
            return
        }
        val children = node.children!!
        val childCap = capacity(node.depth - 1)
        if (childCap <= 0) return
        var idx = (offset / childCap).toInt()
        var localOffset = offset - idx.toLong() * childCap
        var remainingLength = length
        while (remainingLength > 0 && idx < children.size) {
            val childNode = runRead { loadNode(children[idx]) } ?: break
            val before = out.size()
            readInto(childNode, localOffset, remainingLength, out)
            val got = out.size() - before
            if (got == 0) break
            remainingLength -= got
            idx++
            localOffset = 0
        }
    }

    fun writeWholeBlob(existingRootId: CryfsBlockId?, newContent: ByteArray): CryfsBlockId =
        publish(existingRootId, buildTree(newContent))

    fun writeWholeBlobStream(existingRootId: CryfsBlockId?, inputStream: InputStream): CryfsBlockId =
        publish(existingRootId, buildTreeFromStream(inputStream))

    /**
     * Publishes [scratchRootId] -- a freshly built blob tree that nothing in
     * the live vault tree references yet -- as the new content of
     * [existingRootId], or simply returns it as a brand-new blob's id if
     * [existingRootId] is null.
     *
     * [existingRootId]'s *own* current children are captured before
     * anything is overwritten, and freed using that captured list
     * afterward -- not by re-reading [existingRootId]'s node once the swap
     * below has landed, which would already reflect the *new* content and
     * would free the blocks we just published instead of the ones we're
     * replacing. (An earlier version of this function did exactly that: it
     * called the old "delete descendants" step after the swap instead of
     * before, so it silently destroyed every overwrite of a blob spanning
     * more than one leaf block and leaked the true old blocks forever.)
     *
     * Only the swap itself -- two single-block store/remove calls -- needs
     * the write lock: it's the only step that touches something the live
     * tree currently points at. Building [scratchRootId] and freeing the
     * old children are both safe with no lock at all, since neither one is
     * ever reachable from the live tree while it's happening -- the same
     * reasoning [CryfsSession.deleteFile] uses to free a deleted file's
     * blocks without holding the lock either.
     */
    private fun publish(existingRootId: CryfsBlockId?, scratchRootId: CryfsBlockId): CryfsBlockId {
        if (existingRootId == null) return scratchRootId
        val oldChildren = runRead { loadNode(existingRootId) }?.children
        val topNodeRaw = blockStore.load(scratchRootId)
            ?: throw IllegalStateException("Failed to build new blob content")
        runWrite {
            blockStore.store(existingRootId, topNodeRaw)
            blockStore.remove(scratchRootId)
        }
        oldChildren?.let { deleteChildren(it) }
        return existingRootId
    }

    private fun deleteChildren(children: List<CryfsBlockId>) {
        if (children.isEmpty()) return
        val startTime = System.currentTimeMillis()
        logDeletionPath("deleteChildren")
        val count = AtomicInteger(0)
        deleteChildrenConcurrently(children, count)
        logDeletionCompleted("deleteChildren", count.get(), startTime)
    }

    /**
     * Deletes [rootId] and everything beneath it. Callers must only pass a
     * [rootId] that's already unreachable from the live vault tree (e.g.
     * [CryfsSession.deleteFile] removes the directory entry pointing at it
     * *before* calling this) -- this runs with no lock at all, relying on
     * that detachment rather than coarse-lock exclusion for safety.
     */
    fun deleteBlob(rootId: CryfsBlockId) {
        val startTime = System.currentTimeMillis()
        logDeletionPath("deleteBlob")
        val node = loadNode(rootId) ?: run {
            blockStore.remove(rootId)
            logDeletionCompleted("deleteBlob", 1, startTime)
            return
        }
        val count = AtomicInteger(0)
        node.children?.let { deleteChildrenConcurrently(it, count) }
        blockStore.remove(rootId)
        logDeletionCompleted("deleteBlob", count.incrementAndGet(), startTime)
    }

    // Guarded by volId (same "not running inside a real session" signal
    // runRead/runWrite use) rather than logging unconditionally, so
    // CryfsDataTree stays usable from a plain JVM unit test against a fake
    // CryfsBlockStorage -- android.util.Log isn't mocked there and throws.
    private fun logDeletionPath(method: String) {
        if (volId < 0) return
        if (blockStore.isRaw) {
            android.util.Log.d(TAG, "$method FAST-PATH using raw filesystem")
        } else {
            android.util.Log.w(TAG, "$method SLOW-PATH using SAF (parallel, pool size $SAF_POOL_SIZE)")
        }
    }

    private fun logDeletionCompleted(method: String, blockCount: Int, startTime: Long) {
        if (volId < 0) return
        val elapsed = System.currentTimeMillis() - startTime
        android.util.Log.d(
            TAG,
            "$method COMPLETED $blockCount block(s) in ${elapsed}ms (FastPath=${blockStore.isRaw})"
        )
    }

    private fun deleteChildrenConcurrently(children: List<CryfsBlockId>, count: AtomicInteger) {
        if (children.isEmpty()) return
        if (children.size == 1 || insideSharedExecutor.get()) {
            children.forEach { deleteBlobSequential(it, count) }
            return
        }
        val futures = children.map { child ->
            sharedExecutor.submit(Callable {
                insideSharedExecutor.set(true)
                try {
                    deleteBlobSequential(child, count)
                } finally {
                    insideSharedExecutor.set(false)
                }
            })
        }
        awaitAllOrThrow(futures)
    }

    private fun deleteBlobSequential(rootId: CryfsBlockId, count: AtomicInteger) {
        val node = loadNode(rootId) ?: run {
            blockStore.remove(rootId)
            count.incrementAndGet()
            return
        }
        node.children?.forEach { deleteBlobSequential(it, count) }
        blockStore.remove(rootId)
        count.incrementAndGet()
    }

    private fun awaitAllOrThrow(futures: List<Future<*>>) {
        var primary: Throwable? = null
        for (future in futures) {
            try {
                future.get()
            } catch (e: ExecutionException) {
                val cause = e.cause ?: e
                if (primary == null) primary = cause else primary.addSuppressed(cause)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
                if (primary == null) primary = e else primary.addSuppressed(e)
            }
        }
        primary?.let { throw CryfsBlockDeletionException(it) }
    }

    /**
     * Builds a brand-new blob tree out of [content] under fresh, random
     * block ids. Nothing references any of these blocks until [publish]
     * swaps the finished tree into place, so this needs no lock at all --
     * that's also why the SAF-backed parallel path below is safe to run at
     * full [sharedExecutor] concurrency rather than serializing through the
     * per-volume lock.
     */
    private fun buildTree(content: ByteArray): CryfsBlockId {
        if (content.size <= maxLeafPayload) {
            return writeLeaf(content)
        }
        val level = mutableListOf<CryfsBlockId>()
        val futures = java.util.ArrayDeque<Future<CryfsBlockId>>()
        val maxInFlight = 128
        val useParallel = blockStore.isRaw
        var offset = 0
        while (offset < content.size) {
            val end = minOf(offset + maxLeafPayload, content.size)
            val chunk = content.copyOfRange(offset, end)
            if (useParallel) {
                if (futures.size >= maxInFlight) {
                    level.add(futures.removeFirst().get())
                }
                futures.add(sharedExecutor.submit(Callable { writeLeaf(chunk) }))
            } else {
                level.add(writeLeaf(chunk))
            }
            offset = end
        }
        while (futures.isNotEmpty()) {
            level.add(futures.removeFirst().get())
        }
        var depth = 1
        while (level.size > 1) {
            val next = ArrayList<CryfsBlockId>((level.size + maxChildren - 1) / maxChildren)
            var i = 0
            while (i < level.size) {
                val group = level.subList(i, minOf(i + maxChildren, level.size))
                next.add(writeInner(depth, group))
                i += maxChildren
            }
            level.clear()
            level.addAll(next)
            depth++
        }
        return level[0]
    }

    /** Streaming counterpart of [buildTree]; same "no lock needed" reasoning. */
    private fun buildTreeFromStream(inputStream: InputStream): CryfsBlockId {
        val level = mutableListOf<CryfsBlockId>()
        val buffer = ByteArray(maxLeafPayload)
        val futures = java.util.ArrayDeque<Future<CryfsBlockId>>()
        val maxInFlight = 128
        val useParallel = blockStore.isRaw
        while (true) {
            var read = 0
            while (read < maxLeafPayload) {
                val n = inputStream.read(buffer, read, maxLeafPayload - read)
                if (n <= 0) break
                read += n
            }
            if (read <= 0) break
            val chunk = if (read == maxLeafPayload) buffer.copyOf() else buffer.copyOf(read)
            if (useParallel) {
                if (futures.size >= maxInFlight) {
                    level.add(futures.removeFirst().get())
                }
                futures.add(sharedExecutor.submit(Callable { writeLeaf(chunk) }))
            } else {
                level.add(writeLeaf(chunk))
            }
            if (read < maxLeafPayload) break
        }
        if (level.isEmpty() && futures.isEmpty()) {
            return writeLeaf(ByteArray(0))
        }
        while (futures.isNotEmpty()) {
            level.add(futures.removeFirst().get())
        }
        var depth = 1
        while (level.size > 1) {
            val next = ArrayList<CryfsBlockId>((level.size + maxChildren - 1) / maxChildren)
            var i = 0
            while (i < level.size) {
                val group = level.subList(i, minOf(i + maxChildren, level.size))
                next.add(writeInner(depth, group))
                i += maxChildren
            }
            level.clear()
            level.addAll(next)
            depth++
        }
        return level[0]
    }

    /**
 * Overwrites [newBytes] at [offset] within [rootId]'s *first* leaf block,
 * in place, without rebuilding the tree. Only valid for overwrites that
 * stay inside the fixed-size header region every blob's first leaf
 * carries (see [CryfsFsBlob]) -- it never changes payload length.
 */
fun patchFirstLeafBytes(rootId: CryfsBlockId, offset: Int, newBytes: ByteArray) {
    runWrite {
        val leafId = findFirstLeafId(rootId) ?: return@runWrite
        val raw = blockStore.load(leafId) ?: return@runWrite
        val off = NODE_HEADER_SIZE + offset
        if (off + newBytes.size > raw.size) return@runWrite
        System.arraycopy(newBytes, 0, raw, off, newBytes.size)
        blockStore.store(leafId, raw, isNewBlock = false)
    }
}

private fun findFirstLeafId(rootId: CryfsBlockId): CryfsBlockId? {
    var current = rootId
    while (true) {
        val node = loadNode(current) ?: return null
        if (node.depth == 0) return current
        current = node.children?.firstOrNull() ?: return null
    }
}

    private fun writeLeaf(payload: ByteArray): CryfsBlockId {
        val id = CryfsBlockId.randomFast(random)
        val raw = ByteArray(nodeBlockSize)
        writeU16LE(raw, 0, NODE_FORMAT_VERSION_HEADER)
        raw[2] = 0
        raw[3] = 0
        writeU32LE(raw, 4, payload.size)
        System.arraycopy(payload, 0, raw, NODE_HEADER_SIZE, payload.size)
        blockStore.store(id, raw, isNewBlock = true)
        return id
    }

    private fun writeInner(depth: Int, children: List<CryfsBlockId>): CryfsBlockId {
        val id = CryfsBlockId.randomFast(random)
        val raw = ByteArray(nodeBlockSize)
        writeU16LE(raw, 0, NODE_FORMAT_VERSION_HEADER)
        raw[2] = 0
        raw[3] = depth.toByte()
        writeU32LE(raw, 4, children.size)
        children.forEachIndexed { i, child -> System.arraycopy(child.bytes, 0, raw, NODE_HEADER_SIZE + i * 16, 16) }
        blockStore.store(id, raw, isNewBlock = true)
        return id
    }

    companion object {
        private const val NODE_HEADER_SIZE = 8
        private const val NODE_FORMAT_VERSION_HEADER = 0
        private const val TAG = "CryfsDataTree"
        private val SAF_POOL_SIZE = Runtime.getRuntime().availableProcessors().coerceIn(4, 8)
        private val sharedExecutor = Executors.newFixedThreadPool(SAF_POOL_SIZE)
        private val insideSharedExecutor = ThreadLocal.withInitial { false }
        private fun writeU16LE(dst: ByteArray, off: Int, v: Int) {
            dst[off] = (v and 0xFF).toByte()
            dst[off + 1] = ((v ushr 8) and 0xFF).toByte()
        }
        private fun writeU32LE(dst: ByteArray, off: Int, v: Int) {
            dst[off] = (v and 0xFF).toByte()
            dst[off + 1] = ((v ushr 8) and 0xFF).toByte()
            dst[off + 2] = ((v ushr 16) and 0xFF).toByte()
            dst[off + 3] = ((v ushr 24) and 0xFF).toByte()
        }
        private fun readU16LE(src: ByteArray, off: Int): Int =
            (src[off].toInt() and 0xFF) or ((src[off + 1].toInt() and 0xFF) shl 8)
        private fun readU32LE(src: ByteArray, off: Int): Int =
            (src[off].toInt() and 0xFF) or
                ((src[off + 1].toInt() and 0xFF) shl 8) or
                ((src[off + 2].toInt() and 0xFF) shl 16) or
                ((src[off + 3].toInt() and 0xFF) shl 24)
    }
}

class CryfsBlockDeletionException(cause: Throwable) :
    java.io.IOException("Failed to delete one or more blocks: ${cause.message}", cause)