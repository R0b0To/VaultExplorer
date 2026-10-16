package com.aeidolon.vaultexplorer.automation

import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.util.UUID

/** WorkManager persists its input in an app database, so secrets stay in the
 * AndroidKeyStore-encrypted automation preferences and the worker receives
 * only a random one-use reference. */
internal object VaultAutomationActionPayload {
    private val stringKeys = setOf(
        VaultAutomationReceiver.EXTRA_API_TOKEN,
        VaultAutomationReceiver.EXTRA_VAULT_URI,
        VaultAutomationReceiver.EXTRA_PASSWORD,
        VaultAutomationReceiver.EXTRA_KEYFILE_URIS,
        VaultAutomationReceiver.EXTRA_SOURCE_PATH,
        VaultAutomationReceiver.EXTRA_DEST_PATH,
        VaultAutomationReceiver.EXTRA_VAULT_PATH,
        VaultAutomationReceiver.EXTRA_PATTERN,
        VaultAutomationReceiver.EXTRA_EXCLUDE_PATTERN,
        VaultAutomationReceiver.EXTRA_CAMERA_FACING,
        VaultAutomationReceiver.EXTRA_VIDEO_QUALITY,
        VaultAutomationReceiver.EXTRA_AUDIO_QUALITY,
    )
    private val intKeys = setOf(
        VaultAutomationReceiver.EXTRA_TIER,
        VaultAutomationReceiver.EXTRA_PIM,
        VaultAutomationReceiver.EXTRA_CIPHER_ID,
        VaultAutomationReceiver.EXTRA_HASH_ID,
    )
    private val booleanKeys = setOf(
        VaultAutomationReceiver.EXTRA_READ_ONLY,
        VaultAutomationReceiver.EXTRA_DELETE_SOURCE,
        VaultAutomationReceiver.EXTRA_RECURSIVE,
        VaultAutomationReceiver.EXTRA_STREAM_MODE,
        VaultAutomationReceiver.EXTRA_RECORD_AUDIO,
    )

    fun persist(context: Context, intent: Intent): String? {
        val id = UUID.randomUUID().toString()
        val payload = JSONObject().put("action", intent.action)
        val extras = intent.extras
        for (key in stringKeys) {
            val value = extras?.get(key) as? String ?: continue
            payload.put(key, value)
        }
        for (key in intKeys) {
            val value = extras?.get(key) as? Int ?: continue
            payload.put(key, value)
        }
        for (key in booleanKeys) {
            val value = extras?.get(key) as? Boolean ?: continue
            payload.put(key, value)
        }
        return if (AutomationSettings.storePendingActionPayload(context, id, payload.toString())) id else null
    }

    fun consume(context: Context, id: String): Intent? {
        val raw = AutomationSettings.consumePendingActionPayload(context, id) ?: return null
        return try {
            val payload = JSONObject(raw)
            val action = payload.optString("action").takeIf { it.isNotEmpty() } ?: return null
            Intent(action).apply {
                for (key in stringKeys) if (payload.has(key)) putExtra(key, payload.getString(key))
                for (key in intKeys) if (payload.has(key)) putExtra(key, payload.getInt(key))
                for (key in booleanKeys) if (payload.has(key)) putExtra(key, payload.getBoolean(key))
            }
        } catch (_: Exception) {
            null
        }
    }

    fun clear(context: Context, id: String) = AutomationSettings.clearPendingActionPayload(context, id)
}
