package com.example.cryptbridge

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.cryptbridge/engine"
    private val PICK_CONTAINER_REQUEST = 1001
    private val IMPORT_FILE_REQUEST = 1002
    private val EXPORT_FILE_REQUEST = 1003
    private var pendingFlutterResult: MethodChannel.Result? = null

    // Temporary variables to track background picker operations
    private var pendingImportContainerUri: String? = null
    private var pendingImportTargetName: String? = null
    private var pendingImportPassword: String? = null
    private var pendingImportPim: Int = 0
    private var pendingImportVolId: Int = 0

    private var pendingExportContainerUri: String? = null
    private var pendingExportSourcePath: String? = null
    private var pendingExportPassword: String? = null
    private var pendingExportPim: Int = 0
    private var pendingExportVolId: Int = 0

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {

                "pickContainer" -> {
                    pendingResultCheck(result)
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, PICK_CONTAINER_REQUEST)
                }

                "unlockContainer" -> {
                    val uriString   = call.argument<String>("filePath")
                    val password    = call.argument<String>("password")
                    val pim         = call.argument<Number>("pim")?.toInt() ?: 0
                    val displayName = call.argument<String>("displayName")

                    if (uriString == null || password == null) {
                        result.error("INVALID_ARGS", "filePath and password are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                            val uri = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "r")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val files = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.unlockAndListNative(fd, password, pim, volId)
                            }

                            runOnUiThread {
                                if (files != null) {
                                    VeraCryptSession.activeSessions[volId] = ContainerSession(
                                        uri      = uriString,
                                        password = password,
                                        pim      = pim,
                                        volId    = volId,
                                        cachedFilesList = files.toList(),
                                        displayName = displayName
                                    )

                                    val rootsUri = DocumentsContract.buildRootsUri("com.example.cryptbridge.documents")
                                    contentResolver.notifyChange(rootsUri, null)

                                    result.success(mapOf(
                                        "volId" to volId,
                                        "files" to files.toList()
                                    ))
                                } else {
                                    result.error("AUTH_FAIL", "Incorrect password or invalid container", null)
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "lockContainer" -> {
                    val uriString = call.argument<String>("filePath")
                    if (uriString == null) {
                        result.error("INVALID_ARGS", "filePath is required", null)
                        return@setMethodCallHandler
                    }

                    val volId = VeraCryptSession.getVolumeIdByUri(uriString)
                    if (volId != null) {
                        synchronized(VeraCryptSession.locks[volId]) {
                            VeraCryptEngine.lockNative(volId)
                        }
                        VeraCryptSession.removeSession(volId)

                        val rootsUri = DocumentsContract.buildRootsUri("com.example.cryptbridge.documents")
                        contentResolver.notifyChange(rootsUri, null)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }

                "decryptFile" -> {
                    val uriString = call.argument<String>("filePath")
                    val password  = call.argument<String>("password")
                    val pim       = call.argument<Number>("pim")?.toInt() ?: 0
                    val fileName  = call.argument<String>("fileName")
                    val destPath  = call.argument<String>("destPath")

                    if (uriString == null || password == null || fileName == null || destPath == null) {
                        result.error("INVALID_ARGS", "All arguments are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                            val uri = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "r")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val success = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.unlockAndExtractNative(fd, password, pim, fileName, destPath, volId)
                            }
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_CRASH", e.message, null) }
                        }
                    }.start()
                }

                "getFileSize" -> {
                    val uriString = call.argument<String>("filePath")
                    val password  = call.argument<String>("password")
                    val pim       = call.argument<Number>("pim")?.toInt() ?: 0
                    val fileName  = call.argument<String>("fileName")

                    if (uriString == null || password == null || fileName == null) {
                        result.error("INVALID_ARGS", "filePath, password, and fileName are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                            val uri = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "r")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val size = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.getFileSizeNative(fd, password, pim, fileName, volId)
                            }
                            runOnUiThread { result.success(size) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_CRASH", e.message, null) }
                        }
                    }.start()
                }

                "readFileChunk" -> {
                    val uriString = call.argument<String>("filePath")
                    val password  = call.argument<String>("password")
                    val pim       = call.argument<Number>("pim")?.toInt() ?: 0
                    val fileName  = call.argument<String>("fileName")
                    val offset    = call.argument<Number>("offset")?.toLong() ?: 0L
                    val length    = call.argument<Number>("length")?.toInt() ?: 0

                    if (uriString == null || password == null || fileName == null) {
                        result.error("INVALID_ARGS", "filePath, password, and fileName are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                            val uri = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "r")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val bytes = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.readFileChunkNative(fd, password, pim, fileName, offset, length, volId)
                            }
                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_CRASH", e.message, null) }
                        }
                    }.start()
                }

                "listDirectory" -> {
                    val uriString = call.argument<String>("filePath")
                    val password  = call.argument<String>("password")
                    val pim       = call.argument<Number>("pim")?.toInt() ?: 0
                    val dirPath   = call.argument<String>("dirPath") ?: ""

                    if (uriString == null || password == null) {
                        result.error("INVALID_ARGS", "filePath and password are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                            val uri   = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "r")
                                ?: throw Exception("Could not open file descriptor")
                            val fd    = pfd.detachFd()
                            
                            val files = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.listDirectoryNative(fd, password, pim, dirPath, volId)
                            }
                            runOnUiThread { result.success(files?.toList()) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "createDirectory" -> {
                    val uriString = call.argument<String>("filePath")
                    val password  = call.argument<String>("password")
                    val pim       = call.argument<Number>("pim")?.toInt() ?: 0
                    val dirPath   = call.argument<String>("dirPath")

                    if (uriString == null || password == null || dirPath == null) {
                        result.error("INVALID_ARGS", "All arguments are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                            val uri = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "rw")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val success = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.createDirectoryNative(fd, password, pim, dirPath, volId)
                            }
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "renameFile" -> {
                    val uriString = call.argument<String>("filePath")
                    val password  = call.argument<String>("password")
                    val pim       = call.argument<Number>("pim")?.toInt() ?: 0
                    val oldPath   = call.argument<String>("oldPath")
                    val newPath   = call.argument<String>("newPath")

                    if (uriString == null || password == null || oldPath == null || newPath == null) {
                        result.error("INVALID_ARGS", "All arguments are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                            val uri = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "rw")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val success = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.renameFileNative(fd, password, pim, oldPath, newPath, volId)
                            }
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "writeBackFile" -> {
                    val uriString  = call.argument<String>("filePath")
                    val password   = call.argument<String>("password")
                    val pim        = call.argument<Number>("pim")?.toInt() ?: 0
                    val fileName   = call.argument<String>("fileName")
                    val sourcePath = call.argument<String>("sourcePath")

                    if (uriString == null || password == null || fileName == null || sourcePath == null) {
                        result.error("INVALID_ARGS", "All arguments are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                            val uri = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "rw")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val success = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.writeBackFileNative(fd, password, pim, fileName, sourcePath, volId)
                            }
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_ERROR", e.message, null) }
                        }
                    }.start()
                }
                // Add this handler inside configureFlutterEngine's when (call.method) block in MainActivity.kt:

"getSpaceInfo" -> {
    val uriString = call.argument<String>("filePath")
    val password  = call.argument<String>("password")
    val pim       = call.argument<Number>("pim")?.toInt() ?: 0

    if (uriString == null || password == null) {
        result.error("INVALID_ARGS", "filePath and password are required", null)
        return@setMethodCallHandler
    }

    Thread {
        try {
            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
            val uri = Uri.parse(uriString)
            val pfd = contentResolver.openFileDescriptor(uri, "r")
                ?: throw Exception("Could not open file descriptor")
            val fd = pfd.detachFd()

            val space = synchronized(VeraCryptSession.locks[volId]) {
                VeraCryptEngine.getSpaceInfoNative(fd, password, pim, volId)
            }
            runOnUiThread { result.success(space?.toList()) }
        } catch (e: Exception) {
            runOnUiThread { result.error("C++_CRASH", e.message, null) }
        }
    }.start()
}
                "deleteFile" -> {
                    val uriString = call.argument<String>("filePath")
                    val password  = call.argument<String>("password")
                    val pim       = call.argument<Number>("pim")?.toInt() ?: 0
                    val fileName  = call.argument<String>("fileName")

                    if (uriString == null || password == null || fileName == null) {
                        result.error("INVALID_ARGS", "All arguments are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                            val uri = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "rw")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val success = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.deleteFileNative(fd, password, pim, fileName, volId)
                            }
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "openWithApp" -> {
                    val uriString = call.argument<String>("filePath")
                    val fileName  = call.argument<String>("fileName")
                    
                    if (uriString == null || fileName == null) {
                        result.error("INVALID_ARGS", "filePath and fileName are required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val volId = VeraCryptSession.getVolumeIdByUri(uriString) ?: 0
                        val authority = "com.example.cryptbridge.documents"
                        val documentId = "$volId:file:$fileName"
                        val docUri = DocumentsContract.buildDocumentUri(authority, documentId)

                        val mimeType = getMimeType(fileName)

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(docUri, mimeType)
                            // Enforce both READ and WRITE permissions so editors can write back to our provider [5]
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        }

                        val chooser = Intent.createChooser(intent, "Open file with...")
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_WITH_ERROR", e.message, null)
                    }
                }

                "importFile" -> {
                    pendingResultCheck(result)
                    pendingImportContainerUri = call.argument<String>("filePath")
                    pendingImportTargetName   = call.argument<String>("targetPath") // destination folder path
                    pendingImportPassword     = call.argument<String>("password")
                    pendingImportPim          = call.argument<Number>("pim")?.toInt() ?: 0
                    pendingImportVolId        = VeraCryptSession.getVolumeIdByUri(pendingImportContainerUri!!) ?: 0

                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, IMPORT_FILE_REQUEST)
                }

                "exportFileToStorage" -> {
                    pendingResultCheck(result)
                    pendingExportContainerUri = call.argument<String>("filePath")
                    pendingExportSourcePath   = call.argument<String>("sourcePath")
                    pendingExportPassword     = call.argument<String>("password")
                    pendingExportPim          = call.argument<Number>("pim")?.toInt() ?: 0
                    pendingExportVolId        = VeraCryptSession.getVolumeIdByUri(pendingExportContainerUri!!) ?: 0

                    val fileName = pendingExportSourcePath!!.split("/").last()

                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = getMimeType(fileName)
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, EXPORT_FILE_REQUEST)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun pendingResultCheck(result: MethodChannel.Result) {
        pendingFlutterResult?.error("PICK_CANCELLED", "Another pick operation started", null)
        pendingFlutterResult = result
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == PICK_CONTAINER_REQUEST) {
            val result = pendingFlutterResult ?: return
            pendingFlutterResult = null

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                val takeFlags =
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                contentResolver.takePersistableUriPermission(uri, takeFlags)
                result.success(uri.toString())
            } else {
                result.success(null)
            }
            return
        }

        if (requestCode == IMPORT_FILE_REQUEST) {
            val result = pendingFlutterResult ?: return
            pendingFlutterResult = null

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val pickedUri = data.data!!
                val containerUri = pendingImportContainerUri
                val targetDir = pendingImportTargetName ?: ""
                val password = pendingImportPassword
                val pim = pendingImportPim
                val volId = pendingImportVolId

                if (containerUri != null && password != null) {
                    Thread {
                        try {
                            // Extract the original display name from the Content URI automatically [5]
                            var cleanPickedName = "imported_file"
                            contentResolver.query(pickedUri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                                    if (nameIndex != -1) {
                                        cleanPickedName = cursor.getString(nameIndex)
                                    }
                                }
                            }

                            val targetName = if (targetDir.isEmpty()) cleanPickedName else "$targetDir/$cleanPickedName"

                            // Copy picked file bytes directly to RAM cache folder
                            val tempFile = File(cacheDir, "import_temp")
                            contentResolver.openInputStream(pickedUri)?.use { input ->
                                tempFile.outputStream().use { output ->
                                    input.copyTo(output)
                                }
                            }

                            val uri = Uri.parse(containerUri)
                            val pfd = contentResolver.openFileDescriptor(uri, "rw")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val success = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.writeBackFileNative(
                                    fd, password, pim, targetName, tempFile.absolutePath, volId
                                )
                            }
                            tempFile.delete()

                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("IMPORT_ERROR", e.message, null) }
                        }
                    }.start()
                } else {
                    result.success(false)
                }
            } else {
                result.success(false)
            }
            return
        }

        if (requestCode == EXPORT_FILE_REQUEST) {
            val result = pendingFlutterResult ?: return
            pendingFlutterResult = null

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val destinationUri = data.data!!
                val containerUri = pendingExportContainerUri
                val sourcePath = pendingExportSourcePath
                val password = pendingExportPassword
                val pim = pendingExportPim
                val volId = pendingExportVolId

                if (containerUri != null && sourcePath != null && password != null) {
                    Thread {
                        try {
                            val tempFile = File(cacheDir, "export_temp")

                            val uri = Uri.parse(containerUri)
                            val pfd = contentResolver.openFileDescriptor(uri, "r")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val success = synchronized(VeraCryptSession.locks[volId]) {
                                VeraCryptEngine.unlockAndExtractNative(
                                    fd, password, pim, sourcePath, tempFile.absolutePath, volId
                                )
                            }

                            if (success && tempFile.exists()) {
                                contentResolver.openOutputStream(destinationUri)?.use { output ->
                                    tempFile.inputStream().use { input ->
                                        input.copyTo(output)
                                    }
                                }
                                tempFile.delete()
                                runOnUiThread { result.success(true) }
                            } else {
                                tempFile.delete()
                                runOnUiThread { result.success(false) }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("EXPORT_ERROR", e.message, null) }
                        }
                    }.start()
                } else {
                    result.success(false)
                }
            } else {
                result.success(false)
            }
            return
        }
    }

    private fun getMimeType(fileName: String): String {
        return when {
            fileName.endsWith(".png", true) -> "image/png"
            fileName.endsWith(".jpg", true) || fileName.endsWith(".jpeg", true) -> "image/jpeg"
            fileName.endsWith(".webp", true) -> "image/webp"
            fileName.endsWith(".gif", true) -> "image/gif"
            fileName.endsWith(".mp4", true) || fileName.endsWith(".m4v", true) -> "video/mp4"
            fileName.endsWith(".webm", true) -> "video/webm"
            fileName.endsWith(".mkv", true) -> "video/x-matroska"
            fileName.endsWith(".txt", true) -> "text/plain"
            fileName.endsWith(".pdf", true) -> "application/pdf"
            else -> "application/octet-stream"
        }
    }
}