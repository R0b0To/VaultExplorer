package com.aeidolon.vaultexplorer.automation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Looper
import android.content.pm.ServiceInfo
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.container.ContainerLifecycleCore
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.handlers.ScheduledSyncFileBridge
import com.aeidolon.vaultexplorer.saf.UriToPath
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Runs one scheduled rule in a foreground WorkManager service and relocks in all cases. */
class ScheduledVaultSyncWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    companion object {
        const val KEY_VAULT_URI = "vaultUri"
        const val KEY_VAULT_NAME = "vaultName"
        const val KEY_RULE_ID = "ruleId"
        const val KEY_TARGET_URI = "targetUri"
        const val KEY_TARGET_SUB_PATH = "targetSubPath"
        const val KEY_TARGET_NAME = "targetName"

        private const val CHANNEL_ID = "scheduled_vault_sync"
        private const val NOTIFICATION_ID = 71024
        private const val CONTROL_CHANNEL = "com.aeidolon.vaultexplorer/scheduled_sync"
    }

    private var engine: FlutterEngine? = null
    private var controlChannel: MethodChannel? = null
    private var fileBridge: ScheduledSyncFileBridge? = null

    override suspend fun doWork(): Result {
        val vaultUri = inputData.getString(KEY_VAULT_URI) ?: return Result.failure()
        val ruleId = inputData.getString(KEY_RULE_ID) ?: return Result.failure()
        var ownsVaultSession = false

        try {
            if (!AutomationSettings.canImportExport(applicationContext, vaultUri) ||
                AutomationSettings.getStoredPassword(applicationContext, vaultUri).isNullOrEmpty()
            ) {
                return Result.failure()
            }
            if (!NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()) {
                return Result.failure()
            }
            setForeground(foregroundInfo())

            // Never take ownership of an interactive mount, which may be in use by the person.
            if (ContainerSessionRegistry.getVolumeIdByUri(vaultUri) != null) {
                return Result.success()
            }

            val unlockError = VaultAutomationReceiver().unlockForScheduledSync(
                applicationContext,
                vaultUri,
            )
            if (unlockError != null) return Result.failure()
            ownsVaultSession = true
            val volId = ContainerSessionRegistry.getVolumeIdByUri(vaultUri)
                ?: return Result.failure()
            val targetUri = inputData.getString(KEY_TARGET_URI).orEmpty()
            val vaultRawPath = UriToPath.getRawPath(applicationContext, Uri.parse(vaultUri))
            val targetRawPath = UriToPath.getRawPath(applicationContext, Uri.parse(targetUri))

            val runSucceeded = runHeadlessFlutter(
                mapOf(
                    KEY_VAULT_URI to vaultUri,
                    KEY_VAULT_NAME to (inputData.getString(KEY_VAULT_NAME) ?: "Vault"),
                    "vaultVolId" to volId,
                    KEY_RULE_ID to ruleId,
                    KEY_TARGET_URI to targetUri,
                    "vaultRawPath" to (vaultRawPath ?: vaultUri),
                    "targetRawPath" to (targetRawPath ?: targetUri),
                    KEY_TARGET_SUB_PATH to inputData.getString(KEY_TARGET_SUB_PATH).orEmpty(),
                    KEY_TARGET_NAME to (inputData.getString(KEY_TARGET_NAME) ?: "Folder"),
                ),
            )
            return if (runSucceeded) Result.success() else Result.failure()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            return Result.failure()
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
                if (ownsVaultSession &&
                    ContainerSessionRegistry.getVolumeIdByUri(vaultUri) != null
                ) {
                    ContainerLifecycleCore.lockContainer(applicationContext, vaultUri)
                }
            }
        }
    }

    private suspend fun runHeadlessFlutter(args: Map<String, Any?>): Boolean {
        val ready = CompletableDeferred<Unit>()
        val (createdEngine, channel) = withContext(Dispatchers.Main) {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)

            FlutterEngine(applicationContext).let { flutterEngine ->
                val bridge = ScheduledSyncFileBridge(applicationContext)
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

        // End well before Android 15's dataSync foreground-service time cap.
        // WorkManager cancellation runs the cleanup path and relocks the vault.
        return withTimeout(5 * 60 * 60 * 1000L + 30 * 60 * 1000L) {
            suspendCancellableCoroutine { continuation ->
                channel.invokeMethod(
                    "runScheduledSync",
                    args,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            val success = (result as? Map<*, *>)?.get("success") == true
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
                    HandlerOnMain.post {
                        channel.invokeMethod("cancelScheduledSync", null)
                    }
                }
            }
        }
    }

    private fun foregroundInfo(): ForegroundInfo {
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    applicationContext.getString(R.string.scheduled_sync_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = applicationContext.getString(R.string.scheduled_sync_channel_description)
                    setShowBadge(false)
                },
            )
        }
        val notification: Notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_vault)
            .setContentTitle(applicationContext.getString(R.string.syncing_vault_notification))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private object HandlerOnMain {
        private val handler = android.os.Handler(Looper.getMainLooper())
        fun post(block: () -> Unit) = handler.post(block)
    }
}
