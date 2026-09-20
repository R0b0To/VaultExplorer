package com.aeidolon.vaultexplorer.handlers

import android.content.Context
import com.aeidolon.vaultexplorer.bridge.QuickCaptureBridge
import com.aeidolon.vaultexplorer.quickcapture.QuickCaptureSettings
import com.aeidolon.vaultexplorer.quickcapture.QuickCaptureShortcuts
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart-facing settings + pending-request surface for Quick Capture
 * (see quickcapture/CaptureTileService.kt, quickcapture/QuickCaptureShortcuts.kt,
 * bridge/QuickCaptureBridge.kt). Mirrors PanicSettingsHandlers' shape.
 */
class QuickCaptureSettingsHandlers(private val context: Context) {

    fun handleCheckPendingQuickCaptureRequest(call: MethodCall, result: MethodChannel.Result) {
        result.success(QuickCaptureBridge.takePending())
    }

    fun handleGetQuickCaptureSettings(call: MethodCall, result: MethodChannel.Result) {
        result.success(
            mapOf(
                "tileEnabled" to QuickCaptureSettings.isTileEnabled(context),
            )
        )
    }

    fun handleSetQuickCaptureTileEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        QuickCaptureSettings.setTileEnabled(context, enabled)
        QuickCaptureShortcuts.refreshDynamicShortcut(context)
        result.success(true)
    }

    fun handleRequestPinQuickCaptureShortcut(call: MethodCall, result: MethodChannel.Result) {
        result.success(QuickCaptureShortcuts.requestPinShortcut(context))
    }
}
