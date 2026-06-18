package com.example.cryptbridge

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.cryptbridge/engine"
    private val PICK_CONTAINER_REQUEST = 1001
    private var pendingFlutterResult: MethodChannel.Result? = null

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
                    val uriString = call.argument<String>("filePath")
                    val password  = call.argument<String>("password")
                    val pim       = call.argument<Int>("pim") ?: 0

                    if (uriString == null || password == null) {
                        result.error("INVALID_ARGS", "filePath and password are required", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val volId = VeraCryptSession.getFreeVolumeId()
                            if (volId == null) {
                                runOnUiThread {
                                    result.error("LIMIT_REACHED", "Maximum 4 containers already mounted", null)
                                }
                                return@Thread
                            }

                            val uri = Uri.parse(uriString)
                            val pfd = contentResolver.openFileDescriptor(uri, "r")
                                ?: throw Exception("Could not open file descriptor")
                            val fd = pfd.detachFd()

                            val files = VeraCryptEngine.unlockAndListNative(fd, password, pim, volId)

                            runOnUiThread {
                                if (files != null) {
                                    VeraCryptSession.activeSessions[volId] = ContainerSession(
                                        uri      = uriString,
                                        password = password,
                                        pim      = pim,
                                        volId    = volId,
                                        cachedFilesList = files.toList()
                                    )

                                    // Notify OS sidebar
                                    val rootsUri = DocumentsContract.buildRootsUri(
                                        "com.example.cryptbridge.documents"
                                    )
                                    contentResolver.notifyChange(rootsUri, null)

                                    // Return both volId and file list so Flutter can track the slot
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
                        VeraCryptEngine.lockNative(volId)
                        VeraCryptSession.removeSession(volId)

                        val rootsUri = DocumentsContract.buildRootsUri(
                            "com.example.cryptbridge.documents"
                        )
                        contentResolver.notifyChange(rootsUri, null)
                        result.success(true)
                    } else {
                        // Already locked or unknown URI — treat as success
                        result.success(false)
                    }
                }

                "decryptFile" -> {
                    val uriString = call.argument<String>("filePath")
                    val password  = call.argument<String>("password")
                    val pim       = call.argument<Int>("pim") ?: 0
                    val fileName  = call.argument<String>("fileName")
                    val destPath  = call.argument<String>("destPath")

                    if (uriString == null || password == null ||
                        fileName == null || destPath == null) {
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

                            val success = VeraCryptEngine.unlockAndExtractNative(
                                fd, password, pim, fileName, destPath, volId
                            )
                            runOnUiThread { result.success(success) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("C++_CRASH", e.message, null) }
                        }
                    }.start()
                }

                // ── Future: list a subdirectory ──────────────────────────────
                // Uncomment and implement listDirectory in VeraCryptEngine + C++
                // to support in-app subdirectory navigation.
                //
                // "listDirectory" -> {
                //     val uriString = call.argument<String>("filePath")
                //     val password  = call.argument<String>("password")
                //     val pim       = call.argument<Int>("pim") ?: 0
                //     val dirPath   = call.argument<String>("dirPath") ?: ""
                //
                //     Thread {
                //         try {
                //             val volId = VeraCryptSession.getVolumeIdByUri(uriString!!) ?: 0
                //             val uri   = Uri.parse(uriString)
                //             val pfd   = contentResolver.openFileDescriptor(uri, "r")!!
                //             val fd    = pfd.detachFd()
                //             val files = VeraCryptEngine.listDirectoryNative(
                //                 fd, password!!, pim, dirPath, volId
                //             )
                //             runOnUiThread { result.success(files?.toList()) }
                //         } catch (e: Exception) {
                //             runOnUiThread { result.error("C++_ERROR", e.message, null) }
                //         }
                //     }.start()
                // }

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
        if (requestCode != PICK_CONTAINER_REQUEST) return

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
    }
} 