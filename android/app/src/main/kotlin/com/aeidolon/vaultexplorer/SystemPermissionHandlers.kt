package com.aeidolon.vaultexplorer

import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Small system-level MethodChannel calls that don't belong to any single
 * vault format: the FLAG_SECURE screenshot-blocking toggle, the "All files
 * access" special permission flow, clipboard sanitization (guards against a
 * known OEM bug where a corrupted primary clip crashes unrelated apps on
 * focus regain), and launching a file with an external app / chooser.
 */
class SystemPermissionHandlers(private val activity: MainActivity) {

    fun handleSetSecureScreen(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        if (enabled) {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        result.success(true)
    }

    fun handleHasAllFilesAccess(call: MethodCall, result: MethodChannel.Result) {
        val hasAccess = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
        result.success(hasAccess)
    }

    fun handleRequestAllFilesAccess(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
                activity.startActivity(intent)
            } catch (e: Exception) {
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    activity.startActivity(intent)
                } catch (e2: Exception) {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:${activity.packageName}")
                    }
                    activity.startActivity(intent)
                }
            }
        }
        result.success(true)
    }

    /** Copies vault-secret text to the primary clip, marking it sensitive
     *  ([ClipDescription.EXTRA_IS_SENSITIVE], API 33+) so the system
     *  clipboard preview / cross-device clipboard / OEM clipboard history
     *  redact it instead of showing the plaintext value. No-op fallback
     *  (plain copy) below API 33, where that flag doesn't exist. */
    fun handleSetSensitiveClipboardText(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        try {
            val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                ?: return result.success(false)
            val clip = ClipData.newPlainText("", text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                clip.description.extras = android.os.PersistableBundle().apply {
                    putBoolean(android.content.ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
            }
            clipboard.setPrimaryClip(clip)
            result.success(true)
        } catch (e: Exception) {
            result.error("CLIPBOARD_ERROR", e.message, null)
        }
    }

    /** Guards against a rare OEM clipboard bug where a corrupted primary
     *  clip (a mime-type entry that resolves to null) crashes any app that
     *  touches the clipboard; called from MainActivity.onWindowFocusChanged. */
    fun sanitizeClipboard() {
        try {
            val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
            if (clipboard.hasPrimaryClip()) {
                val description = clipboard.primaryClipDescription
                if (description != null) {
                    var isCorrupt = false
                    for (i in 0 until description.mimeTypeCount) {
                        if (description.getMimeType(i) == null) { isCorrupt = true; break }
                    }
                    if (isCorrupt) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                            clipboard.clearPrimaryClip()
                        else {
                            @Suppress("DEPRECATION")
                            clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                        }
                    }
                }
            }
        } catch (_: Exception) {}
    }

    fun handleSetKeepScreenOn(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        if (enabled) {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        result.success(true)
    }

    fun handleLaunchUrl(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url") ?: return result.error("INVALID_ARGS", "url required", null)
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            activity.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }

    fun handleGetAppVersion(call: MethodCall, result: MethodChannel.Result) {
        try {
            val pInfo = activity.packageManager.getPackageInfo(activity.packageName, 0)
            result.success(pInfo.versionName ?: "1.0.0")
        } catch (e: Exception) {
            result.success("1.0.0")
        }
    }

    fun handleOpenWithApp(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val fileName  = call.argument<String>("fileName")
        val packageName = call.argument<String>("packageName")
        val mimeTypeOverride = call.argument<String>("mimeType")

        if (uriString == null || fileName == null) {
            result.error(
                "INVALID_ARGS",
                "filePath and fileName required",
                null
            )
            return
        }

        try {
            val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                ?: run {
                    result.error("NOT_MOUNTED", "Container not mounted", null)
                    return
                }

            var finalDocId = "$volId:file:$fileName"
            if (mimeTypeOverride != null) {
                finalDocId += "?mimeType=" + mimeTypeOverride
            }

            val docUri = DocumentsContract.buildDocumentUri(
                "com.aeidolon.vaultexplorer.documents",
                finalDocId
            )

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(
                    docUri,
                    mimeTypeOverride ?: MimeTypeHelper.getMimeType(fileName)
                )
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
                if (!packageName.isNullOrEmpty()) {
                    setPackage(packageName)
                }
            }

            if (!packageName.isNullOrEmpty()) {
                try {
                    activity.startActivity(intent)
                } catch (e: Exception) {
                    intent.setPackage(null)
                    val receiverIntent = Intent(activity.ACTION_CHOOSER).apply {
                        val ext = fileName.substringAfterLast('.', "")
                        putExtra("extension", ext)
                        `package` = activity.packageName
                    }
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                    val pendingIntent = PendingIntent.getBroadcast(activity, 0, receiverIntent, flags)
                    val chooser = Intent.createChooser(intent, "Open file with…", pendingIntent.intentSender)
                    activity.startActivity(chooser)
                }
            } else {
                val receiverIntent = Intent(activity.ACTION_CHOOSER).apply {
                    val ext = fileName.substringAfterLast('.', "")
                    putExtra("extension", ext)
                    `package` = activity.packageName
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val pendingIntent = PendingIntent.getBroadcast(activity, 0, receiverIntent, flags)
                val chooser = Intent.createChooser(intent, "Open file with…", pendingIntent.intentSender)
                activity.startActivity(chooser)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_WITH_ERROR", e.message, null)
        }
    }
}