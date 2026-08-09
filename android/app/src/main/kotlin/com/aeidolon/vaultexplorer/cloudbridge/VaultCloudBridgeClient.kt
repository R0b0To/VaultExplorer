package com.aeidolon.vaultexplorer.cloudbridge

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.RemoteException
import android.util.Log
import com.aeidolon.vaultexplorer.syncapi.CloudAccountDescriptor
import com.aeidolon.vaultexplorer.syncapi.IVaultCloudBridgeService
import com.aeidolon.vaultexplorer.syncapi.IVaultCloudCallback
import com.aeidolon.vaultexplorer.syncapi.RemoteVaultDescriptor
import com.aeidolon.vaultexplorer.syncapi.RemoteFolderDescriptor
import com.aeidolon.vaultexplorer.syncapi.VaultCloudApiVersion
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Client for VaultSync Bridge's direct-cloud AIDL service. */
class VaultCloudBridgeClient(context: Context) {
    sealed interface ConnectionState {
        data object Disconnected : ConnectionState
        data object Connecting : ConnectionState
        data object NotInstalled : ConnectionState
        data class Connected(val bridgeApiVersion: String) : ConnectionState
        data class VersionMismatch(val bridgeApiVersion: String) : ConnectionState
    }

    private val context = context.applicationContext
    private val mutableConnectionState = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    val connectionState: StateFlow<ConnectionState> = mutableConnectionState

    @Volatile private var service: IVaultCloudBridgeService? = null
    @Volatile private var bound = false
    var onSessionInvalidated: ((String, String, String) -> Unit)? = null

    private val callback = object : IVaultCloudCallback.Stub() {
        override fun onCloudSessionInvalidated(accountId: String, remoteVaultPath: String, reason: String) {
            onSessionInvalidated?.invoke(accountId, remoteVaultPath, reason)
        }
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val remote = IVaultCloudBridgeService.Stub.asInterface(binder)
            if (remote == null) {
                disconnect()
                return
            }
            try {
                val version = remote.cloudApiVersion
                remote.registerCloudCallback(callback)
                service = remote
                mutableConnectionState.value = if (
                    VaultCloudApiVersion.isCompatible(VaultCloudApiVersion.CURRENT, version)
                ) {
                    ConnectionState.Connected(version)
                } else {
                    ConnectionState.VersionMismatch(version)
                }
            } catch (e: RemoteException) {
                Log.w(TAG, "Cloud Bridge handshake failed", e)
                disconnect()
            } catch (e: SecurityException) {
                Log.w(TAG, "Cloud Bridge rejected this caller", e)
                disconnect()
            }
        }

        // Android keeps an explicit binding alive across a temporary service
        // disconnect and reconnects it when possible. Keep [bound] true here
        // so a subsequent UI query cannot accidentally create a second bind.
        override fun onServiceDisconnected(name: ComponentName?) = disconnect(keepBinding = true)

        override fun onBindingDied(name: ComponentName?) = disconnect()

        override fun onNullBinding(name: ComponentName?) = disconnect()
    }

    @Synchronized
    fun bind() {
        if (bound || mutableConnectionState.value is ConnectionState.Connecting) return
        if (!isBridgeInstalled()) {
            mutableConnectionState.value = ConnectionState.NotInstalled
            return
        }
        mutableConnectionState.value = ConnectionState.Connecting
        bound = try {
            context.bindService(
                Intent().setComponent(ComponentName(BRIDGE_PACKAGE, BRIDGE_SERVICE)),
                connection,
                Context.BIND_AUTO_CREATE,
            )
        } catch (e: SecurityException) {
            Log.w(TAG, "Cloud Bridge bind rejected", e)
            false
        }
        if (!bound) mutableConnectionState.value = ConnectionState.Disconnected
    }

    @Synchronized
    fun unbind() {
        val remote = service
        if (remote != null) {
            try {
                remote.unregisterCloudCallback(callback)
            } catch (_: Exception) {
                // The other process may already be gone.
            }
        }
        if (bound) {
            try {
                context.unbindService(connection)
            } catch (_: IllegalArgumentException) {
                // A dead binding can already have been cleaned up by Android.
            }
        }
        bound = false
        service = null
        mutableConnectionState.value = ConnectionState.Disconnected
    }

    fun listCloudAccounts(): List<CloudAccountDescriptor> = call(emptyList()) { listCloudAccounts() }

    fun discoverRemoteVaults(accountId: String, remoteDirectory: String): List<RemoteVaultDescriptor> =
        call(emptyList()) { discoverRemoteVaults(accountId, remoteDirectory) }

    fun listRemoteFolders(accountId: String, remoteDirectory: String): List<RemoteFolderDescriptor> =
        call(emptyList()) { listRemoteFolders(accountId, remoteDirectory) }

    fun openChunkForRead(accountId: String, remoteVaultPath: String, chunkIndex: Long): ParcelFileDescriptor? =
        call(null) { openRemoteChunkForRead(accountId, remoteVaultPath, chunkIndex) }

    /** Full-chunk convenience for the native ChunkedBlockDevice upcall path. */
    fun readChunk(
        accountId: String,
        remoteVaultPath: String,
        chunkIndex: Long,
        expectedSizeBytes: Int,
    ): ByteArray? {
        if (expectedSizeBytes <= 0) return null
        val descriptor = openChunkForRead(accountId, remoteVaultPath, chunkIndex) ?: return null
        return try {
            ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
                input.readBytes().copyOf(expectedSizeBytes)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not read remote chunk $chunkIndex", e)
            null
        }
    }

    fun openChunkForWrite(
        accountId: String,
        remoteVaultPath: String,
        chunkIndex: Long,
        expectedSizeBytes: Long,
    ): ParcelFileDescriptor? = call(null) {
        openRemoteChunkForWrite(accountId, remoteVaultPath, chunkIndex, expectedSizeBytes)
    }

    fun finalizeChunkWrite(accountId: String, remoteVaultPath: String, chunkIndex: Long): Boolean =
        call(false) { finalizeRemoteChunkWrite(accountId, remoteVaultPath, chunkIndex) }

    fun writeChunk(
        accountId: String,
        remoteVaultPath: String,
        chunkIndex: Long,
        bytes: ByteArray,
    ): Boolean {
        val descriptor = openChunkForWrite(
            accountId,
            remoteVaultPath,
            chunkIndex,
            bytes.size.toLong(),
        ) ?: return false
        return try {
            ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { it.write(bytes) }
            finalizeChunkWrite(accountId, remoteVaultPath, chunkIndex)
        } catch (e: Exception) {
            Log.w(TAG, "Could not write remote chunk $chunkIndex", e)
            false
        }
    }

    fun closeRemoteVaultSession(accountId: String, remoteVaultPath: String) {
        call(Unit) { closeRemoteVaultSession(accountId, remoteVaultPath) }
    }

    private fun <T> call(fallback: T, action: IVaultCloudBridgeService.() -> T): T {
        val remote = service ?: return fallback
        return try {
            remote.action()
        } catch (e: RemoteException) {
            Log.w(TAG, "Cloud Bridge IPC failed", e)
            disconnect()
            fallback
        } catch (e: SecurityException) {
            Log.w(TAG, "Cloud Bridge caller verification failed", e)
            disconnect()
            fallback
        }
    }

    private fun isBridgeInstalled(): Boolean = try {
        context.packageManager.getApplicationInfo(BRIDGE_PACKAGE, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    @Synchronized
    private fun disconnect(keepBinding: Boolean = false) {
        service = null
        if (!keepBinding) bound = false
        mutableConnectionState.value = ConnectionState.Disconnected
    }

    private companion object {
        const val TAG = "VaultCloudBridgeClient"
        const val BRIDGE_PACKAGE = "com.aeidolon.vaultsync"
        const val BRIDGE_SERVICE = "com.aeidolon.vaultsync.bridge.VaultCloudBridgeService"
    }
}
