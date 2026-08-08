package com.aeidolon.vaultexplorer.syncbridge

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.RemoteException
import android.util.Log
import com.aeidolon.vaultexplorer.syncapi.BlockChange
import com.aeidolon.vaultexplorer.syncapi.ChangeSet
import com.aeidolon.vaultexplorer.syncapi.IVaultSyncCallback
import com.aeidolon.vaultexplorer.syncapi.IVaultSyncService
import com.aeidolon.vaultexplorer.syncapi.RootKind
import com.aeidolon.vaultexplorer.syncapi.VaultDescriptor
import com.aeidolon.vaultexplorer.syncapi.VaultSyncApiVersion
import com.aeidolon.vaultexplorer.syncbridge.internal.ILedgerWriter
import kotlinx.coroutines.runBlocking
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Runs in the `:syncbridge` process (`android:process=":syncbridge"` in
 * AndroidManifest.xml) — see docs/architecture.md §8 for the full picture
 * and vaultsync-bridge/docs/architecture.md §1.3 for the client side of
 * every decision cited below.
 *
 * Hosts two AIDL surfaces from the same process:
 *  - [IVaultSyncService] — the public, cross-app contract (`syncapi`
 *    module), bound by VaultSync Bridge. Every method re-checks the
 *    caller (ADR-S-007 on the other side; §8 ownership rule 9 here).
 *  - [ILedgerWriter] — the private, same-app contract used only by
 *    VaultExplorer's own main process (ContainerEngine's write hooks via
 *    [LedgerWriterClient]). Not exposed to, or checked against, the
 *    plugin at all.
 */
class VaultSyncBridgeService : Service() {

    private lateinit var db: SyncLedgerDb
    private val ioExecutor = Executors.newSingleThreadExecutor { r -> Thread(r, "syncbridge-io") }
    private val mainHandler = Handler(Looper.getMainLooper())

    // ---- registered push-callback (rule: at most meaningful to keep one
    // per plugin process; a second registerCallback from the same caller
    // simply replaces the first, matching bindService's own single-
    // connection-per-client shape) ----
    @Volatile private var callback: IVaultSyncCallback? = null
    private var callbackDeathRecipient: IBinder.DeathRecipient? = null

    // ---- open-fd tracking, per calling uid (§8 ownership rule: DoS guard
    // against a buggy or malicious client) ----
    private data class OpenFd(val pfd: ParcelFileDescriptor, val openedAtMs: Long, val callingUid: Int)
    private val openFdsByUid = ConcurrentHashMap<Int, MutableList<OpenFd>>()
    private val MAX_OPEN_FDS_PER_UID = 8
    private val FD_IDLE_TIMEOUT_MS = 60_000L
    private val fdReaper = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "syncbridge-fd-reaper") }

    // ---- pending staged writes: staging file -> (vaultId, relativePath,
    // expectedSizeBytes, callingUid), consumed by finalizeBlockWrite ----
    private data class StagedWrite(val vaultId: String, val relativePath: String, val expectedSizeBytes: Long, val callingUid: Int)
    private val stagedWrites = ConcurrentHashMap<String, StagedWrite>() // key: staging file absolute path

    override fun onCreate() {
        super.onCreate()
        db = SyncLedgerDb.get(applicationContext)
        fdReaper.scheduleWithFixedDelay({ reapIdleFds() }, FD_IDLE_TIMEOUT_MS, FD_IDLE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
    }

    override fun onBind(intent: Intent?): IBinder? {
        // §8.3 binding lifecycle: a caller that fails verification never
        // receives a Stub instance — bindService() itself fails on their
        // side, ServiceConnection.onServiceConnected never fires. This is
        // the first checkpoint; every call is re-checked again below.
        if (!requireCaller(Binder.getCallingUid())) {
            Log.w(TAG, "onBind rejected: uid ${Binder.getCallingUid()} not on pinned allowlist")
            return null
        }
        return when (intent?.action) {
            ACTION_LEDGER_WRITER -> ledgerWriterBinder
            else -> vaultSyncServiceBinder
        }
    }

    // onUnbind returns true (allows onRebind) so repeated short-lived
    // binds from periodic WorkManager jobs on the plugin side don't tear
    // down and recreate this Room connection every time (§8, mirrors
    // vaultsync-bridge §1.3.3).
    override fun onUnbind(intent: Intent?): Boolean = true

    private fun requireCaller(callingUid: Int): Boolean {
        if (callingUid == android.os.Process.myUid()) return true // ILedgerWriter, same app
        return CallerVerifier.check(applicationContext, callingUid)
    }

    // =====================================================================
    // ILedgerWriter — internal, same-app only
    // =====================================================================
    private val ledgerWriterBinder = object : ILedgerWriter.Stub() {
        override fun recordChange(
            rootUri: String,
            relativePath: String,
            changeType: String,
            sizeBytes: Long,
            detectedAtEpochMs: Long,
        ) {
            ioExecutor.execute {
                runBlocking {
                    val vault = db.syncVaultDao().findByRootUri(rootUri) ?: return@runBlocking
                    val nextSeq = db.dirtyLedgerDao().currentMaxSeq(vault.vaultId) + 1
                    db.dirtyLedgerDao().insert(
                        DirtyLedgerEntity(
                            vaultId = vault.vaultId,
                            seq = nextSeq,
                            relativePath = relativePath,
                            changeType = changeType,
                            sizeBytes = sizeBytes,
                            detectedAt = detectedAtEpochMs,
                        )
                    )
                    // Fired synchronously with the ledger insert, from the
                    // same process that did the insert — see
                    // IVaultSyncCallback.aidl's header comment for why
                    // this is safe to do without an extra dispatch hop.
                    notifyCallbackChanged(vault.vaultId, nextSeq)
                }
            }
        }
    }

    private fun notifyCallbackChanged(vaultId: String, cursor: Long) {
        val cb = callback ?: return
        try {
            cb.onVaultChanged(vaultId, cursor)
        } catch (e: RemoteException) {
            Log.w(TAG, "callback.onVaultChanged failed, dropping stale callback", e)
            callback = null
        }
    }

    // =====================================================================
    // IVaultSyncService — public, cross-app
    // =====================================================================
    private val vaultSyncServiceBinder = object : IVaultSyncService.Stub() {

        private fun requireCallerOrThrow() {
            if (!requireCaller(Binder.getCallingUid())) {
                throw SecurityException("caller uid ${Binder.getCallingUid()} is not an allowlisted VaultSync Bridge signer")
            }
        }

        override fun getBridgeApiVersion(): String {
            requireCallerOrThrow()
            return VaultSyncApiVersion.CURRENT
        }

        override fun listRegisteredVaults(): List<VaultDescriptor> {
            requireCallerOrThrow()
            return runBlocking { db.syncVaultDao().listAll().map { it.toDescriptor() } }
        }

        override fun registerVaultForSync(descriptor: VaultDescriptor): VaultDescriptor {
            requireCallerOrThrow()
            val vaultId = descriptor.vaultId.ifBlank { UUID.randomUUID().toString() }
            val entity = SyncVaultEntity(
                vaultId = vaultId,
                displayName = descriptor.displayName,
                format = descriptor.format,
                rootKind = descriptor.rootKind,
                rootUriOrPath = descriptor.rootUriOrPath,
                cursor = 0L,
                createdAt = System.currentTimeMillis(),
            )
            return runBlocking {
                db.syncVaultDao().upsert(entity)
                SyncBridgeActiveMarker.setActive(applicationContext, db.syncVaultDao().count() > 0)
                entity.toDescriptor()
            }
        }

        override fun unregisterVaultForSync(vaultId: String) {
            requireCallerOrThrow()
            runBlocking {
                db.syncVaultDao().delete(vaultId)
                db.dirtyLedgerDao().deleteAllForVault(vaultId)
                SyncBridgeActiveMarker.setActive(applicationContext, db.syncVaultDao().count() > 0)
            }
            callback?.let { cb ->
                try { cb.onVaultUnregistered(vaultId) } catch (e: RemoteException) { /* caller is gone; nothing to do */ }
            }
        }

        override fun listChangedBlocks(vaultId: String, sinceCursor: Long): ChangeSet {
            requireCallerOrThrow()
            return runBlocking {
                val entries = db.dirtyLedgerDao().changesSince(vaultId, sinceCursor)
                val newCursor = entries.lastOrNull()?.seq ?: sinceCursor
                ChangeSet(
                    vaultId = vaultId,
                    newCursor = newCursor,
                    changes = entries.map {
                        BlockChange(
                            changeType = it.changeType,
                            relativePath = it.relativePath,
                            sizeBytes = it.sizeBytes,
                            detectedAtEpochMs = it.detectedAt,
                        )
                    },
                )
            }
        }

        override fun commitCursor(vaultId: String, cursor: Long) {
            requireCallerOrThrow()
            runBlocking {
                db.syncVaultDao().advanceCursor(vaultId, cursor)
                db.dirtyLedgerDao().pruneUpTo(vaultId, cursor)
            }
        }

        override fun openBlockForRead(vaultId: String, relativePath: String): ParcelFileDescriptor? {
            requireCallerOrThrow()
            val root = resolveRoot(vaultId) ?: return null
            return try {
                val file = PathValidator.resolve(root, relativePath)
                trackOpenFd(
                    ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                )
            } catch (e: Exception) {
                Log.w(TAG, "openBlockForRead failed for $relativePath", e)
                null
            }
        }

        override fun openBlockForWrite(vaultId: String, relativePath: String, expectedSizeBytes: Long): ParcelFileDescriptor? {
            requireCallerOrThrow()
            val root = resolveRoot(vaultId) ?: return null
            return try {
                // Never the live path (ADR-S-003 on the other side): a
                // staging file under a hidden per-root directory, promoted
                // only by finalizeBlockWrite.
                PathValidator.resolve(root, relativePath) // validate shape even though we don't open it directly
                val staging = PathValidator.stagingFile(root)
                stagedWrites[staging.absolutePath] = StagedWrite(vaultId, relativePath, expectedSizeBytes, Binder.getCallingUid())
                trackOpenFd(
                    ParcelFileDescriptor.open(
                        staging,
                        ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE
                    )
                )
            } catch (e: Exception) {
                Log.w(TAG, "openBlockForWrite failed for $relativePath", e)
                null
            }
        }

        override fun finalizeBlockWrite(vaultId: String, relativePath: String): Boolean {
            requireCallerOrThrow()
            val root = resolveRoot(vaultId) ?: return false
            val callingUid = Binder.getCallingUid()
            val staged = stagedWrites.entries.find {
                it.value.vaultId == vaultId && it.value.relativePath == relativePath && it.value.callingUid == callingUid
            } ?: return false
            val stagingFile = File(staged.key)
            return try {
                if (!stagingFile.exists()) return false
                if (staged.value.expectedSizeBytes >= 0 && stagingFile.length() != staged.value.expectedSizeBytes) {
                    Log.w(TAG, "finalizeBlockWrite size mismatch for $relativePath: expected ${staged.value.expectedSizeBytes}, got ${stagingFile.length()}")
                    stagingFile.delete()
                    stagedWrites.remove(staged.key)
                    return false
                }
                val live = PathValidator.resolve(root, relativePath)
                live.parentFile?.mkdirs()
                val ok = stagingFile.renameTo(live) // same filesystem, atomic
                stagedWrites.remove(staged.key)
                ok
            } catch (e: Exception) {
                Log.w(TAG, "finalizeBlockWrite failed for $relativePath", e)
                false
            }
        }

        override fun deleteBlock(vaultId: String, relativePath: String): Boolean {
            requireCallerOrThrow()
            val root = resolveRoot(vaultId) ?: return false
            return try {
                PathValidator.resolve(root, relativePath).let { it.exists() && it.delete() }
            } catch (e: Exception) {
                Log.w(TAG, "deleteBlock failed for $relativePath", e)
                false
            }
        }

        override fun registerCallback(cb: IVaultSyncCallback) {
            requireCallerOrThrow()
            callback = cb
            val recipient = IBinder.DeathRecipient {
                Log.i(TAG, "plugin process died, clearing callback and any of its open fds")
                callback = null
                closeAllFdsForUid(Binder.getCallingUid())
            }
            callbackDeathRecipient = recipient
            try {
                cb.asBinder().linkToDeath(recipient, 0)
            } catch (e: RemoteException) {
                callback = null
            }
        }

        override fun unregisterCallback(cb: IVaultSyncCallback) {
            requireCallerOrThrow()
            callbackDeathRecipient?.let { cb.asBinder().unlinkToDeath(it, 0) }
            callback = null
            callbackDeathRecipient = null
        }
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    private fun SyncVaultEntity.toDescriptor() = VaultDescriptor(
        vaultId = vaultId, displayName = displayName, format = format,
        rootKind = rootKind, rootUriOrPath = rootUriOrPath, cursor = cursor,
    )

    private fun resolveRoot(vaultId: String): File? {
        val vault = runBlocking { db.syncVaultDao().get(vaultId) } ?: return null
        // SAF_TREE roots would need DocumentFile resolution to a real
        // filesystem path, which is not always possible depending on the
        // storage provider; DIRECT_PATH (internal-storage vaults, the
        // common case for USB/manually-picked directory vaults) resolves
        // directly. SAF_TREE support is intentionally out of scope for
        // the first cut — registerVaultForSync validates rootKind and a
        // SAF_TREE registration is accepted but openBlockForRead/Write
        // will simply fail closed (return null) until that's added.
        if (vault.rootKind != RootKind.DIRECT_PATH) return null
        val root = File(vault.rootUriOrPath)
        return if (root.isDirectory) root else null
    }

    private fun trackOpenFd(pfd: ParcelFileDescriptor): ParcelFileDescriptor {
        val uid = Binder.getCallingUid()
        val list = openFdsByUid.getOrPut(uid) { java.util.Collections.synchronizedList(mutableListOf()) }
        synchronized(list) {
            if (list.size >= MAX_OPEN_FDS_PER_UID) {
                // Hard cap: close the oldest rather than refuse the new
                // one, since a client that opened 8 and is now opening a
                // 9th almost certainly leaked the earliest ones.
                list.minByOrNull { it.openedAtMs }?.let {
                    runCatching { it.pfd.close() }
                    list.remove(it)
                }
            }
            list.add(OpenFd(pfd, System.currentTimeMillis(), uid))
        }
        return pfd
    }

    private fun reapIdleFds() {
        val now = System.currentTimeMillis()
        for ((_, list) in openFdsByUid) {
            synchronized(list) {
                val idle = list.filter { now - it.openedAtMs > FD_IDLE_TIMEOUT_MS }
                idle.forEach { runCatching { it.pfd.close() } }
                list.removeAll(idle)
            }
        }
    }

    private fun closeAllFdsForUid(uid: Int) {
        openFdsByUid.remove(uid)?.let { list ->
            synchronized(list) { list.forEach { runCatching { it.pfd.close() } } }
        }
    }

    override fun onDestroy() {
        fdReaper.shutdownNow()
        ioExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "VaultSyncBridgeService"
        const val ACTION_LEDGER_WRITER = "com.aeidolon.vaultexplorer.syncbridge.ACTION_LEDGER_WRITER"
    }
}
