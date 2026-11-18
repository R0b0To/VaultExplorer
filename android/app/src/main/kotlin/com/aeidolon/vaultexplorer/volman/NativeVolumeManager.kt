package com.aeidolon.vaultexplorer.volman

import com.aeidolon.vaultexplorer.NativeEngine

/**
 * JNI surface of the platform-neutral volume manager (cpp/volman, bridged by
 * cpp/jni/volman_bridge.cpp).
 *
 * The manager holds unlocked volumes of *both* families behind one interface and does the
 * dispatch, locking and cross-volume work in C++, so that a desktop front-end gets exactly the
 * same behaviour without re-implementing [com.aeidolon.vaultexplorer.container.ContainerEngine].
 * Android moves over one operation at a time; today that is copying a file between volumes.
 *
 * Slots are attached lazily, right before use ([nativeAttachBlock] / [nativeAttachFolderVault]),
 * and cleaned up by the native side itself: a slot whose container was locked, or whose vault was
 * closed, is dropped on the next attach. Nothing has to be told when a volume is locked.
 */
internal object NativeVolumeManager {
    /** [nativeCopyFile] results. */
    const val COPY_OK = 0
    const val COPY_FAILED = 1
    /** A slot is empty or its volume was locked: nothing was copied, use the Kotlin path. */
    const val COPY_NOT_ATTACHED = 2
    const val COPY_CANCELLED = 3

    val isAvailable: Boolean = NativeEngine.isLoaded && try {
        nativeInit()
        true
    } catch (_: UnsatisfiedLinkError) {
        false
    }

    @JvmStatic external fun nativeInit()

    /** Engine block-device volume [volId] into manager slot [volId]. False if it is not unlocked or the slot belongs to another session. */
    @JvmStatic external fun nativeAttachBlock(volId: Int, tag: String): Boolean

    /** The folder vault behind a [com.aeidolon.vaultexplorer.foldervault.NativeFolderVault] handle into manager slot [volId]; the session is shared, not copied. */
    @JvmStatic external fun nativeAttachFolderVault(volId: Int, handle: Long, tag: String): Boolean

    @JvmStatic external fun nativeIsAttached(volId: Int, tag: String): Boolean

    /**
     * One file between two attached volumes, through memory only. Replaces the destination; a failed
     * or cancelled copy removes what it created. Progress and cancellation follow [opId] (0 = untracked),
     * on the same channels as every other copy ([com.aeidolon.vaultexplorer.bridge.CopyProgressBridge],
     * [com.aeidolon.vaultexplorer.cancellation.CopyCancellation]). Returns one of the COPY_ constants.
     */
    @JvmStatic external fun nativeCopyFile(srcVol: Int, srcPath: String, dstVol: Int, dstPath: String, opId: Int): Int
}
