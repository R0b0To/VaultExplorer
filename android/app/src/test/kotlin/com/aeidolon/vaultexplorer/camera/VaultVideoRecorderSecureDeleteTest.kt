package com.aeidolon.vaultexplorer.camera

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.RandomAccessFile

/**
 * secureDeleteFile exists specifically so a leftover plaintext recording
 * isn't just unlinked -- see its own doc comment: on most Android
 * filesystems, delete() alone leaves the content readable until the blocks
 * are reused. That's the one thing worth actually verifying, not just "the
 * file is gone afterward".
 *
 * The technique: open a read handle on the file *before* calling
 * secureDeleteFile. Unix delete()/unlink() only removes the directory
 * entry -- the underlying inode and its data stay reachable through any
 * file descriptor opened before the unlink, until every descriptor
 * pointing at it is closed. Confirmed empirically in this environment
 * before relying on it here: the write secureDeleteFile does (by path,
 * before its own delete() call) lands on the same inode our held-open
 * handle is already pointing at, so reading through that handle afterward
 * shows exactly what was on disk at the moment of deletion.
 */
class VaultVideoRecorderSecureDeleteTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun `overwrites file content with zeros before deleting it`() {
        val file = tempFolder.newFile("recording.mp4")
        file.writeBytes(ByteArray(1000) { 0xAB.toByte() })

        val isWindows = System.getProperty("os.name")?.lowercase()?.contains("win") == true
        if (isWindows) {
            assertTrue(VaultVideoRecorder.zeroFillFile(file))
            val readBack = file.readBytes()
            assertTrue("expected the pre-deletion content to be all zero, found a non-zero byte", readBack.all { it == 0.toByte() })
            assertTrue(VaultVideoRecorder.secureDeleteFile(file))
            assertFalse(file.exists())
            return
        }

        val heldOpenHandle = RandomAccessFile(file, "r")
        try {
            val result = VaultVideoRecorder.secureDeleteFile(file)
            assertTrue(result)
            assertFalse(file.exists())

            heldOpenHandle.seek(0)
            val readBack = ByteArray(1000)
            heldOpenHandle.readFully(readBack)
            assertTrue("expected the pre-deletion content to be all zero, found a non-zero byte", readBack.all { it == 0.toByte() })
        } finally {
            heldOpenHandle.close()
        }
    }

    @Test
    fun `a file larger than the 64KB zero-fill buffer is fully overwritten in one call`() {
        // Exercises the chunked write loop's "remaining > buffer size"
        // branch, which a small fixture never reaches, plus the
        // not-a-whole-number-of-chunks tail (64KB + 100 bytes).
        val size = 64 * 1024 + 100
        val file = tempFolder.newFile("large_recording.mp4")
        file.writeBytes(ByteArray(size) { 0xCD.toByte() })

        val isWindows = System.getProperty("os.name")?.lowercase()?.contains("win") == true
        if (isWindows) {
            assertTrue(VaultVideoRecorder.zeroFillFile(file))
            val readBack = file.readBytes()
            assertTrue(readBack.all { it == 0.toByte() })
            assertTrue(VaultVideoRecorder.secureDeleteFile(file))
            assertFalse(file.exists())
            return
        }

        val heldOpenHandle = RandomAccessFile(file, "r")
        try {
            assertTrue(VaultVideoRecorder.secureDeleteFile(file))
            assertFalse(file.exists())

            heldOpenHandle.seek(0)
            val readBack = ByteArray(size)
            heldOpenHandle.readFully(readBack)
            assertTrue(readBack.all { it == 0.toByte() })
        } finally {
            heldOpenHandle.close()
        }
    }

    @Test
    fun `a zero-length file is deleted without attempting to write`() {
        val file = tempFolder.newFile("empty.mp4")
        assertEquals(0L, file.length())

        assertTrue(VaultVideoRecorder.secureDeleteFile(file))
        assertFalse(file.exists())
    }

    @Test
    fun `a file that does not exist is treated as already successfully deleted`() {
        val neverCreated = java.io.File(tempFolder.root, "does-not-exist.mp4")
        assertFalse(neverCreated.exists())

        assertTrue(VaultVideoRecorder.secureDeleteFile(neverCreated))
    }
}
