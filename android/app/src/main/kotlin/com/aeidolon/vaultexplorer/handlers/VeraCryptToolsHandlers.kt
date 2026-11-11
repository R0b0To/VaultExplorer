package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.NativeOpSupport

/**
 * Desktop-VeraCrypt volume operations on an existing container: volume expansion
 * (and, below, creating a hidden volume inside an existing volume).
 */
class VeraCryptToolsHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    fun handleExpandContainer(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val password = call.argument<String>("password") ?: ""
        val pim = call.argument<Number>("pim")?.toInt() ?: 0
        val cipherId = call.argument<Number>("cipherId")?.toInt() ?: 255
        val hashId = call.argument<Number>("hashId")?.toInt() ?: 255
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        val newSizeBytes = call.argument<Number>("newSizeBytes")?.toLong() ?: 0L
        val initFreeSpace = call.argument<Boolean>("initFreeSpace") ?: true
        if (uri.isNullOrEmpty() || newSizeBytes <= 0L || (password.isEmpty() && keyfilePaths.isNullOrEmpty())) {
            result.error("INVALID_ARGS", "uri, newSizeBytes and a password or keyfile are required", null)
            return
        }
        ioExecutor.execute {
            try {
                // Keyfile fds first, as in the other handlers, so a keyfile that fails to open can't strand the detached container fd.
                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)
                val pfd = activity.contentResolver.openFileDescriptor(Uri.parse(uri), "rw")
                    ?: throw Exception("Could not open file descriptor")
                val outcome = NativeEngine.expandVeraCryptContainerNative(
                    pfd.detachFd(), password, pim, cipherId, hashId, keyfileFds, newSizeBytes, initFreeSpace,
                )
                activity.runOnUiThread {
                    when (outcome) {
                        0 -> result.success(true)
                        1 -> result.error("PASSWORD_INCORRECT", "Incorrect password", null)
                        2 -> result.error("NOT_EXPANDABLE", "Only a standard volume that fills its container can be expanded.", null)
                        3 -> result.error("NOT_LARGER", "The new size must be larger than the current size.", null)
                        5 -> result.error("KEYFILE_ERROR", "A keyfile could not be read.", null)
                        else -> result.error("IO_ERROR", "Could not expand the volume (code $outcome)", null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            }
        }
    }

    private fun hiddenHostErrorFor(outcome: Int): Pair<String, String> = when (outcome) {
        1 -> "PASSWORD_INCORRECT" to "Incorrect password"
        2 -> "UNSUPPORTED_FS" to "The outer volume's file system must be FAT, exFAT or NTFS to host a hidden volume."
        3 -> "NO_SPACE" to "There is not enough free space at the end of the outer volume for a hidden volume of that size."
        5 -> "KEYFILE_ERROR" to "A keyfile could not be read."
        6 -> "INVALID_VOLUME" to "Only a standard volume that fills its container can host a hidden volume, and the hidden password must differ from the outer one."
        else -> "IO_ERROR" to "Operation failed (code $outcome)"
    }

    /** Reads the outer volume's cluster map and reports the largest hidden volume that fits at its end. */
    fun handleAnalyzeHiddenHost(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val password = call.argument<String>("password") ?: ""
        val pim = call.argument<Number>("pim")?.toInt() ?: 0
        val cipherId = call.argument<Number>("cipherId")?.toInt() ?: 255
        val hashId = call.argument<Number>("hashId")?.toInt() ?: 255
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        if (uri.isNullOrEmpty() || (password.isEmpty() && keyfilePaths.isNullOrEmpty())) {
            result.error("INVALID_ARGS", "uri and a password or keyfile are required", null)
            return
        }
        ioExecutor.execute {
            try {
                val keyfileFds = nativeOps.openKeyfileFds(keyfilePaths)
                val pfd = activity.contentResolver.openFileDescriptor(Uri.parse(uri), "r")
                    ?: throw Exception("Could not open file descriptor")
                val out = NativeEngine.analyzeHiddenVolumeHostNative(pfd.detachFd(), password, pim, cipherId, hashId, keyfileFds)
                activity.runOnUiThread {
                    if (out == null || out.size < 4) {
                        result.error("IO_ERROR", "Analysis failed", null)
                    } else if (out[0] != 0L) {
                        val (code, message) = hiddenHostErrorFor(out[0].toInt())
                        result.error(code, message, null)
                    } else {
                        result.success(mapOf("fsKind" to out[1], "clusterSize" to out[2], "maxHiddenBytes" to out[3]))
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            }
        }
    }

    /** Adds a hidden volume to an existing standard volume (desktop VeraCrypt "direct mode"). */
    fun handleCreateHiddenInExisting(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val outerPassword = call.argument<String>("outerPassword") ?: ""
        val outerPim = call.argument<Number>("outerPim")?.toInt() ?: 0
        val outerCipherId = call.argument<Number>("outerCipherId")?.toInt() ?: 255
        val outerHashId = call.argument<Number>("outerHashId")?.toInt() ?: 255
        val outerKeyfilePaths = call.argument<List<String>>("outerKeyfilePaths")
        val hiddenPassword = call.argument<String>("hiddenPassword") ?: ""
        val hiddenPim = call.argument<Number>("hiddenPim")?.toInt() ?: 0
        val hiddenFileSystem = call.argument<String>("hiddenFileSystem") ?: "exFAT"
        val hiddenSizeBytes = call.argument<Number>("hiddenSizeBytes")?.toLong() ?: 0L
        val hiddenCipherId = call.argument<Number>("hiddenCipherId")?.toInt() ?: 255
        val hiddenHashId = call.argument<Number>("hiddenHashId")?.toInt() ?: 255
        val hiddenKeyfilePaths = call.argument<List<String>>("hiddenKeyfilePaths")
        val quickFormat = call.argument<Boolean>("quickFormat") ?: false
        val userEntropy = call.argument<ByteArray>("userEntropy")
        if (uri.isNullOrEmpty() || hiddenSizeBytes <= 0L ||
            (outerPassword.isEmpty() && outerKeyfilePaths.isNullOrEmpty()) ||
            (hiddenPassword.isEmpty() && hiddenKeyfilePaths.isNullOrEmpty())) {
            result.error("INVALID_ARGS", "uri, hiddenSizeBytes and passwords/keyfiles are required", null)
            return
        }
        ioExecutor.execute {
            try {
                val outerKeyfileFds = nativeOps.openKeyfileFds(outerKeyfilePaths)
                val hiddenKeyfileFds = nativeOps.openKeyfileFds(hiddenKeyfilePaths)
                val pfd = activity.contentResolver.openFileDescriptor(Uri.parse(uri), "rw")
                    ?: throw Exception("Could not open file descriptor")
                val outcome = NativeEngine.createHiddenVolumeInExistingNative(
                    pfd.detachFd(), outerPassword, outerPim, outerCipherId, outerHashId, outerKeyfileFds,
                    hiddenPassword, hiddenPim, hiddenFileSystem, hiddenSizeBytes,
                    hiddenCipherId, hiddenHashId, hiddenKeyfileFds, quickFormat, userEntropy,
                )
                activity.runOnUiThread {
                    if (outcome == 0) result.success(true) else {
                        val (code, message) = hiddenHostErrorFor(outcome)
                        result.error(code, message, null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            }
        }
    }
}
