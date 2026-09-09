package com.aeidolon.vaultexplorer.bridge

import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Decoy-identity counterpart to [IncomingShareBridge]: carries "the person
 * shared N file(s) in while Mask Mode's decoy identity was the one active"
 * from [com.aeidolon.vaultexplorer.handlers.ShareIntentHandlers
 * .handleIncomingIntent] to Dart's decoy file manager
 * (lib/features/decoy/local/decoy_share_import_flow.dart) -- kept as a
 * fully separate object, on its own channel
 * (`disguise_channel`, alongside [ExternalOpenBridge]; never the
 * shared engine [channel][IncomingShareBridge] uses), so that nothing
 * here is reachable from -- or even routed through the same plumbing
 * as -- any vault-labeled Dart code before the person has actually
 * unlocked. The decoy's own file manager treats a request delivered
 * here exactly like a real archive/file-manager app would: a folder
 * pick and a plain-storage copy (see
 * LocalFileHandlers.handleImportSharedUrisToLocal), no crypto, no
 * container, no auth prompt.
 *
 * Same two-phase peek/take contract as [IncomingShareBridge]: metadata is
 * visible via [peekPending] as soon as it arrives (just another app's
 * filenames/sizes -- nothing sensitive), the underlying [Uri]s stay
 * buffered until the person finishes picking a destination folder, at
 * which point [LocalFileHandlers.handleImportSharedUrisToLocal] calls
 * [takePendingUris] to actually stream the bytes. Same cold/warm dual
 * delivery too: [deliver] always buffers into [pending] first (covers
 * cold start, where Dart isn't listening yet) and pushes only if
 * [channel] is already wired up (covers warm start, where the decoy
 * screen is already on screen and listening).
 *
 * [pending] always holds only the most recent request -- "most recent
 * wins" is the right behavior for the same reason [IncomingShareBridge]
 * picks it: a second share almost certainly means the person changed
 * their mind about what to send in, not that they want both queued.
 */
object LocalIncomingShareBridge {
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
        mainHandler.post { ch.invokeMethod("onLocalIncomingShareRequest", payload) }
    }

    /** See [IncomingShareBridge.peekPending] -- identical contract. */
    @JvmStatic
    fun peekPending(): Map<String, Any?>? {
        val items = pending ?: return null
        return metadataOf(items)
    }

    /** Consumes and returns the metadata map, clearing pending buffer. */
    @JvmStatic
    fun takePending(): Map<String, Any?>? {
        val items = pending ?: return null
        pending = null
        return metadataOf(items)
    }

    /**
     * Internal, non-wire counterpart of [peekPending] -- returns and
     * consumes the raw [ShareItem] list rather than the Dart-facing
     * metadata map, for [com.aeidolon.vaultexplorer.handlers
     * .ShareIntentHandlers.handleHandoffLocalShareToVault] to reconstruct
     * [IncomingShareBridge.ShareItem]s from. Never exposed to Dart
     * directly.
     */
    @JvmStatic
    fun takePendingRaw(): List<ShareItem>? {
        val items = pending ?: return null
        pending = null
        return items
    }

    /** See [IncomingShareBridge.takePendingUris] -- identical contract. */
    @JvmStatic
    fun takePendingUris(): List<Uri>? {
        val items = pending ?: return null
        pending = null
        return items.map { it.uri }
    }

    /** See [IncomingShareBridge.clear] -- identical contract. */
    @JvmStatic
    fun clear() {
        pending = null
    }
}