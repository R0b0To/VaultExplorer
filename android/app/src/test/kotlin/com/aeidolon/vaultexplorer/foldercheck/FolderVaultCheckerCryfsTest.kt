package com.aeidolon.vaultexplorer.foldercheck

import androidx.documentfile.provider.DocumentFile
import androidx.test.core.app.ApplicationProvider
import com.aeidolon.vaultexplorer.crypto.LittleEndian
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * CryFS counterpart to FolderVaultCheckerGocryptfsTest -- see that file's
 * header for why these call the `internal` checkCryfs directly rather than
 * the public check() entry point.
 *
 * cryfs.config is a binary envelope, not JSON (see CryfsConfigFile's doc
 * comments): a null-terminated header string, an 8-byte little-endian
 * envelope length, then the KDF params (8-byte scryptN, 4-byte scryptR,
 * 4-byte scryptP, then a salt of whatever length fills the declared
 * envelope length), then the still-encrypted inner config. checkStructure
 * (what the no-password path in checkCryfs calls) only validates this outer
 * envelope -- the encrypted inner payload's bytes are never inspected on
 * this path, so the fixture below fills that part with zeros.
 *
 * Only the no-password branch is covered here, same scope limitation as the
 * gocryptfs and Cryptomator counterparts -- the password-verified path
 * (scrypt-derived key, decrypting the inner config, walking the actual
 * CryfsDataTree blob graph) needs real derived key material and is left for
 * a follow-up.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class FolderVaultCheckerCryfsTest {

    private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    private val createdDirs = mutableListOf<File>()

    private fun newFolder(name: String): File {
        val dir = File(context.filesDir, "${name}_${System.nanoTime()}").apply { mkdirs() }
        createdDirs += dir
        return dir
    }

    @After
    fun tearDown() {
        createdDirs.forEach { it.deleteRecursively() }
    }

    /** A structurally valid cryfs.config outer envelope. Only the envelope
     *  (header string + KDF param block bounds) is validated by
     *  checkStructure -- the "encrypted inner config" bytes are opaque to it,
     *  so they're zero-filled here rather than real ciphertext. */
    private fun writeValidConfigEnvelope(dir: File) {
        val header = "cryfs.config;1;scrypt".toByteArray(Charsets.UTF_8) + byteArrayOf(0)

        val salt = ByteArray(8) { it.toByte() }
        val kdfParams = ByteArray(16 + salt.size)
        LittleEndian.writeU64(kdfParams, 0, 32768L) // scryptN
        LittleEndian.writeU32(kdfParams, 8, 8L) // scryptR
        LittleEndian.writeU32(kdfParams, 12, 1L) // scryptP
        System.arraycopy(salt, 0, kdfParams, 16, salt.size)

        val kdfParamsLenBytes = ByteArray(8)
        LittleEndian.writeU64(kdfParamsLenBytes, 0, kdfParams.size.toLong())

        val encryptedInnerConfig = ByteArray(32) // opaque to checkStructure

        File(dir, "cryfs.config").writeBytes(header + kdfParamsLenBytes + kdfParams + encryptedInnerConfig)
    }

    /** One on-disk block matching CryFS's shard/block naming convention:
     *  a 3-hex-char shard directory containing a 29-hex-char block file. */
    private fun writeOneBlock(root: File) {
        val shard = File(root, "0af").apply { mkdirs() }
        File(shard, "a".repeat(29)).writeBytes(ByteArray(0))
    }

    @Test
    fun `checkCryfs scans on-disk blocks and reports no issues with no password given`() {
        val root = newFolder("vault")
        writeValidConfigEnvelope(root)
        writeOneBlock(root)

        val outcome = FolderVaultChecker.checkCryfs(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val success = outcome as? FolderVaultCheckOutcome.Success
            ?: throw AssertionError("expected Success, got $outcome")
        assertTrue("expected no issues, got ${success.report.issues}", success.report.issues.isEmpty())
        assertEquals(1, success.report.filesScanned)
        assertTrue(!success.report.deepScanPerformed)
    }

    @Test
    fun `checkCryfs does not count a shard-shaped file or a wrongly-sized block name`() {
        val root = newFolder("vault")
        writeValidConfigEnvelope(root)
        val shard = File(root, "0af").apply { mkdirs() }
        File(shard, "a".repeat(28)).writeBytes(ByteArray(0)) // one char short
        File(shard, "g" + "a".repeat(28)).writeBytes(ByteArray(0)) // 29 chars, but 'g' isn't hex
        File(root, "bad").writeBytes(ByteArray(0)) // 3 hex chars, but a file, not a directory

        val outcome = FolderVaultChecker.checkCryfs(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val success = outcome as? FolderVaultCheckOutcome.Success
            ?: throw AssertionError("expected Success, got $outcome")
        assertEquals(0, success.report.filesScanned)
    }

    @Test
    fun `checkCryfs reports InvalidVault when cryfs_config is missing`() {
        val root = newFolder("vault")

        val outcome = FolderVaultChecker.checkCryfs(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val invalid = outcome as? FolderVaultCheckOutcome.InvalidVault
            ?: throw AssertionError("expected InvalidVault, got $outcome")
        assertTrue(invalid.message.contains("cryfs.config"))
    }

    @Test
    fun `checkCryfs reports InvalidVault for a corrupt config header`() {
        val root = newFolder("vault")
        File(root, "cryfs.config").writeBytes("not a cryfs config".toByteArray(Charsets.UTF_8))

        val outcome = FolderVaultChecker.checkCryfs(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val invalid = outcome as? FolderVaultCheckOutcome.InvalidVault
            ?: throw AssertionError("expected InvalidVault, got $outcome")
        assertTrue(invalid.message.contains("cryfs.config"))
    }
}
