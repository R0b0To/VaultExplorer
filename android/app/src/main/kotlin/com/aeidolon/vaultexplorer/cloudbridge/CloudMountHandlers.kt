package com.aeidolon.vaultexplorer.cloudbridge

import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.util.Log
import com.aeidolon.vaultexplorer.ContainerEngine
import com.aeidolon.vaultexplorer.ContainerSession
import com.aeidolon.vaultexplorer.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.parseUnlockArgs
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.ExecutorService
import kotlin.concurrent.withLock

/**
 * Backs VaultExplorer's "Cloud Storage" add-vault tab (§5). Everything
 * here is additive to [com.aeidolon.vaultexplorer.VaultUnlockHandlers] —
 * a remote-chunked volume becomes, the moment [handleUnlockRemoteChunkedVault]
 * returns, an ordinary [ContainerSession] that
 * [com.aeidolon.vaultexplorer.VaultUnlockHandlers.handleLockContainer] and
 * every other existing file-browser/editor code path already knows how
 * to handle — see [CloudFuseCallback]'s doc comment for why.
 */
class CloudMountHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    val client = VaultCloudBridgeClient(activity.applicationContext)

    private val fuseThread = HandlerThread("cloudbridge-fuse").apply { start() }
    private val fuseHandler = Handler(fuseThread.looper)

    private val scope = CoroutineScope(Dispatchers.IO)

    init {
        client.onSessionInvalidated = { accountId, remoteVaultPath, reason ->
            val key = "$accountId:$remoteVaultPath"
            val volId = ContainerSessionRegistry.getVolumeIdByCloudVaultKey(key)
            if (volId != null) {
                Log.w(TAG, "cloud session invalidated for volId $volId ($reason) — locking")
                ioExecutor.execute {
                    ContainerSessionRegistry.locks[volId].writeLock().withLock {
                        ContainerEngine.lock(volId)
                    }
                    ContainerSessionRegistry.removeSession(volId)
                    activity.runOnUiThread {
                        activity.methodChannel?.invokeMethod("onCloudSessionInvalidated", mapOf("volId" to volId, "reason" to reason))
                    }
                }
            }
        }
    }

    /** §5.1's "Standalone Graceful Fallback" — the Cloud Storage tab calls
     *  this on becoming visible and shows either the account/vault picker
     *  or the "Install VaultSync Bridge" banner based on the result. */
    fun handleCheckCloudBridgeAvailable(call: MethodCall, result: MethodChannel.Result) {
        client.bind()
        scope.launch {
            val state = withTimeoutOrNull(3000) {
                var s = client.connectionState.value
                while (s is VaultCloudBridgeClient.ConnectionState.Connecting) {
                    kotlinx.coroutines.delay(50)
                    s = client.connectionState.value
                }
                s
            } ?: client.connectionState.value

            val payload = when (state) {
                is VaultCloudBridgeClient.ConnectionState.Connected ->
                    mapOf("available" to true, "version" to state.bridgeApiVersion)
                is VaultCloudBridgeClient.ConnectionState.VersionMismatch ->
                    mapOf("available" to false, "reason" to "version_mismatch", "version" to state.bridgeApiVersion)
                is VaultCloudBridgeClient.ConnectionState.NotInstalled ->
                    mapOf("available" to false, "reason" to "not_installed")
                else ->
                    mapOf("available" to false, "reason" to "disconnected")
            }
            activity.runOnUiThread { result.success(payload) }
        }
    }

    fun handleListCloudAccounts(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            val accounts = client.listCloudAccounts().map {
                mapOf("accountId" to it.accountId, "providerId" to it.providerId, "displayLabel" to it.displayLabel)
            }
            activity.runOnUiThread { result.success(accounts) }
        }
    }

    fun handleDiscoverRemoteVaults(call: MethodCall, result: MethodChannel.Result) {
        val accountId = call.argument<String>("accountId")
        val remoteDirectory = call.argument<String>("remoteDirectory") ?: "/"
        if (accountId == null) {
            result.error("INVALID_ARGS", "accountId is required", null)
            return
        }
        scope.launch {
            val vaults = client.discoverRemoteVaults(accountId, remoteDirectory).map {
                mapOf(
                    "accountId" to it.accountId,
                    "remotePath" to it.remotePath,
                    "displayName" to it.displayName,
                    "format" to it.format,
                    "totalSizeBytes" to it.totalSizeBytes,
                    "chunkSizeNumBytes" to it.chunkSizeNumBytes,
                    "folderUri" to it.folderUri,
                )
            }
            activity.runOnUiThread { result.success(vaults) }
        }
    }

    fun handleListRemoteFolders(call: MethodCall, result: MethodChannel.Result) {
        val accountId = call.argument<String>("accountId")
        val remoteDirectory = call.argument<String>("remoteDirectory") ?: "/"
        if (accountId == null) {
            result.error("INVALID_ARGS", "accountId is required", null)
            return
        }
        scope.launch {
            val folders = client.listRemoteFolders(accountId, remoteDirectory).map {
                mapOf(
                    "accountId" to it.accountId,
                    "remotePath" to it.remotePath,
                    "displayName" to it.displayName,
                    "folderUri" to it.folderUri,
                )
            }
            activity.runOnUiThread { result.success(folders) }
        }
    }

    /**
     * Mounts a remote chunked vault directly, without a local copy —
     * §5.3's whole point. Args mirror [parseUnlockArgs] (password, pim,
     * displayName, etc.) plus this call's own accountId/remoteVaultPath/
     * format/totalSizeBytes/chunkSizeNumBytes from the
     * [com.aeidolon.vaultexplorer.syncapi.RemoteVaultDescriptor] the Dart
     * side picked.
     */
    fun handleUnlockRemoteChunkedVault(call: MethodCall, result: MethodChannel.Result) {
        val accountId = call.argument<String>("accountId")
        val remoteVaultPath = call.argument<String>("remoteVaultPath")
        val totalSizeBytes = call.argument<Number>("totalSizeBytes")?.toLong()
        val chunkSizeBytes = call.argument<Number>("chunkSizeNumBytes")?.toInt()
            ?: com.aeidolon.vaultexplorer.syncapi.DEFAULT_CHUNK_SIZE_BYTES

        if (accountId == null || remoteVaultPath == null || totalSizeBytes == null || totalSizeBytes <= 0) {
            result.error("INVALID_ARGS", "accountId, remoteVaultPath and a positive totalSizeBytes are required", null)
            return
        }

        val cloudVaultKey = "$accountId:$remoteVaultPath"
        val syntheticUri = "cloud://$accountId/${encodePathSegment(remoteVaultPath)}"
        val args = parseUnlockArgs(call, result, syntheticUri, "remoteVaultPath") ?: return

        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(syntheticUri)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "Maximum ${ContainerSessionRegistry.MAX_VOLUMES} containers already mounted", null)
            return
        }
        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))

        ioExecutor.execute {
            var proxyPfd: ParcelFileDescriptor? = null
            try {
                client.bind()

                val fuseCallback = CloudFuseCallback(
                    client = client,
                    accountId = accountId,
                    remoteVaultPath = remoteVaultPath,
                    totalSizeBytes = totalSizeBytes,
                    chunkSizeBytes = chunkSizeBytes,
                    onReleased = { ContainerSessionRegistry.removeSession(targetVolId) },
                )
                val storageManager = activity.getSystemService(StorageManager::class.java)
                proxyPfd = storageManager.openProxyFileDescriptor(ParcelFileDescriptor.MODE_READ_WRITE, fuseCallback, fuseHandler)

                val keyfileFds = nativeOps.openKeyfileFds(args.keyfilePaths)
                val fd = proxyPfd.detachFd() // ownership -> native, same convention as VaultUnlockHandlers.handleUnlockContainer

                val files = ContainerSessionRegistry.locks[targetVolId].writeLock().withLock {
                    ContainerEngine.unlockFile(fd, args.password, args.pim, targetVolId, args.cipherId, args.hashId, args.preservedKey, keyfileFds, args.readOnly)
                }

                activity.runOnUiThread {
                    if (files != null) {
                        ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                            uri = syntheticUri,
                            volId = targetVolId,
                            cachedFilesList = files.toList(),
                            displayName = args.displayName ?: remoteVaultPath.substringAfterLast('/'),
                            documentProvider = args.docProvider,
                            readOnly = args.readOnly,
                            cloudVaultKey = cloudVaultKey,
                        )
                        ContainerSessionRegistry.applyAutoMountFolders(targetVolId, args.autoMountFolders)
                        if (args.docProvider) {
                            activity.contentResolver.notifyChange(
                                DocumentsContract.buildRootsUri("com.aeidolon.vaultexplorer.documents"), null)
                        }
                        val fmt = ContainerEngine.format(targetVolId).wireName
                        result.success(mapOf(
                            "volId" to targetVolId,
                            "filePath" to syntheticUri,
                            "files" to files.toList(),
                            "matchedCipherId" to ContainerEngine.matchedCipherId(targetVolId),
                            "matchedHashId" to ContainerEngine.matchedHashId(targetVolId),
                            "containerFormat" to fmt,
                        ))
                    } else {
                        nativeOps.dispatchNativeError(IllegalStateException("unlock failed"), result)
                    }
                }
            } catch (e: Exception) {
                if (proxyPfd != null) runCatching { proxyPfd.close() }
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    private fun encodePathSegment(s: String): String = android.net.Uri.encode(s)

    fun onActivityDestroyed() {
        client.unbind()
        fuseThread.quitSafely()
    }

    companion object {
        private const val TAG = "CloudMountHandlers"
    }
}
