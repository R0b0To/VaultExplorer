package com.aeidolon.vaultexplorer.saf

/**
 * Cross-cutting notification for a mirrored SAF vault's background
 * content pull -- see [MirrorSyncCoordinator.ensureReadyOrStreamDirect].
 *
 * Exists so a UI-facing consumer (currently [com.aeidolon.vaultexplorer.
 * engine.NativePlayerManager], for the "video won't start / stuck
 * thumbnail with no feedback" symptom) can be told a large cold file is
 * being pulled in the background, WITHOUT the saf/ package knowing
 * anything about Media3, EventChannels, or Flutter. MirrorSyncCoordinator
 * only knows real-SAF URIs; the (volId, virtualPath) pair a player cares
 * about is a session-layer concept, so the session's getPhysicalFileForRead
 * (CryptomatorSession/GocryptfsSession) is what translates one into the
 * other -- see the emit call sites there.
 *
 * Deliberately NOT a Flutter EventChannel/StreamHandler itself: this class
 * has zero Android-framework or plugin dependencies, so saf/ and the
 * cryptomator/gocryptfs session classes -- which have no reason to know a
 * Flutter engine exists -- can depend on it directly. NativePlayerManager
 * is the (sole, for now) bridge to the outside world.
 */
object MirrorPullEvents {
    enum class Phase { STARTED, FINISHED, FAILED }

    fun interface Listener {
        /** [volId]/[virtualPath] identify the vault-relative file this
         *  pull is for -- the same identifiers a player was opened with. */
        fun onMirrorPull(volId: Int, virtualPath: String, phase: Phase)
    }

    // Single slot, not a list: today there is exactly one place in the app
    // that can be actively playing/streaming a large cold file at a time
    // (one NativePlayerManager instance -- see MainActivity's `by lazy`).
    // A list would silently accumulate stale listeners across player
    // lifecycles for no present benefit; if a second concurrent consumer
    // shows up later this can become a CopyOnWriteArrayList instead.
    @Volatile
    private var listener: Listener? = null

    fun setListener(l: Listener?) {
        listener = l
    }

    fun emit(volId: Int, virtualPath: String, phase: Phase) {
        listener?.onMirrorPull(volId, virtualPath, phase)
    }
}
