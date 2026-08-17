package com.aeidolon.vaultexplorer.handlers

import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.container.ContainerSession
import com.aeidolon.vaultexplorer.container.SubFolderMount
import com.aeidolon.vaultexplorer.MainActivity

/**
 * Mounts/unmounts a single folder inside an already-unlocked container as
 * its own DocumentsProvider root — independent of the whole-container
 * [ContainerSession.documentProvider] toggle handled in [VaultUnlockHandlers].
 */
class FolderDocumentProviderHandlers(private val activity: MainActivity) {

    companion object {
        private const val AUTHORITY = "com.aeidolon.vaultexplorer.documents"
    }

    private fun notifyRootsChanged() {
        activity.contentResolver.notifyChange(DocumentsContract.buildRootsUri(AUTHORITY), null)
    }

    fun handleMountContainerFolder(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val fatPath = call.argument<String>("path")
        val displayName = call.argument<String>("displayName")
        if (uriString == null || fatPath.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "filePath and path are required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        val session = volId?.let { ContainerSessionRegistry.activeSessions[it] }
        if (session == null) {
            result.success(false)
            return
        }
        session.subFolderMounts[fatPath] = SubFolderMount(
            fatPath = fatPath,
            displayName = displayName ?: fatPath.substringAfterLast("/"),
            autoMount = session.subFolderMounts[fatPath]?.autoMount ?: false,
        )
        notifyRootsChanged()
        result.success(true)
    }

    fun handleUnmountContainerFolder(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val fatPath = call.argument<String>("path")
        if (uriString == null || fatPath.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "filePath and path are required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        val session = volId?.let { ContainerSessionRegistry.activeSessions[it] }
        val removed = session?.subFolderMounts?.remove(fatPath) != null
        if (removed) notifyRootsChanged()
        result.success(removed)
    }

    fun handleGetMountedContainerFolders(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        if (uriString == null) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        val session = volId?.let { ContainerSessionRegistry.activeSessions[it] }
        result.success(session?.subFolderMounts?.keys?.toList() ?: emptyList<String>())
    }
}
