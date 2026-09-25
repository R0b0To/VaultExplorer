package com.aeidolon.vaultexplorer

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

@RunWith(AndroidJUnit4::class)
class SecureFileWipeTest {

    private lateinit var context: Context
    private lateinit var testDir: File

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        testDir = File(context.cacheDir, "wipe_test_${System.currentTimeMillis()}")
        testDir.mkdirs()
    }

    @Test
    fun testSecureDeleteFile_physicallyOverwritesWithZeros() {
        val file = File(testDir, "test_file.bin")
        val size = 128 * 1024 // 128 KB (2 chunks)
        // Fill file with non-zero bytes (0xAA)
        FileOutputStream(file).use { out ->
            out.write(ByteArray(size) { 0xAA.toByte() })
        }

        // Keep an open read stream BEFORE wiping.
        // Under Linux, unlink() removes the directory entry, but the open fd
        // retains the allocated blocks so we can verify their contents.
        FileInputStream(file).use { keptOpenStream ->
            val success = SecureFileWipe.secureDeleteFile(file)
            assertTrue("secureDeleteFile should return true", success)
            assertFalse("File must be unlinked from disk", file.exists())

            // Verify every single byte was zeroed
            val buffer = ByteArray(size)
            var bytesRead = 0
            while (bytesRead < size) {
                val n = keptOpenStream.read(buffer, bytesRead, size - bytesRead)
                if (n == -1) break
                bytesRead += n
            }
            assertEquals("Should read all bytes from open descriptor", size, bytesRead)
            assertTrue("Every byte must be 0x00", buffer.all { it == 0.toByte() })
        }
    }

    @Test
    fun testSecureDeleteSafDocument_deletesAndZeros() {
        val file = File(testDir, "saf_file.bin")
        val size = 64 * 1024
        FileOutputStream(file).use { it.write(ByteArray(size) { 0x55.toByte() }) }

        val doc = DocumentFile.fromFile(file)
        assertTrue(doc.exists())

        FileInputStream(file).use { keptOpenStream ->
            val success = SecureFileWipe.secureDeleteSafDocument(context, doc)
            assertTrue("secureDeleteSafDocument should return true", success)
            assertFalse("File should be deleted", file.exists())
            assertFalse("DocumentFile should not exist", doc.exists())

            val buffer = ByteArray(size)
            keptOpenStream.read(buffer)
            assertTrue("Every byte must be 0x00", buffer.all { it == 0.toByte() })
        }
    }

    @Test
    fun testSecureDeleteSafTree_deletesNestedFolderHierarchy() {
        val subDir = File(testDir, "sub_folder").apply { mkdirs() }
        val file1 = File(testDir, "file1.txt").apply { writeText("Sample Content 1") }
        val file2 = File(subDir, "file2.txt").apply { writeText("Sample Content 2") }

        val docTree = DocumentFile.fromFile(testDir)
        assertTrue(docTree.isDirectory)

        val success = SecureFileWipe.secureDeleteSafTree(context, docTree)
        assertTrue("secureDeleteSafTree should return true", success)
        assertFalse("file1 should be deleted", file1.exists())
        assertFalse("file2 should be deleted", file2.exists())
        assertFalse("subDir should be deleted", subDir.exists())
        assertFalse("testDir should be deleted", testDir.exists())
    }

    @Test
    fun testSweepOrphanedFiles_wipesMatchingPrefixesOnly() {
        val orphan1 = File(testDir, "export_temp_1").apply { writeText("secret1") }
        val orphan2 = File(testDir, "thumb_temp_2").apply { writeText("secret2") }
        val keepFile = File(testDir, "valid_file.txt").apply { writeText("keep me") }

        val wipedCount = SecureFileWipe.sweepOrphanedFiles(testDir, listOf("export_", "thumb_"))

        assertEquals("Should wipe 2 matching files", 2, wipedCount)
        assertFalse(orphan1.exists())
        assertFalse(orphan2.exists())
        assertTrue("Non-matching file must remain", keepFile.exists())
    }
}