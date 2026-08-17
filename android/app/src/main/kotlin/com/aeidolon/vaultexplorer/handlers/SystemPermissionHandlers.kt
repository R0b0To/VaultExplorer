package com.aeidolon.vaultexplorer.handlers

import android.Manifest
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.MimeTypeHelper

const val STORAGE_PERMISSION_REQUEST_CODE = 9822

class SystemPermissionHandlers(private val activity: MainActivity) {
    var userWantsSecureScreen = false
        private set

    private var backgroundProtectionActive = false

    fun handleSetSecureScreen(call: MethodCall, result: MethodChannel.Result) {
        userWantsSecureScreen = call.argument<Boolean>("enabled") ?: false
        applySecureFlag()
        result.success(true)
    }

    fun handleSetRecentsSnapshotBlocked(call: MethodCall, result: MethodChannel.Result) {
        val blocked = call.argument<Boolean>("blocked") ?: false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.setRecentsScreenshotEnabled(!blocked)
        }
        result.success(true)
    }

    fun setBackgroundProtectionActive(active: Boolean) {
        // Disabled dynamic toggling on pause/resume to prevent SurfaceFlinger hardware flashes
    }

    private fun applySecureFlag() {
        if (userWantsSecureScreen) {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    fun handleHasAllFilesAccess(call: MethodCall, result: MethodChannel.Result) {
        val hasAccess = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                Environment.isExternalStorageManager()
            // API 26-29: READ/WRITE_EXTERNAL_STORAGE are dangerous
            // permissions here and need an explicit runtime grant, same
            // as All Files Access does on 11+ -- there's no automatic
            // grant on these versions.
            else ->
                ContextCompat.checkSelfPermission(
                    activity, Manifest.permission.WRITE_EXTERNAL_STORAGE
                ) == PackageManager.PERMISSION_GRANTED
        }
        result.success(hasAccess)
    }

    fun handleRequestAllFilesAccess(call: MethodCall, result: MethodChannel.Result) {
        // On API 26-29, revoking is the caller's intent when this is true --
        // Android has no API for an app to drop its own granted runtime
        // permission, so that path always needs Settings, same as 30+.
        val forceSettings = call.argument<Boolean>("openSettings") ?: false
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
                    openAppDetailsSettings()
                }
            }
            result.success(true)
        } else if (forceSettings) {
            // API 26-29 has no per-permission deep link like 30+'s
            // MANAGE_APP_ALL_FILES_ACCESS_PERMISSION -- the app's own
            // "App info" page (where the user taps into "Permissions")
            // is the closest equivalent, so go straight there instead of
            // trying 11+-only intents first.
            openAppDetailsSettings()
            result.success(true)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // API 26-29: fire the standard runtime permission dialog. The
            // grant result arrives asynchronously via
            // MainActivity.onRequestPermissionsResult, which forwards it
            // to Dart as "onStoragePermissionResult" -- see
            // VaultExplorerApi.awaitStoragePermissionResult().
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ),
                STORAGE_PERMISSION_REQUEST_CODE,
            )
            result.success(true)
        } else {
            result.success(true)
        }
    }

    private fun openAppDetailsSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        activity.startActivity(intent)
    }

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

    fun handleGetAndroidSdkInt(call: MethodCall, result: MethodChannel.Result) {
        result.success(Build.VERSION.SDK_INT)
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