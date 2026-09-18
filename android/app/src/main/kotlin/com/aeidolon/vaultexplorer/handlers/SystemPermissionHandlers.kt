package com.aeidolon.vaultexplorer.handlers

import android.Manifest
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import android.view.WindowManager
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.R

const val STORAGE_PERMISSION_REQUEST_CODE = 9822
const val NOTIFICATION_PERMISSION_REQUEST_CODE = 9823

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
        val hasAccess = com.aeidolon.vaultexplorer.RawFileResolver.hasExternalStoragePermission(activity)
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

    /**
     * Requests `POST_NOTIFICATIONS`, needed on API 33+ before the
     * "keep vaults running in background" foreground service's
     * notification can actually be shown. Fired unconditionally rather
     * than pre-checking [ContextCompat.checkSelfPermission]: when the
     * permission is already granted (or on API 30-32, where it doesn't
     * exist as a runtime permission at all -- POST_NOTIFICATIONS itself
     * was only introduced in 33), requestPermissions() still delivers an
     * immediate PERMISSION_GRANTED callback with no dialog shown, so
     * callers don't need a separate has-permission check first. The
     * result arrives asynchronously via
     * MainActivity.onRequestPermissionsResult, which forwards it to Dart
     * as "onNotificationPermissionResult" -- see
     * VaultExplorerApi.awaitNotificationPermissionResult().
     */
    fun handleRequestNotificationPermission(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST_CODE,
            )
            result.success(true)
        } else {
            // Below API 33, notifications don't require a runtime grant.
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

    /**
     * Clears the clipboard the way [SensitiveClipboard]'s 30-second timer
     * wants it cleared: silently.
     *
     * [ClipboardManager.setPrimaryClip], even with an empty [ClipData],
     * goes through the same "content entered the clipboard" path that
     * triggers Android 13's clipboard preview overlay -- so replacing the
     * clip with an empty one is just as visible as the original copy was.
     * [ClipboardManager.clearPrimaryClip] (API 28+) removes the clip
     * instead of replacing it, which does not trigger that overlay.
     *
     * `expectedText`, if provided, guards against clobbering something the
     * user copied from elsewhere in the meantime: we only clear when the
     * clipboard still holds exactly what this app put there. Reading the
     * clipboard here is safe from a different Android 13+ standpoint too --
     * the "app pasted from your clipboard" notification is only shown for
     * cross-app reads, never for an app reading back its own clip.
     */
    fun handleClearSensitiveClipboardText(call: MethodCall, result: MethodChannel.Result) {
        val expectedText = call.argument<String>("expectedText")
        try {
            val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                ?: return result.success(false)

            if (expectedText != null) {
                val currentText = clipboard.primaryClip
                    ?.takeIf { it.itemCount > 0 }
                    ?.getItemAt(0)
                    ?.coerceToText(activity)
                    ?.toString()
                if (currentText != expectedText) {
                    result.success(false)
                    return
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                @Suppress("DEPRECATION")
                clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
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

    /**
     * Hands an APK straight to the system package installer, skipping the
     * "open with" chooser [handleOpenWithApp] would otherwise show.
     *
     * The APK is exposed the same way every other external hand-off in
     * this app is -- as a `content://` URI backed by
     * `ContainerDocumentsProvider` (or, for plain device storage, the
     * `localfiles` [FileProvider]) with a one-shot read grant attached to
     * the intent. The installer streams the archive from there; no
     * decrypted copy is written to disk by this app, which is what lets
     * this exist at all given the no-plaintext-at-rest rule. (The
     * installer does stage its own copy inside the system's install
     * session -- unavoidable, since installing is precisely asking the OS
     * to keep the package, and it only happens on an explicit tap.)
     *
     * Installing also needs the user's own per-app "install unknown apps"
     * switch, which `REQUEST_INSTALL_PACKAGES` in the manifest only makes
     * it possible to ask for. When it's off, this opens that settings
     * page rather than firing an intent the installer would silently
     * refuse, and reports back which of the two happened so the caller
     * doesn't treat "sent the user to Settings" as "installing now".
     */
    fun handleInstallApk(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val fileName = call.argument<String>("fileName")
        val isLocalStorage = call.argument<Boolean>("isLocalStorage") ?: false
        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName required", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            Toast.makeText(
                activity,
                R.string.install_unknown_apps_required,
                Toast.LENGTH_LONG,
            ).show()
            try {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}"),
                    )
                )
            } catch (_: Exception) {
                // Some OEM builds don't accept the per-package form of
                // this action; the plain list is a fine second choice.
                try {
                    activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES))
                } catch (e: Exception) {
                    result.error("INSTALL_APK_ERROR", e.message, null)
                    return
                }
            }
            result.success("permissionRequired")
            return
        }

        try {
            val apkUri: Uri = when {
                isLocalStorage && uriString.startsWith("content://") ->
                    activity.safStorageManager.getDocumentUri(Uri.parse(uriString), fileName)
                        ?: run {
                            result.error("NOT_FOUND", "Could not resolve $fileName", null)
                            return
                        }

                isLocalStorage -> {
                    val file = if (fileName.startsWith("/")) File(fileName)
                               else File(uriString, fileName)
                    if (!file.exists()) {
                        result.error("NOT_FOUND", "Local file not found: $fileName", null)
                        return
                    }
                    FileProvider.getUriForFile(
                        activity,
                        "${activity.packageName}.localfiles",
                        file,
                    )
                }

                else -> {
                    val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
                        ?: run {
                            result.error("NOT_MOUNTED", "Container not mounted", null)
                            return
                        }
                    DocumentsContract.buildDocumentUri(
                        "com.aeidolon.vaultexplorer.documents",
                        "$volId:file:$fileName?mimeType=${MimeTypeHelper.APK}",
                    )
                }
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, MimeTypeHelper.APK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            result.success("started")
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(activity, R.string.install_no_installer, Toast.LENGTH_LONG).show()
            result.success("noInstaller")
        } catch (e: Exception) {
            result.error("INSTALL_APK_ERROR", e.message, null)
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
            val readOnly = ContainerSessionRegistry.activeSessions[volId]?.readOnly == true
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(
                    docUri,
                    mimeTypeOverride ?: MimeTypeHelper.getMimeType(fileName)
                )
                // Only grant write access to the external app when the
                // underlying container/vault is itself writable. Granting
                // FLAG_GRANT_WRITE_URI_PERMISSION unconditionally let a
                // read-only-mounted volume still be edited by whatever
                // external app the user picked -- ContainerDocumentsProvider
                // itself would reject the write in openDocument(), but the
                // grant is unnecessary attack surface for a "view" action
                // and better not offered at all.
                var flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                if (!readOnly) {
                    flags = flags or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                }
                addFlags(flags)
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

    fun handleShareFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val fileNames = call.argument<List<String>>("fileNames")
        if (uriString == null || fileNames.isNullOrEmpty()) {
            result.error(
                "INVALID_ARGS",
                "filePath and fileNames required",
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
            val docUris = fileNames.map { fileName ->
                DocumentsContract.buildDocumentUri(
                    "com.aeidolon.vaultexplorer.documents",
                    "$volId:file:$fileName"
                )
            }
            val intent = if (docUris.size == 1) {
                Intent(Intent.ACTION_SEND).apply {
                    putExtra(Intent.EXTRA_STREAM, docUris[0])
                    type = MimeTypeHelper.getMimeType(fileNames[0])
                }
            } else {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(docUris))
                    type = "*/*"
                }
            }
           intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val chooser = Intent.createChooser(intent, null)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val excluded = arrayOf(
                    ComponentName(activity.packageName, "com.aeidolon.vaultexplorer.VaultShareActivity"),
                    ComponentName(activity.packageName, "com.aeidolon.vaultexplorer.ShareTargetAlias"),
                    ComponentName(activity.packageName, "com.aeidolon.vaultexplorer.ShareTargetDecoyAlias"),
                    ComponentName(activity.packageName, "com.aeidolon.vaultexplorer.MainActivity"),
                )
                chooser.putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, excluded)
            }
            activity.startActivity(chooser)
            result.success(true)
        } catch (e: Exception) {
            result.error("SHARE_FILE_ERROR", e.message, null)
        }
    }
}