package com.aeidolon.vaultexplorer.cryfs

import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.SecureRandom

/**
 * Durable, per-vault local integrity bookkeeping: this install's own client
 * ID for the vault, plus the highest block-version number ever seen from
 * every client (including itself) for every block. This is a reimplementation
 * of upstream cryfs's `KnownBlockVersions` + its per-filesystem `myClientId`
 * (see `src/cryfs/impl/localstate/LocalStateDir.h` /
 * `src/blockstore/implementations/integrity/KnownBlockVersions.h` upstream).
 *
 * Why this class needs to exist at all: CryFS's integrity headers only make
 * sense if a *given client ID's* version number for a *given block* only
 * ever goes up, forever -- across process restarts, and independent of
 * whatever version any other client last left on that block. [CryfsBlockStore]
 * used to derive the next version purely from whatever was last read off
 * disk (an in-memory, per-session cache), which quietly breaks that
 * invariant the moment a second client (DroidFS, the reference cryfs client)
 * writes the same block in between two of this app's own writes -- this
 * app's next write then looks, from the other client's point of view, like
 * this app's own version series went *backwards*. That's exactly CryFS
 * error 24/25 (`IntegrityViolationOnPreviousRun` / `IntegrityViolation`).
 *
 * Deliberately takes a plain [File] directory rather than an Android
 * `Context`, so the bookkeeping/persistence logic here -- independent of any
 * SAF or `Context` dependency -- can be covered by a plain JVM unit test,
 * same rationale as [CryfsBlockStorage]'s extraction (see its KDoc).
 *
 * Every mutating call is `@Synchronized`: block I/O in [CryfsBlockStore] can
 * happen from multiple threads at once (its `isRaw` fast path uses a shared
 * executor for parallel block reads/writes), and handing out the same
 * "next version" to two concurrent writers of the same block would recreate
 * the exact bug this class exists to fix.
 */
class CryfsLocalIntegrityState private constructor(
    private val stateDir: File,
    val myClientId: Long,
    private val knownVersions: MutableMap<String, Long>,
    private var pendingLogLines: Int,
) {

    /**
     * The next version to use when *this* client (myClientId) overwrites
     * [blockId]. Always `(this client's own last-used version for this
     * exact block) + 1` -- never derived from whatever version happens to
     * be sitting on the block on disk right now, since that may belong to a
     * completely different client's independent counter. Durably persists
     * the reservation (via an fsync'd append) before returning it, so a
     * crash immediately after this call can never cause the same version
     * to be handed out twice.
     */
    @Synchronized
    fun nextVersionForOwnWrite(blockId: CryfsBlockId): Long {
        val key = keyFor(myClientId, blockId)
        val next = (knownVersions[key] ?: 0L) + 1
        knownVersions[key] = next
        appendMutation(key, next)
        return next
    }

    /**
     * Records a block read carrying [writerClientId]'s claimed [version].
     * Returns `null` if that's consistent with this device's history.
     * Returns the previously-recorded (higher) version if [version] is a
     * rollback -- lower than one this device has already durably recorded
     * for that *exact* (client, block) pair -- which is this app's
     * equivalent of CryFS's error 24/25. A plain repeat read of an
     * already-known version is accepted as a cheap no-op, not re-logged.
     */
    @Synchronized
    fun checkAndRecordRead(writerClientId: Long, blockId: CryfsBlockId, version: Long): Long? {
        val key = keyFor(writerClientId, blockId)
        val known = knownVersions[key]
        if (known != null && version < known) return known
        if (known == null || version > known) {
            knownVersions[key] = version
            appendMutation(key, version)
        }
        return null
    }

    /** Appends one durable log line, compacting into a fresh snapshot once
     *  the log has grown past [COMPACTION_THRESHOLD] lines since the last
     *  compaction (keeps the common case a cheap O(1) append instead of an
     *  O(map size) rewrite on every single block write). */
    private fun appendMutation(key: String, version: Long) {
        FileOutputStream(File(stateDir, LOG_FILE_NAME), /* append = */ true).use { out ->
            out.write("$key=$version\n".toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        pendingLogLines++
        if (pendingLogLines >= COMPACTION_THRESHOLD) compact()
    }

    /** Forces a compaction pass now regardless of the log's current size --
     *  folds it into the snapshot file and truncates it. Cheap to call even
     *  when nothing is pending. Callers ([CryfsBlockStore.clearCache],
     *  [CryfsSession.close]) should call this at natural session
     *  boundaries so the on-disk log doesn't linger larger than it needs
     *  to be between runs. */
    @Synchronized
    fun flush() {
        if (pendingLogLines > 0) compact()
    }

    private fun compact() {
        writeAtomic(File(stateDir, SNAPSHOT_FILE_NAME), serializeSnapshot())
        // Truncate rather than delete-then-recreate: avoids a window where
        // neither an up-to-date log nor a matching snapshot exists on disk.
        FileOutputStream(File(stateDir, LOG_FILE_NAME), /* append = */ false).use { it.fd.sync() }
        pendingLogLines = 0
    }

    private fun serializeSnapshot(): ByteArray {
        val json = JSONObject()
        for ((key, version) in knownVersions) json.put(key, version.toString())
        return json.toString().toByteArray(Charsets.UTF_8)
    }

    companion object {
        private const val CLIENT_ID_FILE_NAME = "myClientId"
        private const val SNAPSHOT_FILE_NAME = "integritydata.snapshot"
        private const val LOG_FILE_NAME = "integritydata.log"

        // Amortizes compaction cost: at most this many cheap appends between
        // full-map rewrites, keeping both individual writes and worst-case
        // startup replay time bounded.
        private const val COMPACTION_THRESHOLD = 200

        private fun keyFor(clientId: Long, blockId: CryfsBlockId) = "$clientId:${blockId.hex}"

        /**
         * Loads (or lazily creates) the local integrity state for one vault,
         * under `[baseDir]/<filesystemId as hex>/`. [baseDir] is meant to be
         * something like `context.filesDir/cryfs_localstate` -- private,
         * per-install storage that survives across app restarts but is (by
         * design, same as upstream cryfs's own local state directory) *not*
         * part of the vault itself, so it's never synced/shared between
         * clients. A fresh install/reinstall or a cleared app data directory
         * legitimately starts a new client identity with no prior history --
         * exactly as reinstalling DroidFS or the desktop cryfs client would.
         */
        fun open(baseDir: File, filesystemId: ByteArray, random: SecureRandom = SecureRandom()): CryfsLocalIntegrityState {
            val fsIdHex = filesystemId.joinToString("") { "%02x".format(it) }
            val stateDir = File(baseDir, fsIdHex)
            if (!stateDir.exists()) stateDir.mkdirs()

            val clientIdFile = File(stateDir, CLIENT_ID_FILE_NAME)
            val myClientId = (if (clientIdFile.exists()) clientIdFile.readText(Charsets.UTF_8).trim().toLongOrNull() else null)
                ?: generateAndPersistClientId(clientIdFile, random)

            val knownVersions = mutableMapOf<String, Long>()
            val snapshotFile = File(stateDir, SNAPSHOT_FILE_NAME)
            if (snapshotFile.exists()) {
                try {
                    val json = JSONObject(snapshotFile.readText(Charsets.UTF_8))
                    for (key in json.keys()) knownVersions[key] = json.getString(key).toLong()
                } catch (_: Exception) {
                    // Corrupt/partial snapshot (e.g. killed mid-write despite the atomic
                    // rename below). Fall through and replay the log on top of an empty
                    // map -- losing only whatever was compacted before the corruption,
                    // never trusting a value we can't parse.
                }
            }

            var pendingLogLines = 0
            val logFile = File(stateDir, LOG_FILE_NAME)
            if (logFile.exists()) {
                logFile.forEachLine(Charsets.UTF_8) { line ->
                    val eq = line.lastIndexOf('=')
                    if (eq <= 0) return@forEachLine
                    val version = line.substring(eq + 1).toLongOrNull() ?: return@forEachLine
                    val key = line.substring(0, eq)
                    // Log lines are append-only and chronological, so the last one
                    // for a given key always wins -- consistent with how each
                    // mutation was derived from (and only ever increases) the prior
                    // known value in the first place.
                    knownVersions[key] = version
                    pendingLogLines++
                }
            }

            return CryfsLocalIntegrityState(stateDir, myClientId, knownVersions, pendingLogLines)
        }

        private fun generateAndPersistClientId(file: File, random: SecureRandom): Long {
            // Positive 32-bit value, matching the width of the clientId field in the
            // integrity header CryfsBlockStore writes/reads (u32 at offset 18).
            val raw = random.nextInt(Int.MAX_VALUE).toLong() and 0xFFFFFFFFL
            val id = if (raw == 0L) 1L else raw
            writeAtomic(file, id.toString().toByteArray(Charsets.UTF_8))
            return id
        }

        private fun writeAtomic(target: File, bytes: ByteArray) {
            val tmp = File(target.parentFile, "${target.name}.tmp")
            FileOutputStream(tmp).use { out ->
                out.write(bytes)
                out.fd.sync()
            }
            if (!tmp.renameTo(target)) {
                // Rename-over-existing can fail on some filesystems; fall back to
                // delete-then-rename rather than leaving stale data in place.
                target.delete()
                tmp.renameTo(target)
            }
        }
    }
}
