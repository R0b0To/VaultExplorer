package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import android.os.ParcelFileDescriptor
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.container.VaultBackendRegistry
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

        val isFolderVault = VaultBackendRegistry.get(volId) != null

        ioExecutor.execute {
            if (isFolderVault) {
                val tempFile = File.createTempFile("arch_scan_", ".tmp", activity.cacheDir)
                var pfd: ParcelFileDescriptor? = null
                try {
                    val extracted = ContainerFileSystem.extractToFile(volId, vaultPath, tempFile.absolutePath)
                    if (!extracted) {
                        activity.runOnUiThread { result.error("ARCHIVE_ERROR", "Failed to read in-vault archive", null) }
                        return@execute
                    }
                    pfd = ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_ONLY)
                    val scanResult = NativeEngine.archiveScanFdNative(pfd.fd, passphrase)
                    activity.runOnUiThread {
                        if (scanResult != null) result.success(scanResult)
                        else result.error("ARCHIVE_ERROR", "Failed to scan in-vault archive", null)
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
                } finally {
                    runCatching { pfd?.close() }
                    SecureFileWipe.secureDeleteFile(tempFile)
                }
            } else {
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

        val isFolderVault = VaultBackendRegistry.get(volId) != null

        ioExecutor.execute {
            if (isFolderVault) {
                val tempFile = File.createTempFile("arch_ext_entry_", ".tmp", activity.cacheDir)
                var pfd: ParcelFileDescriptor? = null
                try {
                    val extracted = ContainerFileSystem.extractToFile(volId, vaultPath, tempFile.absolutePath)
                    if (!extracted) {
                        activity.runOnUiThread { result.error("EXTRACT_FAILED", "Failed to read in-vault archive", null) }
                        return@execute
                    }
                    pfd = ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_ONLY)
                    val bytes = NativeEngine.archiveExtractFdEntryNative(pfd.fd, targetIndex, passphrase)
                    activity.runOnUiThread {
                        if (bytes != null) result.success(bytes)
                        else result.error("EXTRACT_FAILED", "Failed to extract archive entry", null)
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
                } finally {
                    runCatching { pfd?.close() }
                    SecureFileWipe.secureDeleteFile(tempFile)
                }
            } else {
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

        val srcVolId = if (!vaultPath.isNullOrEmpty()) ContainerSessionRegistry.getVolumeIdByUri(filePath) else null
        val srcIsFolderVault = srcVolId != null && VaultBackendRegistry.get(srcVolId) != null
        val destIsFolderVault = VaultBackendRegistry.get(destVolId) != null

        if (!srcIsFolderVault && !destIsFolderVault) {
            ioExecutor.execute {
                var pfd: ParcelFileDescriptor? = null
                try {
                    val extractResult = if (!vaultPath.isNullOrEmpty()) {
                        NativeEngine.archiveExtractVaultAllNative(srcVolId!!, vaultPath, destDirPath, subPath, passphrase, opId)
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
            return
        }

        // Handling folder vault on either source or destination
        ioExecutor.execute {
            var tempArchiveFile: File? = null
            var tempExtractDir: File? = null
            var pfd: ParcelFileDescriptor? = null
            try {
                if (!vaultPath.isNullOrEmpty()) {
                    val temp = File.createTempFile("arch_bulk_src_", ".tmp", activity.cacheDir)
                    tempArchiveFile = temp
                    val ok = ContainerFileSystem.extractToFile(srcVolId!!, vaultPath, temp.absolutePath, opId)
                    if (!ok || !temp.exists()) {
                        activity.runOnUiThread { result.error("EXTRACT_FAILED", "Failed to read archive from vault", null) }
                        return@execute
                    }
                    pfd = ParcelFileDescriptor.open(temp, ParcelFileDescriptor.MODE_READ_ONLY)
                } else {
                    val uri = Uri.parse(filePath)
                    pfd = if (uri.scheme == null || uri.scheme == "file") {
                        val path = uri.path ?: filePath
                        ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
                    } else {
                        activity.contentResolver.openFileDescriptor(uri, "r")
                    }
                }

                if (pfd == null) {
                    activity.runOnUiThread { result.error("FILE_NOT_FOUND", "Could not open archive file", null) }
                    return@execute
                }

                if (!destIsFolderVault) {
                    val extractResult = NativeEngine.archiveExtractFdToVaultNative(
                        pfd.fd, destVolId, destDirPath, subPath, passphrase, opId
                    )
                    activity.runOnUiThread {
                        if (extractResult != null) result.success(extractResult)
                        else result.error("EXTRACT_FAILED", "Failed to bulk extract archive", null)
                    }
                } else {
                    val extDir = File(activity.cacheDir, "arch_bulk_ext_${System.nanoTime()}").apply { mkdirs() }
                    tempExtractDir = extDir
                    val extractResult = NativeEngine.archiveExtractFdToLocalDirNative(
                        pfd.fd, extDir.absolutePath, subPath, passphrase, opId
                    )

                    if (extractResult == null || (extractResult["status"] as? Number)?.toInt() != 0) {
                        activity.runOnUiThread {
                            val msg = extractResult?.get("errorMessage") as? String ?: "Failed to extract archive"
                            result.error("EXTRACT_FAILED", msg, null)
                        }
                        return@execute
                    }

                    val targetBase = destDirPath.trim('/')
                    var importedCount = 0
                    ContainerFileSystem.beginBatchWrite(destVolId)
                    try {
                        for (file in extDir.walkTopDown()) {
                            if (file == extDir) continue
                            val rel = file.relativeTo(extDir).path.replace('\\', '/')
                            val targetPath = if (targetBase.isEmpty()) rel else "$targetBase/$rel"
                            if (file.isDirectory) {
                                ContainerFileSystem.createDirectory(destVolId, targetPath)
                            } else {
                                val parent = targetPath.substringBeforeLast('/', "")
                                if (parent.isNotEmpty()) {
                                    val segs = parent.split('/')
                                    var cur = ""
                                    for (s in segs) {
                                        cur = if (cur.isEmpty()) s else "$cur/$s"
                                        ContainerFileSystem.createDirectory(destVolId, cur)
                                    }
                                }
                                if (ContainerFileSystem.writeBackFile(destVolId, targetPath, file.absolutePath, opId)) {
                                    ContainerFileSystem.finishWrite(destVolId, targetPath)
                                    importedCount++
                                }
                            }
                        }
                    } finally {
                        ContainerFileSystem.endBatchWrite(destVolId)
                    }

                    val resMap = mutableMapOf<String, Any>(
                        "status" to 0,
                        "extractedCount" to importedCount,
                        "errorMessage" to "",
                    )
                    activity.runOnUiThread { result.success(resMap) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                runCatching { pfd?.close() }
                tempArchiveFile?.let { SecureFileWipe.secureDeleteFile(it) }
                tempExtractDir?.let { dir ->
                    dir.walkBottomUp().forEach { f ->
                        if (f.isFile) SecureFileWipe.secureDeleteFile(f) else f.delete()
                    }
                }
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

        val srcIsFolderVault = srcVolId != null && VaultBackendRegistry.get(srcVolId) != null
        val destIsFolderVault = destVolId != null && VaultBackendRegistry.get(destVolId) != null

        // 1. If neither side is a folder vault, use the direct native-to-native C++ streaming paths
        if (!srcIsFolderVault && !destIsFolderVault) {
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
            return
        }

        // 2. Folder vault is involved: bridge through local temporary storage
        ioExecutor.execute {
            var tempSrcDir: File? = null
            var tempArchiveFile: File? = null
            var destPfd: ParcelFileDescriptor? = null
            try {
                // A. Prepare source files
                val localSourcePaths: List<String>
                val localEntryNames: List<String>

                if (srcIsFolderVault) {
                    val dir = File(activity.cacheDir, "arch_src_${System.nanoTime()}").apply { mkdirs() }
                    tempSrcDir = dir
                    val files = mutableListOf<String>()
                    val names = mutableListOf<String>()
                    for (i in srcPaths.indices) {
                        val sp = srcPaths[i]
                        val en = entryNames[i]
                        val tmp = File(dir, "f_${i}_${en.substringAfterLast('/')}")
                        val ok = ContainerFileSystem.extractToFile(srcVolId!!, sp, tmp.absolutePath, opId)
                        if (ok && tmp.exists()) {
                            files.add(tmp.absolutePath)
                            names.add(en)
                        }
                    }
                    localSourcePaths = files
                    localEntryNames = names
                } else {
                    localSourcePaths = srcPaths
                    localEntryNames = entryNames
                }

                // B. Prepare target file descriptor
                val targetPfd: ParcelFileDescriptor
                val isVaultDest = destVolId != null && destVaultPath != null

                if (isVaultDest) {
                    val arch = File(activity.cacheDir, "arch_out_${System.nanoTime()}.tmp")
                    tempArchiveFile = arch
                    targetPfd = ParcelFileDescriptor.open(
                        arch,
                        ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_TRUNCATE
                    )
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
                    targetPfd = destPfd
                }

                // C. Create archive
                val ok = if (srcIsFolderVault || srcVolId == null) {
                    NativeEngine.archiveCreateLocalToFdNative(
                        localSourcePaths.toTypedArray(), localEntryNames.toTypedArray(),
                        targetPfd.fd, format, passphrase, opId
                    )
                } else {
                    NativeEngine.archiveCreateVaultToFdNative(
                        srcVolId, srcPaths.toTypedArray(), entryNames.toTypedArray(),
                        targetPfd.fd, format, passphrase, opId
                    )
                }

                targetPfd.close()
                if (destPfd != null) destPfd = null

                // D. If destination is in a vault, write back from temporary file
                var finalSuccess = ok
                if (ok && isVaultDest && tempArchiveFile != null && tempArchiveFile.exists()) {
                    val written = ContainerFileSystem.writeBackFile(destVolId!!, destVaultPath!!, tempArchiveFile.absolutePath, opId)
                    ContainerFileSystem.finishWrite(destVolId, destVaultPath)
                    finalSuccess = written
                }

                activity.runOnUiThread { result.success(finalSuccess) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                runCatching { destPfd?.close() }
                tempArchiveFile?.let { SecureFileWipe.secureDeleteFile(it) }
                tempSrcDir?.let { dir ->
                    dir.listFiles()?.forEach { SecureFileWipe.secureDeleteFile(it) }
                    dir.delete()
                }
            }
        }
    }
}