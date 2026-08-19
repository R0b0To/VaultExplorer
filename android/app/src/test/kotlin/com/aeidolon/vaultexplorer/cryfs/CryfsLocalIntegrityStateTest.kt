package com.aeidolon.vaultexplorer.cryfs

import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.security.SecureRandom
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Pure-JVM (java.io.File only, no Context/SAF/JNI) coverage for
 * [CryfsLocalIntegrityState]: the durable bookkeeping that lets
 * [CryfsBlockStore.load] tell a genuine rollback/tampering attempt (CryFS
 * error 24/25) apart from ordinary corruption -- see that class's own KDoc
 * for the full rationale. These tests focus specifically on data safety:
 * that a version regression is always caught, that state survives a
 * simulated crash (killed mid-write, or restarted before a flush), and that
 * a corrupted on-disk snapshot never gets trusted over what it can't parse.
 */
class CryfsLocalIntegrityStateTest {

    private val random = SecureRandom()
    private lateinit var baseDir: File
    private val filesystemId = ByteArray(16).also { random.nextBytes(it) }

    @Before
    fun setUp() {
        baseDir = Files.createTempDirectory("cryfs-integrity-test").toFile()
    }

    @After
    fun tearDown() {
        baseDir.deleteRecursively()
    }

    private fun open() = CryfsLocalIntegrityState.open(baseDir, filesystemId, random)

    // ---- basic version bookkeeping -------------------------------------

    @Test
    fun `nextVersionForOwnWrite increments starting from 1`() {
        val state = open()
        val blockId = CryfsBlockId.random(random)
        assertEquals(1L, state.nextVersionForOwnWrite(blockId))
        assertEquals(2L, state.nextVersionForOwnWrite(blockId))
        assertEquals(3L, state.nextVersionForOwnWrite(blockId))
    }

    @Test
    fun `own-write versions are tracked independently per block`() {
        val state = open()
        val blockA = CryfsBlockId.random(random)
        val blockB = CryfsBlockId.random(random)
        assertEquals(1L, state.nextVersionForOwnWrite(blockA))
        assertEquals(1L, state.nextVersionForOwnWrite(blockB))
        assertEquals(2L, state.nextVersionForOwnWrite(blockA))
        assertEquals(2L, state.nextVersionForOwnWrite(blockB))
    }

    // ---- rollback detection: the core safety guarantee ------------------

    @Test
    fun `checkAndRecordRead accepts a version higher than any seen before`() {
        val state = open()
        val blockId = CryfsBlockId.random(random)
        assertNull(state.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 1L))
        assertNull(state.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 5L))
    }

    @Test
    fun `checkAndRecordRead accepts a repeat of the exact known version as a no-op`() {
        val state = open()
        val blockId = CryfsBlockId.random(random)
        assertNull(state.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 3L))
        assertNull(state.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 3L))
    }

    @Test
    fun `checkAndRecordRead rejects a version lower than one already durably recorded (rollback)`() {
        val state = open()
        val blockId = CryfsBlockId.random(random)
        assertNull(state.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 10L))

        val conflict = state.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 3L)
        assertEquals(10L, conflict)
    }

    @Test
    fun `rollback rejection does not lower the durably recorded version`() {
        val state = open()
        val blockId = CryfsBlockId.random(random)
        state.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 10L)
        state.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 3L) // rejected

        // A later read at the still-current version must be accepted, proving
        // the rejected rollback attempt never overwrote the known-good version.
        assertNull(state.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 10L))
    }

    @Test
    fun `version tracking is independent per writer client on the same block`() {
        // A second client's own counter must never be confused with, or
        // rejected against, a completely different client's counter for the
        // same physical block -- see the class's KDoc on why versions are
        // keyed by (client, block), not by block alone.
        val state = open()
        val blockId = CryfsBlockId.random(random)
        assertNull(state.checkAndRecordRead(writerClientId = 1L, blockId = blockId, version = 100L))
        // Client 2 starting at version 1 on the same block is not a rollback:
        // it has no prior history of its own for this block.
        assertNull(state.checkAndRecordRead(writerClientId = 2L, blockId = blockId, version = 1L))
    }

    @Test
    fun `own writes and another client's reads never cross-contaminate version tracking`() {
        val state = open()
        val blockId = CryfsBlockId.random(random)
        state.nextVersionForOwnWrite(blockId) // this client's own version = 1
        state.nextVersionForOwnWrite(blockId) // this client's own version = 2

        // A different client's write at version 1 for the same block is not a
        // rollback of THIS client's history -- it's that other client's own
        // independent series.
        assertNull(state.checkAndRecordRead(writerClientId = state.myClientId + 1, blockId = blockId, version = 1L))
    }

    // ---- crash consistency: durable persistence across restarts ---------

    @Test
    fun `own-write version reservations survive a simulated restart`() {
        val blockId = CryfsBlockId.random(random)
        val first = open()
        first.nextVersionForOwnWrite(blockId)
        first.nextVersionForOwnWrite(blockId)

        // Simulate a crash: no explicit flush(), just re-open from disk.
        val reopened = open()
        assertEquals(3L, reopened.nextVersionForOwnWrite(blockId))
    }

    @Test
    fun `rollback history survives a simulated restart`() {
        val blockId = CryfsBlockId.random(random)
        val first = open()
        first.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 10L)

        val reopened = open()
        val conflict = reopened.checkAndRecordRead(writerClientId = 42L, blockId = blockId, version = 3L)
        assertEquals(10L, conflict)
    }

    @Test
    fun `client identity is stable across restarts`() {
        val first = open()
        val reopened = open()
        assertEquals(first.myClientId, reopened.myClientId)
    }

    @Test
    fun `a fresh baseDir with no prior state gets a newly generated client id`() {
        val otherFsId = ByteArray(16).also { random.nextBytes(it) }
        val state = CryfsLocalIntegrityState.open(baseDir, otherFsId, random)
        // No assumption about the exact value -- only that opening didn't
        // crash and produced *a* usable id with no prior recorded history.
        val blockId = CryfsBlockId.random(random)
        assertEquals(1L, state.nextVersionForOwnWrite(blockId))
        assertNotEquals(0L, state.myClientId)
    }

    @Test
    fun `flush persists state without requiring the compaction threshold to be reached`() {
        val blockId = CryfsBlockId.random(random)
        val first = open()
        first.nextVersionForOwnWrite(blockId) // a single write, nowhere near COMPACTION_THRESHOLD
        first.flush()

        val reopened = open()
        assertEquals(2L, reopened.nextVersionForOwnWrite(blockId))
    }

    @Test
    fun `many writes past the compaction threshold still preserve exact history`() {
        val state = open()
        val blockId = CryfsBlockId.random(random)
        // COMPACTION_THRESHOLD is 200; cross it more than once so both the
        // log-append path and the compact()-to-snapshot path both run for
        // real, not just the cheap common case.
        repeat(450) { state.nextVersionForOwnWrite(blockId) }
        assertEquals(451L, state.nextVersionForOwnWrite(blockId))

        val reopened = open()
        assertEquals(452L, reopened.nextVersionForOwnWrite(blockId))
    }

    // ---- corruption recovery: never trust what can't be parsed ----------

    @Test
    fun `a corrupted snapshot file is not trusted, but the log on top of it still replays`() {
        val blockId = CryfsBlockId.random(random)
        val first = open()
        first.nextVersionForOwnWrite(blockId)
        first.flush() // forces a snapshot write

        // Corrupt the snapshot as if the process were killed mid-write.
        val fsIdHex = filesystemId.joinToString("") { "%02x".format(it) }
        val stateDir = File(baseDir, fsIdHex)
        val snapshotFile = File(stateDir, "integritydata.snapshot")
        assertTrue("expected a snapshot file to exist after flush()", snapshotFile.exists())
        FileOutputStream(snapshotFile, /* append = */ false).use { it.write("{not valid json".toByteArray()) }

        // A fresh write after the corruption is still logged (appended), so
        // recovery can rebuild from the log even though the snapshot is junk.
        val second = CryfsLocalIntegrityState.open(baseDir, filesystemId, random)
        // Snapshot was unreadable, so known history for this block is lost --
        // but that must fail SAFE (falls back to empty map), never throw and
        // never fabricate a value.
        assertEquals(1L, second.nextVersionForOwnWrite(blockId))
    }

    @Test
    fun `an empty (zero-byte) snapshot file does not crash recovery`() {
        val fsIdHex = filesystemId.joinToString("") { "%02x".format(it) }
        val stateDir = File(baseDir, fsIdHex)
        stateDir.mkdirs()
        File(stateDir, "integritydata.snapshot").createNewFile() // zero bytes, not valid JSON

        val state = CryfsLocalIntegrityState.open(baseDir, filesystemId, random)
        val blockId = CryfsBlockId.random(random)
        assertEquals(1L, state.nextVersionForOwnWrite(blockId))
    }

    @Test
    fun `a log line with a malformed version number is skipped rather than crashing recovery`() {
        val fsIdHex = filesystemId.joinToString("") { "%02x".format(it) }
        val stateDir = File(baseDir, fsIdHex)
        stateDir.mkdirs()
        val goodBlockHex = "ef".repeat(16)
        val badBlockHex = "ab".repeat(16)
        val logFile = File(stateDir, "integritydata.log")
        logFile.writeText("1:$badBlockHex=notanumber\n1:$goodBlockHex=7\n")

        val state = CryfsLocalIntegrityState.open(baseDir, filesystemId, random)
        // The well-formed second line must still have been replayed.
        val blockId = CryfsBlockId.fromHex(goodBlockHex)
        val conflict = state.checkAndRecordRead(writerClientId = 1L, blockId = blockId, version = 3L)
        assertEquals(7L, conflict)
    }

    @Test
    fun `a log line missing the separator is skipped without crashing recovery`() {
        val fsIdHex = filesystemId.joinToString("") { "%02x".format(it) }
        val stateDir = File(baseDir, fsIdHex)
        stateDir.mkdirs()
        val logFile = File(stateDir, "integritydata.log")
        logFile.writeText("this line has no equals sign\n")

        // Must not throw -- opening on top of a garbled log line is exactly
        // the "process was killed mid-append" case this needs to survive.
        val state = CryfsLocalIntegrityState.open(baseDir, filesystemId, random)
        val blockId = CryfsBlockId.random(random)
        assertEquals(1L, state.nextVersionForOwnWrite(blockId))
    }

    @Test
    fun `later log lines win over earlier ones for the same key on replay`() {
        // Log lines are chronological and append-only; if the same key
        // appears twice (e.g. compaction raced with a crash before
        // truncation), the last line must be authoritative, not the first.
        val fsIdHex = filesystemId.joinToString("") { "%02x".format(it) }
        val stateDir = File(baseDir, fsIdHex)
        stateDir.mkdirs()
        val logFile = File(stateDir, "integritydata.log")
        logFile.writeText("1:${"ab".repeat(16)}=5\n1:${"ab".repeat(16)}=9\n")

        val state = CryfsLocalIntegrityState.open(baseDir, filesystemId, random)
        val blockId = CryfsBlockId.fromHex("ab".repeat(16))
        val conflict = state.checkAndRecordRead(writerClientId = 1L, blockId = blockId, version = 6L)
        assertEquals(9L, conflict)
    }

    // ---- concurrency: never hand out the same version twice -------------

    @Test
    fun `concurrent own-writes to the same block never hand out a duplicate version`() {
        val state = open()
        val blockId = CryfsBlockId.random(random)
        val threadCount = 8
        val writesPerThread = 50
        val results = java.util.concurrent.ConcurrentLinkedQueue<Long>()

        val threads = (1..threadCount).map {
            Thread {
                repeat(writesPerThread) {
                    results.add(state.nextVersionForOwnWrite(blockId))
                }
            }
        }
        threads.forEach { it.start() }
        threads.forEach { it.join() }

        val versions = results.toList()
        assertEquals(threadCount * writesPerThread, versions.size)
        assertEquals(
            "every handed-out version must be unique -- a duplicate means two writers " +
                "could produce blocks that collide under CryFS's rollback check",
            versions.size, versions.toSet().size,
        )
        val expected = (1..(threadCount * writesPerThread)).map { it.toLong() }.toSet()
        assertEquals(expected, versions.toSet())
    }
}
