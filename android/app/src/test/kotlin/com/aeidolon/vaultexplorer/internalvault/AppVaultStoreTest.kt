package com.aeidolon.vaultexplorer.internalvault

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files

/**
 * The store decides what the app is willing to hand out as a vault location
 * and, above all, what [AppVaultStore.deleteTree] may remove. These tests pin
 * the containment rules (`..`, sibling directories sharing a prefix, symlinks
 * out of the folder) that stop a bad URI from deleting anything outside it.
 */
class AppVaultStoreTest {
    private lateinit var sandbox: File
    private lateinit var root: File
    private lateinit var store: AppVaultStore

    @Before
    fun setUp() {
        sandbox = Files.createTempDirectory("appvault-test").toFile()
        root = File(sandbox, "files/vaults")
        store = AppVaultStore(root)
        store.ensureRoot()
    }

    @After
    fun tearDown() {
        sandbox.deleteRecursively()
    }

    // ---- naming -----------------------------------------------------------------

    @Test
    fun sanitizeNameReplacesSeparatorsAndControlCharacters() {
        assertEquals("a_b_c", AppVaultStore.sanitizeName("a/b\\c"))
        assertEquals("a_b", AppVaultStore.sanitizeName("a\u0000b"))
        assertEquals("a_b_c_d", AppVaultStore.sanitizeName("a:b*c?d"))
    }

    @Test
    fun sanitizeNameNeverStartsWithADotOrMimicsStaging() {
        assertEquals("_.._evil.hc", AppVaultStore.sanitizeName("../../evil.hc"))
        assertFalse(AppVaultStore.sanitizeName("..").startsWith("."))
        assertFalse(AppVaultStore.sanitizeName(".part-abc").startsWith(AppVaultStore.STAGING_PREFIX))
        assertFalse(AppVaultStore.sanitizeName("...hidden").startsWith("."))
    }

    @Test
    fun sanitizeNameFallsBackWhenNothingUsableRemains() {
        assertEquals("vault", AppVaultStore.sanitizeName(""))
        assertEquals("vault", AppVaultStore.sanitizeName("   "))
        assertEquals("vault", AppVaultStore.sanitizeName("..."))
        assertEquals("vault", AppVaultStore.sanitizeName(null))
        assertEquals("mine", AppVaultStore.sanitizeName("", fallback = "mine"))
    }

    @Test
    fun sanitizeNameKeepsUnicodeAndLimitsUtf8Length() {
        assertEquals("Фото 日本語", AppVaultStore.sanitizeName("Фото 日本語"))
        val long = "日".repeat(200)
        val out = AppVaultStore.sanitizeName(long)
        assertTrue(out.toByteArray(StandardCharsets.UTF_8).size <= 120)
        assertTrue(out.isNotEmpty())
        // Never cuts a character in half.
        assertEquals(out, String(out.toByteArray(StandardCharsets.UTF_8), StandardCharsets.UTF_8))
        val emoji = "😀".repeat(100)
        assertTrue(AppVaultStore.sanitizeName(emoji).toByteArray(StandardCharsets.UTF_8).size <= 120)
    }

    @Test
    fun splitExtensionOnlyTreatsShortAlphanumericSuffixesAsExtensions() {
        assertEquals("vault" to ".hc", AppVaultStore.splitExtension("vault.hc"))
        assertEquals("my.vault" to ".hc", AppVaultStore.splitExtension("my.vault.hc"))
        assertEquals("vault" to "", AppVaultStore.splitExtension("vault"))
        assertEquals(".hidden" to "", AppVaultStore.splitExtension(".hidden"))
        assertEquals("trailing." to "", AppVaultStore.splitExtension("trailing."))
        assertEquals("a.not an ext" to "", AppVaultStore.splitExtension("a.not an ext"))
        assertEquals("a.waytoolongext" to "", AppVaultStore.splitExtension("a.waytoolongext"))
    }

    // ---- URIs -------------------------------------------------------------------

    @Test
    fun fileUriRoundTripsAwkwardNames() {
        val names = listOf(
            "plain.hc", "with space.hc", "paren (1).hc", "100%.hc", "hash#tag.hc",
            "q-and-a.hc", "Фото.hc", "日本語.hc", "emoji😀.hc", "a+b.hc",
        )
        for (n in names) {
            val file = File(root, n)
            val uri = AppVaultStore.fileUriString(file)
            assertTrue("starts with file:/// for $n", uri.startsWith("file:///"))
            assertFalse("no raw space in $uri", uri.contains(' '))
            assertEquals("round trip of $n", file.absolutePath, AppVaultStore.pathFromFileUri(uri))
        }
    }

    @Test
    fun pathFromFileUriRejectsAnythingThatIsNotALocalFileUri() {
        assertNull(AppVaultStore.pathFromFileUri("content://com.android.providers/tree/x"))
        assertNull(AppVaultStore.pathFromFileUri("/data/user/0/app/files/vaults/a.hc"))
        assertNull(AppVaultStore.pathFromFileUri("usb:/dev/bus/usb/001/002"))
        assertNull(AppVaultStore.pathFromFileUri("file://remote-host/share/a.hc"))
        assertNull(AppVaultStore.pathFromFileUri(""))
    }

    @Test
    fun pathFromFileUriKeepsMalformedPercentSequencesLiterally() {
        assertEquals("/a%zzb", AppVaultStore.pathFromFileUri("file:///a%zzb"))
        assertEquals("/a%", AppVaultStore.pathFromFileUri("file:///a%"))
        assertEquals("/a%4", AppVaultStore.pathFromFileUri("file:///a%4"))
        assertEquals("/a A", AppVaultStore.pathFromFileUri("file:///a%20%41"))
    }

    // ---- containment ------------------------------------------------------------

    @Test
    fun isInsideIsStrict() {
        assertTrue(store.isInside(File(root, "a.hc")))
        assertTrue(store.isInside(File(root, "dir/sub/file")))
        assertFalse("the root itself is not a vault", store.isInside(root))
        assertFalse(store.isInside(File(sandbox, "files")))
        assertFalse(store.isInside(File(sandbox, "elsewhere/a.hc")))
    }

    @Test
    fun isInsideRejectsDotDotEscapes() {
        assertFalse(store.isInside(File(root, "../outside.hc")))
        assertFalse(store.isInside(File(root, "a/../../outside.hc")))
        assertTrue("a path that goes up and back down is still inside", store.isInside(File(root, "a/../b.hc")))
    }

    @Test
    fun isInsideRejectsSiblingDirectoryThatSharesThePrefix() {
        val sibling = File(sandbox, "files/vaults2")
        sibling.mkdirs()
        assertFalse(store.isInside(File(sibling, "a.hc")))
        assertFalse(store.isInside(File(sandbox, "files/vaults-evil/a.hc")))
    }

    @Test
    fun isInsideRejectsASymlinkThatPointsOutside() {
        val outside = File(sandbox, "outside").apply { mkdirs() }
        File(outside, "precious.txt").writeText("keep me")
        val link = File(root, "sneaky")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        assertFalse(store.isInside(link))
        assertFalse(store.isInside(File(link, "precious.txt")))
    }

    @Test
    fun resolveUriOnlyAcceptsFileUrisInsideTheRoot() {
        val ok = AppVaultStore.fileUriString(File(root, "My vault.hc"))
        assertEquals(File(root, "My vault.hc").absolutePath, store.resolveUri(ok)?.absolutePath)
        assertNull(store.resolveUri(AppVaultStore.fileUriString(root)))
        assertNull(store.resolveUri(AppVaultStore.fileUriString(File(sandbox, "other/x.hc"))))
        assertNull(store.resolveUri("file://" + root.absolutePath + "/../escape.hc"))
        assertNull(store.resolveUri("content://x/y"))
    }

    // ---- reserving and publishing -----------------------------------------------

    @Test
    fun reserveContainerFileMakesNamesUniqueAndKeepsTheExtension() {
        val a = store.reserveContainerFile("vault.hc")
        val b = store.reserveContainerFile("vault.hc")
        val c = store.reserveContainerFile("vault.hc")
        assertEquals("vault.hc", a.name)
        assertEquals("vault (1).hc", b.name)
        assertEquals("vault (2).hc", c.name)
        assertTrue(a.isFile && b.isFile && c.isFile)
        assertEquals(0L, a.length())
    }

    @Test
    fun reserveContainerFileCannotBeSteeredOutsideTheRoot() {
        val f = store.reserveContainerFile("../../evil.hc")
        assertTrue(store.isInside(f))
        assertEquals(root.canonicalFile, f.canonicalFile.parentFile)
        val g = store.reserveContainerFile("a/b/c.hc")
        assertEquals(root.canonicalFile, g.canonicalFile.parentFile)
    }

    @Test
    fun reserveFolderVaultDirMakesNamesUnique() {
        val a = store.reserveFolderVaultDir("Notes")
        val b = store.reserveFolderVaultDir("Notes")
        assertEquals("Notes", a.name)
        assertEquals("Notes (1)", b.name)
        assertTrue(a.isDirectory && b.isDirectory)
    }

    @Test
    fun publishMovesAStagedFileOntoItsReservedName() {
        val reserved = store.reserveContainerFile("v.hc")
        val staging = store.newStagingPath()
        staging.writeBytes(byteArrayOf(1, 2, 3))
        store.publish(staging, reserved)
        assertFalse(staging.exists())
        assertEquals(listOf<Byte>(1, 2, 3), reserved.readBytes().toList())
    }

    @Test
    fun publishMovesAStagedFolderOntoItsReservedEmptyDirectory() {
        val reserved = store.reserveFolderVaultDir("vault")
        val staging = store.newStagingPath().also { it.mkdir() }
        File(staging, "gocryptfs.conf").writeText("cfg")
        File(staging, "sub").mkdir()
        File(staging, "sub/x").writeText("x")
        store.publish(staging, reserved)
        assertFalse(staging.exists())
        assertEquals("cfg", File(reserved, "gocryptfs.conf").readText())
        assertEquals("x", File(reserved, "sub/x").readText())
    }

    @Test
    fun publishRefusesPathsOutsideTheRoot() {
        val outside = File(sandbox, "outside.hc").apply { writeText("x") }
        val reserved = store.reserveContainerFile("v.hc")
        var threw = false
        try {
            store.publish(outside, reserved)
        } catch (_: IllegalArgumentException) {
            threw = true
        }
        assertTrue(threw)
        assertTrue(outside.exists())
    }

    // ---- staging ----------------------------------------------------------------

    @Test
    fun stagingEntriesAreHiddenFromTheListAndSweptAway() {
        val vault = store.reserveContainerFile("real.hc")
        val s1 = store.newStagingPath().apply { writeText("partial") }
        val s2 = store.newStagingPath().also { it.mkdir() }
        File(s2, "deep").mkdir()
        File(s2, "deep/f").writeText("partial")
        assertEquals(listOf("real.hc"), store.list().map { it.file.name })
        assertEquals(2, store.sweepStaging())
        assertFalse(s1.exists())
        assertFalse(s2.exists())
        assertTrue("a registered vault is never swept", vault.exists())
    }

    @Test
    fun newStagingPathsAreDistinctAndInsideTheRoot() {
        val a = store.newStagingPath()
        val b = store.newStagingPath()
        assertTrue(a.name != b.name)
        assertTrue(a.name.startsWith(AppVaultStore.STAGING_PREFIX))
        assertTrue(store.isInside(a))
    }

    @Test
    fun sweepReservationsRemovesOnlyNamesThatWereNeverFilled() {
        val emptyFile = store.reserveContainerFile("abandoned.hc")           // 0 bytes: reserved, never published
        val emptyDir = store.reserveFolderVaultDir("abandoned-folder")        // empty: reserved, never published
        val realFile = store.reserveContainerFile("real.hc").apply { writeBytes(ByteArray(4096)) }
        val realDir = store.reserveFolderVaultDir("real-folder").also { File(it, "gocryptfs.conf").writeText("cfg") }
        assertEquals(2, store.sweepReservations())
        assertFalse(emptyFile.exists())
        assertFalse(emptyDir.exists())
        assertTrue(realFile.exists())
        assertTrue(File(realDir, "gocryptfs.conf").exists())
    }

    @Test
    fun sweepReservationsLeavesStagingAndSymlinksAlone() {
        val staging = store.newStagingPath().also { it.mkdir() }
        val outside = File(sandbox, "outside").apply { mkdirs() }
        val link = File(root, "link-to-empty-dir")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        assertEquals(0, store.sweepReservations())
        assertTrue(staging.exists())
        assertTrue(Files.isSymbolicLink(link.toPath()))
        assertTrue(outside.exists())
    }

    // ---- deletion ---------------------------------------------------------------

    @Test
    fun deleteTreeRemovesANestedVault() {
        val dir = store.reserveFolderVaultDir("v")
        File(dir, "a/b").mkdirs()
        File(dir, "a/b/c").writeText("c")
        File(dir, "top").writeText("t")
        assertTrue(store.deleteTree(dir))
        assertFalse(dir.exists())
    }

    @Test
    fun deleteTreeOfAMissingPathIsSuccess() {
        assertTrue(store.deleteTree(File(root, "never-existed")))
    }

    @Test
    fun deleteTreeRefusesTheRootAndAnythingOutsideIt() {
        val keep = File(sandbox, "files/keep.txt").apply { writeText("keep") }
        val inside = store.reserveContainerFile("v.hc")
        assertFalse(store.deleteTree(root))
        assertFalse(store.deleteTree(File(sandbox, "files")))
        assertFalse(store.deleteTree(keep))
        assertFalse(store.deleteTree(File(root, "../keep.txt")))
        assertTrue(root.exists() && keep.exists() && inside.exists())
    }

    @Test
    fun deleteTreeDoesNotFollowASymlinkOutOfTheFolder() {
        val outside = File(sandbox, "outside").apply { mkdirs() }
        val precious = File(outside, "precious.txt").apply { writeText("keep me") }
        val dir = store.reserveFolderVaultDir("v")
        File(dir, "real").writeText("r")
        Files.createSymbolicLink(File(dir, "link").toPath(), outside.toPath())
        assertTrue(store.deleteTree(dir))
        assertFalse(dir.exists())
        assertTrue("target of the link must survive", precious.exists())
        assertEquals("keep me", precious.readText())
    }

    // ---- listing and sizes ------------------------------------------------------

    @Test
    fun listReportsKindsAndSizesSortedByName() {
        store.reserveContainerFile("b.hc").writeBytes(ByteArray(10))
        val dir = store.reserveFolderVaultDir("A folder")
        File(dir, "x").writeBytes(ByteArray(5))
        File(dir, "n").mkdir()
        File(dir, "n/y").writeBytes(ByteArray(7))
        val entries = store.list()
        assertEquals(listOf("A folder", "b.hc"), entries.map { it.file.name })
        assertTrue(entries[0].isDirectory)
        assertEquals(12L, entries[0].sizeBytes)
        assertFalse(entries[1].isDirectory)
        assertEquals(10L, entries[1].sizeBytes)
    }

    @Test
    fun availableBytesIsPositiveAndEnsureRootCreatesTheFolder() {
        val fresh = AppVaultStore(File(sandbox, "brand/new/vaults"))
        assertFalse(fresh.root.exists())
        assertNotNull(fresh.ensureRoot())
        assertTrue(fresh.root.isDirectory)
        assertTrue(fresh.availableBytes() > 0)
    }
}
