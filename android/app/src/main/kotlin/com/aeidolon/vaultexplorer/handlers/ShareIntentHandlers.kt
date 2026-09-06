package com.aeidolon.vaultexplorer.handlers

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.bridge.IncomingShareBridge
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService

/**
 * Opt-in Android Share Sheet integration (see AndroidManifest.xml's
 * `ShareTargetAlias` and docs/architecture.md, "Android Share Sheet
 * Integration"): lets other apps share one or more files directly into an
 * encrypted vault via ACTION_SEND/ACTION_SEND_MULTIPLE.
 *
 * Split from [ImportExportHandlers] along the same line the rest of that
 * class's doc comment draws for the two-phase import machinery: this class
 * owns the *share-intent* side (toggling the alias, deciding whether an
 * incoming intent should be acted on at all, extracting its metadata) --
 * [ImportExportHandlers.handlePrepareShareImport] owns turning the result
 * into an actual import, since that needs the same `pickedFilesByToken`
 * bookkeeping [ImportExportHandlers.handlePickImportFiles] already
 * maintains and there's no value in duplicating it here.
 *
 * Deliberately holds no lock-status check of its own: whether the app is
 * currently asking for a master password is a Dart-owned, purely
 * UI-navigation concept (`SessionLockController`/`LockGateScreen`,
 * see docs/architecture.md §1.1's ownership split) that this class has no
 * way to observe from native code, and doesn't need to -- an incoming
 * share simply sits in [IncomingShareBridge] until whichever Dart screen is
 * actually on top asks for it (`MainShell.initState`, which by
 * construction only ever runs once `LockGateScreen` has already let the
 * person through). Mask Mode is the one thing here that *is* native's to
 * decide (see [handleIncomingIntent]), because it's the one piece of this
 * gating PackageManager -- not Dart -- is authoritative for.
 */
class ShareIntentHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    companion object {
        private const val ALIAS_SHARE_TARGET = "com.aeidolon.vaultexplorer.ShareTargetAlias"
        private const val TAG = "ShareIntentHandlers"
    }

    private fun aliasComponent() = ComponentName(activity.packageName, ALIAS_SHARE_TARGET)

    /**
     * Called from [MainActivity.onCreate]/`onNewIntent` for *every*
     * incoming intent, cold or warm -- a no-op for anything that isn't an
     * ACTION_SEND/ACTION_SEND_MULTIPLE the person shared into the app, so
     * it's cheap to call unconditionally rather than threading a "was this
     * a share?" check into both callers.
     *
     * If Mask Mode's decoy identity is the one currently active, the
     * intent is silently dropped here -- no metadata is resolved, nothing
     * is buffered or pushed, and the activity proceeds to boot into
     * whichever screen it normally would (the decoy's plain zip-browser
     * UI). This is the one part of the feature spec's Step 3 gating native
     * can and must own itself: [IncomingShareBridge] existing at all, even
     * briefly, would be observable from Dart, and Dart is exactly the side
     * a decoy-identity session is trying to keep free of any sign a vault
     * identity exists. Mirrors [DisguiseModeHandlers.isDecoyActive]'s own
     * "context-only, no cached copy" contract -- this always re-checks
     * PackageManager, never a remembered flag.
     */
    fun handleIncomingIntent(intent: Intent?) {
        val action = intent?.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        if (DisguiseModeHandlers.isDecoyActive(activity)) return

        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            val single = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            single?.let { uris.add(it) }
        } else {
            val many = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            many?.let { uris.addAll(it) }
        }
        if (uris.isEmpty()) return

        // Metadata resolution (DocumentFile.fromSingleUri/ContentResolver)
        // touches disk/IPC -- off the main thread, same as every other
        // ContentResolver-backed lookup in ImportExportHandlers.
        ioExecutor.execute {
            val items = uris.mapNotNull { uri ->
                try {
                    val doc = DocumentFile.fromSingleUri(activity, uri) ?: return@mapNotNull null
                    val name = doc.name ?: uri.lastPathSegment?.substringAfterLast('/') ?: return@mapNotNull null
                    IncomingShareBridge.ShareItem(
                        uri = uri,
                        displayName = name,
                        sizeBytes = doc.length(),
                        mimeType = doc.type,
                    )
                } catch (e: Exception) {
                    VeLog.w(TAG) { "Failed to resolve shared item metadata for $uri: ${e.message}" }
                    null
                }
            }
            IncomingShareBridge.deliver(items)
        }
    }

    /**
     * Flips [ALIAS_SHARE_TARGET]'s enabled state -- the "opt-in toggle
     * under Security/System Integration settings" the feature spec's Step
     * 1/Step 6 describe (see `AppSettingsScreen`'s "Share Sheet
     * Integration" switch). `DONT_KILL_APP` matches
     * [DisguiseModeHandlers.handleSetMode]'s use of the same flag: flipping
     * a component's enabled state does restart *that* component next time
     * it's resolved, but must not kill the running process the toggle
     * itself is a click inside of.
     *
     * No separate persistence: [PackageManager.setComponentEnabledSetting]
     * already survives app restarts and device reboots on its own (it's
     * package-manager state, not app state), so mirroring it into
     * SharedPreferences/secure storage as well would just be a second copy
     * that could drift out of sync with the real, OS-level truth --
     * exactly the failure mode docs/architecture.md's Mask Mode invariant
     * (state "must always be freshly queried from PackageManager, never
     * cached elsewhere") exists to rule out. [handleIsShareTargetEnabled]
     * always re-queries PackageManager for the same reason.
     */
    fun handleSetShareTargetEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        try {
            activity.packageManager.setComponentEnabledSetting(
                aliasComponent(),
                if (enabled) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                },
                PackageManager.DONT_KILL_APP,
            )
            result.success(null)
        } catch (e: Exception) {
            result.error("SHARE_TARGET_ERROR", e.message, null)
        }
    }

    fun handleIsShareTargetEnabled(call: MethodCall, result: MethodChannel.Result) {
        val setting = activity.packageManager.getComponentEnabledSetting(aliasComponent())
        // Manifest declares this alias disabled by default, so the
        // "never explicitly touched" DEFAULT state also reads as false --
        // unlike VaultLauncherAlias/ZipExplorerAlias there's no
        // complementary component whose default is "on" to fall back to.
        result.success(setting == PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
    }

    /** See [IncomingShareBridge.peekPending]. */
    fun handleCheckPendingShareRequest(call: MethodCall, result: MethodChannel.Result) {
        result.success(IncomingShareBridge.peekPending())
    }

    /** See [IncomingShareBridge.clear]. */
    fun handleCancelPendingShareRequest(call: MethodCall, result: MethodChannel.Result) {
        IncomingShareBridge.clear()
        result.success(null)
    }
}
