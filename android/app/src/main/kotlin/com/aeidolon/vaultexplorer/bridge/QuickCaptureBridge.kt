package com.aeidolon.vaultexplorer.bridge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Carries "open the Quick Capture camera" requests from
 * [com.aeidolon.vaultexplorer.VaultQuickCaptureActivity] (launched by the
 * Quick Settings tile or the pinned home-screen shortcut -- see
 * `quickcapture/CaptureTileService.kt` and
 * `quickcapture/QuickCaptureShortcuts.kt`) to Dart.
 *
 * Mirrors [IncomingShareBridge]'s cold-start/warm-start split, just with
 * no payload to carry: [deliver] both buffers the request (for
 * `ChannelMethods.CHECK_PENDING_QUICK_CAPTURE_REQUEST`, pulled once Dart
 * is ready -- see `MainShell.initState`) and, if Dart's engine is
 * already alive, pushes it immediately as `onQuickCaptureRequested`.
 */
object QuickCaptureBridge {
    @Volatile
    var channel: MethodChannel? = null

    @Volatile
    private var pending: Boolean = false

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun deliver() {
        pending = true
        val ch = channel ?: return
        mainHandler.post { ch.invokeMethod("onQuickCaptureRequested", null) }
    }

    /** Consumes the pending flag, if set -- called once by Dart at
     *  startup so a cold-started request isn't lost to the
     *  invokeMethod-before-Dart-is-listening race. */
    @JvmStatic
    fun takePending(): Boolean {
        val was = pending
        pending = false
        return was
    }

    /** Drops whatever is buffered -- mirrors IncomingShareBridge.clear(),
     *  called from VaultQuickCaptureActivity.onDestroy so a stale request
     *  never resurfaces for a later, unrelated launch of that Activity. */
    @JvmStatic
    fun clear() {
        pending = false
    }
}
