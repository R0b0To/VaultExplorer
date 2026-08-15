package com.aeidolon.vaultexplorer.cryfs

import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * In-memory [CryfsBlockStorage] fake: plaintext, unshareded, no SAF/Context
 * dependency at all -- just enough for [CryfsDataTree]'s own tree-rebuild
 * logic to run against in a plain JVM test. `isRaw = true` so tests exercise
 * the parallel (`sharedExecutor`) build/delete path, not just the serial one.
 */
private class FakeBlockStorage : CryfsBlockStorage {
    val blocks = ConcurrentHashMap<String, ByteArray>()
    override val isRaw: Boolean = true
    override fun load(id: CryfsBlockId): ByteArray? = blocks[id.hex]?.copyOf()
    override fun store(id: CryfsBlockId, payload: ByteArray, isNewBlock: Boolean) {
        blocks[id.hex] = payload.copyOf()
    }
    override fun remove(id: CryfsBlockId): Boolean = blocks.remove(id.hex) != null
}

/**
 * Covers [CryfsDataTree.writeWholeBlob]/[CryfsDataTree.writeWholeBlobStream]'s
 * "publish" step for blobs spanning more than one leaf block -- the case an
 * earlier version of this code got wrong. That version deleted a blob's old
 * content by re-reading its root block *after* the new content had already
 * been swapped in, so it deleted the newly-written children instead of the
 * old ones: overwriting any multi-leaf file silently destroyed it. A small
 * [nodeBlockSize] here forces even short test content across several
 * leaves, so these tests fail immediately if that regression reappears.
 */
class CryfsDataTreeTest {

    private val random = SecureRandom()

    /** 64-byte blocks, 8-byte header -> 56-byte leaf payload, so anything
     *  over 56 bytes spans multiple leaves. */
    private fun newTree(storage: FakeBlockStorage) = CryfsDataTree(storage, nodeBlockSize = 64, random = random)

    @Test
    fun `overwriting a multi-leaf blob with new multi-leaf content reads back correctly`() {
        val storage = FakeBlockStorage()
        val tree = newTree(storage)

        val original = ByteArray(500) { (it % 251).toByte() }
        val rootId = tree.writeWholeBlob(null, original)
        assertArrayEquals(original, tree.readAll(rootId))

        val replacement = ByteArray(800) { ((it * 7 + 3) % 251).toByte() }
        val newRootId = tree.writeWholeBlob(rootId, replacement)

        // Same blob id: overwriting in place doesn't need a new one.
        assertEquals(rootId, newRootId)
        assertArrayEquals(replacement, tree.readAll(newRootId))
        assertEquals(replacement.size.toLong(), tree.size(newRootId))
    }

    @Test
    fun `overwriting frees the old blocks and leaves no orphans`() {
        val storage = FakeBlockStorage()
        val tree = newTree(storage)

        val original = ByteArray(500) { it.toByte() }
        val rootId = tree.writeWholeBlob(null, original)
        val blockCountAfterFirstWrite = storage.blocks.size
        assertTrue("expected the 500-byte blob to span multiple blocks", blockCountAfterFirstWrite > 1)

        val replacement = ByteArray(300) { it.toByte() }
        tree.writeWholeBlob(rootId, replacement)

        // Every block still on "disk" must be reachable by reading the blob
        // back through the tree -- readAll/size only ever follow the live
        // root, so if any old, now-unreferenced block were left behind, the
        // block count wouldn't match what a fresh write of the same content
        // would produce.
        val freshStorage = FakeBlockStorage()
        val freshTree = newTree(freshStorage)
        freshTree.writeWholeBlob(null, replacement)
        assertEquals(
            "overwrite should leave the same block count as writing the replacement fresh (i.e. no leaked old blocks)",
            freshStorage.blocks.size,
            storage.blocks.size,
        )
    }

    @Test
    fun `writeWholeBlobStream overwrite of multi-leaf content matches writeWholeBlob`() {
        val storage = FakeBlockStorage()
        val tree = newTree(storage)

        val original = ByteArray(500) { it.toByte() }
        val rootId = tree.writeWholeBlobStream(null, original.inputStream())
        assertArrayEquals(original, tree.readAll(rootId))

        val replacement = ByteArray(900) { ((it * 13) % 251).toByte() }
        val newRootId = tree.writeWholeBlobStream(rootId, replacement.inputStream())

        assertEquals(rootId, newRootId)
        assertArrayEquals(replacement, tree.readAll(newRootId))
    }

    @Test
    fun `overwriting a large blob with small content still reads back correctly`() {
        val storage = FakeBlockStorage()
        val tree = newTree(storage)

        val original = ByteArray(2000) { it.toByte() }
        val rootId = tree.writeWholeBlob(null, original)

        val replacement = ByteArray(10) { it.toByte() }
        val newRootId = tree.writeWholeBlob(rootId, replacement)

        assertArrayEquals(replacement, tree.readAll(newRootId))
        assertEquals(replacement.size.toLong(), tree.size(newRootId))
    }

    @Test
    fun `overwriting a single-leaf blob in place still works`() {
        val storage = FakeBlockStorage()
        val tree = newTree(storage)

        val original = ByteArray(20) { it.toByte() }
        val rootId = tree.writeWholeBlob(null, original)

        val replacement = ByteArray(30) { (it + 1).toByte() }
        val newRootId = tree.writeWholeBlob(rootId, replacement)

        assertEquals(rootId, newRootId)
        assertArrayEquals(replacement, tree.readAll(newRootId))
    }

    @Test
    fun `deleteBlob frees every block in a multi-leaf subtree`() {
        val storage = FakeBlockStorage()
        val tree = newTree(storage)

        val content = ByteArray(1000) { it.toByte() }
        val rootId = tree.writeWholeBlob(null, content)
        assertTrue(storage.blocks.isNotEmpty())

        tree.deleteBlob(rootId)

        assertEquals(0, storage.blocks.size)
    }

    @Test
    fun `repeated overwrites never leak blocks`() {
        val storage = FakeBlockStorage()
        val tree = newTree(storage)

        var rootId = tree.writeWholeBlob(null, ByteArray(50) { it.toByte() })
        repeat(5) { i ->
            val content = ByteArray(200 + i * 137) { ((it + i) % 251).toByte() }
            rootId = tree.writeWholeBlob(rootId, content)
            assertArrayEquals(content, tree.readAll(rootId))
        }

        // One last overwrite down to a single leaf, then delete: if any
        // earlier overwrite had leaked its old blocks, this would leave
        // more than the single current blob's blocks behind.
        val final = ByteArray(5) { it.toByte() }
        rootId = tree.writeWholeBlob(rootId, final)
        tree.deleteBlob(rootId)
        assertEquals(0, storage.blocks.size)
    }
}
