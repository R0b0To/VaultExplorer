package com.aeidolon.vaultexplorer

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Carries "please open this PDF" requests that arrived via the decoy
 * identity's Open-With/Share intent-filters (docs/architecture.md §7.3)
 * from [MainActivity.onCreate]/[MainActivity.onNewIntent] to Dart.
 *
 * Two delivery paths, both needed:
 *
 * * **Cold start** (app not running yet): the request arrives in
 *   `onCreate`, before Dart's isolate has even run `main()`, let alone
 *   registered anything to receive a push -- an `invokeMethod` call sent
 *   this early would simply be dropped. [pending] buffers it instead;
 *   [DisguiseChannelMethods.CONSUME_PENDING_OPEN_REQUEST]
 *   (`DisguiseModeHandlers.handleConsumePendingOpenRequest`) is the *pull*
 *   Dart uses once it's actually ready (`_DisguiseModeGate._resolveMode`).
 * * **Warm start** (`MainActivity` already running, `singleTop`): the
 *   request arrives via `onNewIntent` while Dart is definitely already
 *   alive and listening, so [deliver] also pushes it immediately as an
 *   `externalOpenRequest` method call on the same `disguise_channel`.
 *
 * [pending] always holds only the most recent request -- if a second
 * Open-With arrives before the first was consumed, "most recent wins" is
 * the right behavior (the user asked to open a different file), not a
 * queue of stale ones.
 *
 * There's no separate check anywhere for "are we actually in Discrete
 * Mode" before acting on one of these: `VaultLauncherAlias` deliberately
 * declares neither the VIEW nor the SEND intent-filter (see
 * AndroidManifest.xml), so Android itself only ever resolves an external
 * PDF-open request to this app while `PDFViewerAlias` -- i.e. Discrete
 * Mode -- is the currently-enabled component. If this bridge fires at all,
 * that precondition is already guaranteed.
 */
object ExternalOpenBridge {
    @Volatile
    var channel: MethodChannel? = null

    @Volatile
    private var pending: Map<String, Any?>? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    @JvmStatic
    fun deliver(uri: String, displayName: String) {
        val request = mapOf("uri" to uri, "displayName" to displayName)
        pending = request
        val ch = channel ?: return
        mainHandler.post { ch.invokeMethod("externalOpenRequest", request) }
    }

    /** Returns and clears whatever request is currently buffered, if any. */
    @JvmStatic
    fun consumePending(): Map<String, Any?>? {
        val result = pending
        pending = null
        return result
    }
}
