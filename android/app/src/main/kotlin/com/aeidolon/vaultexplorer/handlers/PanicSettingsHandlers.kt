package com.aeidolon.vaultexplorer.handlers

import android.content.Context
import com.aeidolon.vaultexplorer.panic.PanicKitSettings
import com.aeidolon.vaultexplorer.panic.PanicManager
import com.aeidolon.vaultexplorer.panic.PanicSettings
import com.aeidolon.vaultexplorer.panic.PanicTier
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService

class PanicSettingsHandlers(
    private val context: Context,
    private val ioExecutor: ExecutorService,
) {
    fun handleGetPanicSettings(call: MethodCall, result: MethodChannel.Result) {
        result.success(
            mapOf(
                "configuredTier" to PanicSettings.getConfiguredTier(context).level,
                "quickTileEnabled" to PanicSettings.isQuickTileEnabled(context),
            )
        )
    }

    fun handleSetPanicTier(call: MethodCall, result: MethodChannel.Result) {
        val level = call.argument<Int>("level")
        val tier = level?.let { PanicTier.fromLevel(it) }
        if (tier == null) {
            result.error("INVALID_ARGS", "Valid level (1, 2, 3) required", null)
            return
        }
        PanicSettings.setConfiguredTier(context, tier)
        result.success(true)
    }

    fun handleSetQuickTileEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        PanicSettings.setQuickTileEnabled(context, enabled)
        result.success(true)
    }

    fun handleGetPanicKitStatus(call: MethodCall, result: MethodChannel.Result) {
        result.success(
            mapOf(
                "responderEnabled" to PanicKitSettings.isResponderEnabled(context),
                "pairingEnforcementEnabled" to PanicKitSettings.isPairingEnforcementEnabled(context),
                "trustedPackage" to PanicKitSettings.getTrustedPackage(context),
                "hasTrustedCert" to (PanicKitSettings.getTrustedCertSha256(context) != null),
            )
        )
    }

    fun handleSetPanicKitEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        PanicKitSettings.setResponderEnabled(context, enabled)
        result.success(true)
    }

    fun handleSetPanicKitPairingEnforcement(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: true
        PanicKitSettings.setPairingEnforcementEnabled(context, enabled)
        result.success(true)
    }

    fun handleUnpairPanicKit(call: MethodCall, result: MethodChannel.Result) {
        PanicKitSettings.clearTrustedTrigger(context)
        result.success(true)
    }

    fun handleTriggerPanic(call: MethodCall, result: MethodChannel.Result) {
        val level = call.argument<Int>("level")
        val tier = level?.let { PanicTier.fromLevel(it) } ?: PanicSettings.getConfiguredTier(context)
        ioExecutor.execute {
            val outcome = PanicManager.execute(context, tier, source = "in_app")
            result.success(
                mapOf(
                    "success" to outcome.success,
                    "containersLocked" to outcome.containersLocked,
                    "keystoreAliasesPurged" to outcome.keystoreAliasesPurged,
                    "filesWiped" to outcome.filesWiped,
                )
            )
        }
    }
}
