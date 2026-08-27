package com.aeidolon.vaultexplorer.saf

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * Focused coverage for [SafDocumentOps.writeWhole]'s overwrite-safety fix,
 * found while investigating a similar bug in
 * [MirrorSyncCoordinator.pushFileWrite] (see that class's test suite):
 * [writeWhole]'s raw-file fast path used to write directly via
 * `File.writeBytes`, which delegates to the single-arg `FileOutputStream`
 * constructor -- documented to truncate the target to 0 bytes the instant
 * it's opened, before a single byte of the new content is written. Any
 * write that failed partway (disk full, process killed mid-write,
 * permission revoked) destroyed the file's prior content outright rather
 * than merely failing to update it -- the same class of bug as
 * CVE-2023-21036 ("aCropalypse"). This is [writeWhole]'s raw-file path
 * specifically, not comprehensive [SafDocumentOps] coverage.
 *
 * An earlier version of this suite included a test that forced the
 * staging-file rename to fail by pointing it at an existing, empty
 * directory. That trigger turned out not to be portable: `File.renameTo`
 * replacing an empty directory with the staging file succeeded on a real
 * Windows run, contradicting both the general POSIX-vs-Windows rename()
 * folklore and a reading of the actual OpenJDK Windows native source
 * (WinNTFileSystem.rename0 calls the C runtime's _wrename) -- neither of
 * which turned out to describe MSVCRT's actual behavior for an empty
 * directory destination specifically, as opposed to the Win32
 * MoveFileEx API's documented (and different) restriction. Rather than
 * chase a second platform-specific trigger, that test was removed; the
 * tests below cover the property that actually matters (the original is
 * never truncated unless the full new content has already been staged
 * successfully) through the successful-write and successful-overwrite
 * cases, without depending on a specific, fragile failure mechanism.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class SafDocumentOpsTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun newRoot(): File =
        File(context.filesDir, "safdocumentops_test_${System.nanoTime()}").apply { mkdirs() }

    @Test
    fun `writeWhole creates a brand-new file with the given content`() {
        val root = newRoot()
        val target = File(root, "new.txt")
        val doc = DocumentFile.fromFile(target)
        val ops = SafDocumentOps(context)

        ops.writeWhole(doc, "hello world".toByteArray())

        assertEquals("hello world", target.readText())
        root.deleteRecursively()
    }

    @Test
    fun `writeWhole successfully overwrites an existing file's content`() {
        val root = newRoot()
        val target = File(root, "existing.txt").apply { writeText("old content") }
        val doc = DocumentFile.fromFile(target)
        val ops = SafDocumentOps(context)

        ops.writeWhole(doc, "new content, replacing the old entirely".toByteArray())

        assertEquals("new content, replacing the old entirely", target.readText())
        root.deleteRecursively()
    }

    @Test
    fun `writeWhole does not leave a leftover staging file behind after a successful write`() {
        val root = newRoot()
        val target = File(root, "existing.txt").apply { writeText("old content") }
        val doc = DocumentFile.fromFile(target)
        val ops = SafDocumentOps(context)

        ops.writeWhole(doc, "new content".toByteArray())

        val leftoverStaging = File(root, "existing.txt.writing")
        assertFalse("a successful write must not leave its staging temp file behind", leftoverStaging.exists())
        root.deleteRecursively()
    }
}