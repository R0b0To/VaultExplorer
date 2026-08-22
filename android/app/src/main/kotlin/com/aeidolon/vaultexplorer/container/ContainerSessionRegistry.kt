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
    val subFolderMounts: MutableMap<String, SubFolderMount> = mutableMapOf(),
)

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