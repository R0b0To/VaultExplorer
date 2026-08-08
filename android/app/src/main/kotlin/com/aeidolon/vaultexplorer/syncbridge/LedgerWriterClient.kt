package com.aeidolon.vaultexplorer.syncbridge

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.os.RemoteException
import android.util.Log
import com.aeidolon.vaultexplorer.syncbridge.internal.ILedgerWriter
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Called from [com.aeidolon.vaultexplorer.ContainerEngine]'s write hooks
 * (docs/architecture.md ADR-029). Every entry point is a fire-and-forget
 * best-effort notification — a dropped or delayed ledger entry means a
 * sync happens on the next reconciliation pull instead of the next push
 * (vaultsync-bridge §4.1), never a correctness problem for VaultExplorer
 * itself, so nothing here may throw, block the caller, or affect a write
 * that already succeeded on disk.
 */
object LedgerWriterClient {

    @Volatile private var appContext: Context? = null
    @Volatile private var binder: ILedgerWriter? = null
    private val pending = ConcurrentLinkedQueue<PendingChange>()
    private val MAX_PENDING = 256 // bound the queue; a dead/never-installed plugin must not leak memory

    private data class PendingChange(
        val rootUri: String, val relativePath: String, val changeType: String,
        val sizeBytes: Long, val detectedAtEpochMs: Long,
    )

    /** Called once, very early, by [SyncBridgeContextInitializer] — see
     *  that class for why this is a ContentProvider trick rather than a
     *  custom Application subclass. */
    fun attachContext(context: Context) {
        if (appContext == null) appContext = context.applicationContext
    }

    fun notifyChangeIfActive(rootUri: String, relativePath: String, changeType: String, sizeBytes: Long) {
        val context = appContext ?: return
        if (!SyncBridgeActiveMarker.isActive(context)) return // near-zero-cost common case
        val change = PendingChange(rootUri, relativePath, changeType, sizeBytes, System.currentTimeMillis())
        val current = binder
        if (current != null) {
            sendOrQueue(current, change)
        } else {
            enqueue(change)
            bindIfNeeded(context)
        }
    }

    private fun sendOrQueue(b: ILedgerWriter, change: PendingChange) {
        try {
            b.recordChange(change.rootUri, change.relativePath, change.changeType, change.sizeBytes, change.detectedAtEpochMs)
        } catch (e: RemoteException) {
            binder = null
            enqueue(change)
        }
    }

    private fun enqueue(change: PendingChange) {
        pending.add(change)
        while (pending.size > MAX_PENDING) pending.poll()
    }

    @Volatile private var binding = false

    private fun bindIfNeeded(context: Context) {
        if (binding || binder != null) return
        binding = true
        val intent = Intent(context, VaultSyncBridgeService::class.java).apply {
            action = VaultSyncBridgeService.ACTION_LEDGER_WRITER
        }
        val ok = context.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        if (!ok) {
            binding = false
            Log.w(TAG, "bindService(:syncbridge) failed")
        }
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder) {
            binding = false
            binder = ILedgerWriter.Stub.asInterface(service)
            drainPending()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            binder = null
        }
    }

    private fun drainPending() {
        val b = binder ?: return
        var change = pending.poll()
        while (change != null) {
            sendOrQueue(b, change)
            change = pending.poll()
        }
    }

    private const val TAG = "LedgerWriterClient"
}
