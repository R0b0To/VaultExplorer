package com.aeidolon.vaultexplorer.cryfs

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.security.SecureRandom

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
        if (node.depth > 0) node.children?.forEach { deleteBlob(it) }
    }

    fun deleteBlob(rootId: CryfsBlockId) {
        val node = loadNode(rootId) ?: run { blockStore.remove(rootId); return }
        if (node.depth > 0) node.children?.forEach { deleteBlob(it) }
        blockStore.remove(rootId)
    }

    private fun buildTree(content: ByteArray): CryfsBlockId {
        if (content.size <= maxLeafPayload) {
            return writeLeaf(content)
        }
        var level: MutableList<CryfsBlockId> = ArrayList()
        var offset = 0
        while (offset < content.size) {
            val end = minOf(offset + maxLeafPayload, content.size)
            level.add(writeLeaf(content.copyOfRange(offset, end)))
            offset = end
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
            level = next
            depth++
        }
        return level[0]
    }

    private fun buildTreeFromStream(inputStream: InputStream): CryfsBlockId {
        var level: MutableList<CryfsBlockId> = ArrayList()
        val buffer = ByteArray(maxLeafPayload)
        while (true) {
            var read = 0
            while (read < maxLeafPayload) {
                val n = inputStream.read(buffer, read, maxLeafPayload - read)
                if (n <= 0) break
                read += n
            }
            if (read <= 0) break
            val chunk = if (read == maxLeafPayload) buffer else buffer.copyOf(read)
            level.add(writeLeaf(chunk))
            if (read < maxLeafPayload) break
        }
        if (level.isEmpty()) {
            return writeLeaf(ByteArray(0))
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
            level = next
            depth++
        }
        return level[0]
    }

    private fun writeLeaf(payload: ByteArray): CryfsBlockId {
        val id = CryfsBlockId.random(random)
        val raw = ByteArray(nodeBlockSize)
        writeU16LE(raw, 0, NODE_FORMAT_VERSION_HEADER)
        raw[2] = 0
        raw[3] = 0
        writeU32LE(raw, 4, payload.size)
        System.arraycopy(payload, 0, raw, NODE_HEADER_SIZE, payload.size)
        blockStore.store(id, raw)
        return id
    }

    private fun writeInner(depth: Int, children: List<CryfsBlockId>): CryfsBlockId {
        val id = CryfsBlockId.random(random)
        val raw = ByteArray(nodeBlockSize)
        writeU16LE(raw, 0, NODE_FORMAT_VERSION_HEADER)
        raw[2] = 0
        raw[3] = depth.toByte()
        writeU32LE(raw, 4, children.size)
        children.forEachIndexed { i, child -> System.arraycopy(child.bytes, 0, raw, NODE_HEADER_SIZE + i * 16, 16) }
        blockStore.store(id, raw)
        return id
    }

    companion object {
        private const val NODE_HEADER_SIZE = 8
        private const val NODE_FORMAT_VERSION_HEADER = 0

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