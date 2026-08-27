package com.aeidolon.vaultexplorer.handlers

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.bridge.CopyProgressBridge
import com.aeidolon.vaultexplorer.cancellation.CopyCancellation

class FileOperationHandlers(
    private val nativeOps: NativeOpSupport,
    private val fullResExecutor: ExecutorService,
) {
    companion object {
        const val MAX_CHUNK_BYTES = 64 * 1024 * 1024  // 64 MB
    }

    private val queryExecutor: ExecutorService = Executors.newFixedThreadPool(4)

    fun handleDecryptFile(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val destPath = call.argument<String>("destPath")
        if (fileName == null || destPath == null) {
            result.error("INVALID_ARGS", "fileName and destPath required", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.extractToFile(volId, fileName, destPath)
        }
    }

    fun handleGetFileSize(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        if (fileName == null) {
            result.error("INVALID_ARGS", "fileName required", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result, executor = queryExecutor) { volId ->
            ContainerFileSystem.getFileSize(volId, fileName)
        }
    }

    fun handleGetFolderSize(call: MethodCall, result: MethodChannel.Result) {
        val dirPath = call.argument<String>("dirPath") ?: ""
        nativeOps.runNativeOp(call.argument<String>("filePath"), result, executor = queryExecutor) { volId ->
            ContainerFileSystem.getFolderSize(volId, dirPath)
        }
    }

    fun handleReadFileChunk(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val offset    = call.argument<Number>("offset")?.toLong() ?: 0L
        val length    = call.argument<Number>("length")?.toInt() ?: 0
        if (fileName == null) {
            result.error("INVALID_ARGS", "fileName required", null)
            return
        }
        if (length <= 0 || length > MAX_CHUNK_BYTES) {
            result.error("INVALID_ARGS", "length must be between 1 and $MAX_CHUNK_BYTES bytes", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.readFileChunk(volId, fileName, offset, length)
        }
    }

    fun handleGetMediaFileSize(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        if (fileName == null) {
            result.error("INVALID_ARGS", "fileName required", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result, executor = fullResExecutor) { volId ->
            ContainerFileSystem.getFileSize(volId, fileName)
        }
    }

    fun handleReadMediaFileChunk(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val offset    = call.argument<Number>("offset")?.toLong() ?: 0L
        val length    = call.argument<Number>("length")?.toInt() ?: 0
        if (fileName == null) {
            result.error("INVALID_ARGS", "fileName required", null)
            return
        }
        if (length <= 0 || length > MAX_CHUNK_BYTES) {
            result.error("INVALID_ARGS", "length must be between 1 and $MAX_CHUNK_BYTES bytes", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result, executor = fullResExecutor) { volId ->
            ContainerFileSystem.readFileChunk(volId, fileName, offset, length)
        }
    }

    fun handleListDirectory(call: MethodCall, result: MethodChannel.Result) {
        val dirPath = call.argument<String>("dirPath") ?: ""
        val refresh = call.argument<Boolean>("refresh") ?: false
        nativeOps.runNativeOp(call.argument<String>("filePath"), result, executor = queryExecutor) { volId ->
            if (refresh) {
                ContainerFileSystem.invalidateCache(volId, dirPath)
            }
            ContainerFileSystem.listDirectory(volId, dirPath)?.toList()
        }
    }

    fun handleCreateDirectory(call: MethodCall, result: MethodChannel.Result) {
        val dirPath = call.argument<String>("dirPath")
        if (dirPath == null) {
            result.error("INVALID_ARGS", "dirPath required", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.createDirectory(volId, dirPath)
        }
    }

    fun handleRenameFile(call: MethodCall, result: MethodChannel.Result) {
        val oldPath = call.argument<String>("oldPath")
        val newPath = call.argument<String>("newPath")
        if (oldPath == null || newPath == null) {
            result.error("INVALID_ARGS", "oldPath and newPath required", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.renameFile(volId, oldPath, newPath)
        }
    }

    fun handleCopyFile(call: MethodCall, result: MethodChannel.Result) {
        val srcPath = call.argument<String>("srcPath")
        val destPath = call.argument<String>("destPath")
        val srcUri = call.argument<String>("srcUri")
        val destUri = call.argument<String>("destUri")
        // opId is optional -- absent/0 just means the caller doesn't want
        // progress callbacks (see CopyProgressBridge / NativeEngine.copyFile).
        val opId = call.argument<Int>("opId") ?: 0
        if (srcPath == null || destPath == null || srcUri == null || destUri == null) {
            result.error("INVALID_ARGS", "srcPath, destPath, srcUri, and destUri required", null)
            return
        }
        nativeOps.runNativeOp(srcUri, result) { srcVolId ->
            val destVolId = ContainerSessionRegistry.getVolumeIdByUri(destUri)
                ?: throw IllegalStateException("NOT_UNLOCKED: dest")
            try {
                ContainerFileSystem.copyFile(srcVolId, srcPath, destVolId, destPath, opId)
            } finally {
                // Flush whatever's still sitting in the 50ms throttle window --
                // otherwise the tail of the file (up to one throttle interval's
                // worth of chunks) never reaches Dart and transferredBytes falls
                // permanently short of totalBytes for this file.
                if (opId > 0) CopyProgressBridge.flushPending(opId)
            }
        }
    }

    fun handleCancelCopy(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId == null) {
            result.error("INVALID_ARGS", "opId required", null)
            return
        }
        CopyCancellation.cancel(opId)
        result.success(true)
    }

    /**
     * Called once from Dart's FileOperationService._run() finally block,
     * after every item in a copy/move op.id has finished -- NOT per-file
     * (unlike CopyProgressBridge.flushPending above). Clearing
     * CopyCancellation mid-operation would incorrectly "un-cancel" other
     * items still in flight under the same shared opId.
     */
    fun handleClearCopyState(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId == null) {
            result.error("INVALID_ARGS", "opId required", null)
            return
        }
        CopyCancellation.clear(opId)
        CopyProgressBridge.clear(opId)
        result.success(true)
    }

    fun handleWriteBackFile(call: MethodCall, result: MethodChannel.Result) {
        val fileName   = call.argument<String>("fileName")
        val sourcePath = call.argument<String>("sourcePath")
        if (fileName == null || sourcePath == null) {
            result.error("INVALID_ARGS", "fileName and sourcePath required", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.writeBackFile(volId, fileName, sourcePath)
        }
    }

    fun handleSetLastModifiedTime(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val epochSecs = call.argument<Number>("epochSeconds")?.toLong()
        if (fileName == null || epochSecs == null) {
            result.error("INVALID_ARGS", "fileName and epochSeconds required", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.setLastModifiedTime(volId, fileName, epochSecs)
        }
    }

    fun handleGetSpaceInfo(call: MethodCall, result: MethodChannel.Result) {
        nativeOps.runNativeOp(call.argument<String>("filePath"), result, executor = queryExecutor) { volId ->
            ContainerFileSystem.getSpaceInfo(volId)?.toList()
        }
    }

    fun handleGetVaultInfo(call: MethodCall, result: MethodChannel.Result) {
        nativeOps.runNativeOp(call.argument<String>("filePath"), result, executor = queryExecutor) { volId ->
            ContainerFileSystem.getVaultInfo(volId)
        }
    }

    fun handleDeleteFile(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        if (fileName == null) {
            result.error("INVALID_ARGS", "fileName required", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.deleteFile(volId, fileName)
        }
    }

    fun handleWriteFileChunk(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val offset   = call.argument<Number>("offset")?.toLong() ?: 0L
        val data     = call.argument<ByteArray>("data")
        if (fileName == null || data == null) {
            result.error("INVALID_ARGS", "fileName and data required", null)
            return
        }
        if (data.size > MAX_CHUNK_BYTES) {
            result.error("INVALID_ARGS", "Chunk too large (max $MAX_CHUNK_BYTES bytes)", null)
            return
        }
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.writeFileChunk(volId, fileName, offset, data)
        }
    }

    fun handleBeginBatchWrite(call: MethodCall, result: MethodChannel.Result) {
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.beginBatchWrite(volId)
            true
        }
    }

    fun handleEndBatchWrite(call: MethodCall, result: MethodChannel.Result) {
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.endBatchWrite(volId)
            true
        }
    }

    fun handleBeginBatchDelete(call: MethodCall, result: MethodChannel.Result) {
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.beginBatchDelete(volId)
            true
        }
    }

    fun handleEndBatchDelete(call: MethodCall, result: MethodChannel.Result) {
        nativeOps.runNativeOp(call.argument<String>("filePath"), result) { volId ->
            ContainerFileSystem.endBatchDelete(volId)
            true
        }
    }
}
    

