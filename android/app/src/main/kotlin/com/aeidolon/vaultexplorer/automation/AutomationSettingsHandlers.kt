package com.aeidolon.vaultexplorer.automation

import android.content.Context
import com.aeidolon.vaultexplorer.container.ContainerLifecycleCore.DirectoryVaultFormat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel-facing wrapper around AutomationSettings, so the Dart
 * settings UI can manage the automation token and each vault's
 * automation tier/format/stored-password without Dart ever touching
 * AutomationSettings' storage directly -- that file is Kotlin-only by
 * design (see its own doc comment). This is the only class that bridges
 * the two; VaultAutomationReceiver reads AutomationSettings directly and
 * has no need to go through here.
 *
 * Deliberately has no handleGetAutomationPassword: the UI only ever needs
 * to know WHETHER a password is stored (see hasStoredPassword in
 * handleGetAutomationVaultConfig's response) so it can show "Set" vs
 * "Change" -- there is no legitimate reason for Dart to read the stored
 * password back out.
 */
class AutomationSettingsHandlers(private val context: Context) {

    fun handleGetAutomationToken(call: MethodCall, result: MethodChannel.Result) {
        result.success(mapOf("token" to AutomationSettings.getOrCreateToken(context)))
    }

    fun handleRegenerateAutomationToken(call: MethodCall, result: MethodChannel.Result) {
        result.success(mapOf("token" to AutomationSettings.regenerateToken(context)))
    }

    fun handleGetAutomationVaultConfig(call: MethodCall, result: MethodChannel.Result) {
        val vaultUri = call.argument<String>("vaultUri")
        if (vaultUri == null) {
            result.error("INVALID_ARGS", "vaultUri is required", null)
            return
        }
        result.success(
            mapOf(
                "tier" to AutomationSettings.getTier(context, vaultUri).name,
                "format" to directoryFormatToWire(AutomationSettings.getFormat(context, vaultUri)),
                "hasStoredPassword" to (AutomationSettings.getStoredPassword(context, vaultUri) != null),
            )
        )
    }

    fun handleSetAutomationTier(call: MethodCall, result: MethodChannel.Result) {
        val vaultUri = call.argument<String>("vaultUri")
        val tierName = call.argument<String>("tier")
        if (vaultUri == null || tierName == null) {
            result.error("INVALID_ARGS", "vaultUri and tier are required", null)
            return
        }
        val tier = try {
            AutomationSettings.AutomationTier.valueOf(tierName)
        } catch (e: Exception) {
            result.error("INVALID_ARGS", "Unknown tier: $tierName", null)
            return
        }
        AutomationSettings.setTier(context, vaultUri, tier, wireFormatToDirectoryFormat(call.argument<String>("format")))
        result.success(true)
    }

    fun handleSetAutomationPassword(call: MethodCall, result: MethodChannel.Result) {
        val vaultUri = call.argument<String>("vaultUri")
        if (vaultUri == null) {
            result.error("INVALID_ARGS", "vaultUri is required", null)
            return
        }
        AutomationSettings.setStoredPassword(context, vaultUri, call.argument<String>("password"))
        result.success(true)
    }

    private fun wireFormatToDirectoryFormat(wire: String?): DirectoryVaultFormat? = when (wire) {
        "cryptomator" -> DirectoryVaultFormat.CRYPTOMATOR
        "gocryptfs" -> DirectoryVaultFormat.GOCRYPTFS
        "cryfs" -> DirectoryVaultFormat.CRYFS
        else -> null
    }

    private fun directoryFormatToWire(format: DirectoryVaultFormat?): String? = format?.wireName
}