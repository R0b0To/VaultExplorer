package com.aeidolon.vaultexplorer.bridge

import android.net.Uri
import io.flutter.plugin.common.MethodChannel

/**
 * Decoy-identity counterpart to [IncomingShareBridge]: carries "the person
 * shared N file(s) in while Mask Mode's decoy identity was the one active"
 * from [com.aeidolon.vaultexplorer.handlers.ShareIntentHandlers
 * .handleIncomingIntent] to Dart's decoy file manager
 * (lib/features/decoy/local/decoy_share_import_flow.dart) -- kept as a
 * fully separate object, on its own channel
 * (`disguise_channel`; never the
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
 * delivery too: [deliver] always buffers into the pending buffer first (covers
 * cold start, where Dart isn't listening yet) and pushes only if
 * [channel] is already wired up (covers warm start, where the decoy
 * screen is already on screen and listening).
 *
 * the pending buffer always holds only the most recent request -- "most recent
 * wins" is the right behavior for the same reason [IncomingShareBridge]
 * picks it: a second share almost certainly means the person changed
 * their mind about what to send in, not that they want both queued.
 */
object LocalIncomingShareBridge {
    private val buffer = PendingShareBuffer("onLocalIncomingShareRequest")

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

    /** Consumes and returns the metadata map, clearing the buffer. */
    @JvmStatic
    fun takePending(): Map<String, Any?>? = buffer.takeMetadata()

    /**
     * Internal, non-wire counterpart of [peekPending]: returns and consumes the raw [ShareItem] list, for
     * [com.aeidolon.vaultexplorer.handlers.ShareIntentHandlers.handleHandoffLocalShareToVault] to re-deliver
     * through [IncomingShareBridge]. Never exposed to Dart directly.
     */
    @JvmStatic
    fun takePendingRaw(): List<ShareItem>? = buffer.takeItems()

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
