package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.security.SecureRandom

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class CryptomatorResilienceTest {

    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val random = SecureRandom()
    private lateinit var vaultDir: File
    private lateinit var masterkey: CryptomatorMasterkey
    private lateinit var session: CryptomatorSession

    @Before
    fun setUp() {
        vaultDir = File(context.filesDir, "test_vault_${System.nanoTime()}").apply { mkdirs() }
        File(vaultDir, "d").mkdirs()

        masterkey = CryptomatorMasterkey.generate(random)
        session = CryptomatorSession(
            context = context,
            vaultRootUri = Uri.fromFile(vaultDir),
            masterkey = masterkey,
            vaultFormat = 8,
            cipherCombo = "SIV_GCM",
            shorteningThreshold = 220,
            readOnly = false,
        )
    }

    @After
    fun tearDown() {
        session.close()
        vaultDir.deleteRecursively()
    }

    @Test
    fun testDiridCreationAndListingFiltering() {
        val created = session.createDirectory("/TestDir")
        assertTrue("createDirectory should succeed", created)

        val rootEntries = session.listDirectory("")
        assertNotNull("Root listing should not be null", rootEntries)
        assertEquals("Root should have exactly 1 entry", 1, rootEntries!!.size)
        assertTrue("Root entry should be directory TestDir", rootEntries[0].contains("TestDir"))

        val dirEntries = session.listDirectory("/TestDir")
        assertNotNull("TestDir listing should not be null", dirEntries)
        assertEquals("TestDir should appear empty (dirid.c9r hidden)", 0, dirEntries!!.size)

        val testDirId = session.tree.resolveDirId("/TestDir")
        val hash = session.nameCryptor.hashDirectoryId(testDirId)
        val lvl1 = hash.substring(0, 2)
        val lvl2 = hash.substring(2)
        val physicalDir = File(File(vaultDir, "d/$lvl1"), lvl2)
        assertTrue("Physical directory d/$lvl1/$lvl2 should exist", physicalDir.exists())

        val diridFile = File(physicalDir, "dirid.c9r")
        assertTrue("dirid.c9r backup file should exist inside backing folder", diridFile.exists())

        val bytes = diridFile.readBytes()
        val header = session.contentCryptor.decryptHeader(bytes.copyOfRange(0, session.contentCryptor.headerSize), masterkey)
        val chunk = bytes.copyOfRange(session.contentCryptor.headerSize, bytes.size)
        val cleartext = session.contentCryptor.decryptChunk(chunk, 0L, header, masterkey)
        val parentDirId = String(cleartext, Charsets.UTF_8)
        assertEquals("dirid.c9r should contain parent dirId (root = empty string)", "", parentDirId)

        val subCreated = session.createDirectory("/TestDir/SubDir")
        assertTrue("Subfolder creation should succeed", subCreated)
        val subDirId = session.tree.resolveDirId("/TestDir/SubDir")
        val subHash = session.nameCryptor.hashDirectoryId(subDirId)
        val subPhysicalDir = File(File(vaultDir, "d/${subHash.substring(0, 2)}"), subHash.substring(2))
        val subDiridFile = File(subPhysicalDir, "dirid.c9r")
        assertTrue("subfolder dirid.c9r should exist", subDiridFile.exists())

        val subBytes = subDiridFile.readBytes()
        val subHeader = session.contentCryptor.decryptHeader(subBytes.copyOfRange(0, session.contentCryptor.headerSize), masterkey)
        val subChunk = subBytes.copyOfRange(session.contentCryptor.headerSize, subBytes.size)
        val subCleartext = session.contentCryptor.decryptChunk(subChunk, 0L, subHeader, masterkey)
        assertEquals("subfolder dirid.c9r should contain TestDir's dirId", testDirId, String(subCleartext, Charsets.UTF_8))
    }

    @Test
    fun testListingHollowDirectoryAutoHeals() {
        session.createDirectory("/ExternalDeleteDir")
        val dirId = session.tree.resolveDirId("/ExternalDeleteDir")
        val hash = session.nameCryptor.hashDirectoryId(dirId)
        val physicalDir = File(File(vaultDir, "d/${hash.substring(0, 2)}"), hash.substring(2))
        assertTrue(physicalDir.exists())

        physicalDir.deleteRecursively()
        assertTrue(!physicalDir.exists())

        session.tree.invalidateAll()

        val entries = session.listDirectory("/ExternalDeleteDir")
        assertNotNull("Listing should not be null", entries)
        assertEquals("Deleted backing folder should list as empty", 0, entries!!.size)

        assertTrue("Backing directory should be auto-recreated on list", physicalDir.exists())
    }

    @Test
    fun testWritingToHollowDirectoryAutoHeals() {
        session.createDirectory("/WritableDir")
        val dirId = session.tree.resolveDirId("/WritableDir")
        val hash = session.nameCryptor.hashDirectoryId(dirId)
        val physicalDir = File(File(vaultDir, "d/${hash.substring(0, 2)}"), hash.substring(2))
        assertTrue(physicalDir.exists())

        physicalDir.deleteRecursively()
        assertTrue(!physicalDir.exists())

        session.tree.invalidateAll()

        val fileContent = "Hello from resilient Cryptomator!".toByteArray(Charsets.UTF_8)
        val wroteChunk = session.writeFileChunk("/WritableDir/hello.txt", 0L, fileContent)
        assertTrue("Writing file chunk into hollow folder should succeed", wroteChunk)
        val finished = session.finishWrite("/WritableDir/hello.txt")
        assertTrue("finishWrite should succeed", finished)

        val readBack = session.readFileChunk("/WritableDir/hello.txt", 0L, fileContent.size)
        assertNotNull("File content should be readable", readBack)
        assertEquals("File content should match", String(fileContent), String(readBack!!))

        val diridFile = File(physicalDir, "dirid.c9r")
        assertTrue("dirid.c9r should be auto-recreated when writing", diridFile.exists())
    }

    @Test
    fun testDeletingGhostDirectorySucceeds() {
        session.createDirectory("/GhostDir")
        val dirId = session.tree.resolveDirId("/GhostDir")
        val hash = session.nameCryptor.hashDirectoryId(dirId)
        val physicalDir = File(File(vaultDir, "d/${hash.substring(0, 2)}"), hash.substring(2))
        assertTrue(physicalDir.exists())

        physicalDir.deleteRecursively()
        assertTrue(!physicalDir.exists())

        session.tree.invalidateAll()

        val deleted = session.deleteFile("/GhostDir")
        assertTrue("deleteFile should succeed even when backing storage was deleted", deleted)

        val rootEntries = session.listDirectory("")
        assertNotNull(rootEntries)
        assertEquals("GhostDir should be completely deleted from root", 0, rootEntries!!.size)
    }

    @Test
    fun testDeletingFolderWithCorruptedPointerSucceeds() {
        session.createDirectory("/BrokenPointerDir")
        val node = session.tree.resolve("/BrokenPointerDir") as VaultNode.VDir

        val realPointer = File(node.physicalFolder.uri.path!!, "dir.c9r")
        if (realPointer.exists()) {
            realPointer.writeBytes(ByteArray(0))
        }

        session.tree.invalidateAll()

        val deleted = session.deleteFile("/BrokenPointerDir")
        assertTrue("deleteFile should succeed for broken dir.c9r pointer", deleted)

        val rootEntries = session.listDirectory("")
        assertNotNull(rootEntries)
        assertEquals("Broken pointer folder should be removed from listing", 0, rootEntries!!.size)
    }
}
