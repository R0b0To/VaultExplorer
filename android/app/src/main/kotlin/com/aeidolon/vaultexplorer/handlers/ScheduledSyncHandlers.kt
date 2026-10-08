package com.aeidolon.vaultexplorer.handlers

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.work.Data
import androidx.work.WorkManager
import com.aeidolon.vaultexplorer.automation.AutomationSettings
import com.aeidolon.vaultexplorer.automation.ScheduledVaultSyncAlarmReceiver
import com.aeidolon.vaultexplorer.automation.ScheduledVaultSyncWorker
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Calendar
import java.util.Locale

/** Schedules device-local daily syncs. No password is stored in alarms or work input. */
class ScheduledSyncHandlers(context: Context) {
    private val appContext = context.applicationContext

    companion object {
        const val ACTION_DAILY_SYNC = "com.aeidolon.vaultexplorer.action.DAILY_VAULT_SYNC"
        const val ACTION_EXACT_ALARM_PERMISSION_CHANGED =
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
        const val EXTRA_VAULT_URI = "scheduledVaultUri"
        const val EXTRA_RULE_ID = "scheduledRuleId"
        const val EXTRA_SCHEDULED_FOR = "scheduledForMillis"

        private const val VAULT_TAG_PREFIX = "scheduled-vault-sync-vault-"
        private const val RULE_TAG_PREFIX = "scheduled-vault-sync-rule-"
        private const val CONFIG_PREFIX = "schedule-"
        private const val PREFS_NAME = "scheduled_vault_sync"
        private val scheduleLock = Any()

        fun canScheduleExactAlarms(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            return manager.canScheduleExactAlarms()
        }

        fun requestExactAlarmAccess(context: Context): Boolean {
            if (canScheduleExactAlarms(context)) return true
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
            return runCatching {
                val request = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.applicationContext.startActivity(request)
                true
            }.getOrDefault(false)
        }

        fun cancelSchedulesForVault(context: Context, vaultUri: String) {
            val appContext = context.applicationContext
            synchronized(scheduleLock) {
                val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val editor = prefs.edit()
                for ((key, value) in prefs.all) {
                    if (!key.startsWith(CONFIG_PREFIX) || value !is String) continue
                    val stored = runCatching { JSONObject(value) }.getOrNull() ?: continue
                    if (stored.optString("vaultUri") != vaultUri) continue
                    cancelAlarm(appContext, stored.optString("vaultUri"), stored.optString("ruleId"))
                    editor.remove(key)
                }
                editor.commit()
            }
            WorkManager.getInstance(appContext).cancelAllWorkByTag(vaultTag(vaultUri))
        }

        /** Queue tomorrow's exact alarm before doing work, so failures don't end the schedule. */
        fun isScheduleActive(context: Context, input: Data): Boolean {
            val vaultUri = input.getString(ScheduledVaultSyncWorker.KEY_VAULT_URI)
                ?: return false
            val ruleId = input.getString(ScheduledVaultSyncWorker.KEY_RULE_ID)
                ?: return false
            val hour = input.getInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_HOUR, -1)
            val minute = input.getInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_MINUTE, -1)
            if (!isValidTime(hour, minute)) return false

            synchronized(scheduleLock) {
                val prefs = context.applicationContext.getSharedPreferences(
                    PREFS_NAME,
                    Context.MODE_PRIVATE,
                )
                val stored = prefs.getString(configKey(vaultUri, ruleId), null)
                    ?.let { runCatching { JSONObject(it) }.getOrNull() }
                    ?: return false
                return stored.optString("vaultUri") == vaultUri &&
                    stored.optString("ruleId") == ruleId &&
                    stored.optInt("hour", -1) == hour &&
                    stored.optInt("minute", -1) == minute &&
                    stored.optString("targetUri").isNotBlank() &&
                    AutomationSettings.canImportExport(context, vaultUri) &&
                    !AutomationSettings.getStoredPassword(context, vaultUri).isNullOrEmpty()
            }
        }

        fun getStoredInput(
            context: Context,
            vaultUri: String,
            ruleId: String,
            scheduledForMillis: Long,
        ): Data? {
            val stored = context.applicationContext.getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE,
            ).getString(configKey(vaultUri, ruleId), null)
                ?.let { runCatching { JSONObject(it) }.getOrNull() }
                ?: return null
            if (stored.optString("vaultUri") != vaultUri || stored.optString("ruleId") != ruleId) {
                return null
            }
            val targetUri = stored.optString("targetUri")
            if (targetUri.isBlank()) return null
            return workData(
                vaultUri = vaultUri,
                vaultName = stored.optString("vaultName", "Vault"),
                ruleId = ruleId,
                targetUri = targetUri,
                targetSubPath = stored.optString("targetSubPath", ""),
                targetName = stored.optString("targetName", "Folder"),
                hour = stored.optInt("hour", -1),
                minute = stored.optInt("minute", -1),
                scheduledForMillis = scheduledForMillis,
            )
        }

        fun inputFromServiceIntent(context: Context, intent: Intent): Data? {
            val vaultUri = intent.getStringExtra(EXTRA_VAULT_URI) ?: return null
            val ruleId = intent.getStringExtra(EXTRA_RULE_ID) ?: return null
            val scheduledFor = intent.getLongExtra(EXTRA_SCHEDULED_FOR, 0L)
            return getStoredInput(context, vaultUri, ruleId, scheduledFor)
        }

        /** Called by startup and system broadcasts to restore alarms after reboot/time changes. */
        fun rescheduleAll(context: Context) {
            val appContext = context.applicationContext
            if (!canScheduleExactAlarms(appContext)) return
            val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val configs = prefs.all.entries
                .filter { it.key.startsWith(CONFIG_PREFIX) && it.value is String }
                .mapNotNull { (key, value) ->
                    val stored = runCatching { JSONObject(value as String) }.getOrNull()
                        ?: return@mapNotNull null
                    Pair(stored.optString("vaultUri"), stored.optString("ruleId"))
                }

            for ((vaultUri, ruleId) in configs) {
                if (vaultUri.isBlank() || ruleId.isBlank()) continue
                val input = getStoredInput(appContext, vaultUri, ruleId, 0L)
                if (input == null || !isScheduleActive(appContext, input)) continue

                val hour = input.getInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_HOUR, -1)
                val minute = input.getInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_MINUTE, -1)
                cancelAlarm(appContext, vaultUri, ruleId)
                val next = nextOccurrence(hour, minute, Calendar.getInstance())
                scheduleAlarm(appContext, input, next.timeInMillis)
                cancelLegacyWork(appContext, vaultUri, ruleId)
            }
        }

        /** Queue tomorrow's exact alarm before doing work, so failures or OS stops don't end the schedule. */
        fun scheduleNextOccurrence(context: Context, input: Data) {
            if (!isScheduleActive(context, input) || !canScheduleExactAlarms(context)) return
            val vaultUri = input.getString(ScheduledVaultSyncWorker.KEY_VAULT_URI) ?: return
            val ruleId = input.getString(ScheduledVaultSyncWorker.KEY_RULE_ID) ?: return
            val hour = input.getInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_HOUR, -1)
            val minute = input.getInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_MINUTE, -1)
            if (!isValidTime(hour, minute)) return

            synchronized(scheduleLock) {
                val next = nextOccurrence(
                    hour,
                    minute,
                    Calendar.getInstance(),
                    input.getLong(ScheduledVaultSyncWorker.KEY_SCHEDULED_FOR, 0L),
                )
                scheduleAlarm(context.applicationContext, input, next.timeInMillis)
            }
        }

        /** Migrate target details carried by an already-enqueued WorkManager request. */
        fun captureLegacyWorkerInput(context: Context, input: Data): Boolean {
            val vaultUri = input.getString(ScheduledVaultSyncWorker.KEY_VAULT_URI) ?: return false
            val ruleId = input.getString(ScheduledVaultSyncWorker.KEY_RULE_ID) ?: return false
            val targetUri = input.getString(ScheduledVaultSyncWorker.KEY_TARGET_URI).orEmpty()
            val hour = input.getInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_HOUR, -1)
            val minute = input.getInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_MINUTE, -1)
            if (targetUri.isBlank() || !isValidTime(hour, minute)) return false
            synchronized(scheduleLock) {
                val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val key = configKey(vaultUri, ruleId)
                val stored = prefs.getString(key, null)?.let { runCatching { JSONObject(it) }.getOrNull() }
                    ?: return false
                if (stored.optString("vaultUri") != vaultUri ||
                    stored.optString("ruleId") != ruleId ||
                    stored.optInt("hour", -1) != hour ||
                    stored.optInt("minute", -1) != minute
                ) return false
                val oldTarget = stored.optString("targetUri")
                if (oldTarget.isNotBlank() && oldTarget != targetUri) return false

                val migrated = JSONObject(stored.toString())
                    .put("vaultName", input.getString(ScheduledVaultSyncWorker.KEY_VAULT_NAME) ?: "Vault")
                    .put("targetUri", targetUri)
                    .put("targetSubPath", input.getString(ScheduledVaultSyncWorker.KEY_TARGET_SUB_PATH) ?: "")
                    .put("targetName", input.getString(ScheduledVaultSyncWorker.KEY_TARGET_NAME) ?: "Folder")
                return prefs.edit().putString(key, migrated.toString()).commit()
            }
        }

        fun cancelLegacyWorkForInput(context: Context, input: Data) {
            val vaultUri = input.getString(ScheduledVaultSyncWorker.KEY_VAULT_URI) ?: return
            val ruleId = input.getString(ScheduledVaultSyncWorker.KEY_RULE_ID) ?: return
            cancelLegacyWork(context.applicationContext, vaultUri, ruleId)
        }

        private fun scheduleAlarm(context: Context, input: Data, scheduledForMillis: Long) {
            val vaultUri = input.getString(ScheduledVaultSyncWorker.KEY_VAULT_URI)
                ?: error("vaultUri is required")
            val ruleId = input.getString(ScheduledVaultSyncWorker.KEY_RULE_ID)
                ?: error("ruleId is required")
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            check(canScheduleExactAlarms(context)) { "Exact-alarm access is not granted" }
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                scheduledForMillis,
                alarmPendingIntent(context, vaultUri, ruleId, scheduledForMillis),
            )
        }

        private fun cancelAlarm(context: Context, vaultUri: String, ruleId: String) {
            if (vaultUri.isBlank() || ruleId.isBlank()) return
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pending = alarmPendingIntent(context, vaultUri, ruleId, 0L)
            manager.cancel(pending)
            pending.cancel()
        }

        private fun alarmPendingIntent(
            context: Context,
            vaultUri: String,
            ruleId: String,
            scheduledForMillis: Long,
        ): PendingIntent {
            val identity = digest("$vaultUri\n$ruleId")
            val intent = Intent(context, ScheduledVaultSyncAlarmReceiver::class.java).apply {
                action = ACTION_DAILY_SYNC
                data = Uri.parse("vaultexplorer://scheduled-sync/$identity")
                putExtra(EXTRA_VAULT_URI, vaultUri)
                putExtra(EXTRA_RULE_ID, ruleId)
                putExtra(EXTRA_SCHEDULED_FOR, scheduledForMillis)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getBroadcast(context, identity.take(7).toInt(16), intent, flags)
        }

        private fun cancelLegacyWork(context: Context, vaultUri: String, ruleId: String) {
            val manager = WorkManager.getInstance(context)
            manager.cancelUniqueWork(baseWorkName(vaultUri, ruleId))
            manager.cancelAllWorkByTag(ruleTag(vaultUri, ruleId))
        }

        private fun workData(
            vaultUri: String,
            vaultName: String,
            ruleId: String,
            targetUri: String,
            targetSubPath: String,
            targetName: String,
            hour: Int,
            minute: Int,
            scheduledForMillis: Long,
        ): Data = Data.Builder()
            .putString(ScheduledVaultSyncWorker.KEY_VAULT_URI, vaultUri)
            .putString(ScheduledVaultSyncWorker.KEY_VAULT_NAME, vaultName)
            .putString(ScheduledVaultSyncWorker.KEY_RULE_ID, ruleId)
            .putString(ScheduledVaultSyncWorker.KEY_TARGET_URI, targetUri)
            .putString(ScheduledVaultSyncWorker.KEY_TARGET_SUB_PATH, targetSubPath)
            .putString(ScheduledVaultSyncWorker.KEY_TARGET_NAME, targetName)
            .putInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_HOUR, hour)
            .putInt(ScheduledVaultSyncWorker.KEY_SCHEDULED_MINUTE, minute)
            .putLong(ScheduledVaultSyncWorker.KEY_SCHEDULED_FOR, scheduledForMillis)
            .build()

        private fun nextOccurrence(
            hour: Int,
            minute: Int,
            now: Calendar,
            previousOccurrenceMillis: Long = 0L,
        ): Calendar {
            val next = Calendar.getInstance().apply {
                timeInMillis = if (previousOccurrenceMillis > 0L) previousOccurrenceMillis else now.timeInMillis
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (previousOccurrenceMillis > 0L) next.add(Calendar.DAY_OF_YEAR, 1)
            while (next.timeInMillis <= now.timeInMillis) next.add(Calendar.DAY_OF_YEAR, 1)
            return next
        }

        private fun baseWorkName(vaultUri: String, ruleId: String): String =
            "scheduled-vault-sync-${digest("$vaultUri\n$ruleId") }"

        private fun configKey(vaultUri: String, ruleId: String): String =
            "$CONFIG_PREFIX${digest("$vaultUri\n$ruleId") }"

        private fun vaultTag(vaultUri: String): String = "$VAULT_TAG_PREFIX${digest(vaultUri)}"

        private fun ruleTag(vaultUri: String, ruleId: String): String =
            "$RULE_TAG_PREFIX${digest("$vaultUri\n$ruleId") }"

        private fun digest(value: String): String {
            val bytes = MessageDigest.getInstance("SHA-256")
                .digest(value.toByteArray(Charsets.UTF_8))
            return bytes.take(12).joinToString("") { "%02x".format(it) }
        }

        private fun isValidTime(hour: Int, minute: Int): Boolean = hour in 0..23 && minute in 0..59
    }

    fun handleCanScheduleExactAlarms(result: MethodChannel.Result) {
        result.success(canScheduleExactAlarms(appContext))
    }

    fun handleRequestExactAlarmAccess(result: MethodChannel.Result) {
        result.success(requestExactAlarmAccess(appContext))
    }

    fun handleSchedule(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") == true
        val vaultUri = call.argument<String>("vaultUri")
        val ruleId = call.argument<String>("ruleId")
        if (vaultUri.isNullOrBlank() || ruleId.isNullOrBlank()) {
            result.error("INVALID_ARGS", "vaultUri and ruleId are required", null)
            return
        }

        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val key = configKey(vaultUri, ruleId)
        if (!enabled) {
            synchronized(scheduleLock) { prefs.edit().remove(key).commit() }
            cancelAlarm(appContext, vaultUri, ruleId)
            cancelLegacyWork(appContext, vaultUri, ruleId)
            result.success(true)
            return
        }

        if (!canScheduleExactAlarms(appContext) ||
            !AutomationSettings.canImportExport(appContext, vaultUri) ||
            AutomationSettings.getStoredPassword(appContext, vaultUri).isNullOrEmpty()
        ) {
            result.success(false)
            return
        }

        if (!androidx.core.app.NotificationManagerCompat.from(appContext).areNotificationsEnabled()) {
            result.success(false)
            return
        }

        val targetUri = call.argument<String>("targetUri")
        val targetSubPath = call.argument<String>("targetSubPath") ?: ""
        val targetName = call.argument<String>("targetDisplayName") ?: "Folder"
        val vaultName = call.argument<String>("vaultDisplayName") ?: "Vault"
        val hour = call.argument<Int>("scheduledHour") ?: 3
        val minute = call.argument<Int>("scheduledMinute") ?: 0
        if (targetUri.isNullOrBlank()) {
            result.error("INVALID_ARGS", "targetUri is required", null)
            return
        }
        if (!isValidTime(hour, minute)) {
            result.error("INVALID_ARGS", "scheduledHour or scheduledMinute is invalid", null)
            return
        }

        val config = JSONObject()
            .put("vaultUri", vaultUri)
            .put("ruleId", ruleId)
            .put("hour", hour)
            .put("minute", minute)
            .put("vaultName", vaultName)
            .put("targetUri", targetUri)
            .put("targetSubPath", targetSubPath)
            .put("targetName", targetName)
        val persisted = synchronized(scheduleLock) {
            prefs.edit().putString(key, config.toString()).commit()
        }
        if (!persisted) {
            result.success(false)
            return
        }

        val selectedTime = nextOccurrence(hour, minute, Calendar.getInstance())
        val input = workData(
            vaultUri,
            vaultName,
            ruleId,
            targetUri,
            targetSubPath,
            targetName,
            hour,
            minute,
            selectedTime.timeInMillis,
        )
        runCatching {
            cancelAlarm(appContext, vaultUri, ruleId)
            cancelLegacyWork(appContext, vaultUri, ruleId)
            scheduleAlarm(appContext, input, selectedTime.timeInMillis)
        }.onSuccess {
            result.success(true)
        }.onFailure {
            synchronized(scheduleLock) { prefs.edit().remove(key).commit() }
            result.success(false)
        }
    }
}
