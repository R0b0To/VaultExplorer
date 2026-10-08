package com.aeidolon.vaultexplorer.automation

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Looper
import android.util.Log
import androidx.work.Data
import com.aeidolon.vaultexplorer.container.ContainerLifecycleCore
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.handlers.ScheduledSyncFileBridge
import com.aeidolon.vaultexplorer.handlers.ScheduledSyncHandlers
import com.aeidolon.vaultexplorer.saf.UriToPath
import com.aeidolon.vaultexplorer.service.VaultKeepAliveService
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Performs one scheduled sync and always relocks a vault session it opened. */
class ScheduledVaultSyncRunner(
    private val context: Context,
    private val inputData: Data,
) {
    companion object {
        private const val TAG = "ScheduledVaultSyncRunner"
        private const val CONTROL_CHANNEL = "com.aeidolon.vaultexplorer/scheduled_sync"
        private val vaultSyncLocks = ConcurrentHashMap<String, Mutex>()
    }

    private var engine: FlutterEngine? = null
    private var controlChannel: MethodChannel? = null
    private var fileBridge: ScheduledSyncFileBridge? = null

    suspend fun run(): Boolean {
        val vaultUri = inputData.getString(ScheduledVaultSyncWorker.KEY_VAULT_URI)
            ?: return false
        val ruleId = inputData.getString(ScheduledVaultSyncWorker.KEY_RULE_ID)
            ?: return false
        if (!ScheduledSyncHandlers.isScheduleActive(context, inputData)) return true

        val lock = vaultSyncLocks.computeIfAbsent(vaultUri) { Mutex() }
        return lock.withLock { performScheduledSync(vaultUri, ruleId) }
    }

    private suspend fun performScheduledSync(vaultUri: String, ruleId: String): Boolean {
        if (!ScheduledSyncHandlers.isScheduleActive(context, inputData)) return true
        var ownsVaultSession = false

        try {
            // Never take ownership of an interactive mount, which may be in use by the person.
            if (ContainerSessionRegistry.getVolumeIdByUri(vaultUri) != null) return true

            val unlockError = VaultAutomationReceiver().unlockForScheduledSync(context, vaultUri)
            if (unlockError != null) return false
            ownsVaultSession = true
            val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri) ?: return false
            val targetUri = inputData.getString(ScheduledVaultSyncWorker.KEY_TARGET_URI).orEmpty()
            val vaultRawPath = UriToPath.getRawPath(context, Uri.parse(vaultUri))
            val targetRawPath = UriToPath.getRawPath(context, Uri.parse(targetUri))

            return runHeadlessFlutter(
                mapOf(
                    ScheduledVaultSyncWorker.KEY_VAULT_URI to vaultUri,
                    ScheduledVaultSyncWorker.KEY_VAULT_NAME to
                        (inputData.getString(ScheduledVaultSyncWorker.KEY_VAULT_NAME) ?: "Vault"),
                    "vaultVolId" to volId,
                    ScheduledVaultSyncWorker.KEY_RULE_ID to ruleId,
                    ScheduledVaultSyncWorker.KEY_TARGET_URI to targetUri,
                    "vaultRawPath" to (vaultRawPath ?: vaultUri),
                    "targetRawPath" to (targetRawPath ?: targetUri),
                    ScheduledVaultSyncWorker.KEY_TARGET_SUB_PATH to
                        inputData.getString(ScheduledVaultSyncWorker.KEY_TARGET_SUB_PATH).orEmpty(),
                    ScheduledVaultSyncWorker.KEY_TARGET_NAME to
                        (inputData.getString(ScheduledVaultSyncWorker.KEY_TARGET_NAME) ?: "Folder"),
                ),
            )
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Scheduled sync execution threw ${e.javaClass.simpleName}: ${e.message}", e)
            return false
        } finally {
            withContext(NonCancellable) {
                withContext(Dispatchers.Main) {
                    controlChannel?.setMethodCallHandler(null)
                    controlChannel = null
                    engine?.destroy()
                    engine = null
                }
                fileBridge?.dispose()
                fileBridge = null
                if (ownsVaultSession && ContainerSessionRegistry.getVolumeIdByUri(vaultUri) != null) {
                    val locked = ContainerLifecycleCore.lockContainer(context, vaultUri)
                    if (!locked) {
                        Log.e(TAG, "Could not lock the vault after scheduled sync")
                    } else if (!ContainerSessionRegistry.hasAnyActiveSessions()) {
                        // The unlock path can start this separate keep-alive service. The
                        // scheduled service owns its own foreground notification, so stop the
                        // keep-alive service after its temporary vault session has been closed.
                        context.stopService(Intent(context, VaultKeepAliveService::class.java))
                    }
                }
            }
        }
    }

    private suspend fun runHeadlessFlutter(args: Map<String, Any?>): Boolean {
        val ready = CompletableDeferred<Unit>()
        val (createdEngine, channel) = withContext(Dispatchers.Main) {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(context)
            loader.ensureInitializationComplete(context, null)

            FlutterEngine(context).let { flutterEngine ->
                val bridge = ScheduledSyncFileBridge(context)
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    "com.aeidolon.vaultexplorer/engine",
                ).setMethodCallHandler(bridge)
                fileBridge = bridge

                val control = MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    CONTROL_CHANNEL,
                )
                control.setMethodCallHandler { call, result ->
                    if (call.method == "ready") {
                        ready.complete(Unit)
                        result.success(null)
                    } else {
                        result.notImplemented()
                    }
                }
                flutterEngine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "scheduledSyncBackgroundEntrypoint",
                    ),
                )
                Pair(flutterEngine, control)
            }
        }

        engine = createdEngine
        controlChannel = channel
        withTimeout(30_000) { ready.await() }

        // Keep this below Android's dataSync foreground-service time limit.
        return withTimeout(5 * 60 * 60 * 1000L + 30 * 60 * 1000L) {
            withContext(Dispatchers.Main) {
                suspendCancellableCoroutine { continuation ->
                    channel.invokeMethod(
                        "runScheduledSync",
                        args,
                        object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                val payload = result as? Map<*, *>
                                val success = payload?.get("success") == true
                                if (!success) {
                                    val reason = payload?.get("reason")?.toString()
                                        ?: "The headless sync returned no failure details"
                                    Log.e(TAG, "Scheduled sync rule failed: $reason")
                                }
                                if (continuation.isActive) continuation.resume(success)
                            }

                            override fun error(code: String, message: String?, details: Any?) {
                                if (continuation.isActive) {
                                    continuation.resumeWithException(
                                        IllegalStateException("$code: ${message.orEmpty()}"),
                                    )
                                }
                            }

                            override fun notImplemented() {
                                if (continuation.isActive) {
                                    continuation.resumeWithException(
                                        IllegalStateException("Scheduled sync entrypoint is unavailable"),
                                    )
                                }
                            }
                        },
                    )
                    continuation.invokeOnCancellation {
                        HandlerOnMain.post { channel.invokeMethod("cancelScheduledSync", null) }
                    }
                }
            }
        }
    }

    private object HandlerOnMain {
        private val handler = android.os.Handler(Looper.getMainLooper())
        fun post(block: () -> Unit) = handler.post(block)
    }
}
