package com.aeidolon.vaultexplorer.foldercheck

import androidx.documentfile.provider.DocumentFile
import androidx.test.core.app.ApplicationProvider
import org.json.JSONArray
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
 * FolderVaultChecker is the "Check & Repair" tool's implementation: it reads
 * and (for repair) mutates a folder-vault's on-disk structure directly, and
 * until now had zero test coverage despite that -- see the tech-debt audit
 * that led to this file.
 *
 * checkGocryptfs/checkCryptomator/checkCryfs/repairGocryptfs/repairCryptomator
 * were changed from `private` to `internal` (visibility only, no logic
 * touched) specifically so these tests can call them directly with a
 * DocumentFile.fromFile(...) fixture. The public check()/repair() entry
 * points call DocumentFile.fromTreeUri(context, vaultRootUri), which needs a
 * real SAF tree-Uri content provider that a plain temp folder can't satisfy
 * -- the same constraint ChunkedFileEngineTest, MirrorSyncCoordinatorTest and
 * SafDocumentOpsTest all work around by testing one layer below the Uri
 * entry point.
 *
 * These tests only cover the structural/no-password path (session == null,
 * password == null) -- the branch that runs the size/DirIV/filename-sidecar
 * checks without needing a real masterkey. That deliberately avoids
 * GocryptfsMasterkey.unlock's native-scrypt dependency (see
 * GocryptfsMasterkeyTest's Assume guard for why that's not always available
 * on a host JVM), so these tests should run everywhere the other Robolectric
 * suites do. Password-verified and session-backed paths, and the
 * cryfs/cryptomator equivalents, are NOT yet covered -- this is a first
 * slice, not the full backfill the audit called for.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class FolderVaultCheckerGocryptfsTest {

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

    private val testScryptN = 16
    private val testScryptR = 8
    private val testScryptKeyLen = 32

    /** Cipher/header-size constants FolderVaultChecker.checkGocryptfs derives
     *  from the config -- duplicated here (not imported) so a test fixture
     *  bug and a production bug can't cancel each other out. */
    private val headerLen = 18 // GocryptfsContentCryptor.HEADER_LEN
    private val cleartextChunkSize = 4096 // GocryptfsContentCryptor.CLEARTEXT_CHUNK_SIZE
    private val nonceLenAesGcm = 16
    private val expectedChunkSize = nonceLenAesGcm + cleartextChunkSize + 16 // + GCM tag

    /** Writes a valid, parseable gocryptfs.conf (AES-256-GCM, DirIV, EME
     *  names) into [dir]. Content of EncryptedKey doesn't matter for the
     *  no-password structural-check path -- only that it's valid base64. */
    private fun writeValidConfig(dir: File) {
        val scryptObject = JSONObject().apply {
            put("Salt", Base64.getEncoder().encodeToString(ByteArray(16)))
            put("N", testScryptN)
            put("R", testScryptR)
            put("P", 1)
            put("KeyLen", testScryptKeyLen)
        }
        val json = JSONObject().apply {
            put("Creator", "VaultExplorer test fixture")
            put("EncryptedKey", Base64.getEncoder().encodeToString(ByteArray(48)))
            put("ScryptObject", scryptObject)
            put("Version", 2)
            put("FeatureFlags", JSONArray(listOf("GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF")))
        }
        File(dir, "gocryptfs.conf").writeBytes(json.toString().toByteArray(Charsets.UTF_8))
    }

    private fun writeDiriv(dir: File) {
        File(dir, "gocryptfs.diriv").writeBytes(ByteArray(16))
    }

    /** One exactly-aligned ciphertext chunk: header + one full chunk body,
     *  so checkGocryptfs's remainder check sees 0 and raises nothing. Bytes
     *  are zero-filled -- content is never decrypted on this path since no
     *  password/session is supplied. */
    private fun writeAlignedCiphertextFile(dir: File, name: String) {
        File(dir, name).writeBytes(ByteArray(headerLen + expectedChunkSize))
    }

    @Test
    fun `checkGocryptfs reports no issues for a healthy vault with no password given`() {
        val root = newFolder("vault")
        writeValidConfig(root)
        writeDiriv(root)
        writeAlignedCiphertextFile(root, "ABCDEFGHIJKLMNOPQRSTUV")

        val outcome = FolderVaultChecker.checkGocryptfs(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val success = outcome as? FolderVaultCheckOutcome.Success
            ?: throw AssertionError("expected Success, got $outcome")
        assertTrue(
            "expected no issues, got ${success.report.issues}",
            success.report.issues.isEmpty(),
        )
        assertEquals(1, success.report.filesScanned)
        assertTrue("password-less check should not claim a deep scan", !success.report.deepScanPerformed)
    }

    @Test
    fun `checkGocryptfs flags a missing gocryptfs_diriv as critical`() {
        val root = newFolder("vault")
        writeValidConfig(root)
        // writeDiriv(root) intentionally omitted
        writeAlignedCiphertextFile(root, "ABCDEFGHIJKLMNOPQRSTUV")

        val outcome = FolderVaultChecker.checkGocryptfs(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val success = outcome as? FolderVaultCheckOutcome.Success
            ?: throw AssertionError("expected Success, got $outcome")
        val issue = success.report.issues.singleOrNull()
            ?: throw AssertionError("expected exactly one issue, got ${success.report.issues}")
        assertEquals(FolderVaultIssueSeverity.CRITICAL, issue.severity)
        assertTrue(issue.message.contains("gocryptfs.diriv"))
    }

    @Test
    fun `checkGocryptfs reports InvalidVault when gocryptfs_conf is missing`() {
        val root = newFolder("empty-vault")

        val outcome = FolderVaultChecker.checkGocryptfs(
            context, DocumentFile.fromFile(root), password = null, session = null, log = {},
        )

        val invalid = outcome as? FolderVaultCheckOutcome.InvalidVault
            ?: throw AssertionError("expected InvalidVault, got $outcome")
        assertTrue(invalid.message.contains("gocryptfs.conf"))
    }
}
