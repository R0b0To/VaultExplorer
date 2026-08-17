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