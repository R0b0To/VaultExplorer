package com.aeidolon.vaultexplorer.bridge

import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Carries "the user shared N file(s) into VaultExplorer" requests that
 * arrived via [com.aeidolon.vaultexplorer.handlers.ShareIntentHandlers]
 * (ACTION_SEND/ACTION_SEND_MULTIPLE, routed through the opt-in
 * `ShareTargetAlias` -- see AndroidManifest.xml and
 * docs/architecture.md, "Android Share Sheet Integration") from
 * [com.aeidolon.vaultexplorer.MainActivity.onCreate]/`onNewIntent` to Dart.
 *
 * Two delivery paths, both needed -- same reasoning as [ExternalOpenBridge],
 * which this mirrors:
 *
 * * **Cold start** (app not running yet): the request arrives in
 *   `onCreate`, before Dart's isolate has even run `main()`, so an
 *   `invokeMethod` sent this early is simply dropped. [pending] buffers it;
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
 * Unlike [ExternalOpenBridge], "consuming" this request is not a single
 * step: the metadata (name/size/mime) is free to cross into Dart
 * immediately (see [peekPending]'s doc comment), but the underlying
 * content:// [Uri]s stay buffered in [pending] until the person actually
 * finishes picking a destination vault + folder -- which can take several
 * screens (an unlock prompt, a vault switcher, a folder browser) -- at
 * which point [takePendingUris] hands them to
 * `ImportExportHandlers.handlePrepareShareImport` and clears the buffer.
 * If the person backs out of that flow instead,
 * `ShareIntentHandlers.handleCancelPendingShareRequest` clears it via
 * [clear] so it doesn't linger and resurface later.
 *
 * [pending] always holds only the most recent request -- if a second Share
 * arrives before the first was acted on, "most recent wins" is correct
 * (the person asked to import something else), not a queue of stale ones.
 */
object IncomingShareBridge {
    data class ShareItem(
        val uri: Uri,
        val displayName: String,
        val sizeBytes: Long,
        val mimeType: String?,
    )

    @Volatile
    var channel: MethodChannel? = null

    @Volatile
    private var pending: List<ShareItem>? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private fun metadataOf(items: List<ShareItem>): Map<String, Any?> = mapOf(
        "items" to items.map {
            mapOf(
                "uri" to it.uri.toString(),
                "displayName" to it.displayName,
                "sizeBytes" to it.sizeBytes,
                "mimeType" to it.mimeType,
            )
        },
    )

    @JvmStatic
    fun deliver(items: List<ShareItem>) {
        if (items.isEmpty()) return
        pending = items
        val ch = channel ?: return
        val payload = metadataOf(items)
        mainHandler.post { ch.invokeMethod("onIncomingShareRequest", payload) }
    }

    /**
     * Read-only snapshot of whatever is currently buffered, as the
     * `{"items": [...]}` shape `VaultFileIoApi.checkPendingShareRequest`
     * (via the shared `incomingShareItemFromWire` parser) expects -- does
     * *not* clear [pending], since the metadata can be shown (this is "the
     * temporary, unauthenticated pending queue" the feature spec's Step 3
     * describes -- filenames/sizes from the *other* app, not anything
     * about this app's vaults) well before the person has finished picking
     * a destination.
     */
    @JvmStatic
    fun peekPending(): Map<String, Any?>? {
        val items = pending ?: return null
        return metadataOf(items)
    }

    /**
     * Hands the buffered URIs to the caller (see
     * `ImportExportHandlers.handlePrepareShareImport`) and clears
     * [pending] -- called once a destination has actually been chosen, so
     * a second, unrelated share arriving afterward doesn't inherit the
     * URIs of the first.
     */
    @JvmStatic
    fun takePendingUris(): List<Uri>? {
        val items = pending ?: return null
        pending = null
        return items.map { it.uri }
    }

    /** Drops whatever is buffered without importing it -- see class doc. */
    @JvmStatic
    fun clear() {
        pending = null
    }
}
