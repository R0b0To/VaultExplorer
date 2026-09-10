package com.aeidolon.vaultexplorer.panic

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.withLock
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.bridge.UsbBlockBridge
import com.aeidolon.vaultexplorer.bridge.VaultForceLockedBridge
import com.aeidolon.vaultexplorer.container.ContainerEngine
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.pdf.PdfRendererRegistry
import com.aeidolon.vaultexplorer.pdf.VaultPdfSessionRegistry
import com.aeidolon.vaultexplorer.service.VaultAutomationRecordingService
import com.aeidolon.vaultexplorer.service.VaultKeepAliveService

/**
 * Centralized coordinator for every panic/duress trigger in the app --
 * PanicKit (Phase 2), the Quick Settings tile (Phase 3), Duress Unlock
 * (Phase 5), and the in-app "wipe now" action in Settings (Phase 6) all
 * end up calling [execute] here rather than touching any purge subsystem
 * directly. Centralizing this is what makes the "Headless-Safe Native
 * Orchestration" principle from the architecture plan's section 1 hold:
 * every one of those triggers can fire when the Flutter engine is
 * backgrounded, paused, or already torn down, and [execute] never
 * depends on Dart, an Activity, or anything else that might not exist at
 * that moment -- Dart is notified afterward, best-effort, via [hooks],
 * never awaited.
 *
 * ## Threading contract
 * [execute] MUST be called off the main thread. Keystore enumeration and
 * the file I/O in [StorageShredder] can each take anywhere from a few
 * milliseconds to a few hundred, and a [PanicTier.NUCLEAR_WIPE] call does
 * not return in the normal case at all -- it ends in process death. Every
 * caller this plan introduces already satisfies this on its own (a
 * BroadcastReceiver's `goAsync()` executor in Phase 2, a TileService
 * callback's own executor in Phase 3, a MethodChannel handler's
 * `ioExecutor` in Phase 4/6); a future caller must too.
 *
 * ## Tier cascade
 * Each tier's private `xPurge` function starts by calling the one below
 * it, so [execute] never needs a switch that repeats steps -- see
 * [PanicTier]'s own doc comment for why CREDENTIAL_PURGE always includes
 * SESSION_PURGE's work, and NUCLEAR_WIPE always includes CREDENTIAL_PURGE's.
 */
object PanicManager {

    private const val TAG = "PanicManager"

    // Mirrors VaultKeepAliveService's own top-level constant of the same
    // value -- that one is file-private there, so it can't be imported,
    // and duplicating a single authority string here is simpler than
    // exporting it just for this one call site.
    private const val CONTAINER_DOCUMENTS_AUTHORITY = "com.aeidolon.vaultexplorer.documents"

    private val mainHandler = Handler(Looper.getMainLooper())

    // Guards against two triggers landing at once (e.g. a PanicKit
    // broadcast and a Quick Settings tile tap within the same instant) --
    // not a correctness requirement for any single subsystem below (they
    // are each independently safe to call twice), but without it two
    // concurrent Tier 3 calls would both race to dispatch the uninstall
    // intent and kill the process, which is harmless but pointless to
    // let happen twice.
    private val runningGuard = AtomicBoolean(false)

    @Volatile
    private var activityRef: WeakReference<Activity>? = null

    /** Set by Phase 4 to receive the callbacks described in [PanicHooks].
     *  Null (the default) is a fully valid state -- see that interface's
     *  doc comment. */
    @Volatile
    var hooks: PanicHooks? = null

    data class PanicResult(
        val tier: PanicTier,
        val success: Boolean,
        val containersLocked: Int = 0,
        val keystoreAliasesPurged: Int = 0,
        val credentialStoresCleared: Int = 0,
        val filesWiped: Int = 0,
        val error: String? = null,
    )

    /**
     * Registers the currently-foregrounded [MainActivity] instance so a
     * [PanicTier.SESSION_PURGE] (or higher) trigger arriving from outside
     * any Activity -- a broadcast receiver, a tile click -- can still
     * finish it. Call from `onCreate`; call [unregisterActivity] from
     * `onDestroy`. Deliberately a weak reference: this object is a
     * process-lifetime singleton and must never be the thing keeping an
     * Activity from being garbage-collected.
     */
    @JvmStatic
    fun registerActivity(activity: Activity) {
        activityRef = WeakReference(activity)
    }

    @JvmStatic
    fun unregisterActivity(activity: Activity) {
        if (activityRef?.get() === activity) {
            activityRef = null
        }
    }

    /**
     * Runs [tier] (and every lower tier it cascades from) to completion.
     * See this object's doc comment for the threading contract.
     *
     * [source] is a short, log-only string identifying the trigger (e.g.
     * "panickit", "quick_tile", "duress", "settings_manual") -- purely
     * diagnostic. It is never shown to the user and never transmitted
     * anywhere (this app requests no INTERNET permission).
     *
     * Returns a [PanicResult] describing what actually happened -- except
     * for [PanicTier.NUCLEAR_WIPE], whose normal-case return value is
     * moot because the process is dead before any caller could observe
     * it.
     */
    @JvmStatic
    fun execute(context: Context, tier: PanicTier, source: String): PanicResult {
        if (!runningGuard.compareAndSet(false, true)) {
            VeLog.w(TAG) { "execute($tier, source=$source): ignored -- a panic wipe is already in progress" }
            return PanicResult(tier, success = false, error = "already_in_progress")
        }
        VeLog.i(TAG) { "execute($tier, source=$source): starting" }
        val appContext = context.applicationContext
        return try {
            when (tier) {
                PanicTier.SESSION_PURGE -> sessionPurge(appContext, source)
                PanicTier.CREDENTIAL_PURGE -> credentialPurge(appContext, source)
                PanicTier.NUCLEAR_WIPE -> nuclearWipe(appContext, source)
            }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "execute($tier, source=$source): unhandled failure" }
            PanicResult(tier, success = false, error = e.message)
        } finally {
            // Never reached for the normal-case NUCLEAR_WIPE outcome (the
            // process is already dead), which is fine -- there is no next
            // trigger for a dead process to ignore.
            runningGuard.set(false)
        }
    }

    // ── Tier 1: Session Purge ──────────────────────────────────────────

    private fun sessionPurge(context: Context, source: String): PanicResult {
        runCatching { hooks?.onBeforeSessionPurge(context) }
            .onFailure { VeLog.w(TAG, it) { "onBeforeSessionPurge hook threw" } }

        val lockedCount = unmountAllContainers(context)
        cancelBackgroundWork(context)
        finishForegroundActivity()

        runCatching { hooks?.onAfterSessionPurge(context) }
            .onFailure { VeLog.w(TAG, it) { "onAfterSessionPurge hook threw" } }

        VeLog.i(TAG) { "sessionPurge(source=$source): locked $lockedCount container(s)" }
        return PanicResult(PanicTier.SESSION_PURGE, success = true, containersLocked = lockedCount)
    }

    // ── Tier 2: Credential & Metadata Purge ────────────────────────────

    private fun credentialPurge(context: Context, source: String): PanicResult {
        val tier1 = sessionPurge(context, source)

        val aliasesPurged = KeystorePurge.purgeAll()
        val storesCleared = StorageShredder.purgeCredentialStores(context)

        runCatching { hooks?.onAfterCredentialPurge(context) }
            .onFailure { VeLog.w(TAG, it) { "onAfterCredentialPurge hook threw" } }

        VeLog.i(TAG) {
            "credentialPurge(source=$source): purged $aliasesPurged Keystore alias(es), " +
                "cleared $storesCleared credential store(s)"
        }
        return tier1.copy(
            tier = PanicTier.CREDENTIAL_PURGE,
            keystoreAliasesPurged = aliasesPurged,
            credentialStoresCleared = storesCleared,
        )
    }

    // ── Tier 3: Nuclear Wipe ────────────────────────────────────────────

    private fun nuclearWipe(context: Context, source: String): PanicResult {
        val tier2 = credentialPurge(context, source)

        val filesWiped = StorageShredder.wipeAllInternalStorage(context)

        runCatching { hooks?.onBeforeProcessDeath(context) }
            .onFailure { VeLog.w(TAG, it) { "onBeforeProcessDeath hook threw" } }

        VeLog.i(TAG) { "nuclearWipe(source=$source): wiped $filesWiped file(s); dispatching uninstall + process death" }
        dispatchUninstallIntent(context)
        // Give the just-dispatched Intent time to actually reach
        // system_server (see dispatchUninstallIntent's doc comment)
        // before this process disappears out from under it.
        try {
            Thread.sleep(300)
        } catch (_: InterruptedException) {
            // Ignored -- proceed to terminateProcess() regardless; a
            // Tier 3 wipe does not get interrupted partway through.
        }
        terminateProcess()

        // Unreachable in the normal case -- terminateProcess() ends the
        // process above. Kept only so this function has a well-typed
        // return value if both kill paths were somehow suppressed (e.g.
        // a future unit test harness stubbing them out).
        return tier2.copy(tier = PanicTier.NUCLEAR_WIPE, filesWiped = filesWiped)
    }

    // ── Shared subsystems ──────────────────────────────────────────────

    /**
     * Unmounts every currently-open container, mirroring
     * [VaultKeepAliveService]'s "Lock all vaults" notification action --
     * closes any PDF renderer/session tied to the volume, locks it under
     * its write lock, drops USB block registration if it was a USB
     * source, removes the in-memory session, and reports the forced lock
     * to Dart via [VaultForceLockedBridge] (a no-op if no Flutter engine
     * is currently attached). One volume throwing never stops the sweep
     * over the rest, or any later purge step in a higher tier.
     */
    private fun unmountAllContainers(context: Context): Int {
        val volIds = ContainerSessionRegistry.activeSessions.keys.toList()
        var locked = 0
        for (volId in volIds) {
            try {
                val session = ContainerSessionRegistry.activeSessions[volId]
                PdfRendererRegistry.closeAllForVolume(volId)
                VaultPdfSessionRegistry.revokeAllForVolume(volId)

                // 1. Zeroize C++ cryptographic memory
                try {
                    com.aeidolon.vaultexplorer.NativeEngine.emergencyPurgeNative(volId)
                } catch (e: Throwable) {
                    VeLog.w(TAG, e) { "emergencyPurgeNative failed for volId=$volId" }
                }

                // 2. Lock volume and release handles
                ContainerSessionRegistry.locks[volId].writeLock().withLock {
                    ContainerEngine.lock(volId)
                }
                if (session?.isUsbSource == true) {
                    UsbBlockBridge.unregister(volId)
                }
                ContainerSessionRegistry.removeSession(volId)
                VaultForceLockedBridge.reportLocked(volId)
                locked++
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "unmountAllContainers: failed to lock one volume, continuing" }
            }
        }
        if (volIds.isNotEmpty()) {
            try {
                context.contentResolver.notifyChange(
                    DocumentsContract.buildRootsUri(CONTAINER_DOCUMENTS_AUTHORITY), null,
                )
            } catch (_: Exception) {
                // Best-effort notification to third-party SAF clients only.
            }
        }
        return locked
    }

    /**
     * Stops every background component this app can run. There is no
     * network vault-sync feature to cancel here -- this app requests no
     * INTERNET permission anywhere in its manifest -- and, as of this
     * writing, no WorkManager/JobScheduler jobs either; if a future
     * feature adds either, cancel it here too. In-app "media caching"
     * (thumbnails staged in cacheDir) needs no separate cancellation:
     * Tier 1 doesn't touch disk, and Tier 3's [StorageShredder] wipes
     * cacheDir outright.
     */
    private fun cancelBackgroundWork(context: Context) {
        try {
            context.stopService(Intent(context, VaultKeepAliveService::class.java))
        } catch (_: Exception) {
        }
        try {
            // A hard stop, not the service's own graceful ACTION_STOP save
            // path -- a panic wipe should not wait on finalizing/encrypting
            // an in-progress recording. Losing that one clip is the
            // correct trade-off against an immediate confidentiality
            // response.
            context.stopService(Intent(context, VaultAutomationRecordingService::class.java))
        } catch (_: Exception) {
        }
    }

    /**
     * Finishes the registered foreground Activity, if any is currently
     * alive -- Tier 1's "blank the screen and immediately terminate all
     * foreground activities", without killing the process itself (that's
     * reserved for [PanicTier.NUCLEAR_WIPE]; Tier 1 is meant to be a
     * transient lockout the user can reopen the app from). Posted to the
     * main thread since Activity methods are not safe to call from
     * [execute]'s caller thread.
     */
    private fun finishForegroundActivity() {
        val activity = activityRef?.get() ?: return
        mainHandler.post {
            try {
                if (!activity.isFinishing && !activity.isDestroyed) {
                    activity.finishAffinity()
                }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "finishForegroundActivity failed" }
            }
        }
    }

    /**
     * Launches the system's own uninstall confirmation flow targeting
     * this app's package.
     *
     * This is NOT a silent uninstall. Android always shows a system
     * confirmation dialog for `ACTION_UNINSTALL_PACKAGE` -- hosted by a
     * separate system package/process (the platform's package installer
     * UI), even when the requesting app targets itself -- and no
     * ordinary (non device-owner/profile-owner) app can suppress that
     * prompt. Settings copy describing Tier 3 ("Nuclear Wipe") should say
     * so plainly: the wipe itself ([KeystorePurge], [StorageShredder])
     * is what's actually immediate and silent; this dialog is a
     * best-effort bonus attempt on top, not something this app can force
     * through unattended.
     *
     * Dispatched with `FLAG_ACTIVITY_NEW_TASK` since the caller is
     * frequently not an Activity context (a BroadcastReceiver or
     * TileService) -- a new-task launch is valid from an Activity context
     * too, so this works either way. Killing this process immediately
     * after does not cancel the dialog: by the time `startActivity`
     * returns, system_server already has the request queued against the
     * *installer's* process, independent of whether this one still
     * exists (see [nuclearWipe]'s short sleep before [terminateProcess]).
     */
    private fun dispatchUninstallIntent(context: Context) {
        try {
            val intent = Intent(Intent.ACTION_UNINSTALL_PACKAGE).apply {
                data = Uri.parse("package:${context.packageName}")
                putExtra(Intent.EXTRA_RETURN_RESULT, false)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "dispatchUninstallIntent failed" }
        }
    }

    /** Ends this process. `killProcess` alone is sufficient on Android and
     *  never returns; `exit` below is unreachable belt-and-braces, matching
     *  the plan's "process termination calls" (plural). */
    private fun terminateProcess() {
        try {
            android.os.Process.killProcess(android.os.Process.myPid())
        } finally {
            Runtime.getRuntime().exit(0)
        }
    }
}
