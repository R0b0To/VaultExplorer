package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.VeLog
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

class MirrorPushException(message: String, cause: Throwable? = null) : Exception(message, cause)

class MirrorSyncCoordinator(
    private val context: Context,
    sessionTag: String,
    val realOps: SafDocumentOps,
) {
    companion object {
        /** Buffer size for the tmp-file-then-rename pull/push copies below.
         *  Kotlin's `copyTo` default (8KB) means far more read()/write()
         *  round trips than necessary for a large file streamed over a
         *  ContentResolver pipe -- bumped to cut that overhead on big
         *  pulls/pushes. */
        private const val COPY_BUFFER_SIZE = 256 * 1024

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

    val mirrorRoot: File = File(File(context.filesDir, "vault_mirrors"), sessionTag)
    private val uriToMirror = ConcurrentHashMap<String, File>()
    // Reverse index of uriToMirror, keyed by mirror absolute path -- kept in
    // lock-step via link()/unlink() below. Exists so realUriFor() and the
    // alias check in mirrorChildFor() are O(1) instead of a linear scan over
    // every file the coordinator has ever seen. That scan didn't matter at
    // the scale of a single folder, but this coordinator's whole purpose is
    // serving a document-provider mount, where an external app (a gallery/
    // media scanner) typically walks the ENTIRE exposed tree -- which made a
    // full-vault crawl O(n^2) in total file count (confirmed against a large
    // test vault: each newly-discovered child paid a scan over every file
    // already registered so far).
    private val mirrorPathToKey = ConcurrentHashMap<String, String>()
    // Per-parent index of the keys currently registered under a given
    // mirrored directory -- lets pullListingIfMissing's stale-entry sweep
    // scan just that folder's known children instead of every file in the
    // vault. Keyed by the mirrored parent directory's absolute path.
    private val childKeysByParent = ConcurrentHashMap<String, MutableSet<String>>()
    private val listedFolders = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val pulledContent = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    // Mirror-file absolute paths with a local write in flight that hasn't
    // been pushed back to the real SAF tree yet. See markPendingLocalWrite()
    // and its call sites (CryptomatorSession/GocryptfsSession
    // getOrCreatePhysicalFileForWrite) for the full story: pulledContent
    // means "mirror and real are in sync", and it gets set the moment ANY
    // push succeeds -- including the very first, empty-placeholder push a
    // brand-new file gets at creation time, before its real content has
    // even been written. If something forces a directory re-listing
    // (pullListingIfMissing, below) while a raw-I/O writer is still filling
    // in that content -- e.g. a batched import that deliberately defers its
    // content push until endBatchWrite, with an intervening
    // setLastModifiedTime call that resolves the parent directory -- the
    // stale pulledContent flag makes the reconciliation logic read "the
    // real file changed under us, re-pull it" from what is actually just
    // the real file not having the new content yet. That deletes and
    // recreates the mirror file empty, destroying the pending write with
    // no error raised anywhere (confirmed via production MirrorTrace logs:
    // a raw java.io.File(path).length() on the mirror path reads the
    // correct, just-written size right after the write, then reads back 0
    // once endBatchWrite finally pushes -- with nothing in between except
    // exactly this reconciliation path running). A path in this set always
    // overrides a stale pulledContent flag.
    private val pendingLocalWrites = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    // Per-key monitors guarding pullFileIfMissing -- without these, two
    // threads racing a cold pull of the SAME file (e.g. ensureContentPulled
    // from a readWhole() call and the background pull kicked off by
    // ensureReadyOrStreamDirect below) both see pulledContent not yet
    // containing the key and both copy into the SAME ".pulling" tmp path at
    // once. Previously this was implicitly safe only because the one caller
    // (ChunkedFileEngine's getPhysicalFileForRead) always ran under that
    // engine's own per-path lock; ensureReadyOrStreamDirect's background
    // pulls run on a separate executor, outside that lock, so the guard
    // needs to live here instead.
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

    private fun link(key: String, mirrored: File) {
        val previous = uriToMirror.put(key, mirrored)
        if (previous != null && previous.absolutePath != mirrored.absolutePath) {
            mirrorPathToKey.remove(previous.absolutePath, key)
            previous.parentFile?.absolutePath?.let { childKeysByParent[it]?.remove(key) }
        }
        mirrorPathToKey[mirrored.absolutePath] = key
        mirrored.parentFile?.absolutePath?.let {
            childKeysByParent.computeIfAbsent(it) { java.util.concurrent.ConcurrentHashMap.newKeySet() }.add(key)
        }
    }

    private fun unlink(key: String): File? {
        val removed = uriToMirror.remove(key) ?: return null
        mirrorPathToKey.remove(removed.absolutePath, key)
        removed.parentFile?.absolutePath?.let { childKeysByParent[it]?.remove(key) }
        return removed
    }

    fun markPendingLocalWrite(mirrored: File) {
        pendingLocalWrites.add(mirrored.absolutePath)
    }

    fun reset(realVaultRoot: DocumentFile) {
        if (mirrorRoot.exists()) mirrorRoot.deleteRecursively()
        mirrorRoot.mkdirs()
        uriToMirror.clear()
        mirrorPathToKey.clear()
        childKeysByParent.clear()
        listedFolders.clear()
        pulledContent.clear()
        pendingLocalWrites.clear()
        pullLocks.clear()
        folderLocks.clear()
        pullsInFlight.clear()
        val rootMirror = File(mirrorRoot, "root")
        rootMirror.mkdirs()
        link(realVaultRoot.uri.toString(), rootMirror)
    }

    fun teardown() {
        uriToMirror.clear()
        mirrorPathToKey.clear()
        childKeysByParent.clear()
        listedFolders.clear()
        pulledContent.clear()
        pendingLocalWrites.clear()
        pullLocks.clear()
        folderLocks.clear()
        pullsInFlight.clear()
        pullExecutor.shutdownNow()
        try {
            mirrorRoot.deleteRecursively()
        } catch (e: Exception) {
            VeLog.e("MirrorSyncCoordinator", e) { "teardown failed to delete mirror at ${mirrorRoot.absolutePath}" }
        }
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
        val existing = uriToMirror[key]
        val expectedName = sanitizedMirrorName(realDoc.name)
        if (existing != null) {
            if (existing.name == expectedName && existing.parentFile == mirroredParent) {
                return existing
            }
            pulledContent.remove(key)
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
        // listing. Migrate registration (and any already-pulled marker) to
        // the new key instead of leaving the old one behind to be treated
        // as stale. O(1) via mirrorPathToKey instead of scanning every
        // registered file for one whose target File matches.
        if (existing == null) {
            val aliasKey = mirrorPathToKey[mirrored.absolutePath]
            if (aliasKey != null) {
                unlink(aliasKey)
                if (pulledContent.remove(aliasKey)) pulledContent.add(key)
            }
        }
        link(key, mirrored)
        return mirrored
    }

    fun registerExisting(realDoc: DocumentFile, mirrored: File) {
        link(realDoc.uri.toString(), mirrored)
    }

    fun realUriFor(mirrored: File): Uri? =
        mirrorPathToKey[mirrored.absolutePath]?.let { Uri.parse(it) }

    fun hasContent(realDoc: DocumentFile): Boolean = pulledContent.contains(realDoc.uri.toString())

    fun pullFileIfMissing(realDoc: DocumentFile): File {
        val key = realDoc.uri.toString()
        val mirrored = uriToMirror[key]
            ?: throw SafIOException("pullFileIfMissing: no mirror mapping for ${realDoc.uri}")
        if (pulledContent.contains(key)) {
            VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key already pulled, mirrorLength=${mirrored.length()}" }
            return mirrored
        }
        // Guards concurrent callers of the SAME key -- e.g. a readWhole()'s
        // ensureContentPulled racing the background pull
        // ensureReadyOrStreamDirect kicks off below, or two large-file cold
        // reads landing on the same file at once. Without this, both would
        // pass the pulledContent check above, then both write into the SAME
        // ".pulling" tmp path concurrently.
        synchronized(pullLockFor(key)) {
            // Re-check: another thread may have finished the pull while we
            // were waiting for the lock.
            if (pulledContent.contains(key)) {
                VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key pulled by another thread while waiting, mirrorLength=${mirrored.length()}" }
                return mirrored
            }
            VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key not yet pulled, fetching from real SAF" }
            mirrored.parentFile?.mkdirs()
            val tmp = File(mirrored.parentFile, mirrored.name + ".pulling")
            var bytesCopied = 0L
            context.contentResolver.openInputStream(realDoc.uri)?.use { input ->
                tmp.outputStream().use { out -> bytesCopied = input.copyTo(out, COPY_BUFFER_SIZE) }
            } ?: throw SafIOException("pullFileIfMissing: could not open ${realDoc.uri} for reading")
            if (!tmp.renameTo(mirrored)) {
                tmp.delete()
                throw SafIOException("pullFileIfMissing: could not finalize pulled file for ${realDoc.uri}")
            }
            pulledContent.add(key)
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
        if (pulledContent.contains(key)) return true
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
                        onBackgroundPullPhase?.invoke(MirrorPullEvents.Phase.FINISHED)
                    } catch (e: Exception) {
                        VeLog.w("MirrorTrace", e) { "ensureReadyOrStreamDirect: background pull failed for $key" }
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
        if (listedFolders.contains(key)) return emptyList()
        synchronized(folderLockFor(key)) {
            if (listedFolders.contains(key)) return emptyList()
            mirroredParent.mkdirs()
            val realChildren = realOps.listChildren(realFolder)
            val realUris = realChildren.map { it.uri.toString() }.toSet()
            val children = realChildren.map { child ->
                val childKey = child.uri.toString()
                val mirrored = mirrorChildFor(child, mirroredParent, isDirectory = child.isDirectory)
                if (child.isDirectory) {
                    if (!mirrored.exists()) mirrored.mkdirs()
                } else {
                    if (!mirrored.exists()) {
                        mirrored.parentFile?.mkdirs()
                        mirrored.createNewFile()
                    }
                    if (pulledContent.contains(childKey) && mirrored.absolutePath !in pendingLocalWrites) {
                        val realLen = child.length()
                        val realMod = child.lastModified()
                        if (mirrored.length() != realLen || (realMod > 0 && mirrored.lastModified() != realMod)) {
                            pulledContent.remove(childKey)
                            mirrored.delete()
                            mirrored.createNewFile()
                        }
                    }
                }
                child to mirrored
            }
            // Scoped to this folder's own known children via childKeysByParent
            // instead of scanning uriToMirror's entire (vault-wide) entry set --
            // see that index's doc comment above.
            val staleKeys = childKeysByParent[mirroredParent.absolutePath]
                .orEmpty()
                .filter { it !in realUris }
            for (staleKey in staleKeys) {
                val staleFile = unlink(staleKey) ?: continue
                pulledContent.remove(staleKey)
                listedFolders.remove(staleKey)
                VeLog.d("MirrorTrace") { "pullListingIfMissing: removing stale mirror entry uri=$staleKey path=${staleFile.absolutePath}" }
                try {
                    staleFile.deleteRecursively()
                } catch (e: Exception) {
                    VeLog.w("MirrorTrace", e) { "pullListingIfMissing: failed to delete stale mirror entry ${staleFile.absolutePath}" }
                }
            }
            listedFolders.add(key)
            return children
        }
    }

    fun hasListed(realFolder: DocumentFile): Boolean = listedFolders.contains(realFolder.uri.toString())

    fun markListedEmpty(realFolder: DocumentFile) {
        listedFolders.add(realFolder.uri.toString())
    }

    fun invalidateListing(realFolder: DocumentFile) {
        val key = realFolder.uri.toString()
        listedFolders.remove(key)
        realOps.invalidate(realFolder)
    }

    fun invalidateAll() {
        listedFolders.clear()
        realOps.invalidateAll()
    }

    fun pushFileWrite(mirrored: File, realParent: DocumentFile?, existingRealDoc: DocumentFile?, displayName: String, mimeType: String) {
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
        var observedLength = mirrored.length()
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
        }
        VeLog.d("MirrorTrace") { "pushFileWrite: displayName=$displayName mirroredPath=${mirrored.absolutePath} mirroredLength=$observedLength existingRealDoc=${existingRealDoc?.uri}" }
        try {
            val target = existingRealDoc ?: run {
                val parent = realParent ?: throw MirrorPushException("pushFileWrite: no real parent for new file $displayName")
                realOps.createFileSafe(parent, mimeType, displayName)
                    ?: throw MirrorPushException("pushFileWrite: could not create $displayName on real SAF tree")
            }
            var bytesCopied = 0L
            context.contentResolver.openOutputStream(target.uri, "wt")?.use { out ->
                mirrored.inputStream().use { input -> bytesCopied = input.copyTo(out, COPY_BUFFER_SIZE) }
            } ?: throw MirrorPushException("pushFileWrite: could not open ${target.uri} for writing")
            registerExisting(target, mirrored)
            pulledContent.add(target.uri.toString())
            pendingLocalWrites.remove(mirrored.absolutePath)
            if (bytesCopied == 0L && observedLength > 0L) {
                // The retry above saw real content moments before the
                // actual copy, but the copy itself still moved 0 bytes --
                // this is now a genuinely inconsistent state worth failing
                // loudly on rather than silently leaving a 0-byte file on
                // real storage.
                throw MirrorPushException("pushFileWrite: copied 0 bytes for $displayName despite mirror showing ${observedLength} bytes moments earlier")
            }
        } catch (e: MirrorPushException) {
            VeLog.e("MirrorTrace", e) { "pushFileWrite: displayName=$displayName FAILED" }
            throw e
        } catch (e: Exception) {
            VeLog.e("MirrorTrace", e) { "pushFileWrite: displayName=$displayName FAILED" }
            throw MirrorPushException("pushFileWrite failed for $displayName", e)
        }
    }

    fun pushCreateDirectory(realParent: DocumentFile, name: String): DocumentFile {
        return realOps.createDirectorySafe(realParent, name)
            ?: throw MirrorPushException("pushCreateDirectory: could not create $name on real SAF tree")
    }

    fun pushRename(realDoc: DocumentFile, newName: String, realParent: DocumentFile?): DocumentFile {
        try {
            return realOps.renameDocumentAndGet(realDoc, newName, realParent)
        } catch (e: Exception) {
            throw MirrorPushException("pushRename failed for ${realDoc.uri} -> $newName", e)
        }
    }

    fun pushMove(realDoc: DocumentFile, realOldParent: DocumentFile, realNewParent: DocumentFile) {
        try {
            realOps.movePhysicalDocument(realDoc, realOldParent, realNewParent)
        } catch (e: Exception) {
            throw MirrorPushException("pushMove failed for ${realDoc.uri}", e)
        }
    }

    fun pushDelete(realDoc: DocumentFile) {
        try {
            realOps.deleteRecursively(realDoc)
        } catch (e: Exception) {
            throw MirrorPushException("pushDelete failed for ${realDoc.uri}", e)
        } finally {
            val key = realDoc.uri.toString()
            uriToMirror.remove(key)?.let { pendingLocalWrites.remove(it.absolutePath) }
            pulledContent.remove(key)
        }
    }
}