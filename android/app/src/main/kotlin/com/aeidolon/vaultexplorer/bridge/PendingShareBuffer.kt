package com.aeidolon.vaultexplorer.bridge

import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** One shared file: the metadata Dart may see right away, plus the content:// [uri] that stays native-side. */
data class ShareItem(
    val uri: Uri,
    val displayName: String,
    val sizeBytes: Long,
    val mimeType: String?,
)

/**
 * The buffer behind [IncomingShareBridge] and [LocalIncomingShareBridge] (see those for the
 * cold-start/warm-start delivery and peek/take contract). Each bridge owns its own instance, so the vault
 * and decoy identities still share no state.
 *
 * Holds only the most recent request: a second share before the first was acted on means the person
 * changed their mind, not that they want both queued.
 *
 * @param pushMethod the Dart method [deliver] invokes on [channel] when it is already wired up.
 */
internal class PendingShareBuffer(private val pushMethod: String) {
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

    /** Buffers [items] (cold start) and, if Dart is already listening, pushes their metadata (warm start). */
    fun deliver(items: List<ShareItem>) {
        if (items.isEmpty()) return
        pending = items
        val ch = channel ?: return
        val payload = metadataOf(items)
        mainHandler.post { ch.invokeMethod(pushMethod, payload) }
    }

    /** The buffered metadata as the `{"items": [...]}` wire map, without clearing it. */
    fun peekMetadata(): Map<String, Any?>? = pending?.let(::metadataOf)

    /** Like [peekMetadata], but clears the buffer. */
    fun takeMetadata(): Map<String, Any?>? = takeItems()?.let(::metadataOf)

    /** The buffered items themselves (never sent to Dart), clearing the buffer. */
    fun takeItems(): List<ShareItem>? {
        val items = pending ?: return null
        pending = null
        return items
    }

    fun takeUris(): List<Uri>? = takeItems()?.map { it.uri }

    fun clear() {
        pending = null
    }
}
