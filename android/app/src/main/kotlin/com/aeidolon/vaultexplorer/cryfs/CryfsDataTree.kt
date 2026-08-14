package com.aeidolon.vaultexplorer.cryfs

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.security.SecureRandom
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicInteger

class CryfsDataTree(
    private val blockStore: CryfsBlockStore,
    private val nodeBlockSize: Int,
    private val random: SecureRandom,
) {
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
        val node = loadNode(rootId) ?: return 0L
        return nodeSize(node)
    }

    private fun nodeSize(node: Node): Long {
        if (node.depth == 0) return node.leafPayload!!.size.toLong()
        val children = node.children!!
        if (children.isEmpty()) return 0L
        val childCap = capacity(node.depth - 1)
        val lastNode = loadNode(children.last()) ?: return (children.size - 1).toLong() * childCap
        return (children.size - 1).toLong() * childCap + nodeSize(lastNode)
    }

    fun readAll(rootId: CryfsBlockId): ByteArray {
        val total = size(rootId)
        return read(rootId, 0, total.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
    }

    fun read(rootId: CryfsBlockId, offset: Long, length: Int): ByteArray {
        if (length <= 0) return ByteArray(0)
        val node = loadNode(rootId) ?: return ByteArray(0)
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
            val childNode = loadNode(children[idx]) ?: break
            val before = out.size()
            readInto(childNode, localOffset, remainingLength, out)
            val got = out.size() - before
            if (got == 0) break
            remainingLength -= got
            idx++
            localOffset = 0
        }
    }

    fun writeWholeBlob(existingRootId: CryfsBlockId?, newContent: ByteArray): CryfsBlockId {
        if (existingRootId != null) deleteBlobDescendantsOnly(existingRootId)
        val scratchRootId = buildTree(newContent)
        if (existingRootId == null) return scratchRootId
        val topNodeRaw = blockStore.load(scratchRootId)
            ?: throw IllegalStateException("Failed to build new blob content")
        blockStore.store(existingRootId, topNodeRaw)
        blockStore.remove(scratchRootId)
        return existingRootId
    }

    fun writeWholeBlobStream(existingRootId: CryfsBlockId?, inputStream: InputStream): CryfsBlockId {
        if (existingRootId != null) deleteBlobDescendantsOnly(existingRootId)
        val scratchRootId = buildTreeFromStream(inputStream)
        if (existingRootId == null) return scratchRootId
        val topNodeRaw = blockStore.load(scratchRootId)
            ?: throw IllegalStateException("Failed to build new blob content")
        blockStore.store(existingRootId, topNodeRaw)
        blockStore.remove(scratchRootId)
        return existingRootId
    }

    private fun deleteBlobDescendantsOnly(rootId: CryfsBlockId) {
        val node = loadNode(rootId) ?: return
        val children = node.children ?: return
        val startTime = System.currentTimeMillis()
        logDeletionPath("deleteBlobDescendantsOnly")
        val count = AtomicInteger(0)
        deleteChildrenConcurrently(children, count)
        logDeletionCompleted("deleteBlobDescendantsOnly", count.get(), startTime)
    }

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

    /** Logs, once per top-level delete call, which storage path is about to be used --
     *  mirrors [com.aeidolon.vaultexplorer.engine.ChunkedFileEngine.extractFile]'s
     *  FAST-PATH/SLOW-PATH logging so the two show up the same way in logcat. Warn-level
     *  for the SAF case (like that method's SLOW-PATH log) so it's easy to spot which
     *  vaults are actually hitting the Binder-latency-bound path. */
    private fun logDeletionPath(method: String) {
        if (blockStore.isRaw) {
            android.util.Log.d(TAG, "$method FAST-PATH using raw filesystem")
        } else {
            android.util.Log.w(TAG, "$method SLOW-PATH using SAF (parallel, pool size $SAF_POOL_SIZE)")
        }
    }

    private fun logDeletionCompleted(method: String, blockCount: Int, startTime: Long) {
        val elapsed = System.currentTimeMillis() - startTime
        android.util.Log.d(
            TAG,
            "$method COMPLETED $blockCount block(s) in ${elapsed}ms (FastPath=${blockStore.isRaw})"
        )
    }

    /**
     * Deletes [children] and everything beneath them, fanning out across [sharedExecutor]
     * regardless of [CryfsBlockStore.isRaw]. This is the actual fix for the SAF deletion
     * bottleneck: under SAF, [CryfsBlockStore.remove] is a blocking Binder round-trip
     * (~60-80ms), so a 30 MB file's ~960 sibling leaf blocks used to be deleted one at a
     * time (>90s); running them concurrently brings the wall-clock time down to roughly
     * (block count / pool size) round-trips instead of (block count) of them.
     *
     * Only the level that isn't already running inside a [sharedExecutor] worker actually
     * submits to the pool -- see [deleteBlobSequential]. That's deliberate, not a missed
     * optimization: [sharedExecutor] is a small fixed-size pool, so a node that recursively
     * resubmits its own children and then blocks on `Future.get()` can deadlock the pool
     * once tree depth exceeds the pool size (each blocked parent occupies a worker thread
     * that can never free up to run the children it's waiting on). Real trees built by this
     * app are wide and shallow (maxChildren is in the thousands for any normal block size,
     * so even multi-GB files stay at depth 1-2), but a foreign or maliciously crafted vault
     * could specify a tiny block size to force a much deeper tree. Walking deeper levels
     * in-place on whichever worker picked up the first batch makes the recursion correct
     * for a tree of any depth, and costs no real throughput either way: [sharedExecutor] is
     * already sized to the max useful SAF concurrency, which is the actual bottleneck
     * regardless of how the fan-out is shaped.
     *
     * [count] accumulates how many blocks actually got deleted, purely for
     * [logDeletionCompleted] -- an [AtomicInteger] since multiple [sharedExecutor] workers
     * increment it concurrently.
     */
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

    /** Same recursive delete as [deleteBlob], but always walks its subtree in-place on the
     *  calling thread rather than fanning back out -- used once a subtree is already being
     *  handled by a [sharedExecutor] worker. See [deleteChildrenConcurrently]. */
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

    /**
     * Waits for every future, even after one fails, instead of aborting on the first
     * `Future.get()` exception -- an early return would leave the remaining child-deletion
     * tasks running unsupervised in the background, racing whatever the caller does next.
     * Failures are collected onto a single [CryfsBlockDeletionException] (first failure as
     * the cause, any further ones attached as suppressed exceptions) so a bad block or a SAF
     * permission error surfaces clearly instead of the operation just hanging.
     */
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

    private fun buildTree(content: ByteArray): CryfsBlockId {
        if (content.size <= maxLeafPayload) {
            return writeLeaf(content)
        }
        val level = mutableListOf<CryfsBlockId>()
        val futures = java.util.ArrayDeque<Future<CryfsBlockId>>()
        val maxInFlight = 128 // Cap memory at ~4MB in flight
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

        // Sized for SAF's Binder-latency-bound deletes, not CPU work: each worker mostly
        // sits blocked on a round-trip to the DocumentsProvider, so more threads than
        // cores is fine -- but too many risks exhausting the process's Binder thread pool
        // or triggering framework throttling, hence the 4-8 cap rather than scaling
        // further with core count.
        private val SAF_POOL_SIZE = Runtime.getRuntime().availableProcessors().coerceIn(4, 8)
        private val sharedExecutor = Executors.newFixedThreadPool(SAF_POOL_SIZE)

        // Marks a thread as already running inside sharedExecutor, so deleteChildrenConcurrently
        // knows to recurse in-place instead of submitting more work back to the same pool.
        // See the kdoc on deleteChildrenConcurrently for why that's what keeps arbitrarily
        // deep trees from deadlocking a small fixed-size pool.
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

/**
 * Thrown by [CryfsDataTree.deleteBlob] (and the internal descendants-only delete used when
 * overwriting a blob) when one or more blocks in the subtree fail to delete -- e.g. a SAF
 * permission error or an `IOException` mid-deletion. The first failure becomes the cause;
 * any further failures from sibling blocks are attached via [Throwable.addSuppressed]
 * rather than being silently dropped.
 */
class CryfsBlockDeletionException(cause: Throwable) :
    java.io.IOException("Failed to delete one or more blocks: ${cause.message}", cause)