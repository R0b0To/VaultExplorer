package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.ScopedStorageUtils
import com.aeidolon.vaultexplorer.saf.UriToPath
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.cancellation.SplitJoinCancellation
import com.aeidolon.vaultexplorer.cancellation.SplitJoinCancelledException
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.UriNameResolver

class SingleFileCryptoHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    private fun dispatchError(e: Exception, result: MethodChannel.Result) {
        if (e is SplitJoinCancelledException) {
            result.error("CANCELLED", e.message, null)
        } else {
            result.error("CRYPTO_ERROR", e.message ?: e.toString(), null)
        }
    }

    private data class DestinationTarget(
        val pfd: ParcelFileDescriptor,
        val createdFile: File?,
        val createdDoc: DocumentFile?,
    )

    private fun openDestination(
        outName: String,
        destinationPath: String?,
        destinationTreeUri: String?,
        srcRawFile: File?,
    ): DestinationTarget {
        // 1. If an explicit destination path was provided (and isn't a content:// URI),
        // try raw File I/O if allowed by scoped storage.
        if (!destinationPath.isNullOrEmpty() && !ScopedStorageUtils.isSafUri(destinationPath)) {
            val canWrite = ScopedStorageUtils.canWriteRawPath(activity, destinationPath)
            if (canWrite) {
                val destDir = File(destinationPath)
                if (destDir.exists() || destDir.mkdirs()) {
                    val file = File(destDir, outName)
                    try {
                        val pfd = ParcelFileDescriptor.open(
                            file,
                            ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_TRUNCATE
                        )
                        return DestinationTarget(pfd, file, null)
                    } catch (_: Exception) {
                        // Raw open failed (e.g. permission or I/O error) -> fall through to SAF.
                    }
                }
            }
        }

        // 2. Try SAF DocumentFile destination (cloud storage, SD card / external storage without raw access, etc.)
        val treeDoc = ScopedStorageUtils.resolveTreeDoc(activity, destinationTreeUri, destinationPath)
        if (treeDoc != null && treeDoc.isDirectory && treeDoc.canWrite()) {
            treeDoc.findFile(outName)?.delete()
            val doc = treeDoc.createFile("application/octet-stream", outName)
            if (doc != null) {
                val pfd = activity.contentResolver.openFileDescriptor(doc.uri, "rw")
                if (pfd != null) {
                    return DestinationTarget(pfd, null, doc)
                }
            }
        }

        // 3. If no destination was specified at all, default to the source file's directory if raw-writable.
        if (destinationPath.isNullOrEmpty() && destinationTreeUri.isNullOrEmpty()) {
            if (srcRawFile != null && srcRawFile.parentFile != null && srcRawFile.parentFile.canWrite()) {
                val file = File(srcRawFile.parentFile, outName)
                try {
                    val pfd = ParcelFileDescriptor.open(
                        file,
                        ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_TRUNCATE
                    )
                    return DestinationTarget(pfd, file, null)
                } catch (_: Exception) {}
            }
        }

        throw Exception("Destination directory not writable. Please select a destination folder.")
    }

    fun handleEncryptSingleFile(call: MethodCall, result: MethodChannel.Result) {
        val sourceUriStr = call.argument<String>("sourceUri")
        val cipherIndex = call.argument<Number>("cipherIndex")?.toInt() ?: 0
        val passphrase = call.argument<String>("passphrase") ?: ""
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        val deleteOriginalAfter = call.argument<Boolean>("deleteOriginalAfter") ?: false
        val destinationPath = call.argument<String>("destinationPath")
        val destinationTreeUri = call.argument<String>("destinationTreeUri")
        val opId = call.argument<Number>("opId")?.toInt() ?: 0

        if (sourceUriStr == null) {
            result.error("INVALID_ARGS", "sourceUri is required", null)
            return
        }

        ioExecutor.execute {
            var srcPfd: ParcelFileDescriptor? = null
            var destPfd: ParcelFileDescriptor? = null
            var createdDestFile: File? = null
            var createdDestDoc: DocumentFile? = null
            try {
                val srcUri = Uri.parse(sourceUriStr)
                val srcRawFile = UriToPath.getRawFile(activity, srcUri)
                val srcName = UriNameResolver.resolve(activity.contentResolver, srcUri)
                srcPfd = activity.contentResolver.openFileDescriptor(srcUri, "r")
                    ?: throw Exception("Could not open source file")

                val outName = if (cipherIndex == 2) {
                    if (srcName.endsWith(".aes", ignoreCase = true)) srcName else "$srcName.aes"
                } else if (srcName.endsWith(".vxenc", ignoreCase = true)) {
                    srcName
                } else {
                    "$srcName.vxenc"
                }

                val (targetPfd, targetFile, targetDoc) = openDestination(
                    outName, destinationPath, destinationTreeUri, srcRawFile
                )
                destPfd = targetPfd
                createdDestFile = targetFile
                createdDestDoc = targetDoc

                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)
                val srcFd = (srcPfd ?: throw Exception("Source file descriptor is null")).detachFd()
                val destFd = (destPfd ?: throw Exception("Destination file descriptor is null")).detachFd()

                val ok = NativeEngine.encryptSingleFileNative(
                    srcFd, destFd, cipherIndex, passphrase, keyfileFds, opId
                )

                if (ok) {
                    if (deleteOriginalAfter) {
                        if (srcRawFile != null && srcRawFile.exists()) {
                            srcRawFile.delete()
                        } else {
                            try {
                                DocumentFile.fromSingleUri(activity, srcUri)?.delete()
                            } catch (_: Exception) {}
                        }
                    }
                    activity.runOnUiThread { result.success(true) }
                } else {
                    if (SplitJoinCancellation.isCancelled(opId)) {
                        createdDestFile?.delete()
                        createdDestDoc?.delete()
                        throw SplitJoinCancelledException("Encryption cancelled")
                    }
                    createdDestFile?.delete()
                    createdDestDoc?.delete()
                    activity.runOnUiThread { result.error("CRYPTO_ERROR", "Encryption failed", null) }
                }
            } catch (e: Exception) {
                if (SplitJoinCancellation.isCancelled(opId)) {
                    createdDestFile?.delete()
                    createdDestDoc?.delete()
                }
                activity.runOnUiThread { dispatchError(e, result) }
            } finally {
                try { srcPfd?.close() } catch (_: Exception) {}
                try { destPfd?.close() } catch (_: Exception) {}
                SplitJoinCancellation.clear(opId)
            }
        }
    }

    fun handleDecryptSingleFile(call: MethodCall, result: MethodChannel.Result) {
        val sourceUriStr = call.argument<String>("sourceUri")
        val passphrase = call.argument<String>("passphrase") ?: ""
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        val destinationPath = call.argument<String>("destinationPath")
        val destinationTreeUri = call.argument<String>("destinationTreeUri")
        val opId = call.argument<Number>("opId")?.toInt() ?: 0

        if (sourceUriStr == null) {
            result.error("INVALID_ARGS", "sourceUri is required", null)
            return
        }

        ioExecutor.execute {
            var srcPfd: ParcelFileDescriptor? = null
            var destPfd: ParcelFileDescriptor? = null
            var createdDestFile: File? = null
            var createdDestDoc: DocumentFile? = null
            try {
                val srcUri = Uri.parse(sourceUriStr)
                val srcRawFile = UriToPath.getRawFile(activity, srcUri)
                val srcName = UriNameResolver.resolve(activity.contentResolver, srcUri)
                srcPfd = activity.contentResolver.openFileDescriptor(srcUri, "r")
                    ?: throw Exception("Could not open encrypted source file")

                var outName = if (srcName.endsWith(".vxenc", ignoreCase = true)) {
                    srcName.substring(0, srcName.length - 6)
                } else if (srcName.endsWith(".aes", ignoreCase = true)) {
                    srcName.substring(0, srcName.length - 4)
                } else if (srcName.endsWith(".enc", ignoreCase = true)) {
                    srcName.substring(0, srcName.length - 4)
                } else {
                    "$srcName.decrypted"
                }

                if (outName.isEmpty()) outName = "decrypted_file"

                val (targetPfd, targetFile, targetDoc) = openDestination(
                    outName, destinationPath, destinationTreeUri, srcRawFile
                )
                destPfd = targetPfd
                createdDestFile = targetFile
                createdDestDoc = targetDoc

                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)
                val srcFd = (srcPfd ?: throw Exception("Source file descriptor is null")).detachFd()
                val destFd = (destPfd ?: throw Exception("Destination file descriptor is null")).detachFd()

                val ok = NativeEngine.decryptSingleFileNative(
                    srcFd, destFd, passphrase, keyfileFds, opId
                )

                if (ok) {
                    activity.runOnUiThread { result.success(true) }
                } else {
                    createdDestFile?.delete()
                    createdDestDoc?.delete()
                    if (SplitJoinCancellation.isCancelled(opId)) {
                        throw SplitJoinCancelledException("Decryption cancelled")
                    }
                    activity.runOnUiThread {
                        result.error("AUTH_FAIL", "Incorrect password or keyfiles, or corrupted file", null)
                    }
                }
            } catch (e: Exception) {
                createdDestFile?.delete()
                createdDestDoc?.delete()
                activity.runOnUiThread { dispatchError(e, result) }
            } finally {
                try { srcPfd?.close() } catch (_: Exception) {}
                try { destPfd?.close() } catch (_: Exception) {}
                SplitJoinCancellation.clear(opId)
            }
        }
    }
}