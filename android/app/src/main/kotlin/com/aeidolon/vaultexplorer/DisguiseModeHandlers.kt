package com.aeidolon.vaultexplorer

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService

/**
 * Method names for the dedicated Discrete Mode channel
 * (`com.aeidolon.vaultexplorer/disguise_channel`), mirrored 1:1 by
 * `DisguiseModeApi` (Dart) -- see docs/architecture.md §8.4 for the
 * contract and ADR-025/026/027/029 for why this is a *separate* channel
 * from `com.aeidolon.vaultexplorer/engine` rather than more methods bolted
 * onto `ChannelMethods` in MainActivity.
 */
internal object DisguiseChannelMethods {
    const val GET_MODE                     = "getMode"
    const val SET_MODE                     = "setMode"
    const val PICK_LOCAL_PDF_FILE          = "pickLocalPdfFile"
    const val CONSUME_PENDING_OPEN_REQUEST = "consumePendingOpenRequest"
}

/** Values returned/accepted by [DisguiseChannelMethods.GET_MODE]/[DisguiseChannelMethods.SET_MODE]. */
internal object DisguiseMode {
    const val VAULT = "vault"
    const val DECOY = "decoy"
}

/**
 * Discrete Mode: launcher-alias switching (real "Vault Explorer" identity
 * vs. decoy "Doc Viewer" identity) and the decoy reader's own local-file
 * picker.
 *
 * Ownership rule (docs/architecture.md §2.9): exactly one of
 * [ALIAS_VAULT]/[ALIAS_DECOY] is `COMPONENT_ENABLED_STATE_ENABLED` at any
 * time. [handleSetMode] enforces this by flipping both components in a
 * single call -- never expose a path that could enable or disable only one
 * side, or the app could end up with two launcher icons (breaks the
 * disguise) or zero (app becomes unreachable from the launcher).
 *
 * There is deliberately no separate persisted "discrete mode enabled" flag
 * anywhere in Dart-land (ADR-025): [handleGetMode] always answers from the
 * live `PackageManager` component-enabled state, which is also what the
 * launcher itself is reading. A separately persisted flag could drift from
 * the real component state (e.g. if a save failed on one side), and -- for
 * this specific feature -- a plaintext preferences file recording "this
 * device has an active Discrete Mode" would itself be a fingerprint that
 * partially defeats the disguise for anyone who goes looking at app data.
 * Deriving the answer from PackageManager sidesteps both problems: it's a
 * single source of truth and it's not a new place to leak the app's true
 * nature from.
 *
 * The local-PDF picker reuses the existing SAF `ACTION_OPEN_DOCUMENT` +
 * [PendingActivityResult] pattern already used by [VaultPickerHandlers]
 * (ADR-027) rather than adding a third-party file-picker dependency, and
 * takes a **read-only** persistable grant -- the decoy reader never writes
 * to anything outside the app sandbox.
 */
class DisguiseModeHandlers(
    private val activity: MainActivity,
    private val pendingResult: PendingActivityResult,
    private val ioExecutor: ExecutorService,
) {
    companion object {
        private const val ALIAS_VAULT = "com.aeidolon.vaultexplorer.VaultLauncherAlias"
        private const val ALIAS_DECOY = "com.aeidolon.vaultexplorer.PDFViewerAlias"
    }

    // Registered eagerly (not lazily) -- see VaultPickerHandlers' doc comment
    // for why: an ActivityResultContract launcher must be registered before
    // the Activity leaves the CREATED state.
    private val pickLocalPdfLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            ioExecutor.execute {
                try {
                    // Read-only: the decoy reader never needs write access.
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: SecurityException) {}
                val name = UriNameResolver.resolve(activity.contentResolver, uri)
                activity.runOnUiThread {
                    res.success(mapOf(
                        "uri" to uri.toString(),
                        "displayName" to name,
                    ))
                }
            }
        } else {
            res.success(null)
        }
    }

    private fun aliasComponent(name: String) = ComponentName(activity.packageName, name)

    private fun isAliasEnabled(name: String): Boolean {
        val pm = activity.packageManager
        val setting = pm.getComponentEnabledSetting(aliasComponent(name))
        // COMPONENT_ENABLED_STATE_DEFAULT means "use the manifest's
        // android:enabled value" -- only true before the first toggle ever
        // happens on a fresh install, since VaultLauncherAlias defaults to
        // enabled="true" in the manifest.
        return when (setting) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED -> false
            else -> name == ALIAS_VAULT // COMPONENT_ENABLED_STATE_DEFAULT
        }
    }

    fun updateActivityIdentity() {
        val decoyActive = isAliasEnabled(ALIAS_DECOY) && !isAliasEnabled(ALIAS_VAULT)
        val label = if (decoyActive) activity.getString(R.string.decoy_app_name) else activity.getString(R.string.app_name)
        val iconRes = if (decoyActive) R.mipmap.ic_launcher_pdf else R.mipmap.ic_launcher

        activity.title = label

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val taskDesc = ActivityManager.TaskDescription.Builder()
                    .setLabel(label)
                    .setIcon(iconRes)
                    .build()
                activity.setTaskDescription(taskDesc)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                @Suppress("DEPRECATION")
                val taskDesc = ActivityManager.TaskDescription(label, iconRes)
                activity.setTaskDescription(taskDesc)
            } else {
                val iconBitmap = BitmapFactory.decodeResource(activity.resources, iconRes)
                @Suppress("DEPRECATION")
                val taskDesc = ActivityManager.TaskDescription(label, iconBitmap)
                activity.setTaskDescription(taskDesc)
            }
        } catch (_: Exception) {}
    }

    fun handleGetMode(call: MethodCall, result: MethodChannel.Result) {
        val decoyActive = isAliasEnabled(ALIAS_DECOY) && !isAliasEnabled(ALIAS_VAULT)
        result.success(if (decoyActive) DisguiseMode.DECOY else DisguiseMode.VAULT)
    }

    fun handleSetMode(call: MethodCall, result: MethodChannel.Result) {
        val mode = call.argument<String>("mode")
        if (mode != DisguiseMode.VAULT && mode != DisguiseMode.DECOY) {
            result.error("INVALID_ARGS", "mode must be \"vault\" or \"decoy\"", null)
            return
        }
        try {
            val pm = activity.packageManager
            val enableDecoy = mode == DisguiseMode.DECOY
            // DONT_KILL_APP: flipping a launcher-alias component would
            // otherwise restart the whole process by default, which would
            // blow away any unlocked in-memory volId sessions (§5 of
            // docs/architecture.md). This call only ever changes how the
            // *launcher* presents the app; the running Activity/engine
            // instance must be left alone.
            pm.setComponentEnabledSetting(
                aliasComponent(ALIAS_VAULT),
                if (enableDecoy) PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                else PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            pm.setComponentEnabledSetting(
                aliasComponent(ALIAS_DECOY),
                if (enableDecoy) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
            updateActivityIdentity()
            result.success(null)
        } catch (e: Exception) {
            result.error("DISGUISE_MODE_ERROR", e.message, null)
        }
    }

    fun handlePickLocalPdfFile(call: MethodCall, result: MethodChannel.Result) {
        updateActivityIdentity()
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
        }
        try {
            pickLocalPdfLauncher.launch(intent)
        } catch (e: Exception) {
            pendingResult.take()?.error("PICK_FAILED", e.message, null)
        }
    }

    fun handleConsumePendingOpenRequest(call: MethodCall, result: MethodChannel.Result) {
        result.success(ExternalOpenBridge.consumePending())
    }

    /**
     * Called from [MainActivity.onCreate]/[MainActivity.onNewIntent] for
     * every incoming Intent, not just ones we care about -- most of the
     * time this is a no-op (returns immediately) since it only matches the
     * two shapes the decoy's Open-With/Share intent-filters can produce.
     * See [ExternalOpenBridge] for why there's no separate "are we in
     * Discrete Mode" check here.
     */
    fun handleIncomingIntent(intent: Intent?) {
        intent ?: return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (intent.type == "application/pdf") {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                } else null
            else -> null
        } ?: return

        ioExecutor.execute {
            try {
                // Not every inbound grant supports this (some senders only
                // attach a task-scoped FLAG_GRANT_READ_URI_PERMISSION,
                // without FLAG_GRANT_PERSISTABLE_URI_PERMISSION) -- when it
                // fails, the document still opens fine for this session via
                // the grant Android already attached to the Intent; it may
                // just not be re-openable later from the decoy reader's
                // recents list, same graceful-degradation path as
                // PdfViewerPlugin already has for any revoked grant.
                activity.contentResolver.takePersistableUriPermission(
                    uri!!,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) {}
            val name = UriNameResolver.resolve(activity.contentResolver, uri!!)
            ExternalOpenBridge.deliver(uri.toString(), name)
        }
    }
}