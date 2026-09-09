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
import com.aeidolon.vaultexplorer.bridge.LocalIncomingShareBridge
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
 * person through).
 *
 * Mask Mode is the one thing here that *is* native's to decide (see
 * [handleIncomingIntent]), because it's the one piece of this gating
 * PackageManager -- not Dart -- is authoritative for. It routes, though,
 * rather than drops: while the decoy identity is active, metadata is
 * delivered to [LocalIncomingShareBridge] instead of [IncomingShareBridge]
 * -- a fully separate buffer/channel that only Dart's decoy file manager
 * (`lib/features/decoy/local/decoy_share_import_flow.dart`) ever drains,
 * and which never requires unlocking anything. This is what lets the
 * decoy identity behave like a genuine file manager receiving a shared
 * file -- pick a folder, save it, plain storage, no auth prompt -- instead
 * of the share silently going nowhere. Reaching the *actual* vault with a
 * shared file while disguised is still possible, just via the existing
 * `HiddenVaultTrigger` gesture rather than anything share-specific.
 *
 * Both aliases -- [ALIAS_SHARE_TARGET] (real identity) and
 * [ALIAS_SHARE_TARGET_DECOY] (decoy identity) -- are kept in sync with
 * Mask Mode by [DisguiseModeHandlers.syncShareTargetIdentity]; exactly one
 * is ever enabled at a time, mirroring how VaultLauncherAlias/
 * ZipExplorerAlias are handled for the launcher itself.
 */
class ShareIntentHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    companion object {
        private const val ALIAS_SHARE_TARGET = "com.aeidolon.vaultexplorer.ShareTargetAlias"
        private const val ALIAS_SHARE_TARGET_DECOY = "com.aeidolon.vaultexplorer.ShareTargetDecoyAlias"
        private const val TAG = "ShareIntentHandlers"
    }

    private fun aliasComponent(name: String) = ComponentName(activity.packageName, name)

    /**
     * Called from [MainActivity.onCreate]/`onNewIntent` for *every*
     * incoming intent, cold or warm -- a no-op for anything that isn't an
     * ACTION_SEND/ACTION_SEND_MULTIPLE the person shared into the app, so
     * it's cheap to call unconditionally rather than threading a "was this
     * a share?" check into both callers.
     *
     * Metadata resolution is identical either way; only the destination
     * bridge differs, decided by [DisguiseModeHandlers.isDecoyActive] --
     * snapshotted once up front, before hopping to [ioExecutor], since
     * it's the identity *at arrival time* that should decide routing, not
     * whatever happens to be current once resolution finishes. Mirrors
     * [DisguiseModeHandlers.isDecoyActive]'s own "context-only, no cached
     * copy" contract -- this always re-checks PackageManager, never a
     * remembered flag.
     */
    fun handleIncomingIntent(intent: Intent?) {
        val action = intent?.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

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

        // Consume the intent so that if the activity is recreated or resumed,
        // this intent is not treated as a fresh incoming share.
        intent.action = null
        intent.removeExtra(Intent.EXTRA_STREAM)

        val decoyActive = DisguiseModeHandlers.isDecoyActive(activity)

        // Metadata resolution (DocumentFile.fromSingleUri/ContentResolver)
        // touches disk/IPC -- off the main thread, same as every other
        // ContentResolver-backed lookup in ImportExportHandlers.
        ioExecutor.execute {
            data class Resolved(val uri: Uri, val name: String, val size: Long, val mime: String?)
            val resolved = uris.mapNotNull { uri ->
                try {
                    val doc = DocumentFile.fromSingleUri(activity, uri) ?: return@mapNotNull null
                    val name = doc.name ?: uri.lastPathSegment?.substringAfterLast('/') ?: return@mapNotNull null
                    Resolved(uri, name, doc.length(), doc.type)
                } catch (e: Exception) {
                    VeLog.w(TAG) { "Failed to resolve shared item metadata for $uri: ${e.message}" }
                    null
                }
            }
            if (resolved.isEmpty()) return@execute
            if (decoyActive) {
                LocalIncomingShareBridge.deliver(
                    resolved.map {
                        LocalIncomingShareBridge.ShareItem(it.uri, it.name, it.size, it.mime)
                    },
                )
            } else {
                IncomingShareBridge.deliver(
                    resolved.map {
                        IncomingShareBridge.ShareItem(it.uri, it.name, it.size, it.mime)
                    },
                )
            }
        }
    }

    /**
     * Flips whichever of [ALIAS_SHARE_TARGET]/[ALIAS_SHARE_TARGET_DECOY]
     * matches Mask Mode's *current* state -- the "opt-in toggle under
     * Security/System Integration settings" the feature spec's Step 1/Step
     * 6 describe (see `AppSettingsScreen`'s "Share Sheet Integration"
     * switch). Turning it off disables both, regardless of which one was
     * active, so there's no way to end up with a stray enabled alias if
     * Mask Mode happened to flip in between. `DONT_KILL_APP` matches
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
     * always re-queries PackageManager for the same reason. Once on, which
     * of the two aliases stays enabled is kept correct going forward by
     * [DisguiseModeHandlers.syncShareTargetIdentity] on every subsequent
     * mode switch -- this method only has to get it right at the moment
     * the person flips the switch.
     */
    fun handleSetShareTargetEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        try {
            val pm = activity.packageManager
            if (enabled) {
                val decoyActive = DisguiseModeHandlers.isDecoyActive(activity)
                val targetAlias = if (decoyActive) ALIAS_SHARE_TARGET_DECOY else ALIAS_SHARE_TARGET
                val otherAlias = if (decoyActive) ALIAS_SHARE_TARGET else ALIAS_SHARE_TARGET_DECOY
                pm.setComponentEnabledSetting(
                    aliasComponent(targetAlias),
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP,
                )
                pm.setComponentEnabledSetting(
                    aliasComponent(otherAlias),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            } else {
                pm.setComponentEnabledSetting(
                    aliasComponent(ALIAS_SHARE_TARGET),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
                pm.setComponentEnabledSetting(
                    aliasComponent(ALIAS_SHARE_TARGET_DECOY),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("SHARE_TARGET_ERROR", e.message, null)
        }
    }

    fun handleIsShareTargetEnabled(call: MethodCall, result: MethodChannel.Result) {
        fun enabled(name: String): Boolean {
            val setting = activity.packageManager.getComponentEnabledSetting(aliasComponent(name))
            return setting == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        }
        // Manifest declares both aliases disabled by default, so the
        // "never explicitly touched" DEFAULT state also reads as false --
        // unlike VaultLauncherAlias/ZipExplorerAlias there's no
        // complementary component whose default is "on" to fall back to.
        // Either alias being enabled counts as "the feature is on", since
        // exactly one of the two is ever enabled at a time.
        result.success(enabled(ALIAS_SHARE_TARGET) || enabled(ALIAS_SHARE_TARGET_DECOY))
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

    /** See [LocalIncomingShareBridge.peekPending]. */
    fun handleCheckPendingLocalShareRequest(call: MethodCall, result: MethodChannel.Result) {
        result.success(LocalIncomingShareBridge.peekPending())
    }

    /** See [LocalIncomingShareBridge.takePending]. */
    fun handleTakePendingLocalShareRequest(call: MethodCall, result: MethodChannel.Result) {
        result.success(LocalIncomingShareBridge.takePending())
    }

    /** See [LocalIncomingShareBridge.clear]. */
    fun handleCancelPendingLocalShareRequest(call: MethodCall, result: MethodChannel.Result) {
        LocalIncomingShareBridge.clear()
        result.success(null)
    }

    /**
     * The native half of the decoy share flow's hidden-reveal path (see
     * `HiddenVaultTrigger.onBeforeReveal` in
     * lib/features/decoy/widgets/hidden_vault_trigger.dart, used from
     * lib/features/decoy/local/decoy_share_import_flow.dart): moves
     * whatever's currently buffered in [LocalIncomingShareBridge] into
     * [IncomingShareBridge], so that once the person actually authenticates
     * -- which may happen immediately, or after backing out and trying
     * again -- `MainShell`'s already-existing pending-share pull picks it
     * up exactly as if the share had arrived while the real identity was
     * active all along. No Dart-side change needed on that end at all.
     *
     * A *move* ([LocalIncomingShareBridge.takePendingRaw], not a peek):
     * once the person has deliberately triggered the hidden reveal for a
     * given share, that share is committed to the vault path. An earlier
     * version of this left it copied-but-not-removed, so the decoy's own
     * local-save picker would still have something to act on if the person
     * backed out without authenticating -- but that interacts badly with
     * `HiddenVaultTrigger` popping its own host screen on return (see that
     * screen's doc comment): since the picker route the reveal was
     * triggered from gets popped either way once the excursion ends, a
     * copy left the *decoy's* own pending buffer holding a stale,
     * already-handled request -- reachable again by simply backing further
     * out to wherever was underneath, letting the same file be saved into
     * local storage a second time after already being imported into the
     * vault. Moving it removes that possibility outright rather than
     * relying on navigation staying exactly in sync with buffer state.
     *
     * Returns `false` (rather than erroring) when there's nothing to hand
     * off, e.g. this is reached via some path other than the share flow --
     * `HiddenVaultTrigger` reveals the vault either way, this affecting
     * only whether a share request happens to be waiting once it does.
     */
    fun handleHandoffLocalShareToVault(call: MethodCall, result: MethodChannel.Result) {
        val items = LocalIncomingShareBridge.takePendingRaw()
        if (items.isNullOrEmpty()) {
            result.success(false)
            return
        }
        IncomingShareBridge.deliver(
            items.map { IncomingShareBridge.ShareItem(it.uri, it.displayName, it.sizeBytes, it.mimeType) },
        )
        result.success(true)
    }
}