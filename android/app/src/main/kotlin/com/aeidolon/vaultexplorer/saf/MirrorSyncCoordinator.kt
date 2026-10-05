package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.VeLog
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

class MirrorPushException(message: String, cause: Throwable? = null) : Exception(message, cause)

class MirrorSyncCoordinator(
    private val context: Context,
    private val sessionTag: String,
    val realOps: SafDocumentOps,
) {
    companion object {
        /** Name of the folder under `filesDir` that holds every session's
         *  mirror (`vault_mirrors/<sessionTag>/`). */
        private const val MIRRORS_DIR_NAME = "vault_mirrors"

        /** Session tags of coordinators that are alive in THIS process --
         *  registered in `init`, removed at the end of [teardown]. Lets
         *  [sweepOrphanedMirrors] tell a live session's mirror folder from
         *  one left behind by a process that died before [teardown] ran. */
        private val activeTags: MutableSet<String> = ConcurrentHashMap.newKeySet()

        /**
         * Deletes every `vault_mirrors/<tag>/` folder that no live
         * coordinator in this process owns, and returns how many were
         * removed.
         *
         * A mirror is only ever deleted by [teardown], which a killed or
         * crashed process never reaches. The registry that maps mirror
         * files to real SAF URIs lives purely in memory and every unlock
         * uses a fresh random tag, so such a folder can never be reused or
         * cleaned by a later session -- it is dead weight (encrypted
         * copies of vault files) until something removes it.
         *
         * Safe to call at any time, including while sessions are open:
         * a tag is registered in `init`, before its folder is created, so
         * any folder belonging to a live session is skipped. Any pending
         * write that was still unpushed in an orphaned mirror is lost
         * along with it, but it was already unreachable -- nothing can
         * push it once the process that tracked it is gone.
         */
        fun sweepOrphanedMirrors(context: Context): Int {
            val children = File(context.filesDir, MIRRORS_DIR_NAME).listFiles() ?: return 0
            var removed = 0
            for (child in children) {
                if (child.name in activeTags) continue
                try {
                    if (child.deleteRecursively()) {
                        removed++
                    } else {
                        VeLog.w("MirrorSyncCoordinator") { "sweepOrphanedMirrors: could not fully delete ${child.absolutePath}" }
                    }
                } catch (e: Exception) {
                    VeLog.w("MirrorSyncCoordinator", e) { "sweepOrphanedMirrors: failed to delete ${child.absolutePath}" }
                }
            }
            if (removed > 0) {
                VeLog.d("MirrorTrace") { "sweepOrphanedMirrors: removed $removed orphaned mirror folder(s)" }
            }
            return removed
        }

        /** Buffer size for the tmp-file-then-rename pull/push copies below.
         *  Kotlin's `copyTo` default (8KB) means far more read()/write()
         *  round trips than necessary for a large file streamed over a
         *  ContentResolver pipe -- bumped to cut that overhead on big
         *  pulls/pushes. */
        private const val COPY_BUFFER_SIZE = 256 * 1024

        /** How long the first content push of a newly created file is held
         *  back -- see [pushContent]. */
        private const val DEFERRED_PUSH_DELAY_MS = 2_000L

        /** Providers (by authority) where overwriting a real document that
         *  already holds content in place was observed not to take effect
         *  -- see [replaceRealDocument]. Process-wide, so the one-off
         *  detection cost is paid once, not once per vault session. */
        private val unreliableOverwriteAuthorities: MutableSet<String> = ConcurrentHashMap.newKeySet()

        /** Below this size, a cold read of a not-yet-mirrored file just
         *  pays the synchronous full pull like before -- the latency is
         *  negligible and it's not worth the bookkeeping of a background
         *  pull. At or above it (video, large PDFs, disk images, etc.),
         *  [ensureReadyOrStreamDirect] instead kicks off the pull in the
         *  background and hands the caller the REAL document to stream
         *  directly from for this read, so opening a large cold file for
         *  playback/seeking through the document-provider mount doesn't
         *  block on downloading the whole thing first. */
        const val LARGE_FILE_STREAM_THRESHOLD_BYTES = 8L * 1024 * 1024
    }

    val mirrorRoot: File = File(File(context.filesDir, MIRRORS_DIR_NAME), sessionTag)

    init {
        // Before anything creates mirrorRoot on disk -- see sweepOrphanedMirrors.
        activeTags.add(sessionTag)
    }

    // All URI<->mirror-file bookkeeping (link/unlink, listed-folder flags,
    // and content-pulled/pending-write state) lives in MirrorRegistry --
    // see that class's doc comment for why it's split out: it's plain
    // String/File collections with no Android dependency, so it can be
    // unit-tested directly, and it collapses what used to be two
    // independently-mutated sets (pulledContent, pendingLocalWrites) into
    // one per-key state machine where "pending write" always wins over a
    // stale "synced" flag by construction rather than by every call site
    // remembering to check both in the right order.
    private val registry = MirrorRegistry()

    // Per-key monitors guarding pullFileIfMissing -- without these, two
    // threads racing a cold pull of the SAME file (e.g. ensureContentPulled
    // from a readWhole() call and the background pull kicked off by
    // ensureReadyOrStreamDirect below) both see the content not yet marked
    // synced and both copy into the SAME ".pulling" tmp path at once.
    // Previously this was implicitly safe only because the one caller
    // (ChunkedFileEngine's getPhysicalFileForRead) always ran under that
    // engine's own per-path lock; ensureReadyOrStreamDirect's background
    // pulls run on a separate executor, outside that lock, so the guard
    // needs to live here instead. This is operation coordination, not
    // registry state, so it stays here rather than moving to MirrorRegistry.
    private val pullLocks = ConcurrentHashMap<String, Any>()
    private fun pullLockFor(key: String): Any = pullLocks.computeIfAbsent(key) { Any() }

    // Per-folder monitors guarding pullListingIfMissing -- MirroredSafDocumentOps'
    // hasListed()-then-pullListingIfMissing() check in listChildren/childOf is a
    // classic check-then-act race: the in-app browser and an external
    // document-provider client (e.g. a gallery app) listing the same
    // not-yet-listed folder at the same moment would otherwise both run the
    // full listing + per-child registration pass. Folded into
    // pullListingIfMissing itself so every caller gets the dedup for free.
    private val folderLocks = ConcurrentHashMap<String, Any>()
    private fun folderLockFor(key: String): Any = folderLocks.computeIfAbsent(key) { Any() }

    // Real-doc URI keys with a background pull in flight -- see
    // ensureReadyOrStreamDirect. Guards against two large-file cold reads of
    // the SAME file both scheduling their own redundant full copy.
    private val pullsInFlight = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    // Bounded and session-scoped (shut down in teardown()), same rationale
    // as the app's other small fixed pools (e.g. VideoThumbnailCoordinator):
    // a burst of large cold opens against one vault session queues behind a
    // fixed number of workers instead of spawning one thread per file.
    private val pullExecutor = java.util.concurrent.Executors.newFixedThreadPool(2)

    // What we know about a real document's content, by real URI: false =
    // created by us and still empty, true = we pushed non-empty content.
    // Absent = unknown (e.g. discovered by a listing).
    private val realContent = ConcurrentHashMap<String, Boolean>()

    // Write-behind for the first content push of a new file, by real URI.
    // See pushContent.
    private val deferLock = Any()
    private val deferred = HashMap<String, java.util.concurrent.ScheduledFuture<*>>()
    private val deferExecutor = java.util.concurrent.Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "mirror-deferred-push").apply { isDaemon = true }
    }

    fun markPendingLocalWrite(mirrored: File) {
        // A write handle is being opened: its commit pushes the full
        // content, and a deferred push firing mid-write would upload a
        // half-written mirror.
        cancelDeferred(mirrored)
        // Translated from mirror path to the real-URI key that
        // MirrorRegistry's content state is keyed by (see that class's doc
        // comment). Both call sites (CryptomatorSession/GocryptfsSession's
        // getOrCreatePhysicalFileForWrite) only ever pass a DocumentFile
        // that's either freshly created (registerExisting/link already ran
        // as part of creating it) or resolved from the tree (which means
        // it was linked whenever it was first discovered) -- so a miss
        // here means something upstream skipped registration, not a
        // legitimate case to silently ignore. The whole point of this
        // call is to protect an in-flight write from being reconciled
        // away; failing to record it silently would reproduce the exact
        // bug this mechanism exists to prevent, just one level up.
        val key = registry.keyForMirrorPath(mirrored.absolutePath)
        if (key == null) {
            VeLog.e("MirrorTrace") {
                "markPendingLocalWrite: no registered key for mirror path ${mirrored.absolutePath} -- " +
                    "this write is NOT protected from being reconciled away by a concurrent directory re-listing"
            }
            return
        }
        registry.markPendingLocalWrite(key)
    }

    fun reset(realVaultRoot: DocumentFile) {
        if (mirrorRoot.exists()) mirrorRoot.deleteRecursively()
        mirrorRoot.mkdirs()
        registry.clear()
        realContent.clear()
        synchronized(deferLock) { deferred.values.forEach { it.cancel(false) }; deferred.clear() }
        pullLocks.clear()
        folderLocks.clear()
        pullsInFlight.clear()
        val rootMirror = File(mirrorRoot, "root")
        rootMirror.mkdirs()
        registry.link(realVaultRoot.uri.toString(), rootMirror)
    }

    fun teardown() {
        // Don't lose content whose push was still being held back.
        val pending = synchronized(deferLock) { deferred.keys.toList() }
        pending.forEach(::runDeferred)
        deferExecutor.shutdownNow()
        realContent.clear()
        registry.clear()
        pullLocks.clear()
        folderLocks.clear()
        pullsInFlight.clear()
        pullExecutor.shutdownNow()
        try {
            mirrorRoot.deleteRecursively()
        } catch (e: Exception) {
            VeLog.e("MirrorSyncCoordinator", e) { "teardown failed to delete mirror at ${mirrorRoot.absolutePath}" }
        }
        // Even if the delete above failed: the folder is then an orphan the
        // next sweepOrphanedMirrors() call should be free to retry.
        activeTags.remove(sessionTag)
    }

    private fun sanitizedMirrorName(name: String?): String {
        val unsafe = name.isNullOrEmpty() ||
            name == "." || name == ".." ||
            name.contains(File.separatorChar) || name.contains('\u0000')
        if (!unsafe) return name!!
        VeLog.w("MirrorSyncCoordinator") { "Unsafe SAF display name for mirroring (len=${name?.length ?: 0}), falling back to a hashed name" }
        val digest = MessageDigest.getInstance("SHA-256").digest((name ?: "").toByteArray(Charsets.UTF_8))
        return "_" + digest.joinToString("") { "%02x".format(it) }
    }

    private fun mirrorChildFor(realDoc: DocumentFile, mirroredParent: File, isDirectory: Boolean): File {
        val key = realDoc.uri.toString()
        val existing = registry.mirrorFor(key)
        val expectedName = sanitizedMirrorName(realDoc.name)
        if (existing != null) {
            if (existing.name == expectedName && existing.parentFile == mirroredParent) {
                return existing
            }
            registry.forgetContent(key)
            try { existing.deleteRecursively() } catch (_: Exception) {}
        }
        val mirrored = File(mirroredParent, expectedName)
        // Some SAF providers (Google Drive's in particular) can hand back a
        // provisional document URI from createDocument()/DocumentsContract
        // and then report a different, canonical URI for that same
        // document on a subsequent listing query. When that happens this
        // is really the same file getting a new key, not a new child --
        // but any old key(s) still pointing at this exact File would
        // otherwise survive into the stale-entry sweep in
        // pullListingIfMissing() below and have their target deleted,
        // since that sweep only knows to keep keys present in the fresh
        // listing. Migrate registration (and whatever content state --
        // synced OR pending-local-write -- it had) to the new key instead
        // of leaving the old one behind to be treated as stale. O(1) via
        // MirrorRegistry's mirror-path index instead of scanning every
        // registered file for one whose target File matches.
        if (existing == null) {
            val aliasKey = registry.keyForMirrorPath(mirrored.absolutePath)
            if (aliasKey != null) {
                registry.unlink(aliasKey)
                registry.migrateContentState(aliasKey, key)
            }
        }
        registry.link(key, mirrored)
        return mirrored
    }

    fun registerExisting(realDoc: DocumentFile, mirrored: File) {
        registry.link(realDoc.uri.toString(), mirrored)
    }

    /** Call right after [registerExisting] for a document THIS caller just
     *  created on the real tree (never for one that already existed) --
     *  see [MirrorRegistry.neverListed]'s doc comment. Protects the new
     *  registration from [pullListingIfMissing]'s stale-key sweep until a
     *  real-side listing actually confirms the child is present. */
    fun markFreshlyCreated(realDoc: DocumentFile) {
        registry.markNeverListed(realDoc.uri.toString())
    }

    fun realUriFor(mirrored: File): Uri? =
        registry.keyForMirrorPath(mirrored.absolutePath)?.let { Uri.parse(it) }

    fun hasContent(realDoc: DocumentFile): Boolean = registry.hasContent(realDoc.uri.toString())

    fun pullFileIfMissing(realDoc: DocumentFile): File {
        val key = realDoc.uri.toString()
        val mirrored = registry.mirrorFor(key)
            ?: throw SafIOException("pullFileIfMissing: no mirror mapping for ${realDoc.uri}")
        if (registry.hasContent(key)) {
            VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key already pulled, mirrorLength=${mirrored.length()}" }
            return mirrored
        }
        // A pending local write (a batched import's staged mirror content,
        // or any other deferred-push write) always wins over pulling from
        // real SAF -- same rule as MirrorRegistry.markSynced and
        // reconcileStaleContent, see MirrorRegistry's class doc comment.
        // Without this check, this was the third, previously-unaddressed
        // instance of that same production bug: hasContent(key) above is
        // false for PENDING_LOCAL_WRITE (it's a distinct ContentState, not
        // SYNCED), so a background thumbnailer/media-scanner read landing
        // here mid-import fell through to "not yet pulled" and pulled from
        // the real SAF document -- which, this early in the batch, is
        // either not yet pushed at all or only an empty placeholder --
        // then overwrote the mirror's already-written real content with
        // those 0 bytes via the tmp.renameTo(mirrored) below. The batch's
        // later pushFileWrite then read the now-truncated mirror and
        // committed an empty file to the real vault: silent data loss for
        // every file whose read lost this race, with no error anywhere
        // (pushFileWrite's own 0-byte retry/warning exists for a different
        // reason -- a fresh write's length not being visible to a `stat`
        // moments after it completes -- and can't catch this, since the
        // mirror file DID stably read as 0 bytes: it had actually been
        // overwritten, not just observed too early).
        if (registry.hasPendingLocalWrite(key)) {
            VeLog.d("MirrorTrace") {
                "pullFileIfMissing: uri=$key has a pending local write, not pulling -- " +
                    "returning mirror as-is, mirrorLength=${mirrored.length()}"
            }
            return mirrored
        }
        // Guards concurrent callers of the SAME key -- e.g. a readWhole()'s
        // ensureContentPulled racing the background pull
        // ensureReadyOrStreamDirect kicks off below, or two large-file cold
        // reads landing on the same file at once. Without this, both would
        // pass the hasContent check above, then both write into the SAME
        // ".pulling" tmp path concurrently.
        synchronized(pullLockFor(key)) {
            // Re-check: another thread may have finished the pull, OR
            // marked a pending local write, while we were waiting for the
            // lock.
            if (registry.hasContent(key)) {
                VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key pulled by another thread while waiting, mirrorLength=${mirrored.length()}" }
                return mirrored
            }
            if (registry.hasPendingLocalWrite(key)) {
                VeLog.d("MirrorTrace") {
                    "pullFileIfMissing: uri=$key gained a pending local write while waiting, not pulling -- " +
                        "returning mirror as-is, mirrorLength=${mirrored.length()}"
                }
                return mirrored
            }
            VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key not yet pulled, fetching from real SAF" }
            mirrored.parentFile?.mkdirs()
            val tmp = File(mirrored.parentFile, mirrored.name + ".pulling")
            var bytesCopied = 0L
            // NOTE: the pfd.use{} block below (successful
            // openFileDescriptor) can still throw mid-transfer if the
            // underlying file disappears or becomes unreadable AFTER the
            // descriptor was already opened (already-open fd revoked,
            // disk removed, etc.) -- a real but much rarer failure mode
            // than "file doesn't exist at all" (the descriptor open
            // itself already confirmed existence). Left unwrapped here,
            // same as before this fix: no specific bug or test currently
            // drives wrapping it, and doing so without one risks scope
            // creep on what should stay a targeted fix. If this ever
            // surfaces in practice, it needs the same SafIOException
            // translation as the openInputStream fallback below.
            val pfd = try { context.contentResolver.openFileDescriptor(realDoc.uri, "r") } catch (_: Exception) { null }
            if (pfd != null) {
                try {
                    pfd.use { fd ->
                        java.io.FileInputStream(fd.fileDescriptor).use { fis ->
                            tmp.outputStream().use { fos ->
                                bytesCopied = fis.copyTo(fos, COPY_BUFFER_SIZE)
                            }
                        }
                    }
                } catch (e: Exception) {
                    tmp.delete()
                    throw SafIOException("pullFileIfMissing: failed to read from file descriptor for ${realDoc.uri}", e)
                }
            } else {
                try {
                    context.contentResolver.openInputStream(realDoc.uri)?.use { input ->
                        tmp.outputStream().use { out -> bytesCopied = input.copyTo(out, COPY_BUFFER_SIZE) }
                    } ?: throw SafIOException("pullFileIfMissing: could not open ${realDoc.uri} for reading")
                } catch (e: SafIOException) {
                    tmp.delete()
                    throw e
                } catch (e: Exception) {
                    // openInputStream (and everything under it -- the
                    // underlying FileInputStream construction for a
                    // file://-backed real document in particular) is NOT
                    // guaranteed to only throw SafIOException: it throws
                    // whatever the real I/O layer throws (a raw
                    // FileNotFoundException on Android and under
                    // Robolectric alike, if the real file no longer exists
                    // -- e.g. deleted externally between listing and
                    // pulling). The openFileDescriptor attempt above is
                    // already swallow-and-fall-through on ANY exception
                    // since it's a best-effort fast path with this branch
                    // as its fallback; this branch has no further
                    // fallback, so its failures must surface as the same
                    // SafIOException every other failure path in this
                    // function uses -- otherwise a caller that only
                    // catches SafIOException (see
                    // ensureReadyOrStreamDirect's two catch clauses) sees
                    // a raw platform exception it never asked to handle
                    // leak straight through it uncaught.
                    tmp.delete()
                    throw SafIOException("pullFileIfMissing: failed to read ${realDoc.uri}", e)
                }
            }
            if (!tmp.renameTo(mirrored)) {
                mirrored.delete()
                if (!tmp.renameTo(mirrored)) {
                    tmp.delete()
                    throw SafIOException("pullFileIfMissing: could not finalize pulled file for ${realDoc.uri}")
                }
            }
            registry.markSynced(key)
            VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key pulled bytesCopied=$bytesCopied mirrorLengthAfter=${mirrored.length()}" }
            return mirrored
        }
    }

    /**
     * Cold-read entry point for [MirroredSafDocumentOps.resolveForRead].
     * Returns true once [realDoc]'s content is present in the local mirror
     * and safe to read from -- pulling it synchronously first when it's
     * small enough (below [LARGE_FILE_STREAM_THRESHOLD_BYTES]) that the
     * latency doesn't matter, same as before this existed.
     *
     * For a large not-yet-pulled file, returns false WITHOUT blocking:
     * kicks off (or joins, if one's already running for this exact file) a
     * background pull instead, so the caller can hand ChunkedFileEngine the
     * REAL document to stream directly from for this read -- via its
     * existing non-raw SAF fallback (openFileDescriptor/openInputStream),
     * see readRange()'s "SAF_PFD"/"SAF_STREAM" paths -- while the mirror
     * warms up in the background for the next open of this file.
     *
     * [onBackgroundPullPhase], when given, fires STARTED the moment a
     * background pull is actually kicked off for THIS call (not for a
     * pull some earlier caller already has in flight -- see the
     * pullsInFlight.add() guard below), and FINISHED/FAILED when that
     * same pull completes. This coordinator only ever sees real-SAF URIs,
     * so it has no (volId, virtualPath) to report -- that translation, and
     * deciding what to do with the phase (e.g. surface a "downloading"
     * indicator), is entirely the caller's job. See
     * [com.aeidolon.vaultexplorer.saf.MirrorPullEvents] for the one
     * consumer today.
     */
    fun ensureReadyOrStreamDirect(
        realDoc: DocumentFile,
        onBackgroundPullPhase: ((MirrorPullEvents.Phase) -> Unit)? = null,
    ): Boolean {
        val key = realDoc.uri.toString()
        if (registry.hasContent(key)) return true
        val size = realDoc.length()
        if (size < LARGE_FILE_STREAM_THRESHOLD_BYTES) {
            return try {
                pullFileIfMissing(realDoc)
                true
            } catch (e: SafIOException) {
                VeLog.w("MirrorTrace", e) { "ensureReadyOrStreamDirect: sync pull failed for $key (size=$size), streaming direct instead" }
                false
            }
        }
        if (pullsInFlight.add(key)) {
            VeLog.d("MirrorTrace") { "ensureReadyOrStreamDirect: uri=$key size=$size over threshold, streaming direct + background pull" }
            onBackgroundPullPhase?.invoke(MirrorPullEvents.Phase.STARTED)
            try {
                pullExecutor.execute {
                    try {
                        pullFileIfMissing(realDoc)
                        VeLog.d("MirrorTrace") { "ensureReadyOrStreamDirect: background pull complete for $key" }
                        pullsInFlight.remove(key)
                        onBackgroundPullPhase?.invoke(MirrorPullEvents.Phase.FINISHED)
                    } catch (e: Exception) {
                        VeLog.w("MirrorTrace", e) { "ensureReadyOrStreamDirect: background pull failed for $key" }
                        pullsInFlight.remove(key)
                        onBackgroundPullPhase?.invoke(MirrorPullEvents.Phase.FAILED)
                    } finally {
                        pullsInFlight.remove(key)
                    }
                }
            } catch (e: java.util.concurrent.RejectedExecutionException) {
                // Session tearing down -- nothing to warm up for any more.
                pullsInFlight.remove(key)
            }
        }
        // A pull for this exact file is already in flight from an earlier
        // call (pullsInFlight.add() above returned false) -- still false
        // (stream direct), but no STARTED fires here: the caller that
        // actually started it already got that notification, and firing
        // a second STARTED with no matching FINISHED/FAILED for THIS call
        // would leave a listener's "downloading" state stuck forever if
        // it treats phases as a per-call pair rather than a global flag.
        return false
    }

    // Both current callers (MirroredSafDocumentOps.listChildren/childOf) discard this
    // return value -- they only care about the side effect (mirror placeholders +
    // registrations populated) and re-read the actual listing from the local mirror
    // afterward. That's what lets the early-return below skip real work entirely
    // when another thread already did it while this one waited for the lock.
    fun pullListingIfMissing(realFolder: DocumentFile, mirroredParent: File): List<Pair<DocumentFile, File>> {
        val key = realFolder.uri.toString()
        if (registry.hasListed(key)) return emptyList()
        synchronized(folderLockFor(key)) {
            if (registry.hasListed(key)) return emptyList()
            mirroredParent.mkdirs()
            val realChildren = realOps.listChildren(realFolder)
            val realUris = realChildren.map { it.uri.toString() }.toSet()
            val children = realChildren.map { child ->
                val childKey = child.uri.toString()
                val mirrored = mirrorChildFor(child, mirroredParent, isDirectory = child.isDirectory)
                // This child is now confirmed present in an actual real-side
                // listing of its parent -- lift any neverListed protection
                // it was carrying (see MirrorRegistry.neverListed's doc
                // comment). No-op if it was never marked (an already-known
                // child rediscovered by an ordinary listing pass).
                registry.clearNeverListed(childKey)
                val realLength = child.length()
                val realMtime = child.lastModified()
                if (child.isDirectory) {
                    if (!mirrored.exists()) mirrored.mkdirs()
                } else {
                    if (!mirrored.exists()) {
                        mirrored.parentFile?.mkdirs()
                        mirrored.createNewFile()
                    }
                    // Delegates the "is this child's cached content actually
                    // stale" decision to MirrorRegistry.reconcileStaleContent,
                    // which treats SYNCED and PENDING_LOCAL_WRITE as one
                    // mutually-exclusive per-key state rather than two
                    // independently-checked sets -- a pending local write can
                    // no longer be mistaken for a stale synced entry and
                    // deleted out from under an in-flight write.
                    val stale = registry.reconcileStaleContent(
                        childKey = childKey,
                        mirrorLength = mirrored.length(),
                        mirrorLastModified = mirrored.lastModified(),
                        realLength = realLength,
                        realLastModified = realMtime,
                    )
                    if (stale) {
                        // If the local mirror already has the exact same non-zero size as the real file,
                        // it's not stale (it's our just-pushed content). Just sync the mtime.
                        if (mirrored.length() > 0L && mirrored.length() == realLength) {
                            registry.markSynced(childKey)
                        } else {
                            // Remote file changed on SAF; reset to a sparse placeholder matching real size
                            registry.forgetContent(childKey)
                            if (realLength > 0L) {
                                try {
                                    java.io.RandomAccessFile(mirrored, "rw").use { it.setLength(realLength) }
                                } catch (_: Exception) {
                                    mirrored.delete()
                                    mirrored.createNewFile()
                                }
                            } else {
                                mirrored.delete()
                                mirrored.createNewFile()
                            }
                        }
                    } else if (!registry.hasContent(childKey) && !registry.hasPendingLocalWrite(childKey)) {
                        // Cold file (not yet downloaded): set placeholder length so the UI previews real size
                        if (mirrored.length() != realLength && realLength > 0L) {
                            try {
                                java.io.RandomAccessFile(mirrored, "rw").use { it.setLength(realLength) }
                            } catch (_: Exception) {}
                        }
                    }
                    // Keep mirror timestamp synchronized with SAF's timestamp
                    if (realMtime > 0L) {
                        mirrored.setLastModified(realMtime)
                    }
                }
                child to mirrored
            }
            // Scoped to this folder's own known children via MirrorRegistry's
            // per-parent child index instead of scanning every registered
            // file in the vault -- see that index's doc comment.
            val staleKeys = registry.staleChildKeys(mirroredParent.absolutePath, realUris)
            for (staleKey in staleKeys) {
                if (registry.hasPendingLocalWrite(staleKey)) continue
                val staleFile = registry.forget(staleKey) ?: continue
                registry.clearListed(staleKey)
                VeLog.d("MirrorTrace") { "pullListingIfMissing: removing stale mirror entry uri=$staleKey path=${staleFile.absolutePath}" }
                try {
                    staleFile.deleteRecursively()
                } catch (e: Exception) {
                    VeLog.w("MirrorTrace", e) { "pullListingIfMissing: failed to delete stale mirror entry ${staleFile.absolutePath}" }
                }
            }
            // A neverListed child (see that flag's doc comment) absent from
            // THIS listing survived staleChildKeys' filter above -- correct
            // for the first miss, since it's more likely still propagating
            // through the real provider than genuinely gone. But the
            // protection has to expire, or a child that really was deleted
            // before its creation ever got listed would stay an
            // un-forgettable phantom mapping forever. One reprieve is
            // enough to cover the propagation-delay case this exists for;
            // clearing the flag here (rather than forgetting the mapping
            // outright) means a SECOND consecutive miss falls through to
            // the ordinary staleChildKeys path above on the next listing
            // pass and is reported stale like any other missing child --
            // still one full listing's worth of grace, just not unbounded.
            for (childKey in registry.childKeys(mirroredParent.absolutePath)) {
                if (childKey !in realUris) registry.clearNeverListed(childKey)
            }
            registry.markListed(key)
            return children
        }
    }

    fun hasListed(realFolder: DocumentFile): Boolean = registry.hasListed(realFolder.uri.toString())
    fun hasListed(uri: Uri): Boolean = registry.hasListed(uri.toString())
    fun hasListed(key: String): Boolean = registry.hasListed(key)
    
    fun markListedEmpty(realFolder: DocumentFile) {
        registry.markListed(realFolder.uri.toString())
    }

    fun invalidateListing(realFolder: DocumentFile) {
        val key = realFolder.uri.toString()
        registry.clearListed(key)
        realOps.invalidate(realFolder)
    }

    fun invalidateAll() {
        // registry.clearAllListed(), NOT registry.clear(): the latter would
        // also drop the URI<->mirror-file mapping and content state,
        // forcing a full re-pull of every already-mirrored file's bytes on
        // the next listing. invalidateAll's contract (see
        // realOps.invalidateAll(), which this mirrors) is "the LISTING may
        // be stale, re-list everything" -- not "the mirror's local copies
        // are gone".
        registry.clearAllListed()
        realOps.invalidateAll()
    }

    /**
     * Copies [mirrored]'s full contents into [targetUri] by opening it
     * directly via [Context.getContentResolver] in truncating ("wt") mode.
     * Returns the number of bytes actually copied.
     *
     * CAUTION: opening in "wt" mode truncates [targetUri] to 0 bytes the
     * instant it's opened, before anything is written -- if the copy that
     * follows fails partway (or [mirrored] can't be read at all), whatever
     * [targetUri] held before this call is already gone. This is safe to
     * call directly ONLY when [targetUri] has no prior content worth
     * protecting (a freshly-created, still-empty file) or when there is no
     * raw [File] available to stage a safer copy-then-rename against (see
     * [pushFileWrite]'s own use of this, which reserves the truncating
     * direct write for exactly those two cases and stages+renames
     * everywhere else).
     */
    private fun copyDirectTruncating(mirrored: File, targetUri: Uri): Long {
        var bytesCopied = 0L
        val pfd = try { context.contentResolver.openFileDescriptor(targetUri, "wt") } catch (_: Exception) { null }
        if (pfd != null) {
            try {
                pfd.use { fd ->
                    mirrored.inputStream().use { fis ->
                        java.io.FileOutputStream(fd.fileDescriptor).use { fos ->
                            bytesCopied = fis.copyTo(fos, COPY_BUFFER_SIZE)
                        }
                    }
                }
            } catch (e: Exception) {
                throw MirrorPushException("copyDirectTruncating: failed to write to file descriptor for $targetUri", e)
            }
        } else {
            context.contentResolver.openOutputStream(targetUri, "wt")?.use { out ->
                mirrored.inputStream().use { input -> bytesCopied = input.copyTo(out, COPY_BUFFER_SIZE) }
            } ?: throw MirrorPushException("copyDirectTruncating: could not open $targetUri for writing")
        }
        return bytesCopied
    }

    /**
     * Copies a complete local mirror to a SAF document and verifies that the
     * provider reports the full byte length after closing the output stream.
     * Some cloud providers acknowledge a write while leaving the document
     * empty or partially uploaded, so success from copyTo() alone is not a
     * sufficient commit signal. The mirror remains authoritative if all
     * attempts fail; the caller can then leave the write pending for retry.
     */
    private fun copyAndVerify(mirrored: File, targetUri: Uri): Long {
        var lastFailure: Exception? = null
        repeat(3) { index ->
            val attempt = index + 1
            try {
                val expectedLength = mirrored.length()
                val bytesCopied = copyDirectTruncating(mirrored, targetUri)
                if (bytesCopied != expectedLength || mirrored.length() != expectedLength) {
                    throw MirrorPushException(
                        "copyAndVerify: local mirror changed or copied incompletely for $targetUri " +
                            "(expected=$expectedLength, copied=$bytesCopied, current=${mirrored.length()})",
                    )
                }
                if (awaitRealLength(targetUri, expectedLength)) return bytesCopied
                throw MirrorPushException(
                    "copyAndVerify: provider did not report $expectedLength bytes for $targetUri after upload",
                )
            } catch (e: Exception) {
                lastFailure = e
                VeLog.w("MirrorTrace", e) {
                    "copyAndVerify: attempt $attempt/3 failed for $targetUri"
                }
                if (attempt < 3) Thread.sleep(250L * attempt)
            }
        }
        throw MirrorPushException("copyAndVerify: failed to upload and verify $targetUri after 3 attempts", lastFailure)
    }

    private inline fun <T> withPushActivity(block: () -> T): T {
        val activityId = MirrorPushEvents.begin()
        try {
            return block()
        } finally {
            MirrorPushEvents.finish(activityId)
        }
    }

    fun pushFileWrite(mirrored: File, realParent: DocumentFile?, existingRealDoc: DocumentFile?, displayName: String, mimeType: String) =
        withPushActivity {
            pushFileWriteInternal(mirrored, realParent, existingRealDoc, displayName, mimeType)
        }

    private fun pushFileWriteInternal(mirrored: File, realParent: DocumentFile?, existingRealDoc: DocumentFile?, displayName: String, mimeType: String) {
        // Defensive re-stat with a short retry -- but only when
        // existingRealDoc is non-null, i.e. this push is expected to carry
        // real content (a completed write being synced back to an already-
        // existing real file). For a brand-new file (existingRealDoc ==
        // null) this is the empty-placeholder push made at creation time,
        // before any content has been written -- 0 bytes is the correct,
        // expected value there, not a race to retry around. Retrying
        // anyway cost every single newly-created file up to ~300ms of pure
        // sleep for a result that could never change: confirmed against
        // production MirrorTrace logs, where every retry on a fresh
        // placeholder read back the same genuine 0.
        //
        // This retry is NOT a substitute for proper synchronization -- it
        // exists because the writer that produces `mirrored`'s bytes and
        // this push can be arbitrarily separated in time and thread (a
        // batched import defers its content push to endBatchWrite; a
        // background raw-I/O write for cryfs goes through
        // CryfsBlockStore's own executor), with no completion handoff
        // between them beyond "some earlier call finished". A stat
        // observed here can legitimately still be racing a not-yet-visible
        // write on some devices/filesystems; retrying a few times over a
        // short window is a real mitigation for that, not a workaround for
        // something better solved with a lock -- there's nothing to take a
        // lock on from in here, since the writer that matters isn't
        // necessarily this call's caller.
        var observedLength = mirrored.length()
        var retriedAndStillZero = false
        if (existingRealDoc != null && observedLength == 0L && mirrored.exists()) {
            for (attempt in 1..5) {
                Thread.sleep(20L * attempt)
                val recheck = mirrored.length()
                VeLog.w("MirrorTrace") { "pushFileWrite: displayName=$displayName mirroredLength read 0 on first stat, retry $attempt -> $recheck" }
                if (recheck > 0L) {
                    observedLength = recheck
                    break
                }
            }
            // All 5 retries (up to 300ms total) still read 0. This is
            // ambiguous, not necessarily wrong: it's either a genuine
            // empty-content write to an existing file (truncating a
            // document to empty is a legitimate user action) or a race
            // that simply outlasted the retry window. Previously this
            // fell through silently and pushed the 0 bytes as if it were
            // confirmed-legitimate -- indistinguishable in the logs from
            // the fast, single-stat 0 a real empty write produces. Flag it
            // explicitly instead so a real "did we just truncate someone's
            // file" incident has something in MirrorTrace to search for,
            // without refusing to push (that would break legitimate empty
            // writes, which are equally plausible from here).
            if (observedLength == 0L) {
                retriedAndStillZero = true
                VeLog.w("MirrorTrace") {
                    "pushFileWrite: displayName=$displayName mirroredLength still 0 after all retries -- " +
                        "proceeding as an UNCONFIRMED empty write (could be legitimate, could be an unresolved race)"
                }
            }
        }
        VeLog.d("MirrorTrace") { "pushFileWrite: displayName=$displayName mirroredPath=${mirrored.absolutePath} mirroredLength=$observedLength existingRealDoc=${existingRealDoc?.uri}" }
        // Hoisted so the catch blocks below can see whether a NEW real
        // file was actually created by THIS call (freshlyCreatedTarget !=
        // null) before something later in the same call failed --
        // realOps.createFileSafe succeeding is itself success, it's the
        // COPY into that freshly-created file that can still fail after
        // the fact (disk full, permission revoked mid-write, provider
        // hiccup). Without tracking this, a copy failure right after a
        // successful creation left a stray empty file on the real SAF
        // tree with no mirror counterpart and nothing in MirrorRegistry --
        // confirmed via MirroredSafDocumentOps.createFileSafe's own catch
        // block, which only ever cleans up the MIRROR side, never a real
        // file this function might have already created before failing.
        // (It does self-heal: the next listing of that folder discovers
        // the orphan as an ordinary new child and mirrors it fresh -- so
        // this was never data loss, just a spurious empty file surviving
        // a failed create until the next listing. Still worth not doing.)
        var freshlyCreatedTarget: DocumentFile? = null
        try {
            var target = existingRealDoc ?: run {
                val parent = realParent ?: throw MirrorPushException("pushFileWrite: no real parent for new file $displayName")
                val created = realOps.createFileSafe(parent, mimeType, displayName)
                    ?: throw MirrorPushException("pushFileWrite: could not create $displayName on real SAF tree")
                freshlyCreatedTarget = created
                created
            }
            var bytesCopied = 0L
            if (existingRealDoc != null) {
                // Overwriting an EXISTING real file with real prior
                // content: never open it in a truncating mode directly.
                // "wt" (and even bare "w" on many providers/OS versions)
                // truncates the file to 0 bytes the instant it's opened --
                // before a single byte of the new content has been
                // written -- so if the copy that follows fails for ANY
                // reason (disk full, permission revoked mid-write,
                // provider hiccup, or simply `mirrored` being unreadable,
                // which is exactly what a MirrorSyncCoordinatorTest case
                // caught: a failed push silently destroyed the existing
                // real file's content, leaving it empty, not merely
                // failing to update it), the user's prior content is
                // already gone with nothing successfully written in its
                // place. This is the same class of bug as CVE-2023-21036
                // ("aCropalypse"): open-in-truncating-mode-then-write is
                // unsafe for any overwrite of an existing file precisely
                // because the truncate and the write are not atomic with
                // each other.
                //
                // Where a raw File is available for the real target (the
                // common case for this app's raw-file-backed real trees),
                // stage the full copy into a sibling temp file first and
                // only replace the original via an atomic rename once the
                // ENTIRE copy has succeeded -- the original's bytes are
                // never touched until the replacement is fully ready.
                // Where no raw File is available (a genuine content://-only
                // provider with no filesystem escape hatch), there is no
                // rename to fall back to; this still uses the direct
                // truncating write for that case, same risk as before this
                // fix -- a real, currently-unaddressed gap for that
                // specific provider shape, called out explicitly rather
                // than silently carried forward.
                val rawTarget = com.aeidolon.vaultexplorer.RawFileResolver.getRawFile(context, target)
                if (rawTarget != null && rawTarget.exists()) {
                    val stagingTmp = File(rawTarget.parentFile, rawTarget.name + ".pushing")
                    try {
                        mirrored.inputStream().use { input ->
                            stagingTmp.outputStream().use { out -> bytesCopied = input.copyTo(out, COPY_BUFFER_SIZE) }
                        }
                        if (bytesCopied != observedLength || stagingTmp.length() != observedLength || mirrored.length() != observedLength) {
                            throw MirrorPushException(
                                "pushFileWrite: staged copy of $displayName changed or was incomplete " +
                                    "(expected=$observedLength, copied=$bytesCopied, staged=${stagingTmp.length()}, source=${mirrored.length()})",
                            )
                        }
                        if (!stagingTmp.renameTo(rawTarget)) {
                            rawTarget.delete()
                            if (!stagingTmp.renameTo(rawTarget)) {
                                throw MirrorPushException("pushFileWrite: could not finalize overwrite of ${target.uri} (staging rename failed)")
                            }
                        }
                    } finally {
                        stagingTmp.delete()
                    }
                } else {
                    // A content:// provider with no raw file. Overwriting a
                    // real document that already holds content is not
                    // reliable everywhere: Filen takes the first content
                    // write into a document but silently keeps the old
                    // bytes on later overwrites, so after lock/unlock the
                    // item comes back empty. Verify the overwrite and, if
                    // it didn't take, replace the document instead.
                    val known = realContent[target.uri.toString()]
                    val overwritesContent = observedLength > 0L && (
                        known == true ||
                            (known == null && (try { target.length() } catch (_: Exception) { 0L }) > 0L)
                        )
                    val authority = target.uri.authority.orEmpty()
                    var replace = overwritesContent && authority in unreliableOverwriteAuthorities
                    if (!replace) {
                        try {
                            bytesCopied = copyAndVerify(mirrored, target.uri)
                        } catch (e: MirrorPushException) {
                            if (!overwritesContent) throw e
                            VeLog.w("MirrorTrace") {
                                "pushFileWrite: in-place overwrite of ${target.uri} could not be verified -- " +
                                    "replacing documents on $authority from now on (${e.message})"
                            }
                            unreliableOverwriteAuthorities.add(authority)
                            replace = true
                        }
                    }
                    if (replace) {
                        val created = replaceRealDocument(mirrored, target, realParent, displayName, mimeType)
                        freshlyCreatedTarget = created
                        target = created
                        bytesCopied = copyAndVerify(mirrored, created.uri)
                    }
                }
            } else {
                // Freshly-created empty file (freshlyCreatedTarget != null,
                // via the `run` block above): no prior content exists to
                // protect, so a failed copy just leaves it empty -- exactly
                // how it started -- and the orphan-rollback in the catch
                // blocks below deletes it entirely on failure anyway. The
                // truncate-before-write risk this whole branch exists to
                // avoid does not apply here. An empty new file needs no
                // write at all: opening it just to write 0 bytes changes
                // nothing.
                if (observedLength > 0L) bytesCopied = copyAndVerify(mirrored, target.uri)
            }
            // Propagate the mirror's intended lastModified timestamp to the real SAF target
            // so the real file doesn't get stuck with the current time of the push operation.
            registerExisting(target, mirrored)
            registry.markPushed(target.uri.toString())
            realContent[target.uri.toString()] = observedLength > 0L
            // Sync the mirror's timestamp to match SAF's current write timestamp
            val targetMtime = target.lastModified()
            if (targetMtime > 0L) {
                mirrored.setLastModified(targetMtime)
            }
            if (freshlyCreatedTarget != null) {
                // See MirrorRegistry.neverListed's doc comment: this
                // document was just created on the real tree by THIS call,
                // so it hasn't necessarily propagated to the provider's own
                // listing yet -- protect its registration from being
                // dropped by a pullListingIfMissing sweep that races that
                // propagation, until a listing actually confirms it (see
                // clearNeverListed in pullListingIfMissing below).
                registry.markNeverListed(target.uri.toString())
            }
            if (bytesCopied == 0L && observedLength > 0L) {
                // The retry above saw real content moments before the
                // actual copy, but the copy itself still moved 0 bytes --
                // this is now a genuinely inconsistent state worth failing
                // loudly on. Keep freshlyCreatedTarget set until after this
                // check so the catch block rolls back the empty real file
                // created by this call.
                throw MirrorPushException("pushFileWrite: copied 0 bytes for $displayName despite mirror showing ${observedLength} bytes moments earlier")
            }
            // The copy and consistency checks succeeded (or this was a
            // legitimate empty file), so later bookkeeping failures should
            // not roll back this newly-created real file.
            freshlyCreatedTarget = null
            if (retriedAndStillZero && bytesCopied == 0L) {
                VeLog.w("MirrorTrace") { "pushFileWrite: displayName=$displayName confirmed 0-byte push after unconfirmed retries -- treating as legitimate empty write" }
            }
        } catch (e: MirrorPushException) {
            VeLog.e("MirrorTrace", e) { "pushFileWrite: displayName=$displayName FAILED" }
            freshlyCreatedTarget?.let { orphan ->
                VeLog.w("MirrorTrace") { "pushFileWrite: displayName=$displayName rolling back orphaned real file ${orphan.uri} created by this call before it failed" }
                runCatching { realOps.deleteRecursively(orphan) }
            }
            throw e
        } catch (e: Exception) {
            VeLog.e("MirrorTrace", e) { "pushFileWrite: displayName=$displayName FAILED" }
            freshlyCreatedTarget?.let { orphan ->
                VeLog.w("MirrorTrace") { "pushFileWrite: displayName=$displayName rolling back orphaned real file ${orphan.uri} created by this call before it failed" }
                runCatching { realOps.deleteRecursively(orphan) }
            }
            throw MirrorPushException("pushFileWrite failed for $displayName", e)
        }
    }

    /** Pushes [mirrored]'s content to [realDoc] now. */
    fun pushContentNow(mirrored: File, realDoc: DocumentFile) =
        pushFileWrite(mirrored, null, realDoc, mirrored.name, "application/octet-stream")

    /**
     * Pushes [mirrored]'s content to [realDoc] -- except for the first
     * content push of a file we just created, which is held back for
     * [DEFERRED_PUSH_DELAY_MS] (write-behind). A new file is normally
     * written more than once in quick succession (create + header, then
     * the content; or a scratch ".tmp" that is renamed right after
     * writing), and some providers (Filen) only honour the FIRST content
     * write into a document and upload in the background: a later
     * overwrite is ignored, and a rename of a document with an upload in
     * flight leaves the content behind under the old name. Holding the
     * push back lets a following write open ([markPendingLocalWrite]) or
     * rename ([claimDeferred]) supersede it, so the content reaches the
     * provider in a single write, into the final document.
     */
    fun pushContent(mirrored: File, realDoc: DocumentFile) {
        if (realContent[realDoc.uri.toString()] == false) scheduleDeferred(realDoc.uri.toString())
        else pushContentNow(mirrored, realDoc)
    }

    private fun scheduleDeferred(key: String) = synchronized(deferLock) {
        deferred.remove(key)?.cancel(false)
        deferred[key] = deferExecutor.schedule(
            { runDeferred(key) }, DEFERRED_PUSH_DELAY_MS, java.util.concurrent.TimeUnit.MILLISECONDS,
        )
    }

    /** True if a deferred push for [realDoc] was pending; the caller then
     *  owns pushing that content (or must call [rescheduleDeferred]). */
    fun claimDeferred(realDoc: DocumentFile): Boolean = claimDeferred(realDoc.uri.toString())

    private fun claimDeferred(key: String): Boolean = synchronized(deferLock) {
        deferred.remove(key)?.also { it.cancel(false) } != null
    }

    private fun cancelDeferred(mirrored: File) {
        registry.keyForMirrorPath(mirrored.absolutePath)?.let { claimDeferred(it) }
    }

    fun rescheduleDeferred(realDoc: DocumentFile) = scheduleDeferred(realDoc.uri.toString())

    /** Carries the content knowledge over when a rename changed the URI. */
    fun migrateContentKnowledge(old: DocumentFile, renamed: DocumentFile) {
        if (old.uri == renamed.uri) return
        realContent.remove(old.uri.toString())?.let { realContent[renamed.uri.toString()] = it }
    }

    private fun runDeferred(key: String) {
        if (!claimDeferred(key)) return
        val mirrored = registry.mirrorFor(key) ?: return
        val realDoc = DocumentFile.fromSingleUri(context, Uri.parse(key)) ?: return
        try {
            pushContentNow(mirrored, realDoc)
        } catch (e: Exception) {
            // The write stays PENDING_LOCAL_WRITE, so the mirror content is
            // protected from re-listing; a later write or teardown retries.
            VeLog.e("MirrorTrace", e) { "deferred push FAILED for $key -- real SAF file was NOT updated" }
        }
    }

    /** Polls (about 1.5 s at most) until the real document reports
     *  [expected] bytes. False means it never did. */
    private fun awaitRealLength(uri: Uri, expected: Long): Boolean {
        // Fast path for file:// URIs (local storage, unit tests under Robolectric)
        if (uri.scheme == "file") {
            val file = uri.path?.let { File(it) }
            return file != null && file.exists() && file.length() == expected
        }
        for (wait in longArrayOf(0L, 150L, 350L, 500L, 500L)) {
            if (wait > 0L) Thread.sleep(wait)
            val length = try {
                context.contentResolver.query(
                    uri,
                    arrayOf(DocumentsContract.Document.COLUMN_SIZE),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
                }
            } catch (e: Exception) {
                VeLog.w("MirrorTrace", e) { "awaitRealLength: failed to query $uri" }
                null
            } ?: try {
                context.contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize }
            } catch (_: Exception) {
                null
            }
            if (length == expected) return true
        }
        return false
    }

    /** Deletes [old] on the real tree and creates an empty document with
     *  the same name in the same real parent; the caller then writes the
     *  content into it -- a first write into a new document, which every
     *  provider handles. Leaves the mirror file alone. */
    private fun replaceRealDocument(
        mirrored: File,
        old: DocumentFile,
        realParentHint: DocumentFile?,
        displayName: String,
        mimeType: String,
    ): DocumentFile {
        val parent = realParentHint
            ?: mirrored.parentFile?.let { realUriFor(it) }?.let { DocumentFile.fromSingleUri(context, it) }
            ?: throw MirrorPushException("replaceRealDocument: no real parent for $displayName")
        val name = old.name ?: displayName
        val oldKey = old.uri.toString()
        realOps.deleteRecursively(old)
        var created: DocumentFile? = null
        for (attempt in 0..3) {
            if (attempt > 0) Thread.sleep(150L * attempt)
            created = try { realOps.createFileSafe(parent, mimeType, name) } catch (_: Exception) { null }
            if (created != null) break
        }
        val replacement = created
            ?: throw MirrorPushException("replaceRealDocument: could not recreate $name after deleting ${old.uri}")
        registry.forget(oldKey)
        realContent.remove(oldKey)
        return replacement
    }

    fun pushCreateDirectory(realParent: DocumentFile, name: String): DocumentFile {
        return withPushActivity {
            realOps.createDirectorySafe(realParent, name)
                ?: throw MirrorPushException("pushCreateDirectory: could not create $name on real SAF tree")
        }
    }

    fun pushRename(realDoc: DocumentFile, newName: String, realParent: DocumentFile?): DocumentFile {
        return withPushActivity {
            try {
                realOps.renameDocumentAndGet(realDoc, newName, realParent)
            } catch (e: Exception) {
                throw MirrorPushException("pushRename failed for ${realDoc.uri} -> $newName", e)
            }
        }
    }

    fun pushMove(realDoc: DocumentFile, realOldParent: DocumentFile, realNewParent: DocumentFile) {
        withPushActivity {
            try {
                realOps.movePhysicalDocument(realDoc, realOldParent, realNewParent)
            } catch (e: Exception) {
                throw MirrorPushException("pushMove failed for ${realDoc.uri}", e)
            }
        }
    }

    fun pushDelete(realDoc: DocumentFile) {
        withPushActivity {
            claimDeferred(realDoc)
            realContent.remove(realDoc.uri.toString())
            try {
                realOps.deleteRecursively(realDoc)
            } catch (e: Exception) {
                throw MirrorPushException("pushDelete failed for ${realDoc.uri}", e)
            } finally {
                registry.forget(realDoc.uri.toString())
            }
        }
    }
}
