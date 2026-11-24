package com.aeidolon.vaultexplorer.internalvault

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import java.util.Random

/**
 * [TreeCopier] is what makes it safe to delete the original after a vault
 * move: a "verified" copy must really be byte-identical, and any difference
 * (a flipped byte, a missing or extra entry, a provider that renamed a file)
 * must surface as [RelocationVerifyException] rather than pass silently.
 */
class TreeCopierTest {
    private lateinit var sandbox: File
    private lateinit var src: File
    private lateinit var dst: File

    @Before
    fun setUp() {
        sandbox = Files.createTempDirectory("treecopier-test").toFile()
        src = File(sandbox, "src").apply { mkdirs() }
        dst = File(sandbox, "dst").apply { mkdirs() }
    }

    @After
    fun tearDown() {
        sandbox.deleteRecursively()
    }

    private fun randomBytes(n: Int, seed: Long = 7L) = ByteArray(n).also { Random(seed).nextBytes(it) }

    private fun buildVaultTree(): Map<String, ByteArray> {
        val files = linkedMapOf(
            "gocryptfs.conf" to randomBytes(300, 1),
            "gocryptfs.diriv" to randomBytes(16, 2),
            "ab/cdef0123" to randomBytes(32 * 1024, 3),
            "ab/9999" to randomBytes(5, 4),
            "ff/deep/er/block" to randomBytes(700_001, 5),
            "empty.bin" to ByteArray(0),
            "ünï cödé name (1).txt" to randomBytes(10, 6),
        )
        for ((rel, bytes) in files) {
            val f = File(src, rel)
            f.parentFile.mkdirs()
            f.writeBytes(bytes)
        }
        File(src, "emptydir/nested").mkdirs()
        return files
    }

    // ---- single file ------------------------------------------------------------

    @Test
    fun copyFileProducesAnIdenticalVerifiedFile() {
        val bytes = randomBytes(1_000_003)
        val s = File(sandbox, "in.hc").apply { writeBytes(bytes) }
        val d = File(sandbox, "out.hc")
        val copier = TreeCopier(bufferSize = 4096)
        val fp = d.outputStream().use { copier.copyFile(LocalNode(s), it) }
        assertEquals(bytes.size.toLong(), fp.size)
        assertEquals(64, fp.sha256.length)
        assertTrue(bytes.contentEquals(d.readBytes()))
        copier.verifyFile(LocalNode(d), fp)   // must not throw
    }

    @Test
    fun verifyFileDetectsASingleFlippedByte() {
        val bytes = randomBytes(50_000)
        val s = File(sandbox, "in.hc").apply { writeBytes(bytes) }
        val d = File(sandbox, "out.hc")
        val copier = TreeCopier(bufferSize = 1024)
        val fp = d.outputStream().use { copier.copyFile(LocalNode(s), it) }
        val corrupted = d.readBytes().also { it[25_000] = (it[25_000].toInt() xor 0x01).toByte() }
        d.writeBytes(corrupted)
        assertThrows(RelocationVerifyException::class.java) { copier.verifyFile(LocalNode(d), fp) }
    }

    @Test
    fun verifyFileDetectsATruncatedCopy() {
        val s = File(sandbox, "in.hc").apply { writeBytes(randomBytes(10_000)) }
        val d = File(sandbox, "out.hc")
        val copier = TreeCopier()
        val fp = d.outputStream().use { copier.copyFile(LocalNode(s), it) }
        d.writeBytes(d.readBytes().copyOf(9_999))
        assertThrows(RelocationVerifyException::class.java) { copier.verifyFile(LocalNode(d), fp) }
    }

    @Test
    fun copyingAnEmptyFileVerifies() {
        val s = File(sandbox, "empty").apply { writeBytes(ByteArray(0)) }
        val d = File(sandbox, "empty-out")
        val copier = TreeCopier()
        val fp = d.outputStream().use { copier.copyFile(LocalNode(s), it) }
        assertEquals(0L, fp.size)
        copier.verifyFile(LocalNode(d), fp)
    }

    // ---- trees ------------------------------------------------------------------

    @Test
    fun copyTreeThenVerifyTreePassesForAnIdenticalCopy() {
        val expected = buildVaultTree()
        val copier = TreeCopier(bufferSize = 8192)
        val manifest = copier.copyTree(LocalNode(src), LocalWritableDir(dst))
        assertEquals(expected.keys, manifest.files.keys)
        assertTrue(manifest.directories.containsAll(listOf("ab", "ff", "ff/deep", "ff/deep/er", "emptydir", "emptydir/nested")))
        assertEquals(expected.values.sumOf { it.size }.toLong(), manifest.totalBytes)
        for ((rel, bytes) in expected) assertTrue(rel, bytes.contentEquals(File(dst, rel).readBytes()))
        assertTrue(File(dst, "emptydir/nested").isDirectory)
        copier.verifyTree(LocalWritableDir(dst), manifest)   // must not throw
    }

    @Test
    fun verifyTreeDetectsAChangedFile() {
        buildVaultTree()
        val copier = TreeCopier()
        val manifest = copier.copyTree(LocalNode(src), LocalWritableDir(dst))
        val target = File(dst, "ab/cdef0123")
        target.writeBytes(target.readBytes().also { it[100] = (it[100].toInt() xor 0xff).toByte() })
        val e = assertThrows(RelocationVerifyException::class.java) { copier.verifyTree(LocalWritableDir(dst), manifest) }
        assertTrue(e.message!!.contains("ab/cdef0123"))
    }

    @Test
    fun verifyTreeDetectsAMissingFile() {
        buildVaultTree()
        val copier = TreeCopier()
        val manifest = copier.copyTree(LocalNode(src), LocalWritableDir(dst))
        assertTrue(File(dst, "gocryptfs.diriv").delete())
        val e = assertThrows(RelocationVerifyException::class.java) { copier.verifyTree(LocalWritableDir(dst), manifest) }
        assertTrue(e.message!!.contains("gocryptfs.diriv"))
    }

    @Test
    fun verifyTreeDetectsAnExtraFileSuchAsAProviderRenamedDuplicate() {
        buildVaultTree()
        val copier = TreeCopier()
        val manifest = copier.copyTree(LocalNode(src), LocalWritableDir(dst))
        File(dst, "gocryptfs (1).conf").writeText("dup")
        val e = assertThrows(RelocationVerifyException::class.java) { copier.verifyTree(LocalWritableDir(dst), manifest) }
        assertTrue(e.message!!.contains("gocryptfs (1).conf"))
    }

    @Test
    fun verifyTreeDetectsAMissingAndAnExtraFolder() {
        buildVaultTree()
        val copier = TreeCopier()
        val manifest = copier.copyTree(LocalNode(src), LocalWritableDir(dst))
        File(dst, "emptydir/nested").delete()
        assertThrows(RelocationVerifyException::class.java) { copier.verifyTree(LocalWritableDir(dst), manifest) }
        File(dst, "emptydir/nested").mkdir()
        File(dst, "surprise").mkdir()
        assertThrows(RelocationVerifyException::class.java) { copier.verifyTree(LocalWritableDir(dst), manifest) }
    }

    @Test
    fun symlinksInTheSourceAreNeitherFollowedNorCopied() {
        buildVaultTree()
        val outside = File(sandbox, "outside").apply { mkdirs() }
        File(outside, "secret.txt").writeText("not part of the vault")
        Files.createSymbolicLink(File(src, "escape").toPath(), outside.toPath())
        Files.createSymbolicLink(File(src, "filelink").toPath(), File(outside, "secret.txt").toPath())
        val manifest = TreeCopier().copyTree(LocalNode(src), LocalWritableDir(dst))
        assertFalse(File(dst, "escape").exists())
        assertFalse(File(dst, "filelink").exists())
        assertFalse(manifest.files.keys.any { it.contains("secret") || it.startsWith("escape") || it == "filelink" })
    }

    @Test
    fun measureCountsBytesAndFiles() {
        val expected = buildVaultTree()
        val (bytes, files) = TreeCopier().measure(LocalNode(src))
        assertEquals(expected.values.sumOf { it.size }.toLong(), bytes)
        assertEquals(expected.size.toLong(), files)
        val single = File(sandbox, "one").apply { writeBytes(ByteArray(42)) }
        assertEquals(42L to 1L, TreeCopier().measure(LocalNode(single)))
    }

    // ---- progress and cancellation ----------------------------------------------

    @Test
    fun copyAndVerifyEachReportEveryByteOnce() {
        val expected = buildVaultTree()
        val total = expected.values.sumOf { it.size }.toLong()
        var seen = 0L
        val copier = TreeCopier(onBytes = { seen += it }, bufferSize = 4096)
        val manifest = copier.copyTree(LocalNode(src), LocalWritableDir(dst))
        assertEquals(total, seen)
        copier.verifyTree(LocalWritableDir(dst), manifest)
        assertEquals(2 * total, seen)
    }

    @Test
    fun cancellationDuringCopyStopsPromptly() {
        File(src, "big").writeBytes(randomBytes(2_000_000))
        File(src, "later").writeBytes(randomBytes(10))
        var calls = 0
        val copier = TreeCopier(isCancelled = { ++calls > 3 }, bufferSize = 1024)
        assertThrows(RelocationCancelledException::class.java) {
            copier.copyTree(LocalNode(src), LocalWritableDir(dst))
        }
        assertFalse("must stop long before the copy would finish", File(dst, "big").length() >= 2_000_000)
        assertFalse(File(dst, "later").exists())
    }

    @Test
    fun cancellationDuringVerifyIsReportedAsCancelledNotAsMismatch() {
        buildVaultTree()
        val manifest = TreeCopier().copyTree(LocalNode(src), LocalWritableDir(dst))
        var cancelNow = false
        val copier = TreeCopier(isCancelled = { cancelNow }, onBytes = { cancelNow = true })
        assertThrows(RelocationCancelledException::class.java) {
            copier.verifyTree(LocalWritableDir(dst), manifest)
        }
    }

    // ---- hostile or odd providers -----------------------------------------------

    private class MemNode(
        override val name: String,
        private val bytes: ByteArray?,
        private val kids: List<MemNode> = emptyList(),
        private val reportedLength: Long = bytes?.size?.toLong() ?: -1L,
    ) : VaultNode {
        override val isDirectory: Boolean get() = bytes == null
        override val length: Long get() = reportedLength
        override fun children(): List<VaultNode> = kids
        override fun openRead(): InputStream = ByteArrayInputStream(bytes ?: throw IOException("dir"))
    }

    private class MemDir : WritableDir {
        val files = LinkedHashMap<String, ByteArray>()
        val dirs = LinkedHashMap<String, MemDir>()
        override val name = "mem"
        override val isDirectory = true
        override val length = -1L
        override fun children(): List<VaultNode> =
            dirs.map { (n, d) -> MemNode(n, null, d.children().map { it as MemNode }) } +
                files.map { (n, b) -> MemNode(n, b) }
        override fun openRead(): InputStream = throw IOException("dir")
        override fun makeDir(name: String): WritableDir = MemDir().also { dirs[name] = it }
        override fun makeFile(name: String): OutputStream = object : ByteArrayOutputStream() {
            override fun close() {
                files[name] = toByteArray()
            }
        }
    }

    @Test
    fun entriesWithPathTraversalNamesAreRefused() {
        for (bad in listOf("..", ".", "", "a/b", "..\u0000x")) {
            val root = MemNode("root", null, listOf(MemNode(bad, byteArrayOf(1))))
            val e = assertThrows(IOException::class.java) { TreeCopier().copyTree(root, MemDir()) }
            assertTrue("name [$bad]: ${e.message}", e.message!!.contains("unsafe name"))
        }
    }

    @Test
    fun aProviderThatDoesNotReportLengthStillCopiesAndVerifies() {
        val data = randomBytes(5000)
        val root = MemNode("root", null, listOf(MemNode("f", data, reportedLength = -1L)))
        val out = MemDir()
        val copier = TreeCopier()
        val (bytes, files) = copier.measure(root)
        assertEquals(0L, bytes)   // unknown counts as 0; progress is clamped by the caller
        assertEquals(1L, files)
        val manifest = copier.copyTree(root, out)
        assertEquals(5000L, manifest.files.getValue("f").size)
        copier.verifyTree(out, manifest)
        assertTrue(data.contentEquals(out.files.getValue("f")))
    }

    @Test
    fun aSourceThatEndsEarlierThanItsReportedLengthIsRefused() {
        // The provider says 5000 bytes but hands back only 3000 before EOF: both hashes would agree
        // with each other, so only the length check stops a truncated vault being "verified".
        val root = MemNode("root", null, listOf(MemNode("f", randomBytes(3000), reportedLength = 5000L)))
        val e = assertThrows(RelocationVerifyException::class.java) { TreeCopier().copyTree(root, MemDir()) }
        assertTrue(e.message!!.contains("3000 of 5000"))
    }

    @Test
    fun aReportedLengthOfZeroIsTreatedAsUnknownNotAsTruncation() {
        val data = randomBytes(2000)
        val root = MemNode("root", null, listOf(MemNode("f", data, reportedLength = 0L)))
        val out = MemDir()
        val copier = TreeCopier()
        val manifest = copier.copyTree(root, out)
        copier.verifyTree(out, manifest)
        assertTrue(data.contentEquals(out.files.getValue("f")))
    }

    @Test
    fun aDestinationThatSilentlyLosesBytesIsCaught() {
        val data = randomBytes(5000)
        val root = MemNode("root", null, listOf(MemNode("f", data)))
        val out = MemDir()
        val copier = TreeCopier()
        val manifest = copier.copyTree(root, out)
        out.files["f"] = out.files.getValue("f").copyOf(4000)
        assertThrows(RelocationVerifyException::class.java) { copier.verifyTree(out, manifest) }
    }

    // ---- local writer -----------------------------------------------------------

    @Test
    fun localWritableDirRefusesToOverwriteAnExistingEntry() {
        File(dst, "taken").writeText("x")
        val w = LocalWritableDir(dst)
        assertThrows(IOException::class.java) { w.makeFile("taken") }
        assertThrows(IOException::class.java) { w.makeDir("taken") }
        assertEquals("x", File(dst, "taken").readText())
    }
}
