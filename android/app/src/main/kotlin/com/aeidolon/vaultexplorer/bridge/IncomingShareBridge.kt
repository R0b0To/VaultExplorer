package com.aeidolon.vaultexplorer.bridge

import android.net.Uri
import io.flutter.plugin.common.MethodChannel

/**
 * Carries "the user shared N file(s) into VaultExplorer" requests that
 * arrived via [com.aeidolon.vaultexplorer.handlers.ShareIntentHandlers]
 * (ACTION_SEND/ACTION_SEND_MULTIPLE, routed through the opt-in
 * `ShareTargetAlias` -- see AndroidManifest.xml and
 * docs/architecture.md, "Android Share Sheet Integration") from
 * [com.aeidolon.vaultexplorer.MainActivity.onCreate]/`onNewIntent` to Dart.
 *
 * Two delivery paths, both needed:
 *
 * * **Cold start** (app not running yet): the request arrives in
 *   `onCreate`, before Dart's isolate has even run `main()`, so an
 *   `invokeMethod` sent this early is simply dropped. the pending buffer buffers it;
 *   `ChannelMethods.CHECK_PENDING_SHARE_REQUEST`
 *   (`VaultFileIoApi.checkPendingShareRequest` on the Dart side) is the
 *   *pull* used once Dart is actually ready and past the app-lock screen
 *   (see `MainShell.initState`).
 * * **Warm start** (`MainActivity` already running, `singleTop`): the
 *   request arrives via `onNewIntent` while Dart is definitely alive, so
 *   [deliver] also pushes it immediately as an `onIncomingShareRequest`
 *   method call on the shared engine channel (dispatched by
 *   `VaultEngineEvents`, like every other native -> Dart push on that
 *   channel).
 *
 * "Consuming" this request is not a single
 * step: the metadata (name/size/mime) is free to cross into Dart
 * immediately (see [peekPending]'s doc comment), but the underlying
 * content:// [Uri]s stay buffered in the pending buffer until the person actually
 * finishes picking a destination vault + folder -- which can take several
 * screens (an unlock prompt, a vault switcher, a folder browser) -- at
 * which point [takePendingUris] hands them to
 * `ImportExportHandlers.handlePrepareShareImport` and clears the buffer.
 * If the person backs out of that flow instead,
 * `ShareIntentHandlers.handleCancelPendingShareRequest` clears it via
 * [clear] so it doesn't linger and resurface later.
 *
 * the pending buffer always holds only the most recent request -- if a second Share
 * arrives before the first was acted on, "most recent wins" is correct
 * (the person asked to import something else), not a queue of stale ones.
 */
object IncomingShareBridge {
    private val buffer = PendingShareBuffer("onIncomingShareRequest")

    var channel: MethodChannel?
        get() = buffer.channel
        set(value) {
            buffer.channel = value
        }

    @JvmStatic
    fun deliver(items: List<ShareItem>) = buffer.deliver(items)

    /**
     * Read-only snapshot of whatever is currently buffered, as the `{"items": [...]}` shape the Dart side
     * expects. Does *not* clear the buffer: the metadata (filenames/sizes from the *other* app, nothing about
     * this app's vaults) can be shown well before the person has finished picking a destination.
     */
    @JvmStatic
    fun peekPending(): Map<String, Any?>? = buffer.peekMetadata()

    /**
     * Hands the buffered URIs to the caller and clears the buffer -- called once a destination has actually
     * been chosen, so a second, unrelated share arriving afterward doesn't inherit the URIs of the first.
     */
    @JvmStatic
    fun takePendingUris(): List<Uri>? = buffer.takeUris()

    /** Drops whatever is buffered without importing it. */
    @JvmStatic
    fun clear() = buffer.clear()
}
