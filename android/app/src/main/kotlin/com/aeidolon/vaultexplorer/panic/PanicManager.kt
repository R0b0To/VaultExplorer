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

object PanicManager {

    private const val TAG = "PanicManager"
    private const val CONTAINER_DOCUMENTS_AUTHORITY = "com.aeidolon.vaultexplorer.documents"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val runningGuard = AtomicBoolean(false)

    @Volatile
    private var activityRef: WeakReference<Activity>? = null

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
            runningGuard.set(false)
        }
    }

    // ── Tier 1: Session & Vault Credentials Purge ─────────────────────

    private fun sessionPurge(context: Context, source: String): PanicResult {
        runCatching { hooks?.onBeforeSessionPurge(context) }
            .onFailure { VeLog.w(TAG, it) { "onBeforeSessionPurge hook threw" } }

        val lockedCount = unmountAllContainers(context)
        cancelBackgroundWork(context)
        val vaultCredsCleared = StorageShredder.clearVaultCredentials(context)
        finishForegroundActivity()

        runCatching { hooks?.onAfterSessionPurge(context) }
            .onFailure { VeLog.w(TAG, it) { "onAfterSessionPurge hook threw" } }

        VeLog.i(TAG) { "sessionPurge(source=$source): locked $lockedCount container(s), cleared $vaultCredsCleared vault credentials" }
        return PanicResult(
            PanicTier.SESSION_PURGE,
            success = true,
            containersLocked = lockedCount,
            credentialStoresCleared = vaultCredsCleared,
        )
    }

    // ── Tier 2: Credential & Metadata Purge (Identity Reset) ──────────

    private fun credentialPurge(context: Context, source: String): PanicResult {
        val tier1 = sessionPurge(context, source)

        val aliasesPurged = KeystorePurge.purgeAll()
        val storesCleared = StorageShredder.purgeCredentialStores(context)

        runCatching { hooks?.onAfterCredentialPurge(context) }
            .onFailure { VeLog.w(TAG, it) { "onAfterCredentialPurge hook threw" } }

        VeLog.i(TAG) {
            "credentialPurge(source=$source): purged $aliasesPurged Keystore alias(es), " +
                "cleared $storesCleared credential store(s)/metadata file(s)"
        }
        return tier1.copy(
            tier = PanicTier.CREDENTIAL_PURGE,
            keystoreAliasesPurged = aliasesPurged,
            credentialStoresCleared = tier1.credentialStoresCleared + storesCleared,
        )
    }

    // ── Tier 3: Nuclear Destruction ────────────────────────────────────

    private fun nuclearWipe(context: Context, source: String): PanicResult {
        runCatching { hooks?.onBeforeSessionPurge(context) }
            .onFailure { VeLog.w(TAG, it) { "onBeforeSessionPurge hook threw" } }

        val lockedCount = unmountAllContainers(context)
        cancelBackgroundWork(context)

        runCatching { hooks?.onAfterSessionPurge(context) }
            .onFailure { VeLog.w(TAG, it) { "onAfterSessionPurge hook threw" } }

        val aliasesPurged = KeystorePurge.purgeAll()
        val storesCleared = StorageShredder.purgeCredentialStores(context)

        runCatching { hooks?.onAfterCredentialPurge(context) }
            .onFailure { VeLog.w(TAG, it) { "onAfterCredentialPurge hook threw" } }

        val filesWiped = StorageShredder.wipeAllInternalStorage(context)

        runCatching { hooks?.onBeforeProcessDeath(context) }
            .onFailure { VeLog.w(TAG, it) { "onBeforeProcessDeath hook threw" } }

        VeLog.i(TAG) { "nuclearWipe(source=$source): wiped $filesWiped file(s); dispatching system uninstall prompt" }

        // Dispatch system uninstall prompt from foreground activity
        dispatchUninstallIntent(context)

        // Dismiss this application from task manager/recents
        finishForegroundActivity()

        return PanicResult(
            PanicTier.NUCLEAR_WIPE,
            success = true,
            containersLocked = lockedCount,
            keystoreAliasesPurged = aliasesPurged,
            credentialStoresCleared = storesCleared,
            filesWiped = filesWiped,
        )
    }

    // ── Shared subsystems ──────────────────────────────────────────────

    private fun unmountAllContainers(context: Context): Int {
        val volIds = ContainerSessionRegistry.activeSessions.keys.toList()
        var locked = 0
        for (volId in volIds) {
            try {
                val session = ContainerSessionRegistry.activeSessions[volId]
                PdfRendererRegistry.closeAllForVolume(volId)
                VaultPdfSessionRegistry.revokeAllForVolume(volId)

                try {
                    com.aeidolon.vaultexplorer.NativeEngine.emergencyPurgeNative(volId)
                } catch (e: Throwable) {
                    VeLog.w(TAG, e) { "emergencyPurgeNative failed for volId=$volId" }
                }

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
            }
        }
        return locked
    }

    private fun cancelBackgroundWork(context: Context) {
        try {
            context.stopService(Intent(context, VaultKeepAliveService::class.java))
        } catch (_: Exception) {
        }
        try {
            context.stopService(Intent(context, VaultAutomationRecordingService::class.java))
        } catch (_: Exception) {
        }
    }

    private fun finishForegroundActivity() {
        val activity = activityRef?.get() ?: return
        mainHandler.post {
            try {
                if (!activity.isFinishing && !activity.isDestroyed) {
                    activity.finishAndRemoveTask()
                }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "finishForegroundActivity failed" }
            }
        }
    }

    private fun dispatchUninstallIntent(context: Context) {
        try {
            val intent = Intent(Intent.ACTION_DELETE).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val activity = activityRef?.get()
            if (activity != null && !activity.isFinishing && !activity.isDestroyed) {
                activity.startActivity(intent)
            } else {
                context.startActivity(intent)
            }
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "dispatchUninstallIntent failed" }
        }
    }
}