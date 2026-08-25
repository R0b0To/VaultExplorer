package com.aeidolon.vaultexplorer.saf

import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Pure bookkeeping for [MirrorSyncCoordinator]: which real-SAF URI maps to
 * which local mirror [File], which folders have been listed, and whether a
 * given mirror file's content is in sync with (or ahead of) the real tree.
 *
 * Deliberately free of any Android/ContentResolver/DocumentFile dependency
 * -- everything here is `String`/[File] keys and plain collections -- so it
 * can be constructed and exercised directly from a JVM unit test without
 * Robolectric. [MirrorSyncCoordinator] owns all the actual I/O (pulling
 * bytes over a ContentResolver, pushing writes back) and the per-key/
 * per-folder lock maps that serialize concurrent *operations*; this class
 * only owns the bookkeeping *state* those operations read and update.
 *
 * ## Content state as one per-key value, not two independently-mutated sets
 *
 * A mirror file's content state used to be tracked as membership in two
 * separate sets: `pulledContent` ("mirror matches the real file we last
 * synced") and `pendingLocalWrites` ("a local write is in flight, not yet
 * pushed"). Correctness depended on every call site remembering that a key
 * in `pendingLocalWrites` overrides a stale `pulledContent` entry for the
 * same key -- documented in a comment, not enforced by the types. That gap
 * is exactly what caused a real, production-observed bug: a directory
 * re-listing ([MirrorSyncCoordinator.pullListingIfMissing]'s per-child
 * reconciliation, using [reconcileStaleContent] below) running between a
 * raw-I/O write finishing and its content push being pushed back would see
 * the OLD
 * `pulledContent` flag (still true from before this write started), read
 * the mismatched size as "the real file changed under us," and delete the
 * not-yet-pushed mirror content -- destroying the pending write with no
 * error anywhere. `pendingLocalWrites` was added as a second flag that
 * happens to be checked first at the one call site that mattered, rather
 * than fixing the fact that "in sync" and "local write in flight, don't
 * touch me" were two independent booleans that could both be set (or
 * either could be stale) for the same key at once.
 *
 * [ContentState] makes that a single value: a key is [ContentState.SYNCED],
 * [ContentState.PENDING_LOCAL_WRITE], or absent (not yet pulled) --
 * mutually exclusive by construction, so "pending beats a stale synced
 * flag" no longer needs to be remembered at each call site; there is no
 * "both" state left to get out of sync.
 */
class MirrorRegistry {

    enum class ContentState {
        /** Mirror content matches the last-known real-file content. */
        SYNCED,

        /** A local write is in flight for this mirror file and has not yet
         *  been pushed back to the real tree. Overrides any prior
         *  [SYNCED] state for the same key -- see the class doc comment. */
        PENDING_LOCAL_WRITE,
    }

    private val uriToMirror = ConcurrentHashMap<String, File>()

    // Reverse index of uriToMirror, keyed by mirror absolute path -- kept in
    // lock-step via link()/unlink() below. Exists so mirrorPathToKey lookups
    // are O(1) instead of a linear scan over every file ever registered.
    // That scan didn't matter at the scale of a single folder, but this
    // registry's whole purpose is serving a document-provider mount, where
    // an external app (a gallery/media scanner) typically walks the ENTIRE
    // exposed tree -- which made a full-vault crawl O(n^2) in total file
    // count (confirmed against a large test vault: each newly-discovered
    // child paid a scan over every file already registered so far).
    private val mirrorPathToKey = ConcurrentHashMap<String, String>()

    // Per-parent index of the keys currently registered under a given
    // mirrored directory -- lets a stale-entry sweep after a listing scan
    // just that folder's known children instead of every file in the vault.
    // Keyed by the mirrored parent directory's absolute path.
    private val childKeysByParent = ConcurrentHashMap<String, MutableSet<String>>()

    private val listedFolders = ConcurrentHashMap.newKeySet<String>()

    // Single map replacing the old pulledContent/pendingLocalWrites pair --
    // see the class doc comment. Absent key == "not yet pulled".
    private val contentState = ConcurrentHashMap<String, ContentState>()

    fun link(key: String, mirrored: File) {
        val previous = uriToMirror.put(key, mirrored)
        if (previous != null && previous.absolutePath != mirrored.absolutePath) {
            mirrorPathToKey.remove(previous.absolutePath, key)
            previous.parentFile?.absolutePath?.let { childKeysByParent[it]?.remove(key) }
        }
        mirrorPathToKey[mirrored.absolutePath] = key
        mirrored.parentFile?.absolutePath?.let {
            childKeysByParent.computeIfAbsent(it) { ConcurrentHashMap.newKeySet() }.add(key)
        }
    }

    fun unlink(key: String): File? {
        val removed = uriToMirror.remove(key) ?: return null
        mirrorPathToKey.remove(removed.absolutePath, key)
        removed.parentFile?.absolutePath?.let { childKeysByParent[it]?.remove(key) }
        return removed
    }

    fun mirrorFor(key: String): File? = uriToMirror[key]

    fun keyForMirrorPath(mirrorAbsolutePath: String): String? = mirrorPathToKey[mirrorAbsolutePath]

    fun childKeys(mirroredParentAbsolutePath: String): Set<String> =
        childKeysByParent[mirroredParentAbsolutePath].orEmpty()

    fun hasListed(key: String): Boolean = listedFolders.contains(key)

    fun markListed(key: String) {
        listedFolders.add(key)
    }

    fun clearListed(key: String) {
        listedFolders.remove(key)
    }

    /** Clears every folder's "has been listed" flag, forcing the next
     *  access to each to re-list -- WITHOUT touching the URI<->mirror-file
     *  mapping or content state (see [clear] for the version that drops
     *  everything). This is what [MirrorSyncCoordinator.invalidateAll]
     *  needs: "the listing may be stale" is not "the mirror's local copies
     *  are gone". */
    fun clearAllListed() {
        listedFolders.clear()
    }

    /** True once [key]'s mirror content is known to match the real file,
     *  i.e. [markSynced] has been called and nothing has since called
     *  [markPendingLocalWrite] or [forget] for the same key. */
    fun hasContent(key: String): Boolean = contentState[key] == ContentState.SYNCED

    /** True while a local write for [key] is in flight and not yet pushed
     *  back -- see the class doc comment for why this always overrides a
     *  same-key [SYNCED] state rather than the two being independent. */
    fun hasPendingLocalWrite(key: String): Boolean = contentState[key] == ContentState.PENDING_LOCAL_WRITE

    /** A single atomic read of [key]'s current [ContentState] (or null if
     *  never set). [hasContent] and [hasPendingLocalWrite] are each
     *  individually atomic against [contentState], but calling both back
     *  to back is NOT an atomic pair -- under concurrent writers, the
     *  value can change between the two calls, so a caller checking "is it
     *  exactly one of these" (e.g. an invariant check in a test) needs
     *  this instead of `hasContent(key) && hasPendingLocalWrite(key)`,
     *  which can observe a torn read across two different actual states
     *  even though [contentState] only ever holds one value per key at any
     *  given instant. */
    fun contentStateOf(key: String): ContentState? = contentState[key]

    fun markSynced(key: String) {
        // A pending local write always wins: this call means "content is
        // now known to match the real tree", which by definition can't be
        // true yet for a write that hasn't been pushed. Silently no-op
        // rather than clobbering PENDING_LOCAL_WRITE out from under an
        // in-flight write that just hasn't called markPushed() yet.
        contentState.merge(key, ContentState.SYNCED) { existing, new ->
            if (existing == ContentState.PENDING_LOCAL_WRITE) existing else new
        }
    }

    fun markPendingLocalWrite(key: String) {
        contentState[key] = ContentState.PENDING_LOCAL_WRITE
    }

    /** Call once a pending local write has been pushed back to the real
     *  tree: the write is no longer "pending", and content is now known to
     *  match what was just pushed. */
    fun markPushed(key: String) {
        contentState[key] = ContentState.SYNCED
    }

    fun forgetContent(key: String) {
        contentState.remove(key)
    }

    /** Moves whatever [ContentState] is registered under [fromKey] (if any)
     *  to [toKey], removing it from [fromKey]. Used when a SAF provider
     *  hands back a new canonical URI for what is really the same
     *  already-mirrored file (see [MirrorSyncCoordinator.mirrorChildFor]'s
     *  doc comment) -- the content state, whatever it is, describes the
     *  underlying file and should follow it to the new key rather than
     *  being reset to "not yet pulled" or left behind under a key that's
     *  about to be treated as stale and deleted. */
    fun migrateContentState(fromKey: String, toKey: String) {
        contentState.remove(fromKey)?.let { contentState[toKey] = it }
    }

    /** Drops all bookkeeping for [key]: the mirror mapping and its content
     *  state. Returns the mirror [File] that was registered, if any. */
    fun forget(key: String): File? {
        contentState.remove(key)
        return unlink(key)
    }

    /**
     * Reconciles [contentState] for a directory's children against a fresh
     * real-side listing: any child whose real length/lastModified no longer
     * matches what the mirror last observed is dropped back to "not yet
     * pulled" -- UNLESS it has a [ContentState.PENDING_LOCAL_WRITE], which
     * always wins (see the class doc comment; this is the fix for the
     * production bug that method documents). Returns the keys that were
     * reconciled (dropped), for the caller to delete the corresponding
     * mirror files.
     */
    fun reconcileStaleContent(
        childKey: String,
        mirrorLength: Long,
        mirrorLastModified: Long,
        realLength: Long,
        realLastModified: Long,
    ): Boolean {
        if (contentState[childKey] != ContentState.SYNCED) return false
        val changed = mirrorLength != realLength ||
            (realLastModified > 0 && mirrorLastModified != realLastModified)
        if (!changed) return false
        contentState.remove(childKey)
        return true
    }

    /** Keys currently linked under [mirroredParentAbsolutePath] that are
     *  NOT in [stillPresentKeys] -- i.e. mirror entries whose real-side
     *  counterpart is gone from a fresh listing. Does not mutate anything;
     *  caller is expected to [forget] each returned key and delete its
     *  mirror file. */
    fun staleChildKeys(mirroredParentAbsolutePath: String, stillPresentKeys: Set<String>): List<String> =
        childKeys(mirroredParentAbsolutePath).filter { it !in stillPresentKeys }

    fun clear() {
        uriToMirror.clear()
        mirrorPathToKey.clear()
        childKeysByParent.clear()
        listedFolders.clear()
        contentState.clear()
    }
}