package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Notifies Dart when a vault is unlocked from outside the normal
 * Dart-initiated unlockContainer()/unlockDirectoryVault() flow -- currently
 * only VaultAutomationReceiver's UNLOCK_VAULT action, which can run (and
 * mount a container) while no Activity -- and so no Flutter engine -- exists
 * at all. Mirrors [VaultForceLockedBridge] for the opposite direction:
 * best-effort only, silently drops the event if nothing is currently
 * listening.
 *
 * That drop case is expected, not a bug to fix here: this bridge only
 * covers the case the app happens to already be open, with a live engine,
 * when the broadcast lands. A vault unlocked entirely while the app was
 * closed (or backgrounded past the point Android killed the engine) is
 * instead caught by VaultUnlockHandlers.handleGetActiveContainerSessions --
 * VaultDashboardScreen._reconcileActiveSessions calls it on init and on
 * every resume, so this bridge only needs to handle the live-engine case;
 * the cold-start/reattach case has its own separate path.
 *
 * VaultDashboardScreen is the intended listener (see
 * addVaultAutomationUnlockedListener in vault_explorer_api.dart).
 *
 * [channel] doubles as the receiver's "is the app open?" test, so
 * MainActivity.onDestroy must clear it: a stale channel would make
 * SYNC_VAULT hand its work to an engine that no longer exists.
 */
object VaultAutomationUnlockedBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun reportUnlocked(
        volId: Int,
        uri: String,
        displayName: String,
        containerFormat: String,
        readOnly: Boolean,
        files: List<String>,
    ) {
        val ch = channel ?: return
        mainHandler.post {
            ch.invokeMethod(
                "onVaultAutomationUnlocked",
                mapOf(
                    "volId" to volId,
                    "uri" to uri,
                    "displayName" to displayName,
                    "containerFormat" to containerFormat,
                    "readOnly" to readOnly,
                    "files" to files,
                ),
            )
        }
    }

    /** The open app's answer to [requestSync]; [code] is an Outcome result code. */
    data class SyncReply(val code: String, val message: String)

    /**
     * Asks the open app to run its sync rules for [uri] and waits for it to
     * finish. Returns null when no app is listening, so the caller can fall
     * back to a headless sync; a sync that is still running after
     * [timeoutMs] answers BUSY (it keeps running -- only the wait ends).
     *
     * Blocks: never call from the main thread. The automation receiver's
     * executor and WorkManager worker are both off it.
     */
    @JvmStatic
    fun requestSync(uri: String, timeoutMs: Long): SyncReply? {
        val ch = channel ?: return null
        val reply = CompletableFuture<SyncReply>()
        mainHandler.post {
            ch.invokeMethod(
                "onVaultAutomationSyncRequested",
                mapOf("uri" to uri),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val payload = result as? Map<*, *>
                        reply.complete(
                            SyncReply(
                                payload?.get("code") as? String ?: "ERROR",
                                payload?.get("message") as? String
                                    ?: "The open app returned no details",
                            ),
                        )
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        reply.complete(SyncReply("ERROR", message ?: code))
                    }

                    override fun notImplemented() {
                        reply.complete(SyncReply("ERROR", "The open app cannot run sync"))
                    }
                },
            )
        }
        return try {
            reply.get(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: TimeoutException) {
            SyncReply("BUSY", "Sync is still running in the open app")
        } catch (e: Exception) {
            SyncReply("ERROR", "Could not reach the open app (${e.javaClass.simpleName})")
        }
    }
}