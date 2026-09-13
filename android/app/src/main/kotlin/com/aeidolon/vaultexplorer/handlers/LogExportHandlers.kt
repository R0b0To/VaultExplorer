package com.aeidolon.vaultexplorer.handlers

import android.app.Activity
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.PendingActivityResult
import com.aeidolon.vaultexplorer.UriNameResolver

/**
 * Saves in-app Logcat output (see LogcatService/LogcatScreen on the Dart
 * side) to a location the user picks through the system document picker,
 * via `ACTION_CREATE_DOCUMENT`.
 *
 * Previously this content was written directly to this app's external
 * files directory (`Android/data/<package>/files/`), which many file
 * managers can no longer browse on Android 11+ due to scoped storage.
 * Routing through SAF instead lets the user save to Downloads, a
 * cloud-backed folder, an SD card, or anywhere else they're allowed to
 * write -- same fix shape as [AppSettingsFileHandlers].
 *
 * Deliberately its own class rather than a generalized
 * [AppSettingsFileHandlers] (same SAF-export shape, different content
 * type/mime and default file-naming convention): that class's contract
 * (JSON mime type, `contents`/`fileName` args, plain `Boolean` result) is
 * covered by PendingResultLeakTest, so leaving it untouched avoids any
 * risk of regressing the settings export/import flow while adding this.
 */
class LogExportHandlers(
    private val activity: MainActivity,
    private val pendingResult: PendingActivityResult,
    private val ioExecutor: ExecutorService,
) {
    private var pendingLogText: String? = null
    private var pendingFileName: String = "vaultexplorer_logcat.txt"

    private val exportLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val text = pendingLogText
        val fileName = pendingFileName
        pendingLogText = null
        val destUri = activityResult.data?.data

        if (activityResult.resultCode == Activity.RESULT_OK && destUri != null && text != null) {
            ioExecutor.execute {
                try {
                    activity.contentResolver.openOutputStream(destUri)?.use { out ->
                        out.write(text.toByteArray(Charsets.UTF_8))
                    } ?: throw IOException("Could not open destination for writing")
                    // Best-effort: SAF gives us back an opaque content:// Uri,
                    // not a filesystem path, so resolve a human-readable name
                    // for the "Log saved to ..." confirmation instead of
                    // showing the Uri itself. Falls back to the requested
                    // fileName (rather than UriNameResolver's default
                    // "Container", which doesn't make sense here) if the
                    // DISPLAY_NAME query comes back empty.
                    val displayName = UriNameResolver.resolve(activity.contentResolver, destUri, fileName)
                    activity.runOnUiThread {
                        res.success(mapOf("success" to true, "displayName" to displayName))
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread { res.error("IO_ERROR", e.message, null) }
                }
            }
        } else {
            // User cancelled the picker -- null (not an error) tells Dart
            // to quietly abandon the save, mirroring VaultPickerHandlers'
            // pick* methods and AppSettingsFileHandlers' own import picker.
            res.success(null)
        }
    }

    fun handleExportLogFile(call: MethodCall, result: MethodChannel.Result) {
        val contents = call.argument<String>("contents")
        if (contents == null) {
            result.error("INVALID_ARGS", "contents is required", null)
            return
        }
        val fileName = call.argument<String>("fileName") ?: "vaultexplorer_logcat.txt"
        pendingLogText = contents
        pendingFileName = fileName
        pendingResult.stash(result)
        exportLauncher.launch(
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "text/plain"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
        )
    }
}
