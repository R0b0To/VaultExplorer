package com.aeidolon.vaultexplorer.handlers

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.aeidolon.vaultexplorer.cancellation.CopyCancellation
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.saf.SafStorageManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** The narrow native file API required by the headless Dart sync runner. */
internal class ScheduledSyncFileBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext
    private val saf = SafStorageManager(appContext)
    private val executor = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val hashSessions = ConcurrentHashMap<Int, MessageDigest>()

    fun dispose() {
        executor.shutdownNow()
        hashSessions.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getFileSize" -> vaultCall(call, result) { volId ->
                ContainerFileSystem.getFileSize(volId, requiredString(call, "fileName"))
            }
            "readFileChunk" -> vaultCall(call, result) { volId ->
                ContainerFileSystem.readFileChunk(
                    volId,
                    requiredString(call, "fileName"),
                    number(call, "offset").toLong(),
                    number(call, "length").toInt(),
                )
            }
            "writeFileChunk" -> vaultCall(call, result) { volId ->
                ContainerFileSystem.writeFileChunk(
                    volId,
                    requiredString(call, "fileName"),
                    number(call, "offset").toLong(),
                    call.argument<ByteArray>("data") ?: error("data is required"),
                )
            }
            "finishWrite" -> run(call, result) {
                ContainerFileSystem.finishWrite(
                    number(call, "volId").toInt(),
                    requiredString(call, "path"),
                )
            }
            "listDirectory" -> vaultCall(call, result) { volId ->
                val path = call.argument<String>("dirPath") ?: ""
                if (call.argument<Boolean>("refresh") == true) {
                    ContainerFileSystem.invalidateCache(volId, path)
                }
                ContainerFileSystem.listDirectory(volId, path)?.toList()
            }
            "createDirectory" -> vaultCall(call, result) { volId ->
                ContainerFileSystem.createDirectory(volId, requiredString(call, "dirPath"))
            }
            "renameFile" -> vaultCall(call, result) { volId ->
                ContainerFileSystem.renameFile(
                    volId,
                    requiredString(call, "oldPath"),
                    requiredString(call, "newPath"),
                )
            }
            "deleteFile" -> vaultCall(call, result) { volId ->
                ContainerFileSystem.deleteFile(volId, requiredString(call, "fileName"))
            }
            "setLastModifiedTime" -> vaultCall(call, result) { volId ->
                ContainerFileSystem.setLastModifiedTime(
                    volId,
                    requiredString(call, "fileName"),
                    number(call, "epochSeconds").toLong(),
                )
            }
            "writeBackFile" -> vaultCall(call, result) { volId ->
                ContainerFileSystem.writeBackFile(
                    volId,
                    requiredString(call, "fileName"),
                    requiredString(call, "sourcePath"),
                    number(call, "opId", 0).toInt(),
                )
            }
            "decryptFile" -> vaultCall(call, result) { volId ->
                ContainerFileSystem.extractToFile(
                    volId,
                    requiredString(call, "fileName"),
                    requiredString(call, "destPath"),
                    number(call, "opId", 0).toInt(),
                    singlePass = true,
                )
            }
            "copyFile" -> run(call, result) {
                val srcVol = ContainerSessionRegistry.getVolumeIdByUri(requiredString(call, "srcUri"))
                    ?: error("Source vault is not mounted")
                val destVol = ContainerSessionRegistry.getVolumeIdByUri(requiredString(call, "destUri"))
                    ?: error("Destination vault is not mounted")
                ContainerFileSystem.copyFile(
                    srcVol,
                    requiredString(call, "srcPath"),
                    destVol,
                    requiredString(call, "destPath"),
                    number(call, "opId", 0).toInt(),
                )
            }
            "cancelCopy" -> run(call, result) {
                CopyCancellation.cancel(number(call, "opId").toInt())
                true
            }
            "clearCopyState" -> run(call, result) {
                CopyCancellation.clear(number(call, "opId").toInt())
                true
            }
            "safCanListDirectory" -> safCall(call, result) { tree, path ->
                saf.canListDirectory(tree, path)
            }
            "safListDirectory" -> safCall(call, result) { tree, path ->
                saf.listDirectory(tree, path, call.argument<Boolean>("refresh") == true).map { entry ->
                    mapOf(
                        "name" to entry.name,
                        "isDir" to entry.isDir,
                        "size" to entry.size,
                        "lastModified" to entry.lastModified,
                    )
                }
            }
            "safGetFileSize" -> safCall(call, result) { tree, path -> saf.getFileSize(tree, path) }
            "safReadFileChunk" -> safCall(call, result) { tree, path ->
                saf.readFileChunk(
                    tree,
                    path,
                    number(call, "offset").toLong(),
                    number(call, "length").toInt(),
                )
            }
            "safWriteFileChunk" -> safCall(call, result) { tree, path ->
                saf.writeFileChunk(
                    tree,
                    path,
                    number(call, "offset").toLong(),
                    call.argument<ByteArray>("data") ?: error("data is required"),
                )
            }
            "safCreateDirectory" -> run(call, result) {
                saf.createDirectory(
                    Uri.parse(requiredString(call, "treeUri")),
                    call.argument<String>("parentPath") ?: "",
                    requiredString(call, "dirName"),
                )
            }
            "safRenameFile" -> run(call, result) {
                saf.renameFile(
                    Uri.parse(requiredString(call, "treeUri")),
                    requiredString(call, "filePath"),
                    requiredString(call, "newName"),
                )
            }
            "safDeleteFile" -> run(call, result) {
                saf.deleteRecursively(
                    Uri.parse(requiredString(call, "treeUri")),
                    requiredString(call, "filePath"),
                )
            }
            "beginHashSession" -> run(call, result) {
                val opId = number(call, "opId").toInt()
                val algorithms = call.argument<List<String>>("algorithms") ?: error("algorithms are required")
                require(algorithms == listOf("SHA-256")) { "Scheduled sync only supports SHA-256" }
                hashSessions[opId] = MessageDigest.getInstance("SHA-256")
                null
            }
            "updateHashSession" -> run(call, result) {
                val digest = hashSessions[number(call, "opId").toInt()] ?: error("Hash session is missing")
                digest.update(call.argument<ByteArray>("bytes") ?: error("bytes are required"))
                null
            }
            "finishHashSession" -> run(call, result) {
                val opId = number(call, "opId").toInt()
                val digest = hashSessions.remove(opId) ?: error("Hash session is missing")
                mapOf("SHA-256" to digest.digest().joinToString("") { "%02x".format(it) })
            }
            "discardHashSession" -> run(call, result) {
                hashSessions.remove(number(call, "opId").toInt())
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun vaultCall(
        call: MethodCall,
        result: MethodChannel.Result,
        operation: (Int) -> Any?,
    ) {
        val vaultUri = call.argument<String>("filePath")
        if (vaultUri.isNullOrBlank()) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Vault is not mounted", null)
            return
        }
        run(call, result) { operation(volId) }
    }

    private fun safCall(
        call: MethodCall,
        result: MethodChannel.Result,
        operation: (Uri, String) -> Any?,
    ) {
        val tree = call.argument<String>("treeUri")
        if (tree.isNullOrBlank()) {
            result.error("INVALID_ARGS", "treeUri is required", null)
            return
        }
        val path = call.argument<String>("filePath") ?: call.argument<String>("dirPath") ?: ""
        run(call, result) { operation(Uri.parse(tree), path) }
    }

    private fun run(call: MethodCall, result: MethodChannel.Result, operation: () -> Any?) {
        executor.execute {
            try {
                val value = operation()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("SCHEDULED_SYNC_IO", e.message ?: "I/O failed", null) }
            }
        }
    }

    private fun requiredString(call: MethodCall, key: String): String =
        call.argument<String>(key)?.takeIf { it.isNotEmpty() } ?: error("$key is required")

    private fun number(call: MethodCall, key: String, default: Number? = null): Number =
        call.argument<Number>(key) ?: default ?: error("$key is required")
}
