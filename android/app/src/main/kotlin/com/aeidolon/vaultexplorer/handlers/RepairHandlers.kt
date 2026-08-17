package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.bridge.RepairLogBridge
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeEngine

/**
 * Container Utilities → Check & Repair ([ContainerRepairSheet] on the Dart
 * side). See containers/container_repair.cpp for the native diagnosis/
 * restore/check logic this just opens file descriptors for and dispatches
 * to.
 *
 * All four calls follow this file's usual `ioExecutor.execute { ... }` +
 * `activity.runOnUiThread { result.success/error(...) }` shape. File
 * descriptors handed to `NativeEngine.nativeDiagnose*`/`nativeRestore*` are
 * always `detachFd()`'d and NEVER closed again here afterward -- those
 * native calls take ownership and close them internally on every path
 * (matching `changeContainerPassword`'s convention in
 * container_create.cpp), so a second `close()` here would risk a
 * double-close.
 */
class RepairHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    fun handleDiagnoseUnmountedContainerFile(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val opId = call.argument<Number>("opId")?.toInt() ?: -1
        if (uri.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "uri required", null)
            return
        }

        ioExecutor.execute {
            try {
                val pfd = activity.contentResolver.openFileDescriptor(Uri.parse(uri), "r")
                    ?: throw Exception("Could not open file descriptor")
                val packed = NativeEngine.nativeDiagnoseContainerFile(pfd.detachFd(), opId)
                activity.runOnUiThread {
                    if (packed == null || packed.size != 2) {
                        result.error("IO_ERROR", "Could not read the container file", null)
                    } else {
                        val format = if (packed[1] >= 0) ContainerFormat.fromNative(packed[1]).wireName else null
                        result.success(mapOf("diagnosisCode" to packed[0], "format" to format))
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            }
        }
    }

    fun handleDiagnoseMountedVolumeFilesystem(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Number>("volId")?.toInt()
        val opId = call.argument<Number>("opId")?.toInt() ?: -1
        if (volId == null) {
            result.error("INVALID_ARGS", "volId required", null)
            return
        }

        ioExecutor.execute {
            try {
                val code = NativeEngine.nativeDiagnoseMountedVolumeFilesystem(volId, opId)
                activity.runOnUiThread { result.success(mapOf("diagnosisCode" to code, "format" to null)) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            }
        }
    }

    /**
     * [password]/[pim]/[cipherId]/[hashId] only matter for a VeraCrypt/
     * TrueCrypt target -- see repairFormatNeedsPasswordForRestore's doc
     * comment in container_repair.h for why LUKS2 doesn't need a password
     * here. The target's format isn't known to the Dart caller (diagnosis
     * only reports the 3-state RepairDiagnosis, not the underlying
     * format), so this re-probes it with its own short-lived file
     * descriptor before deciding which native restore path applies.
     */
    fun handleRestoreBackupHeaderUnmounted(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val password = call.argument<String>("password")
        val pim = call.argument<Number>("pim")?.toInt() ?: 0
        val cipherId = call.argument<Number>("cipherId")?.toInt() ?: 255
        val hashId = call.argument<Number>("hashId")?.toInt() ?: 255
        val opId = call.argument<Number>("opId")?.toInt() ?: -1
        if (uri.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "uri required", null)
            return
        }

        ioExecutor.execute {
            try {
                val docUri = Uri.parse(uri)
                val probeFd = activity.contentResolver.openFileDescriptor(docUri, "r")
                    ?: throw Exception("Could not open file descriptor")
                val packed = NativeEngine.nativeDiagnoseContainerFile(probeFd.detachFd(), opId)
                val formatOrdinal = if (packed != null && packed.size == 2) packed[1] else -1

                when (formatOrdinal) {
                    2 -> { // LUKS2 -- checksum-verified, no password needed.
                        val pfd = activity.contentResolver.openFileDescriptor(docUri, "rw")
                            ?: throw Exception("Could not open file descriptor")
                        val ok = NativeEngine.nativeRestoreLuks2BackupHeaderFile(pfd.detachFd(), opId)
                        activity.runOnUiThread {
                            if (ok) result.success(true)
                            else result.error("NOTHING_TO_REPAIR", "The backup header copy doesn't verify either", null)
                        }
                    }
                    0 -> { // VeraCrypt/TrueCrypt -- needs a password to decrypt-and-verify the backup first.
                        if (password.isNullOrEmpty()) {
                            activity.runOnUiThread {
                                result.error("PASSWORD_REQUIRED", "A password is needed to verify the backup header", null)
                            }
                            return@execute
                        }
                        val pfd = activity.contentResolver.openFileDescriptor(docUri, "rw")
                            ?: throw Exception("Could not open file descriptor")
                        val outcome = NativeEngine.nativeRestoreVeraCryptBackupHeaderFile(
                            pfd.detachFd(), password, pim, cipherId, hashId, opId
                        )
                        activity.runOnUiThread {
                            when (outcome) {
                                0, 2 -> result.success(true) // success, or already healthy -- nothing left to fix
                                1 -> result.error("PASSWORD_INCORRECT", "Incorrect password", null)
                                else -> result.error("IO_ERROR", "Could not restore the backup header", null)
                            }
                        }
                    }
                    else -> {
                        activity.runOnUiThread {
                            result.error("UNSUPPORTED_FORMAT", "This container format doesn't support backup-header restore", null)
                        }
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            }
        }
    }

    fun handleRunMountedVolumeFilesystemCheck(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Number>("volId")?.toInt()
        val opId = call.argument<Number>("opId")?.toInt() ?: -1
        if (volId == null) {
            result.error("INVALID_ARGS", "volId required", null)
            return
        }

        ioExecutor.execute {
            try {
                val ok = NativeEngine.nativeRunMountedVolumeFilesystemCheck(volId, opId)
                activity.runOnUiThread { result.success(ok) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            }
        }
    }

    /**
     * gocryptfs/CryFS/Cryptomator counterpart to
     * [handleDiagnoseUnmountedContainerFile]/[handleDiagnoseMountedVolumeFilesystem]:
     * these vaults are a directory tree, not a single container file
     * wrapping a block-device filesystem, so there's no fd to hand to
     * native code -- see foldercheck/FolderVaultChecker.kt for why the
     * check itself lives entirely on the Kotlin side. [password] is
     * optional: omitting it runs a structural-only scan (see that file's
     * doc comment for what each depth covers).
     */
    fun handleCheckFolderVault(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val format = call.argument<String>("format")
        val password = call.argument<String>("password")
        val opId = call.argument<Number>("opId")?.toInt() ?: -1
        if (uri.isNullOrEmpty() || format.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "uri and format required", null)
            return
        }

        ioExecutor.execute {
            val passwordChars = password?.toCharArray()
            try {
                val outcome = com.aeidolon.vaultexplorer.foldercheck.FolderVaultChecker.check(
                    activity, Uri.parse(uri), format, passwordChars,
                ) { line -> RepairLogBridge.reportLog(opId, line) }

                activity.runOnUiThread {
                    when (outcome) {
                        is com.aeidolon.vaultexplorer.foldercheck.FolderVaultCheckOutcome.Success -> {
                            val report = outcome.report
                            result.success(
                                mapOf(
                                    "format" to report.formatWire,
                                    "healthy" to report.healthy,
                                    "filesScanned" to report.filesScanned,
                                    "deepScanPerformed" to report.deepScanPerformed,
                                    "issues" to report.issues.map { issue ->
                                        mapOf(
                                            "severity" to issue.severity.wire,
                                            "path" to issue.path,
                                            "message" to issue.message,
                                        )
                                    },
                                ),
                            )
                        }
                        is com.aeidolon.vaultexplorer.foldercheck.FolderVaultCheckOutcome.InvalidVault ->
                            result.error("INVALID_VAULT", outcome.message, null)
                        is com.aeidolon.vaultexplorer.foldercheck.FolderVaultCheckOutcome.WrongPassword ->
                            result.error("PASSWORD_INCORRECT", "Incorrect password", null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            } finally {
                passwordChars?.fill(' ')
            }
        }
    }
}