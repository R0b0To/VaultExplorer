package com.aeidolon.vaultexplorer

import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.util.Log
import com.aeidolon.vaultexplorer.saf.UriToPath
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import kotlin.concurrent.withLock

/**
 * Tools tab's Container Splitter produces a `<name>.001`, `<name>.002`, ...
 * part sequence ([SplitJoinHandlers.handleSplitContainer]); until now the
 * only way back in was [SplitJoinHandlers.handleJoinContainer] rejoining
 * them into one file first. This class skips that step: it exposes the
 * on-disk part sequence as one seekable file via [LocalSplitFuseCallback]
 * and hands the resulting proxy fd straight to
 * [ContainerEngine.unlockFile], exactly like [VaultUnlockHandlers.handleUnlockContainer]
 * hands it a plain single-file fd -- see [LocalSplitFuseCallback]'s doc
 * comment for why every existing mounted-volume code path (browsing,
 * editing, document provider, lock) stays completely unaware the backing
 * store is split across several files on disk. Mirrors the shape of the
 * experimental cloud plugin's `CloudMountHandlers.handleUnlockRemoteChunkedVault`
 * (proxy-fd-then-unlockFile), just with [SplitPartResolver] walking a
 * local folder instead of an RPC listing a remote one.
 */
class SplitContainerMountHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    // Own HandlerThread/Handler for the FUSE callback's binder thread,
    // same reasoning as CloudMountHandlers.fuseHandler: ProxyFileDescriptorCallback
    // methods must not run on the calling (ioExecutor) thread that's
    // waiting on them, and reusing the main looper would serialize
    // every disk read/write behind UI work.
    private val fuseThread = HandlerThread("split-container-fuse").apply { start() }
    private val fuseHandler = Handler(fuseThread.looper)

    /**
     * Mounts a split container directly from its first part, without ever
     * materializing a joined copy on disk. Args mirror
     * [VaultUnlockHandlers.handleUnlockContainer] (password, pim,
     * displayName, hidden-volume options, etc. via [parseUnlockArgs]) plus
     * this call's own `firstPartUri` -- the same "first part" SAF pick
     * [SplitJoinHandlers.handleJoinContainer] already uses, so the Dart
     * side can reuse its existing "pick first part" flow for both.
     */
    fun handleUnlockSplitContainer(call: MethodCall, result: MethodChannel.Result) {
        val firstPartUriStr = call.argument<String>("firstPartUri")
        if (firstPartUriStr == null) {
            result.error("INVALID_ARGS", "firstPartUri is required", null)
            return
        }
        val args = parseUnlockArgs(call, result, firstPartUriStr, "firstPartUri") ?: return

        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(firstPartUriStr)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
            return
        }
        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))

        ioExecutor.execute {
            var proxyPfd: ParcelFileDescriptor? = null
            try {
                val uri = Uri.parse(firstPartUriStr)
                val firstFile = UriToPath.getRawFile(activity, uri)
                    ?: throw Exception(
                        "Couldn't access the picked file directly on disk. " +
                            "Grant \"All files access\" for this app in system settings and try again."
                    )
                val parts = SplitPartResolver.resolvePartSequence(firstFile)

                val fuseCallback = LocalSplitFuseCallback(
                    parts = parts,
                    onReleased = { ContainerSessionRegistry.removeSession(targetVolId) },
                )
                val storageManager = activity.getSystemService(StorageManager::class.java)
                proxyPfd = storageManager.openProxyFileDescriptor(
                    ParcelFileDescriptor.MODE_READ_WRITE, fuseCallback, fuseHandler)

                val keyfileFds = nativeOps.openKeyfileFds(args.keyfilePaths)
                val hiddenKeyfileFds =
                    if (args.protectHiddenVolume) nativeOps.openKeyfileFds(args.hiddenKeyfilePaths) else null
                val fd = proxyPfd.detachFd() // ownership -> native, same convention as VaultUnlockHandlers.handleUnlockContainer

                if (parts.size > 1) {
                    Log.i(TAG, "Mounting split container directly across ${parts.size} parts (volId=$targetVolId)")
                }

                val files = ContainerSessionRegistry.locks[targetVolId].writeLock().withLock {
                    ContainerEngine.unlockFile(
                        fd, args.password, args.pim, targetVolId, args.cipherId, args.hashId, args.preservedKey, keyfileFds, args.readOnly,
                        if (args.protectHiddenVolume) args.hiddenPassword ?: "" else null,
                        args.hiddenPim, args.hiddenCipherId, args.hiddenHashId, hiddenKeyfileFds,
                    )
                }

                activity.runOnUiThread {
                    if (files != null) {
                        ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                            uri = firstPartUriStr,
                            volId = targetVolId,
                            cachedFilesList = files.toList(),
                            displayName = args.displayName ?: displayNameFor(parts.first()),
                            documentProvider = args.docProvider,
                            readOnly = args.readOnly,
                        )
                        ContainerSessionRegistry.applyAutoMountFolders(targetVolId, args.autoMountFolders)
                        val hasFolderMounts = ContainerSessionRegistry.activeSessions[targetVolId]
                            ?.subFolderMounts?.isNotEmpty() == true
                        if (args.docProvider || hasFolderMounts) {
                            activity.contentResolver.notifyChange(
                                DocumentsContract.buildRootsUri(
                                    "com.aeidolon.vaultexplorer.documents"), null)
                        }
                        val fmt = ContainerEngine.format(targetVolId).wireName
                        result.success(mapOf(
                            "volId" to targetVolId,
                            "files" to files.toList(),
                            "matchedCipherId" to ContainerEngine.matchedCipherId(targetVolId),
                            "matchedHashId" to ContainerEngine.matchedHashId(targetVolId),
                            "containerFormat" to fmt,
                            "partCount" to parts.size,
                        ))
                    } else {
                        result.error("AUTH_FAIL",
                            if (args.protectHiddenVolume)
                                "Incorrect password/keyfiles, or the hidden volume password/keyfiles did not match"
                            else
                                "Incorrect password/keyfiles or invalid container", null)
                    }
                }
            } catch (e: Exception) {
                if (proxyPfd != null) runCatching { proxyPfd.close() }
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    // Mirrors handleSplitContainer's own `.NNN` suffix it wrote in the
    // first place -- strips it back off so a mount that skipped
    // handleJoinContainer entirely still shows the pre-split display
    // name by default, same as a joined-then-unlocked file would.
    private fun displayNameFor(firstPart: File): String =
        Regex("""^(.*)\.(\d+|part\d+)$""", RegexOption.IGNORE_CASE)
            .find(firstPart.name)?.groupValues?.get(1) ?: firstPart.name

    fun onActivityDestroyed() {
        fuseThread.quitSafely()
    }

    private companion object {
        const val TAG = "SplitContainerMount"
    }
}
