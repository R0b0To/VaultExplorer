package com.aeidolon.vaultexplorer.foldercheck

import androidx.documentfile.provider.DocumentFile
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.util.Base64

/**
 * Cryptomator counterpart to FolderVaultCheckerGocryptfsTest -- see that
 * file's header for why these call the `internal` checkCryptomator directly
 * rather than the public check() entry point.
 *
 * Only the no-password physical-storage-layout branch is covered
 * (session == null && password == null in checkCryptomator, which returns
 * right after checkCryptomatorDataDirShape). The password-verified path
 * (masterkey unwrap, vault.cryptomator JWT signature verification, directory
 * tree walk with real name/content decryption) is NOT covered here -- it
 * needs a real wrapped masterkey and a signed vault-config JWT, which is a
 * meaningfully bigger fixture-building job left for a follow-up.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class FolderVaultCheckerCryptomatorTest {

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

    /** A structurally valid masterkey.cryptomator per CryptomatorMasterkeyFile.parse's
     *  schema (see that file's doc comment). Field contents are dummy bytes --
     *  parse() only checks that they're valid base64 plus a sane scrypt cost/block
     *  size; nothing here is ever unwrapped on the no-password path this test covers. */
    private fun writeValidMasterkeyFile(dir: File) {
        val json = JSONObject().apply {
            put("version", 999)
            put("scryptSalt", Base64.getEncoder().encodeToString(ByteArray(8)))
            put("scryptCostParam", 32768)
            put("scryptBlockSize", 8)
            put("primaryMasterKey", Base64.getEncoder().encodeToString(ByteArray(40)))
            put("hmacMasterKey", Base64.getEncoder().encodeToString(ByteArray(40)))
            put("versionMac", Base64.getEncoder().encodeToString(ByteArray(32)))
        }
        File(dir, "masterkey.cryptomator").writeBytes(json.toString().toByteArray(Charsets.UTF_8))
    }

    /** One physically-valid encrypted-item directory: a 2-char level-1 dir
     *  containing a 30-char level-2 dir, matching checkCryptomatorDataDirShape's
     *  shape check. Real Cryptomator names these from a hashed directory ID --
     *  the exact characters don't matter here, only the two length checks do. */
    private fun writeOneDataDirEntry(dataDir: File) {
        val lvl1 = File(dataDir, "ab").apply { mkdirs() }
        File(lvl1, "c".repeat(30)).mkdirs()
    }

    @Test
    fun `checkCryptomator reports one warning for a healthy vault with no vault_cryptomator and no password`() {
        val root = newFolder("vault")
        writeValidMasterkeyFile(root)
        val dataDir = File(root, "d").apply { mkdirs() }
        writeOneDataDirEntry(dataDir)
        // vault.cryptomator intentionally omitted -- exercises the
        // "assuming format-7 vault" warning branch.

        val outcome = FolderVaultChecker.checkCryptomator(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val success = outcome as? FolderVaultCheckOutcome.Success
            ?: throw AssertionError("expected Success, got $outcome")
        val issue = success.report.issues.singleOrNull()
            ?: throw AssertionError("expected exactly one issue, got ${success.report.issues}")
        assertEquals(FolderVaultIssueSeverity.WARNING, issue.severity)
        assertTrue(issue.message.contains("vault.cryptomator"))
        assertEquals(1, success.report.filesScanned) // physicalDirCount, despite the field name
        assertTrue(!success.report.deepScanPerformed)
    }

    @Test
    fun `checkCryptomator reports InvalidVault when the d data directory is missing`() {
        val root = newFolder("vault")
        writeValidMasterkeyFile(root)
        // No "d" directory created at all.

        val outcome = FolderVaultChecker.checkCryptomator(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val invalid = outcome as? FolderVaultCheckOutcome.InvalidVault
            ?: throw AssertionError("expected InvalidVault, got $outcome")
        assertTrue(invalid.message.contains("'d' data directory"))
    }

    @Test
    fun `checkCryptomator reports InvalidVault when masterkey_cryptomator is missing`() {
        val root = newFolder("vault")
        File(root, "d").mkdirs()
        // No masterkey.cryptomator written.

        val outcome = FolderVaultChecker.checkCryptomator(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val invalid = outcome as? FolderVaultCheckOutcome.InvalidVault
            ?: throw AssertionError("expected InvalidVault, got $outcome")
        assertTrue(invalid.message.contains("masterkey.cryptomator"))
    }
}
