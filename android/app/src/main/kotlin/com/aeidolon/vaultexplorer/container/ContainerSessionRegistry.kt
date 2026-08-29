package com.aeidolon.vaultexplorer.container
import com.aeidolon.vaultexplorer.handlers.VaultUnlockHandlers

/**
 * A single folder inside a container that has been exposed as its own
 * DocumentsProvider root, independent of the container-wide
 * [ContainerSession.documentProvider] toggle.
 */
data class SubFolderMount(
    val fatPath: String,       // path within the container; never empty
    val displayName: String,   // shown as the SAF root title
    var autoMount: Boolean = false,
)

data class ContainerSession(
    val uri: String,
    val volId: Int,
    var cachedFilesList: List<String>,
    var displayName: String? = null,
    var documentProvider: Boolean = false,
    val isUsbSource: Boolean = false,
    val readOnly: Boolean = false,
    // Set once at unlock time by ContainerLifecycleCore (unlockContainer via
    // ContainerEngine.format, unlockDirectoryVault via
    // DirectoryVaultFormat.asContainerFormat) -- the single source of truth
    // for "what format is this session", used by both
    // VaultAutomationReceiver.reportAutomationUnlock and
    // VaultUnlockHandlers.handleGetActiveContainerSessions rather than each
    // re-deriving it independently. Null only for sessions predating this
    // field (shouldn't happen in practice; every unlock path sets it).
    var containerFormat: ContainerFormat? = null,
    val subFolderMounts: MutableMap<String, SubFolderMount> = mutableMapOf(),
    // Persistent, mount-order-independent identity for this vault, handed
    // out as the SAF root ID and folded into every document ID this vault
    // produces (see ContainerDocumentsProvider). Deliberately NOT [volId]:
    // volId is just "the first free slot" at the moment of unlock
    // (ContainerSessionRegistry.getFreeVolumeId), so locking vault A then
    // vault B and unlocking them back in the *other* order hands B the
    // slot A used to have and vice versa. A third-party file manager that
    // bookmarks a SAF root/document ID (e.g. via
    // takePersistableUriPermission) would then silently open the wrong
    // vault next session. [uri] is the one thing about a vault that stays
    // the same no matter what order it's mounted in -- it's the same key
    // ContainerRepository (Dart side) already uses to identify a saved
    // vault record -- so deriving from it here gives every SAF-facing ID
    // a value that survives relocking in any order. Defaulted rather than
    // threaded through every `ContainerSession(...)` call site, since
    // Kotlin evaluates a data class's default parameter expression per
    // instance from the other constructor args already in scope.
    val stableId: String = stableIdFor(uri),
)

/**
 * Derives [ContainerSession.stableId] from a vault's storage [uri]. Pulled
 * out of the class body (rather than a private fun on the companion
 * object) purely so it's usable as a default-parameter expression on
 * [ContainerSession] itself, which is declared above [ContainerSessionRegistry]
 * in this file -- top-level declarations in the same file see each other
 * regardless of order, so the forward reference from the data class is fine.
 *
 * A SHA-256 digest of the URI, not the URI itself: content:// tree URIs can
 * be long, can contain ':' (the same character [DocumentId]'s wire format
 * uses as a field separator), and are path info we'd rather not echo
 * verbatim into a value handed to arbitrary third-party SAF clients.
 * Truncated to 16 hex chars -- a root/document ID field, not a security
 * boundary, so full collision resistance isn't needed, just "won't collide
 * across the handful of vaults one person has". Prefixed with a non-hex
 * character ("v") so parsing code (see [DocumentId.parse]'s legacy
 * fallback) can always tell a stable ID apart from a bare-integer volId on
 * sight, rather than having to guess from its value.
 */
fun stableIdFor(uri: String): String {
    val digest = java.security.MessageDigest.getInstance("SHA-256")
        .digest(uri.toByteArray(Charsets.UTF_8))
    return "v" + digest.joinToString("") { "%02x".format(it) }.take(16)
}

object ContainerSessionRegistry {

    val MAX_VOLUMES: Int by lazy { ContainerEngine.maxVolumes() }

    val locks: Array<java.util.concurrent.locks.ReentrantReadWriteLock> by lazy { 
        Array(MAX_VOLUMES) { java.util.concurrent.locks.ReentrantReadWriteLock(true) } 
    }
    // ConcurrentHashMap, not mutableMapOf: writes happen from the UI thread
    // on unlock (VaultUnlockHandlers.kt) but from ioExecutor on lock
    // (ContainerEngine.lock -> removeSession), and the per-volId locks in
    // [locks] guard native calls only, not this map. Mirrors the same
    // precedent already established by VaultBackendRegistry.sessions
    // (VaultBackend.kt) for the pure-Kotlin backends.
    val activeSessions = java.util.concurrent.ConcurrentHashMap<Int, ContainerSession>()

    /**
     * Releases and immediately re-acquires volume [volId]'s write lock.
     * Called once per ~2MB chunk from native mid-writeBackFile (see
     * yieldContainerWriteLock in jni_callbacks.h/jni_runtime.cpp) -- the
     * Kotlin-layer counterpart to the C++ volumes[volId].mutex yield done
     * in writeBackFile's progress callback (filesystem_bridge.cpp).
     *
     * ContainerFileSystem.writeBackFile wraps the *entire* native call in
     * withWriteLock. Without this, listDirectory's withReadLock (and every
     * other reader) stalls for the whole transfer no matter what the C++
     * mutex does underneath -- that Kotlin-level lock, not the C++ one, is
     * what actually produces the "loading page until the transfer is
     * done" symptom, since it's acquired before the JNI call is even made
     * and only released after writeBackFile returns.
     *
     * Safe to call re-entrantly on the thread that already holds the
     * write lock -- ReentrantReadWriteLock.WriteLock supports exactly
     * that. [locks] is constructed fair (see above), so a thread already
     * queued here (e.g. a listDirectory call that arrived first) is
     * served ahead of this one on re-acquire; no explicit yield/sleep
     * needed for that guarantee.
     *
     * Must only be called by a thread that already holds [volId]'s write
     * lock, and that holds *no other* lock (read or write) on the same
     * [locks] entry -- calling it without write-lock ownership throws
     * IllegalMonitorStateException on the unlock() below. writeBackFile's
     * call site satisfies this: unlike copyFile, it only ever takes one
     * lock on one volume (withWriteLock(volId) with no nested
     * withReadLock underneath), so there's no outstanding read hold on
     * this lock for the unlock()/lock() pair below to collide with. If a
     * future caller ever wraps this in a nested withReadLock the way
     * copyFile does, use [yieldCopyLocksBriefly]'s same-volume branch as
     * the template instead -- see the deadlock this exact mistake caused
     * there, explained in that function's comment.
     */
    @JvmStatic
    fun yieldWriteLockBriefly(volId: Int) {
        if (volId < 0 || volId >= MAX_VOLUMES) return
        val writeLock = locks[volId].writeLock()
        writeLock.unlock()
        writeLock.lock()
    }

    /**
     * Copy/move counterpart of [yieldWriteLockBriefly]. Releases and
     * re-acquires [destVolId]'s write lock and, when the copy spans two
     * different containers, [srcVolId]'s read lock too -- called once per
     * ~2MB buffer iteration from native mid-copyFile (see
     * yieldContainerCopyLocks in jni_callbacks.h/jni_runtime.cpp), the
     * copyFile entry's counterpart to writeBackFile's
     * yieldContainerWriteLock.
     *
     * ContainerFileSystem.copyFile wraps the *entire* native call in
     * withWriteLock(destVolId) { withReadLock(srcVolId) { ... } }. Without
     * this, listDirectory's withReadLock on either volume stalls for the
     * whole transfer no matter what the C++ locks do underneath -- same
     * root cause writeBackFile had before it got this same treatment (see
     * the comment on [yieldWriteLockBriefly]).
     *
     * Released and re-acquired in the same order [ContainerFileSystem
     * .copyFile] originally took them -- dest write outer, src read inner
     * -- so a thread pausing mid-copy can never observe a different lock
     * order than the one it (and every other copy) started with.
     *
     * When [srcVolId] equals [destVolId], `destWrite` and `srcRead` are
     * two different lock objects on the very same underlying
     * [ReentrantReadWriteLock] (locks[destVolId]) -- copyFile's nested
     * withReadLock(srcVolId) inside withWriteLock(destVolId) is a
     * same-thread write-to-read downgrade acquisition on that one lock,
     * still outstanding here, not a second independent lock. That makes
     * the read hold matter just as much in this branch as in the
     * two-different-volumes branch below: fully releasing the write lock
     * (destWrite.unlock() dropping the hold count to zero) while this
     * thread's outer read lock on that same object is still held is a
     * documented ReentrantReadWriteLock deadlock -- "a thread holding a
     * read lock cannot acquire a write lock" applies here even though
     * it's *this* thread's own read hold, because the JDK's write-lock
     * acquisition only proceeds once the read lock is free for every
     * holder, itself included (this is why upgrade-via-unlock-then-relock
     * is unsupported, unlike the write-then-read downgrade copyFile does
     * on the way in). An earlier version of this function treated the
     * same-object case as "only the write lock is touched" reasoning that
     * inverted this: reusing the same lock object is exactly why the read
     * hold can't be ignored, not a reason it can be. So this branch now
     * yields both locks -- read inner, write outer -- exactly like the
     * two-different-volumes branch, just on the same underlying
     * ReentrantReadWriteLock instead of two.
     *
     * Must only be called by a thread that already holds these locks in
     * this configuration -- calling it without that ownership throws
     * IllegalMonitorStateException on the unlock() calls below, rather
     * than silently corrupting either lock's hold count.
     */
    @JvmStatic
    fun yieldCopyLocksBriefly(srcVolId: Int, destVolId: Int) {
        if (destVolId < 0 || destVolId >= MAX_VOLUMES) return
        val destWrite = locks[destVolId].writeLock()
        if (srcVolId < 0 || srcVolId >= MAX_VOLUMES) {
            destWrite.unlock()
            destWrite.lock()
            return
        }
        // Same object when srcVolId == destVolId (see the comment above);
        // two distinct ReentrantReadWriteLocks' read locks otherwise.
        // Either way, release inner-to-outer (read first, write second)
        // and reacquire outer-to-inner (write first, read second), which
        // is correct and safe in both cases: same-lock write-then-read is
        // the supported downgrade direction, so reacquiring write while
        // still holding no read (already released above) and then
        // downgrading again via read.lock() cannot deadlock the way
        // fully-releasing-write-under-an-outstanding-read did.
        val srcRead = locks[srcVolId].readLock()
        srcRead.unlock()
        destWrite.unlock()
        // Reacquire outer-to-inner, mirroring the original
        // withWriteLock(destVolId) { withReadLock(srcVolId) { ... } }
        // nesting, so this can't invert lock order against another thread
        // doing the same yield for a concurrent copy.
        destWrite.lock()
        srcRead.lock()
    }

    fun isUnlocked(volId: Int) = activeSessions.containsKey(volId)
    fun hasAnyActiveSessions() = activeSessions.isNotEmpty()
    fun getFreeVolumeId(): Int? = (0 until MAX_VOLUMES).firstOrNull { !activeSessions.containsKey(it) }
    fun getSessionByUri(uri: String): ContainerSession? = activeSessions.values.find { it.uri == uri }
    fun getVolumeIdByUri(uri: String): Int? = activeSessions.entries.find { it.value.uri == uri }?.key

    /**
     * Reverse of [stableIdFor]: finds the currently-mounted volume, if
     * any, whose vault this stable ID names. Returns null both when the
     * ID is unrecognized and when it names a vault that simply isn't
     * mounted right now (locked) -- callers treat that the same as
     * "document not found", which is the right SAF answer either way: a
     * client asking for a locked vault's contents should fail exactly
     * like it would if the document had been deleted, not get a stale
     * peek at whichever *other* vault happens to be sitting in some slot.
     */
    fun getVolumeIdByStableId(stableId: String): Int? =
        activeSessions.entries.find { it.value.stableId == stableId }?.key

    fun removeSession(volId: Int) { activeSessions.remove(volId) }

    /**
     * Re-establishes subfolder document-provider roots right after unlock,
     * for folders the person previously marked "auto-mount on unlock".
     * No-op if [paths] is null/empty or the session doesn't exist.
     */
    fun applyAutoMountFolders(volId: Int, paths: List<String>?) {
        if (paths.isNullOrEmpty()) return
        val session = activeSessions[volId] ?: return
        for (path in paths) {
            if (path.isBlank()) continue
            session.subFolderMounts[path] = SubFolderMount(
                fatPath = path,
                displayName = path.substringAfterLast("/"),
                autoMount = true,
            )
        }
    }
}