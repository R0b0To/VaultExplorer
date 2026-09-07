package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.container.ContainerEngine
import com.aeidolon.vaultexplorer.container.ContainerSession
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.saf.UriToPath
import com.aeidolon.vaultexplorer.VeLog

class CompositeContainerHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    private data class OpenedCarriers(
        val paths: Array<String>,
        val fds: IntArray,
    )

    private fun resolveCarrierDescriptors(uris: List<String>, readOnly: Boolean): OpenedCarriers {
        val paths = mutableListOf<String>()
        val fds = mutableListOf<Int>()

        for (uStr in uris) {
            val uri = Uri.parse(uStr)
            val rawFile = UriToPath.getRawFile(activity, uri)
            if (rawFile != null && rawFile.canRead() && (readOnly || rawFile.canWrite())) {
                paths.add(rawFile.absolutePath)
                fds.add(-1)
            } else {
                paths.add("")
                val mode = if (readOnly) "r" else "rw"
                val pfd = try {
                    activity.contentResolver.openFileDescriptor(uri, mode)
                } catch (e: Exception) {
                    VeLog.w("CompositeContainer", e) { "Failed to open $uri in mode $mode" }
                    null
                } ?: throw java.io.IOException("Could not open carrier descriptor in mode '$mode': $uStr")

                val detachedFd = pfd.detachFd()
                fds.add(detachedFd)
            }
        }
        return OpenedCarriers(paths.toTypedArray(), fds.toIntArray())
    }

    fun handleProfileCarriers(call: MethodCall, result: MethodChannel.Result) {
        val carrierUris = call.argument<List<String>>("carrierUris")
        val safetyMargin = call.argument<Number>("safetyMarginPct")?.toInt() ?: 10
        if (carrierUris.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "carrierUris required", null)
            return
        }

        ioExecutor.execute {
            try {
                val opened = resolveCarrierDescriptors(carrierUris, readOnly = true)
                val profile = NativeEngine.profileCarriersNative(opened.paths, opened.fds, safetyMargin)
                activity.runOnUiThread {
                    if (profile != null) result.success(profile)
                    else result.error("PROFILE_FAILED", "Failed profiling carrier files", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleCreateCompositeContainer(call: MethodCall, result: MethodChannel.Result) {
        val carrierUris = call.argument<List<String>>("carrierUris")
        val payloadOffsets = call.argument<List<Number>>("payloadOffsets")?.map { it.toLong() }?.toLongArray()
        val extentLengths = call.argument<List<Number>>("extentLengths")?.map { it.toLong() }?.toLongArray()
        val password = call.argument<String>("password") ?: ""
        val pim = call.argument<Number>("pim")?.toInt() ?: 0
        val fileSystem = call.argument<String>("fileSystem") ?: "fat"
        val containerFormat = call.argument<Number>("containerFormat")?.toInt() ?: 0
        val cipherId = call.argument<Number>("cipherId")?.toInt() ?: 255
        val hashId = call.argument<Number>("hashId")?.toInt() ?: 255
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        val quickFormat = call.argument<Boolean>("quickFormat") ?: false
        val operationId = call.argument<String>("operationId") ?: ""

        if (carrierUris.isNullOrEmpty() || payloadOffsets == null || extentLengths == null) {
            result.error("INVALID_ARGS", "carrierUris, payloadOffsets, and extentLengths required", null)
            return
        }

        val targetVolId = ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "No free volume slots available", null)
            return
        }

        ioExecutor.execute {
            try {
                val opened = resolveCarrierDescriptors(carrierUris, readOnly = false)
                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)
                val ok = NativeEngine.createCompositeContainerNative(
                    targetVolId, opened.paths, opened.fds, payloadOffsets, extentLengths,
                    password, pim, fileSystem, containerFormat, cipherId, hashId,
                    keyfileFds, quickFormat, operationId
                )
                activity.runOnUiThread { result.success(ok) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleUnlockCompositeContainer(call: MethodCall, result: MethodChannel.Result) {
        val carrierUris = call.argument<List<String>>("carrierUris")
        val payloadOffsets = call.argument<List<Number>>("payloadOffsets")?.map { it.toLong() }?.toLongArray()
        val extentLengths = call.argument<List<Number>>("extentLengths")?.map { it.toLong() }?.toLongArray()
        val password = call.argument<String>("password") ?: ""
        val pim = call.argument<Number>("pim")?.toInt() ?: 0
        val cipherId = call.argument<Number>("cipherId")?.toInt() ?: 255
        val hashId = call.argument<Number>("hashId")?.toInt() ?: 255
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        val readOnly = call.argument<Boolean>("readOnly") ?: false
        val displayName = call.argument<String>("displayName") ?: "Composite Vault"
        val docProvider = call.argument<Boolean>("documentProvider") ?: false
        val autoMountFolders = call.argument<List<String>>("autoMountFolders")

        if (carrierUris.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "carrierUris required", null)
            return
        }

        val compositeUriKey = "composite:" + carrierUris.first()
        val targetVolId = ContainerSessionRegistry.getVolumeIdByUri(compositeUriKey)
            ?: ContainerSessionRegistry.getFreeVolumeId()
        if (targetVolId == null) {
            result.error("MAX_CONTAINERS", "No free volume slots available", null)
            return
        }

        activity.methodChannel?.invokeMethod("onUnlockStarted", mapOf("volId" to targetVolId))

        ioExecutor.execute {
            try {
                val opened = resolveCarrierDescriptors(carrierUris, readOnly)
                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)
                val files = NativeEngine.unlockCompositeContainerNative(
                    targetVolId, opened.paths, opened.fds, payloadOffsets, extentLengths,
                    password, pim, cipherId, hashId, keyfileFds, readOnly
                )

                activity.runOnUiThread {
                    if (files != null) {
                        ContainerSessionRegistry.activeSessions[targetVolId] = ContainerSession(
                            uri = compositeUriKey,
                            volId = targetVolId,
                            cachedFilesList = files.toList(),
                            displayName = displayName,
                            documentProvider = docProvider,
                            readOnly = readOnly,
                            containerFormat = ContainerEngine.format(targetVolId),
                        )
                        ContainerSessionRegistry.applyAutoMountFolders(targetVolId, autoMountFolders)
                        if (docProvider) {
                            activity.contentResolver.notifyChange(
                                DocumentsContract.buildRootsUri("com.aeidolon.vaultexplorer.documents"), null
                            )
                        }
                        result.success(
                            mapOf(
                                "volId" to targetVolId,
                                "files" to files.toList(),
                                "matchedCipherId" to ContainerEngine.matchedCipherId(targetVolId),
                                "matchedHashId" to ContainerEngine.matchedHashId(targetVolId),
                                "containerFormat" to ContainerEngine.format(targetVolId).wireName
                            )
                        )
                    } else {
                        result.error("AUTH_FAIL", "Incorrect password or carrier set mismatch", null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }
}