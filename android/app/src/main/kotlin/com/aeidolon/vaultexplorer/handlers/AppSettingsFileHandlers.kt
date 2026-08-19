package com.aeidolon.vaultexplorer.handlers

import android.app.Activity
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.PendingActivityResult

/**
 * Saves/loads the single small JSON text blob behind Settings ->
 * Export/Import (app settings + file-manager toolbar config) through
 * the system document picker.
 *
 * Deliberately separate from [ImportExportHandlers]: that class always
 * resolves a mounted container's volId first and streams to/from the
 * container's virtual filesystem. This one just round-trips plain text
 * between Dart and a document the user picks with
 * `ACTION_CREATE_DOCUMENT` / `ACTION_OPEN_DOCUMENT` -- no container,
 * no volId, no encryption. Nothing security-sensitive (master password
 * hash/salt, per-container favourites/pinned paths, keystore material)
 * is ever handed to this class; the Dart side is responsible for
 * keeping those out of the exported JSON.
 */
class AppSettingsFileHandlers(
    private val activity: MainActivity,
    private val pendingResult: PendingActivityResult,
    private val ioExecutor: ExecutorService,
) {
    companion object {
        /**
         * True if no `contents` string was supplied for an export call.
         * Extracted as a pure function purely so it's directly testable --
         * see PendingResultLeakTest, which exercises this exact predicate
         * to confirm [handleExportAppSettingsFile] replies and returns
         * *before* calling [PendingActivityResult.stash], never after.
         * Mirrors VaultCreationHandlers.isMissingCredentials.
         */
        fun isMissingContents(contents: String?): Boolean = contents == null
    }

    private var pendingExportText: String? = null

    private val exportLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val text = pendingExportText
        pendingExportText = null
        val destUri = activityResult.data?.data

        if (activityResult.resultCode == Activity.RESULT_OK && destUri != null && text != null) {
            ioExecutor.execute {
                try {
                    activity.contentResolver.openOutputStream(destUri)?.use { out ->
                        out.write(text.toByteArray(Charsets.UTF_8))
                    } ?: throw java.io.IOException("Could not open destination for writing")
                    activity.runOnUiThread { res.success(true) }
                } catch (e: Exception) {
                    activity.runOnUiThread { res.error("IO_ERROR", e.message, null) }
                }
            }
        } else {
            res.success(false)
        }
    }

    private val importLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val srcUri = activityResult.data?.data

        if (activityResult.resultCode == Activity.RESULT_OK && srcUri != null) {
            ioExecutor.execute {
                try {
                    val text = activity.contentResolver.openInputStream(srcUri)?.use { inp ->
                        inp.bufferedReader(Charsets.UTF_8).readText()
                    } ?: throw java.io.IOException("Could not open selected file for reading")
                    activity.runOnUiThread { res.success(text) }
                } catch (e: Exception) {
                    activity.runOnUiThread { res.error("IO_ERROR", e.message, null) }
                }
            }
        } else {
            // User cancelled the picker -- null (not an error) tells Dart
            // to quietly abandon the import.
            res.success(null)
        }
    }

    fun handleExportAppSettingsFile(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("contents")
        if (isMissingContents(text)) {
            result.error("INVALID_ARGS", "contents is required", null)
            return
        }
        val fileName = call.argument<String>("fileName") ?: "vaultexplorer_settings.json"
        pendingExportText = text
        pendingResult.stash(result)
        exportLauncher.launch(
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
        )
    }

    fun handleImportAppSettingsFile(call: MethodCall, result: MethodChannel.Result) {
        pendingResult.stash(result)
        importLauncher.launch(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                // application/json is unreliably registered as a document
                // MIME type on some OEM file pickers, so widen with
                // EXTRA_MIME_TYPES instead of trusting `type` alone.
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("application/json", "text/plain", "text/*"),
                )
            }
        )
    }
}
