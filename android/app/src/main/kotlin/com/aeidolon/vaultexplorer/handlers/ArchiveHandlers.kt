package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import android.os.ParcelFileDescriptor
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService

class ArchiveHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    fun handleArchiveScanVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val vaultPath = call.argument<String>("vaultPath")
        val passphrase = call.argument<String>("passphrase")

        if (uriString.isNullOrEmpty() || vaultPath == null) {
            result.error("INVALID_ARGS", "filePath and vaultPath required", null)
            return
        }

        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container not mounted", null)
            return
        }

        ioExecutor.execute {
            try {
                val scanResult = NativeEngine.archiveScanVaultNative(volId, vaultPath, passphrase)
                activity.runOnUiThread {
                    if (scanResult != null) result.success(scanResult)
                    else result.error("ARCHIVE_ERROR", "Failed to scan in-vault archive", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleArchiveExtractVaultEntry(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val vaultPath = call.argument<String>("vaultPath")
        val targetIndex = call.argument<Number>("targetIndex")?.toInt() ?: -1
        val passphrase = call.argument<String>("passphrase")

        if (uriString.isNullOrEmpty() || vaultPath == null || targetIndex < 0) {
            result.error("INVALID_ARGS", "filePath, vaultPath, and targetIndex >= 0 required", null)
            return
        }

        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container not mounted", null)
            return
        }

        ioExecutor.execute {
            try {
                val bytes = NativeEngine.archiveExtractVaultEntryNative(volId, vaultPath, targetIndex, passphrase)
                activity.runOnUiThread {
                    if (bytes != null) result.success(bytes)
                    else result.error("EXTRACT_FAILED", "Failed to extract archive entry", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleArchiveExtractVaultAll(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath") ?: call.argument<String>("localUri")
        val vaultPath = call.argument<String>("vaultPath")
        val destUri = call.argument<String>("destUri") ?: filePath
        val destDirPath = call.argument<String>("destDirPath") ?: ""
        val subPath = call.argument<String>("subPath")
        val passphrase = call.argument<String>("passphrase")
        val opId = call.argument<Number>("opId")?.toInt() ?: 0

        if (filePath.isNullOrEmpty() || destUri.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "filePath and destUri required", null)
            return
        }

        val destVolId = ContainerSessionRegistry.getVolumeIdByUri(destUri)
        if (destVolId == null) {
            result.error("NOT_MOUNTED", "Destination container not mounted", null)
            return
        }

        ioExecutor.execute {
            var pfd: ParcelFileDescriptor? = null
            try {
                val extractResult = if (!vaultPath.isNullOrEmpty()) {
                    val srcVolId = ContainerSessionRegistry.getVolumeIdByUri(filePath)
                    if (srcVolId == null) {
                        activity.runOnUiThread { result.error("NOT_MOUNTED", "Source container not mounted", null) }
                        return@execute
                    }
                    NativeEngine.archiveExtractVaultAllNative(srcVolId, vaultPath, destDirPath, subPath, passphrase, opId)
                } else {
                    val uri = Uri.parse(filePath)
                    pfd = if (uri.scheme == null || uri.scheme == "file") {
                        val path = uri.path ?: filePath
                        ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
                    } else {
                        activity.contentResolver.openFileDescriptor(uri, "r")
                    }

                    if (pfd == null) {
                        activity.runOnUiThread { result.error("FILE_NOT_FOUND", "Could not open archive file", null) }
                        return@execute
                    }

                    NativeEngine.archiveExtractFdToVaultNative(pfd.fd, destVolId, destDirPath, subPath, passphrase, opId)
                }

                activity.runOnUiThread {
                    if (extractResult != null) result.success(extractResult)
                    else result.error("EXTRACT_FAILED", "Failed to bulk extract archive", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                runCatching { pfd?.close() }
            }
        }
    }

    fun handleArchiveScanLocal(call: MethodCall, result: MethodChannel.Result) {
        val pathOrUri = call.argument<String>("filePath") ?: call.argument<String>("localUri")
        val passphrase = call.argument<String>("passphrase")

        if (pathOrUri.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "filePath or localUri required", null)
            return
        }

        ioExecutor.execute {
            var pfd: ParcelFileDescriptor? = null
            try {
                val uri = Uri.parse(pathOrUri)
                pfd = if (uri.scheme == null || uri.scheme == "file") {
                    val path = uri.path ?: pathOrUri
                    ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
                } else {
                    activity.contentResolver.openFileDescriptor(uri, "r")
                }

                if (pfd == null) {
                    activity.runOnUiThread { result.error("FILE_NOT_FOUND", "Could not open archive file", null) }
                    return@execute
                }

                val scanResult = NativeEngine.archiveScanFdNative(pfd.fd, passphrase)
                activity.runOnUiThread {
                    if (scanResult != null) result.success(scanResult)
                    else result.error("ARCHIVE_ERROR", "Failed to scan local archive", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                runCatching { pfd?.close() }
            }
        }
    }

    fun handleArchiveExtractLocalEntry(call: MethodCall, result: MethodChannel.Result) {
        val pathOrUri = call.argument<String>("filePath") ?: call.argument<String>("localUri")
        val targetIndex = call.argument<Number>("targetIndex")?.toInt() ?: -1
        val passphrase = call.argument<String>("passphrase")

        if (pathOrUri.isNullOrEmpty() || targetIndex < 0) {
            result.error("INVALID_ARGS", "filePath/localUri and targetIndex >= 0 required", null)
            return
        }

        ioExecutor.execute {
            var pfd: ParcelFileDescriptor? = null
            try {
                val uri = Uri.parse(pathOrUri)
                pfd = if (uri.scheme == null || uri.scheme == "file") {
                    val path = uri.path ?: pathOrUri
                    ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
                } else {
                    activity.contentResolver.openFileDescriptor(uri, "r")
                }

                if (pfd == null) {
                    activity.runOnUiThread { result.error("FILE_NOT_FOUND", "Could not open archive file", null) }
                    return@execute
                }

                val bytes = NativeEngine.archiveExtractFdEntryNative(pfd.fd, targetIndex, passphrase)
                activity.runOnUiThread {
                    if (bytes != null) result.success(bytes)
                    else result.error("EXTRACT_FAILED", "Failed to extract local archive entry", null)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                runCatching { pfd?.close() }
            }
        }
    }

    fun handleArchiveCreate(call: MethodCall, result: MethodChannel.Result) {
        val format = call.argument<Number>("format")?.toInt() ?: 0
        val passphrase = call.argument<String>("passphrase")
        val opId = call.argument<Number>("opId")?.toInt() ?: 0

        val srcUri = call.argument<String>("srcUri")
        val srcPaths = call.argument<List<String>>("srcPaths")
        val entryNames = call.argument<List<String>>("entryNames") ?: srcPaths?.map { it.substringAfterLast("/") }

        val destUri = call.argument<String>("destUri")
        val destVaultPath = call.argument<String>("destVaultPath")
        val destFilePath = call.argument<String>("destFilePath")

        if (srcPaths.isNullOrEmpty() || entryNames == null || entryNames.size != srcPaths.size) {
            result.error("INVALID_ARGS", "srcPaths and matching entryNames required", null)
            return
        }

        val srcVolId = if (!srcUri.isNullOrEmpty()) ContainerSessionRegistry.getVolumeIdByUri(srcUri) else null
        val destVolId = if (!destUri.isNullOrEmpty()) ContainerSessionRegistry.getVolumeIdByUri(destUri) else null

        ioExecutor.execute {
            var destPfd: ParcelFileDescriptor? = null
            try {
                if (srcVolId != null && destVolId != null && destVaultPath != null) {
                    val ok = NativeEngine.archiveCreateVaultToVaultNative(
                        srcVolId, srcPaths.toTypedArray(), entryNames.toTypedArray(),
                        destVolId, destVaultPath, format, passphrase, opId
                    )
                    activity.runOnUiThread { result.success(ok) }
                } else if (srcVolId != null) {
                    val target = destFilePath ?: destUri
                    if (target == null) {
                        activity.runOnUiThread { result.error("INVALID_ARGS", "Destination path or URI required", null) }
                        return@execute
                    }
                    val targetUri = Uri.parse(target)
                    destPfd = if (targetUri.scheme == "content") {
                        activity.contentResolver.openFileDescriptor(targetUri, "wt")
                    } else {
                        val file = File(targetUri.path ?: target)
                        file.parentFile?.mkdirs()
                        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_TRUNCATE)
                    }
                    if (destPfd == null) {
                        activity.runOnUiThread { result.error("IO_ERROR", "Could not open destination file descriptor", null) }
                        return@execute
                    }

                    val ok = NativeEngine.archiveCreateVaultToFdNative(
                        srcVolId, srcPaths.toTypedArray(), entryNames.toTypedArray(),
                        destPfd.fd, format, passphrase, opId
                    )
                    activity.runOnUiThread { result.success(ok) }
                } else {
                    val target = destFilePath ?: destUri
                    if (target == null) {
                        activity.runOnUiThread { result.error("INVALID_ARGS", "Destination path or URI required", null) }
                        return@execute
                    }
                    val targetUri = Uri.parse(target)
                    destPfd = if (targetUri.scheme == "content") {
                        activity.contentResolver.openFileDescriptor(targetUri, "wt")
                    } else {
                        val file = File(targetUri.path ?: target)
                        file.parentFile?.mkdirs()
                        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_TRUNCATE)
                    }
                    if (destPfd == null) {
                        activity.runOnUiThread { result.error("IO_ERROR", "Could not open destination file descriptor", null) }
                        return@execute
                    }

                    val ok = NativeEngine.archiveCreateLocalToFdNative(
                        srcPaths.toTypedArray(), entryNames.toTypedArray(),
                        destPfd.fd, format, passphrase, opId
                    )
                    activity.runOnUiThread { result.success(ok) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                runCatching { destPfd?.close() }
            }
        }
    }
}