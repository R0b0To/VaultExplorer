package com.aeidolon.vaultexplorer.saf

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Point
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import androidx.exifinterface.media.ExifInterface
import com.aeidolon.vaultexplorer.ImageDecodeGuard
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.VideoThumbnailCoordinator
import com.aeidolon.vaultexplorer.handlers.OpenWithChooser
import com.aeidolon.vaultexplorer.share.StorageFolderShareProvider
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.ConcurrentHashMap

data class SafEntry(
    val name: String,
    val isDir: Boolean,
    val size: Long,
    val lastModified: Long,
    val docId: String,
    val mimeType: String,
) {
    fun toWire(): String = "${if (isDir) "D" else "F"}|$size|$lastModified|$name"
}

/**
 * Changes this app has just made to one folder through a document provider
 * whose own listing cache may lag behind them.
 *
 * RSAF (SFTP/SMB/...) performs a server-side move or copy directly on the
 * backend, bypassing the rclone VFS that answers its folder listings. That VFS
 * keeps serving the old entries until its directory cache expires, so a
 * listing taken right after a successful move still shows the moved item in
 * the source folder and not in the destination. Instead of waiting for (and
 * guessing) the provider's cache lifetime, the app remembers what it changed
 * and applies that to the provider's answer until the provider catches up.
 *
 * Every record drops itself as soon as a provider listing agrees with it, and
 * unconditionally after [PENDING_LISTING_TTL_MS].
 */
internal class PendingListingChanges {
    private val removed = HashMap<String, Long>()
    private val added = HashMap<String, Pair<SafEntry, Long>>()

    // Names in [added] that nothing should wait on the provider for any more:
    // it has answered for them once, or the wait ran out. They keep being
    // injected into listings; only the waiting stops.
    private val settled = HashSet<String>()

    @Synchronized
    fun expectRemoved(name: String, expiresAt: Long) {
        added.remove(name)
        settled.remove(name)
        removed[name] = expiresAt
    }

    @Synchronized
    fun expectAdded(entry: SafEntry, expiresAt: Long) {
        removed.remove(entry.name)
        settled.remove(entry.name)
        added[entry.name] = entry to expiresAt
    }

    /** The app changed [name] again itself; whatever was expected is void. */
    @Synchronized
    fun forget(name: String) {
        removed.remove(name)
        added.remove(name)
        settled.remove(name)
    }

    @Synchronized
    fun isEmpty(): Boolean = removed.isEmpty() && added.isEmpty()

    /** True while [name] is expected to be gone from the folder. */
    @Synchronized
    fun isRemoved(name: String, now: Long): Boolean {
        val expiresAt = removed[name] ?: return false
        return expiresAt > now
    }

    /** The entry this app put into the folder, while that is still expected. */
    @Synchronized
    fun addedEntry(name: String, now: Long): SafEntry? {
        val record = added[name] ?: return null
        return if (record.second > now) record.first else null
    }

    /**
     * True while [name] was put into the folder by this app, the provider has
     * not been seen to know it yet, and nobody has given up waiting for it.
     * The provider can only be asked about such an entry (size, content,
     * children) once it has caught up.
     */
    @Synchronized
    fun awaitingProvider(name: String, now: Long): Boolean {
        val record = added[name] ?: return false
        return record.second > now && name !in settled
    }

    /** The provider answered for [name], or waiting for it any longer is pointless. */
    @Synchronized
    fun stopAwaiting(name: String) {
        if (added.containsKey(name)) settled.add(name)
    }

    /**
     * Waiting for one entry timed out, so the provider is not catching up for
     * this folder at all: stop every other waiter here too rather than make
     * each of them sit out the full wait in turn.
     */
    @Synchronized
    fun stopAwaitingAll() {
        settled.addAll(added.keys)
    }

    /** Names currently tracked, for diagnostics only. */
    @Synchronized
    fun describe(): String = "removed=${removed.size} added=${added.size}"

    /** [listing] as the provider reported it, corrected for what is still pending. */
    @Synchronized
    fun reconcile(listing: List<SafEntry>, now: Long): List<SafEntry> {
        removed.values.removeAll { it <= now }
        added.values.removeAll { it.second <= now }
        settled.retainAll(added.keys)
        if (removed.isEmpty() && added.isEmpty()) return listing

        val names = HashSet<String>(listing.size * 2)
        for (entry in listing) names.add(entry.name)
        // The provider has caught up with these: stop tracking them.
        removed.keys.removeAll { it !in names }
        added.keys.removeAll { it in names }
        settled.retainAll(added.keys)
        if (removed.isEmpty() && added.isEmpty()) return listing

        val out = ArrayList<SafEntry>(listing.size + added.size)
        for (entry in listing) {
            if (!removed.containsKey(entry.name)) out.add(entry)
        }
        for ((entry, _) in added.values) out.add(entry)
        return out
    }
}

/**
 * High-performance SAF (Storage Access Framework) engine modeled after MaterialFiles'
 * DocumentResolver and DocumentFileSystemProvider.
 *
 * Provides:
 * - Thread-safe document ID resolution with O(1) path caching
 * - Fast single-pass cursor directory listings
 * - ExternalStorageProvider direct document-ID optimizations and Android/data / Android/obb hacks
 * - Seekable FileChannel random-access chunk reads and writes
 * - Recursive directory deletion
 * - Efficient thumbnail generation for both images and videos
 * - Direct intent-based external app opening and sharing
 * - Auto-discovery of mounted storage volumes (Internal, SD Card, USB OTG)
 */
class SafStorageManager(private val context: Context) {

    companion object {
        private const val TAG = "SafStorageManager"
        private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
        private const val DOCUMENT_ID_PRIMARY = "primary"
        private const val DOCUMENT_ID_PRIMARY_ANDROID = "primary:Android"
        private const val DOCUMENT_ID_PRIMARY_ANDROID_DATA = "primary:Android/data"
        private const val DOCUMENT_ID_PRIMARY_ANDROID_OBB = "primary:Android/obb"

        // Upper bound for how long a provider's stale folder listing is
        // corrected from what this app knows it changed (see
        // PendingListingChanges). It normally ends sooner: the first listing
        // that agrees with the change ends it.
        private const val PENDING_LISTING_TTL_MS = 20_000L

        // A file or folder this app has just moved/copied into a provider may
        // not exist for that provider yet (see PendingListingChanges): asking
        // it for the size/content/children fails until its cache catches up.
        // Such an access waits for the provider, up to this long, polling.
        private const val PROVIDER_CATCHUP_MAX_WAIT_MS = 12_000L
        private const val PROVIDER_CATCHUP_POLL_MS = 250L

        // Greppable prefix for the diagnostics of this mechanism.
        private const val PENDING_TAG = "[pending]"

        private val PROJECTION_CHILDREN = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS,
        )

        private val PROJECTION_DOCUMENT = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
    }

    // Cache: "$treeUri|$cleanPath" -> documentId
    private val pathDocumentIdCache = ConcurrentHashMap<String, String>()

    // Cache: "$treeUri|$cleanPath" -> List<SafEntry>
    private val dirListingCache = ConcurrentHashMap<String, List<SafEntry>>()

    // Cache: "$treeUri|$cleanFolderPath" -> changes made there that the
    // provider's own listing may not reflect yet.
    private val pendingListingChanges = ConcurrentHashMap<String, PendingListingChanges>()

    private fun nowMs(): Long = System.nanoTime() / 1_000_000L

    /** Local device storage lists straight from the file system: never stale. */
    private fun providerListingMayLag(treeUri: Uri): Boolean =
        treeUri.authority != EXTERNAL_STORAGE_AUTHORITY

    private fun withPending(
        treeUri: Uri,
        folderPath: String,
        change: (PendingListingChanges) -> Unit,
    ) {
        val key = cacheKey(treeUri, normalizePath(folderPath))
        pendingListingChanges.compute(key) { _, existing ->
            (existing ?: PendingListingChanges()).also(change)
        }
        // Whatever listing the app cached for this folder predates the change.
        dirListingCache.remove(key)
    }

    /**
     * This app has just created or renamed something to [cleanPath]: whatever
     * it expected about that name (typically "moved away") no longer applies.
     */
    private fun forgetPendingFor(treeUri: Uri, cleanPath: String) {
        if (pendingListingChanges.isEmpty()) return
        val parent = if (cleanPath.contains('/')) cleanPath.substringBeforeLast('/') else ""
        pendingListingChanges[cacheKey(treeUri, parent)]?.forget(cleanPath.substringAfterLast('/'))
    }

    private fun hasPendingChanges(treeUri: Uri, cleanPath: String): Boolean =
        pendingListingChanges[cacheKey(treeUri, cleanPath)]?.isEmpty() == false

    /**
     * True when this app has moved [cleanPath], or one of its ancestors, away
     * and the provider may still claim it is there.
     */
    private fun isPendingRemovedAlong(treeUri: Uri, cleanPath: String): Boolean {
        if (pendingListingChanges.isEmpty()) return false
        val now = nowMs()
        var parent = ""
        for (segment in cleanPath.split('/')) {
            if (segment.isEmpty()) continue
            val pending = pendingListingChanges[cacheKey(treeUri, parent)]
            if (pending != null && pending.isRemoved(segment, now)) return true
            parent = if (parent.isEmpty()) segment else "$parent/$segment"
        }
        return false
    }

    private fun isMainThread(): Boolean =
        android.os.Looper.myLooper() == android.os.Looper.getMainLooper()

    private fun waitForProvider(
        pending: PendingListingChanges,
        name: String,
        entryUri: Uri,
        where: String,
    ) {
        val startedAt = nowMs()
        var polls = 0
        while (true) {
            polls++
            if (documentExists(entryUri)) {
                pending.stopAwaiting(name)
                VeLog.i(TAG) {
                    "$PENDING_TAG provider knows '$where' after ${nowMs() - startedAt}ms ($polls polls)"
                }
                return
            }
            val now = nowMs()
            if (!pending.awaitingProvider(name, now)) {
                // Another thread settled it, or the expectation ran out.
                return
            }
            if (now - startedAt >= PROVIDER_CATCHUP_MAX_WAIT_MS) {
                pending.stopAwaitingAll()
                VeLog.w(TAG) {
                    "$PENDING_TAG gave up waiting for provider on '$where' after ${now - startedAt}ms ($polls polls)"
                }
                return
            }
            try {
                Thread.sleep(PROVIDER_CATCHUP_POLL_MS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
        }
    }

    /**
     * Blocks (bounded) until the provider can answer for every entry along
     * [cleanPath] that this app has just moved or copied in.
     *
     * Right after such an operation the provider's listing cache does not know
     * the new entry, so a size/read/thumbnail/list request for it fails
     * (zero size, no content) even though the entry is listed to the user from
     * the pending changes. Failing fast here is what left placeholders that
     * never loaded; waiting makes the first attempt succeed.
     */
    private fun awaitProviderCatchUp(treeUri: Uri, cleanPath: String) {
        if (cleanPath.isEmpty() || pendingListingChanges.isEmpty()) return
        // Never stall the UI thread; its callers retry or fail as before.
        if (isMainThread()) return
        var parent = ""
        for (segment in cleanPath.split('/')) {
            if (segment.isEmpty()) continue
            val here = if (parent.isEmpty()) segment else "$parent/$segment"
            val pending = pendingListingChanges[cacheKey(treeUri, parent)]
            val now = nowMs()
            if (pending != null && pending.awaitingProvider(segment, now)) {
                val entry = pending.addedEntry(segment, now)
                if (entry == null || entry.docId.isEmpty()) {
                    pending.stopAwaiting(segment)
                } else {
                    val entryUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, entry.docId)
                    waitForProvider(pending, segment, entryUri, here)
                }
            }
            parent = here
        }
    }

    /**
     * Snapshot of one document's metadata, taken before an operation that
     * leaves it unreadable at its old location. Null when it cannot be read.
     */
    private fun snapshotEntry(docUri: Uri, asName: String): SafEntry? = try {
        context.contentResolver.query(docUri, PROJECTION_DOCUMENT, null, null, null)?.use { c ->
            if (!c.moveToFirst()) return@use null
            val idIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val mimeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val mime = if (mimeIdx >= 0) c.getString(mimeIdx) ?: "" else ""
            val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
            SafEntry(
                name = asName,
                isDir = isDir,
                size = if (isDir || sizeIdx < 0 || c.isNull(sizeIdx)) 0L else c.getLong(sizeIdx),
                lastModified = if (modIdx >= 0 && !c.isNull(modIdx)) c.getLong(modIdx) / 1000L else 0L,
                docId = if (idIdx >= 0) c.getString(idIdx) ?: "" else "",
                mimeType = mime,
            )
        }
    } catch (_: Exception) {
        null
    }

    private fun reconcileWithPendingChanges(
        treeUri: Uri,
        cleanPath: String,
        listing: List<SafEntry>,
    ): List<SafEntry> {
        val key = cacheKey(treeUri, cleanPath)
        val pending = pendingListingChanges[key] ?: return listing
        val reconciled = pending.reconcile(listing, nowMs())
        var finished = false
        pendingListingChanges.computeIfPresent(key) { _, p ->
            if (p.isEmpty()) {
                finished = true
                null
            } else {
                p
            }
        }
        // Nothing is cached for a folder while changes are pending for it; if
        // a racing query cached a pre-change listing anyway, it must not
        // outlive the pending record that was masking it.
        if (finished) dirListingCache.remove(key)
        VeLog.i(TAG) {
            "$PENDING_TAG reconcile '$cleanPath': provider=${listing.size} shown=${reconciled.size} " +
                "finished=$finished (${pending.describe()})"
        }
        return reconciled
    }

    /** Drops every cached id/listing at or below [cleanPath] (its paths no longer exist). */
    private fun invalidateSubtree(treeUri: Uri, cleanPath: String) {
        val base = cacheKey(treeUri, cleanPath)
        val childPrefix = "$base/"
        pathDocumentIdCache.keys.removeIf { it == base || it.startsWith(childPrefix) }
        dirListingCache.keys.removeIf { it == base || it.startsWith(childPrefix) }
        pendingListingChanges.keys.removeIf { it == base || it.startsWith(childPrefix) }
    }

    private fun normalizePath(path: String): String =
        path.trim().trim('/').replace('\\', '/')

    private fun cacheKey(treeUri: Uri, cleanPath: String): String =
        "${treeUri}|$cleanPath"

    fun invalidateCache(treeUri: Uri, relativePath: String? = null) {
        if (relativePath == null) {
            val prefix = "${treeUri}|"
            pathDocumentIdCache.keys.removeIf { it.startsWith(prefix) }
            dirListingCache.keys.removeIf { it.startsWith(prefix) }
        } else {
            val clean = normalizePath(relativePath)
            pathDocumentIdCache.remove(cacheKey(treeUri, clean))
            dirListingCache.remove(cacheKey(treeUri, clean))
            val parentPath = if (clean.contains('/')) clean.substringBeforeLast('/') else ""
            dirListingCache.remove(cacheKey(treeUri, parentPath))
            // This app has just changed that entry itself (create, delete,
            // rename, write); an earlier expectation about it no longer holds.
            pendingListingChanges[cacheKey(treeUri, parentPath)]?.forget(clean.substringAfterLast('/'))
        }
    }

    /**
     * Resolves the Document ID for a relative path under a treeUri.
     */
    fun resolveDocumentId(treeUri: Uri, relativePath: String): String? {
        val clean = normalizePath(relativePath)
        if (clean.isEmpty()) {
            return try {
                if (DocumentsContract.isTreeUri(treeUri)) {
                    DocumentsContract.getTreeDocumentId(treeUri)
                } else {
                    DocumentsContract.getDocumentId(treeUri)
                }
            } catch (e: Exception) {
                VeLog.w(TAG) {
                    "Failed to get document ID: authority=${treeUri.authority}, " +
                        "exception=${e.javaClass.simpleName}"
                }
                null
            }
        }

        // This app moved it (or a parent) away; a stale provider listing or a
        // cached id from before the move must not bring it back.
        if (isPendingRemovedAlong(treeUri, clean)) {
            VeLog.i(TAG) { "$PENDING_TAG resolve '$clean': moved away, treated as missing" }
            return null
        }

        val key = cacheKey(treeUri, clean)
        pathDocumentIdCache[key]?.let { return it }

        // Optimization for ExternalStorageProvider: IDs are of form "rootId:subpath"
        if (treeUri.authority == EXTERNAL_STORAGE_AUTHORITY) {
            val rootDocId = try {
                DocumentsContract.getTreeDocumentId(treeUri)
            } catch (_: Exception) { null }
            if (rootDocId != null) {
                val rootPrefix = if (rootDocId.endsWith(":")) rootDocId else "$rootDocId:"
                val candidateDocId = "$rootPrefix$clean"
                val candidateUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, candidateDocId)
                if (documentExists(candidateUri)) {
                    pathDocumentIdCache[key] = candidateDocId
                    return candidateDocId
                }
            }
        }

        // Segment-by-segment lookup with caching
        val segments = clean.split('/')
        var currentPath = ""
        var currentDocId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (_: Exception) {
            return null
        }

        for (segment in segments) {
            if (segment.isEmpty()) continue
            val nextPath = if (currentPath.isEmpty()) segment else "$currentPath/$segment"
            val cachedNext = pathDocumentIdCache[cacheKey(treeUri, nextPath)]
            if (cachedNext != null) {
                currentPath = nextPath
                currentDocId = cachedNext
                continue
            }

            // Query children of current directory. The provider's answer is
            // corrected for what this app just moved/copied, exactly like a
            // listing the user sees: otherwise an entry that is shown could not
            // be found again to open, size or thumbnail it.
            val children = reconcileWithPendingChanges(
                treeUri,
                currentPath,
                queryChildrenInternal(treeUri, currentDocId, currentPath),
            )
            val matched = children.firstOrNull { it.name.equals(segment, ignoreCase = true) }
            if (matched == null) {
                if (pendingListingChanges.isNotEmpty()) {
                    VeLog.i(TAG) { "$PENDING_TAG resolve '$clean': '$segment' not found in '$currentPath' (${children.size} entries)" }
                }
                return null
            }
            currentPath = nextPath
            currentDocId = matched.docId
            pathDocumentIdCache[cacheKey(treeUri, currentPath)] = currentDocId
        }

        pathDocumentIdCache[key] = currentDocId
        return currentDocId
    }

    fun getDocumentUri(treeUri: Uri, relativePath: String): Uri? {
        val docId = resolveDocumentId(treeUri, relativePath) ?: return null
        awaitProviderCatchUp(treeUri, normalizePath(relativePath))
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
    }

    /**
     * Converts a concatenated tree-path string (e.g. "content://.../tree/rootId/subfolder/file.ext")
     * into a valid Android SAF Document URI containing "/document/<docId>".
     */
    fun resolveDocumentUriFromTreePath(pathOrUri: String): Uri? {
        if (!pathOrUri.startsWith("content://")) return null
        val parsed = Uri.parse(pathOrUri)

        // 1. If already a valid document URI (has /document/), return as-is
        if (DocumentsContract.isDocumentUri(context, parsed)) {
            return parsed
        }

        // 2. Separate base tree URI from the appended relative sub-path
        val path = parsed.encodedPath ?: return null
        val treeMarker = "/tree/"
        val treeIdx = path.indexOf(treeMarker)
        if (treeIdx == -1) return parsed

        val afterTree = path.substring(treeIdx + treeMarker.length)
        val slashIdx = afterTree.indexOf('/')

        if (slashIdx == -1) {
            // Root treeUri itself
            return parsed
        }

        val treeDocIdEncoded = afterTree.substring(0, slashIdx)
        val relPathEncoded = afterTree.substring(slashIdx + 1)
        val relPath = Uri.decode(relPathEncoded)

        val baseTreeUri = Uri.Builder()
            .scheme(parsed.scheme)
            .encodedAuthority(parsed.encodedAuthority)
            .appendPath("tree")
            .appendEncodedPath(treeDocIdEncoded)
            .build()

        return getDocumentUri(baseTreeUri, relPath)
    }

    private fun documentExists(uri: Uri): Boolean {
        return try {
            context.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use {
                it.moveToFirst()
            } ?: false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * True if [treeUri] can actually be opened right now: it still has a
     * persisted read grant AND the tree responds to a live query.
     *
     * A persisted grant alone isn't enough -- Android doesn't revoke it
     * just because removable media (a USB drive, an SD card) was
     * unplugged, so a stale grant for a device that's no longer connected
     * looks identical to a healthy one until you actually try to query
     * it. Callers should check this before opening a saved storage
     * location rather than after (see [resolveDocumentId] / [listDirectory],
     * which silently return null/empty for an inaccessible tree).
     */
    fun isTreeAccessible(treeUri: Uri): Boolean {
        var stage = "read_persisted_grants"
        return try {
            val decodedTarget = runCatching { Uri.decode(treeUri.toString()) }.getOrNull() ?: treeUri.toString()
            val persistedPermissions = context.contentResolver.persistedUriPermissions
            val matchingReadGrants = persistedPermissions.filter { perm ->
                if (!perm.isReadPermission) return@filter false
                if (perm.uri == treeUri || perm.uri.toString() == treeUri.toString()) return@filter true
                val decodedPerm = runCatching { Uri.decode(perm.uri.toString()) }.getOrNull() ?: perm.uri.toString()
                decodedPerm == decodedTarget || (
                    perm.uri.authority == treeUri.authority &&
                    decodedTarget.startsWith(decodedPerm)
                )
            }
            val exactReadGrant = persistedPermissions.any { perm ->
                perm.isReadPermission && (perm.uri == treeUri || perm.uri.toString() == treeUri.toString())
            }
            val authorityReadGrantCount = persistedPermissions.count {
                it.isReadPermission && it.uri.authority == treeUri.authority
            }
            val hasGrant = matchingReadGrants.isNotEmpty()
            VeLog.w(TAG) {
                "Tree access probe: authority=${treeUri.authority}, hasReadGrant=$hasGrant, " +
                    "exactReadGrant=$exactReadGrant, authorityReadGrantCount=$authorityReadGrantCount"
            }
            if (!hasGrant) {
                VeLog.w(TAG) {
                    "Tree access probe unavailable: authority=${treeUri.authority}, " +
                        "reason=no_matching_persisted_read_grant"
                }
                return false
            }

            if (DocumentsContract.isTreeUri(treeUri)) {
                stage = "resolve_tree_root_document_id"
                val rootDocId = resolveDocumentId(treeUri, "")
                if (rootDocId == null) {
                    VeLog.w(TAG) {
                        "Tree access probe unavailable: authority=${treeUri.authority}, " +
                            "reason=root_document_id_unresolved"
                    }
                    return false
                }
                val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootDocId)
                stage = "query_tree_root_document"
                documentExistsForAccessProbe(docUri, treeUri.authority.orEmpty())
            } else {
                stage = "query_document"
                documentExistsForAccessProbe(treeUri, treeUri.authority.orEmpty())
            }
        } catch (e: Exception) {
            VeLog.w(TAG) {
                "Tree access probe threw: authority=${treeUri.authority}, stage=$stage, " +
                    "exception=${e.javaClass.simpleName}"
            }
            false
        }
    }

    /** Same root-document probe as [documentExists], with diagnostic outcomes for saved locations. */
    private fun documentExistsForAccessProbe(uri: Uri, authority: String): Boolean {
        return try {
            val cursor = context.contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )
            if (cursor == null) {
                VeLog.w(TAG) {
                    "Tree access probe root query returned null cursor: authority=$authority"
                }
                false
            } else {
                cursor.use {
                    val hasRow = it.moveToFirst()
                    VeLog.w(TAG) {
                        "Tree access probe root query: authority=$authority, returnedRow=$hasRow"
                    }
                    hasRow
                }
            }
        } catch (e: Exception) {
            VeLog.w(TAG) {
                "Tree access probe root query threw: authority=$authority, " +
                    "exception=${e.javaClass.simpleName}"
            }
            false
        }
    }

    /**
     * Strict scan probe: unlike [listDirectory], this distinguishes an
     * accessible empty directory from a provider/query failure.
     */
    fun canListDirectory(treeUri: Uri, relativePath: String): Boolean {
        return try {
            val docId = resolveDocumentId(treeUri, relativePath) ?: return false
            awaitProviderCatchUp(treeUri, normalizePath(relativePath))
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
            context.contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )?.use { true } ?: false
        } catch (e: Exception) {
            VeLog.w(TAG) { "Strict directory probe failed for $relativePath: ${e.message}" }
            false
        }
    }

    /**
     * Lists directory contents in a single cursor pass with full metadata.
     */
    /**
     * Asks the document provider to re-read a folder from its backing store.
     *
     * Remote providers (SFTP, SMB, cloud) keep their own listing cache, and a
     * plain query after a move or a manual refresh is answered from it, so the
     * moved item stays in the source and is missing from the destination until
     * the provider happens to refresh. ContentResolver.refresh is the SAF way
     * to request that (the system picker's pull-to-refresh uses it). Providers
     * that do not support it return false, so this is best effort.
     */
    private fun requestProviderRefresh(treeUri: Uri, folderDocId: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val accepted = runCatching {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, folderDocId)
            context.contentResolver.refresh(childrenUri, null, null)
        }.getOrDefault(false)
        // false = the provider does not implement refresh (RSAF is expected to
        // be one: it has no way to invalidate its directory cache on request),
        // so the pending-change handling is what keeps the listing right.
        VeLog.i(TAG) { "$PENDING_TAG provider refresh: authority=${treeUri.authority} accepted=$accepted" }
        return accepted
    }

    fun listDirectory(treeUri: Uri, relativePath: String, refresh: Boolean = false): List<SafEntry> {
        val clean = normalizePath(relativePath)
        if (refresh) {
            dirListingCache.remove(cacheKey(treeUri, clean))
        }
        val docId = resolveDocumentId(treeUri, clean) ?: return emptyList()
        if (refresh) requestProviderRefresh(treeUri, docId)
        // A folder this app just moved/copied in has no children for the
        // provider until it catches up: wait instead of listing it as empty.
        awaitProviderCatchUp(treeUri, clean)
        return reconcileWithPendingChanges(
            treeUri,
            clean,
            queryChildrenInternal(treeUri, docId, clean),
        )
    }

    private fun queryChildrenInternal(treeUri: Uri, parentDocId: String, currentPath: String): List<SafEntry> {
        // While this app has changes pending for the folder, the provider's
        // answers are known to lag: never serve a cached one, and (below) never
        // cache one -- it would resurface the stale state once the pending
        // record that masks it is gone.
        val pendingHere = hasPendingChanges(treeUri, currentPath)
        val cached = if (pendingHere) null else dirListingCache[cacheKey(treeUri, currentPath)]
        if (cached != null && cached.isNotEmpty()) {
            return cached
        }

      val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        val entries = mutableListOf<SafEntry>()

        // Use PROJECTION_CHILDREN for ExternalStorageProvider (device storage) to avoid
        // querying all table columns across Binder IPC cursor windows for large folders.
        // For cloud providers (e.g. Google Drive), null projection is standard.
        val preferredProjection = if (treeUri.authority == EXTERNAL_STORAGE_AUTHORITY) PROJECTION_CHILDREN else null
        var cursor = try {
            context.contentResolver.query(childrenUri, preferredProjection, null, null, null)
        } catch (_: Exception) {
            try {
                context.contentResolver.query(
                    childrenUri,
                    if (preferredProjection == null) PROJECTION_CHILDREN else null,
                    null,
                    null,
                    null
                )
            } catch (e: Exception) {
                VeLog.w(TAG) { "queryChildren failed for $childrenUri: ${e.message}" }
                null
            }
        } ?: return emptyList()

        // Cloud provider handling: wait for EXTRA_LOADING to complete network fetch (e.g. Google Drive)
        var isLoading = cursor.extras?.getBoolean(DocumentsContract.EXTRA_LOADING, false) == true
        if (cursor.count == 0 && isLoading) {
            val latch = java.util.concurrent.CountDownLatch(1)
            val observer = object : android.database.ContentObserver(android.os.Handler(android.os.Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) {
                    latch.countDown()
                }
            }
            try {
                cursor.registerContentObserver(observer)
                latch.await(4000, java.util.concurrent.TimeUnit.MILLISECONDS)
            } catch (_: Exception) {
            } finally {
                runCatching { cursor.unregisterContentObserver(observer) }
            }
            cursor.close()
            cursor = try {
                context.contentResolver.query(childrenUri, preferredProjection, null, null, null)
            } catch (_: Exception) {
                null
            } ?: return emptyList()
        }

        cursor.use { c ->
            val idIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)

            while (c.moveToNext()) {
                val childId = if (idIdx >= 0) c.getString(idIdx) else null ?: continue
                val name = if (nameIdx >= 0) c.getString(nameIdx) else null ?: continue
                val mime = if (mimeIdx >= 0) c.getString(mimeIdx) else null ?: ""
                val size = if (sizeIdx >= 0 && !c.isNull(sizeIdx)) c.getLong(sizeIdx) else 0L
                val mod = if (modIdx >= 0 && !c.isNull(modIdx)) c.getLong(modIdx) else 0L
                val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR

                val childPath = if (currentPath.isEmpty()) name else "$currentPath/$name"
                pathDocumentIdCache[cacheKey(treeUri, childPath)] = childId

                entries.add(
                    SafEntry(
                        name = name,
                        isDir = isDir,
                        size = if (isDir) 0L else size,
                        lastModified = mod / 1000L,
                        docId = childId,
                        mimeType = mime,
                    )
                )
            }
        }

        // MaterialFiles Hack: On Android 11+, ExternalStorageProvider omits Android/data and Android/obb
        // from the Android directory. Inject them if they exist and are missing.
        if (treeUri.authority == EXTERNAL_STORAGE_AUTHORITY &&
            (parentDocId == DOCUMENT_ID_PRIMARY_ANDROID || parentDocId.endsWith(":Android"))
        ) {
            injectAndroidSpecialFolders(treeUri, parentDocId, currentPath, entries)
        }

        if (entries.isNotEmpty()) {
            if (hasPendingChanges(treeUri, currentPath)) {
                VeLog.d(TAG) { "$PENDING_TAG '$currentPath': ${entries.size} provider entries not cached (changes pending)" }
            } else {
                dirListingCache[cacheKey(treeUri, currentPath)] = entries
            }
        }
        return entries
    }

    private fun injectAndroidSpecialFolders(
        treeUri: Uri,
        parentDocId: String,
        currentPath: String,
        entries: MutableList<SafEntry>
    ) {
        val rootPrefix = parentDocId.substringBefore(":")
        val hasData = entries.any { it.name.equals("data", ignoreCase = true) }
        val hasObb = entries.any { it.name.equals("obb", ignoreCase = true) }

        if (!hasData) {
            val dataDocId = "$rootPrefix:Android/data"
            val dataUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, dataDocId)
            if (documentExists(dataUri)) {
                val childPath = if (currentPath.isEmpty()) "data" else "$currentPath/data"
                pathDocumentIdCache[cacheKey(treeUri, childPath)] = dataDocId
                entries.add(SafEntry("data", true, 0L, 0L, dataDocId, DocumentsContract.Document.MIME_TYPE_DIR))
            }
        }
        if (!hasObb) {
            val obbDocId = "$rootPrefix:Android/obb"
            val obbUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, obbDocId)
            if (documentExists(obbUri)) {
                val childPath = if (currentPath.isEmpty()) "obb" else "$currentPath/obb"
                pathDocumentIdCache[cacheKey(treeUri, childPath)] = obbDocId
                entries.add(SafEntry("obb", true, 0L, 0L, obbDocId, DocumentsContract.Document.MIME_TYPE_DIR))
            }
        }
    }

    fun getFileSize(treeUri: Uri, relativePath: String): Long {
        val docUri = getDocumentUri(treeUri, relativePath) ?: run {
            // The caller sees -1 either way; this says whether the path could
            // not be resolved at all (stale listing / unknown entry).
            VeLog.w(TAG) { "getFileSize: '$relativePath' did not resolve to a document" }
            return -1L
        }
        return try {
            context.contentResolver.query(docUri, arrayOf(DocumentsContract.Document.COLUMN_SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                    if (idx >= 0 && !c.isNull(idx)) {
                        c.getLong(idx).also { size ->
                            if (size <= 0L) VeLog.w(TAG) { "getFileSize: provider reported size=$size for '$relativePath'" }
                        }
                    } else {
                        VeLog.w(TAG) { "getFileSize: provider reported no size for '$relativePath'" }
                        0L
                    }
                } else {
                    VeLog.w(TAG) { "getFileSize: provider has no row for '$relativePath'" }
                    -1L
                }
            } ?: run {
                VeLog.w(TAG) { "getFileSize: provider returned no cursor for '$relativePath'" }
                -1L
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "getFileSize: query failed for '$relativePath': ${e.javaClass.simpleName}: ${e.message}" }
            -1L
        }
    }

    /**
     * Reads a chunk using seekable FileChannel random access where possible.
     */
    fun readFileChunk(treeUri: Uri, relativePath: String, offset: Long, length: Int): ByteArray? {
        val docUri = getDocumentUri(treeUri, relativePath) ?: run {
            VeLog.w(TAG) { "readFileChunk: '$relativePath' did not resolve to a document" }
            return null
        }
        return try {
            val pfd = context.contentResolver.openFileDescriptor(docUri, "r")
            if (pfd != null) {
                pfd.use { descriptor ->
                    FileInputStream(descriptor.fileDescriptor).use { fis ->
                        val channel = fis.channel
                        channel.position(offset)
                        val bytes = ByteArray(length)
                        val buffer = ByteBuffer.wrap(bytes)
                        var totalRead = 0
                        while (totalRead < length) {
                            val r = channel.read(buffer)
                            if (r <= 0) break
                            totalRead += r
                        }
                        if (totalRead == length) bytes else bytes.copyOf(totalRead)
                    }
                }
            } else {
                context.contentResolver.openInputStream(docUri)?.use { input ->
                    if (offset > 0) {
                        var skipped = 0L
                        while (skipped < offset) {
                            val s = input.skip(offset - skipped)
                            if (s <= 0) break
                            skipped += s
                        }
                    }
                    val buf = ByteArray(length)
                    var totalRead = 0
                    while (totalRead < length) {
                        val r = input.read(buf, totalRead, length - totalRead)
                        if (r == -1) break
                        totalRead += r
                    }
                    if (totalRead == length) buf else buf.copyOf(totalRead)
                }
            }
        } catch (t: Throwable) {
            VeLog.w(TAG) { "readFileChunk error for $relativePath (offset=$offset, len=$length): ${t.message}" }
            if (t is OutOfMemoryError) {
                System.gc()
            }
            null
        }
    }

    /**
     * Writes a chunk using seekable FileChannel random access.
     */
    fun writeFileChunk(treeUri: Uri, relativePath: String, offset: Long, data: ByteArray): Boolean {
        var docUri = getDocumentUri(treeUri, relativePath)
        if (docUri == null) {
            // File does not exist yet; create it first
            if (!createFile(treeUri, relativePath)) {
                return false
            }
            docUri = getDocumentUri(treeUri, relativePath) ?: return false
        }

        return try {
            val mode = if (offset == 0L && data.isEmpty()) "wt" else "rw"
            val pfd = context.contentResolver.openFileDescriptor(docUri, mode)
                ?: context.contentResolver.openFileDescriptor(docUri, "wa")
                ?: return false

            pfd.use { descriptor ->
                FileOutputStream(descriptor.fileDescriptor).use { fos ->
                    val channel = fos.channel
                    channel.position(offset)
                    channel.write(ByteBuffer.wrap(data))
                    channel.force(true)
                }
            }
            invalidateCache(treeUri, relativePath)
            true
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "writeFileChunk failed for $relativePath at offset $offset" }
            false
        }
    }

    fun createFile(treeUri: Uri, relativePath: String, mimeType: String? = null): Boolean {
        val clean = normalizePath(relativePath)
        val parentPath = if (clean.contains('/')) clean.substringBeforeLast('/') else ""
        val fileName = if (clean.contains('/')) clean.substringAfterLast('/') else clean
        val parentUri = getDocumentUri(treeUri, parentPath) ?: return false
        val mime = mimeType ?: MimeTypeHelper.getMimeType(fileName)

        return try {
            val created = DocumentsContract.createDocument(context.contentResolver, parentUri, mime, fileName)
            if (created != null) {
                invalidateCache(treeUri, parentPath)
                forgetPendingFor(treeUri, clean)
                val docId = DocumentsContract.getDocumentId(created)
                pathDocumentIdCache[cacheKey(treeUri, clean)] = docId
                true
            } else {
                false
            }
        } catch (e: Exception) {
            VeLog.w(TAG) { "createFile failed for $relativePath: ${e.message}" }
            false
        }
    }

    fun createDirectory(treeUri: Uri, parentPath: String, dirName: String): Boolean {
        val cleanParent = normalizePath(parentPath)
        val newDirPath = if (cleanParent.isEmpty()) dirName else "$cleanParent/$dirName"

        // Idempotent: SAF providers like ExternalStorageProvider (USB/SD
        // cards) don't fail or return the existing document on a name
        // clash -- they silently rename the new one to "name (1)", "name
        // (2)", etc. Resolve first so a repeat call (e.g. the thumbnail
        // cache ensuring ".thumbcache" exists on every app launch) reuses
        // the real directory instead of piling up duplicates.
        resolveDocumentId(treeUri, newDirPath)?.let { existingId ->
            val existingUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, existingId)
            val isDir = try {
                context.contentResolver.query(
                    existingUri,
                    arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE),
                    null, null, null
                )?.use { c ->
                    c.moveToFirst() && c.getString(0) == DocumentsContract.Document.MIME_TYPE_DIR
                } ?: false
            } catch (_: Exception) {
                false
            }
            if (isDir) return true
            // A file already occupies this name; fall through and let
            // createDocument's own clash handling apply.
        }

        val parentUri = getDocumentUri(treeUri, cleanParent) ?: return false

        return try {
            val created = DocumentsContract.createDocument(
                context.contentResolver,
                parentUri,
                DocumentsContract.Document.MIME_TYPE_DIR,
                dirName
            )
            if (created != null) {
                invalidateCache(treeUri, cleanParent)
                forgetPendingFor(treeUri, newDirPath)
                val docId = DocumentsContract.getDocumentId(created)
                pathDocumentIdCache[cacheKey(treeUri, newDirPath)] = docId
                true
            } else {
                false
            }
        } catch (e: Exception) {
            VeLog.w(TAG) { "createDirectory failed for $dirName in $parentPath: ${e.message}" }
            false
        }
    }

    fun renameFile(treeUri: Uri, relativePath: String, newName: String): Boolean {
        val clean = normalizePath(relativePath)
        val docUri = getDocumentUri(treeUri, clean) ?: return false

        return try {
            val renamedUri = DocumentsContract.renameDocument(context.contentResolver, docUri, newName)
            if (renamedUri != null) {
                invalidateCache(treeUri, clean)
                val parentPath = if (clean.contains('/')) clean.substringBeforeLast('/') else ""
                val newPath = if (parentPath.isEmpty()) newName else "$parentPath/$newName"
                forgetPendingFor(treeUri, newPath)
                val newDocId = DocumentsContract.getDocumentId(renamedUri)
                pathDocumentIdCache[cacheKey(treeUri, newPath)] = newDocId
                true
            } else {
                false
            }
        } catch (e: Exception) {
            VeLog.w(TAG) { "renameFile failed for $relativePath: ${e.message}" }
            false
        }
    }

    fun moveFile(treeUri: Uri, sourcePath: String, destPath: String): Boolean {
        val source = normalizePath(sourcePath)
        val dest = normalizePath(destPath)
        if (source.isEmpty() || dest.isEmpty()) return false
        if (source == dest) return true

        val sourceName = source.substringAfterLast('/')
        val destName = dest.substringAfterLast('/')
        if (sourceName != destName) return false

        val sourceParentPath = source.substringBeforeLast('/', "")
        val destParentPath = dest.substringBeforeLast('/', "")
        if (sourceParentPath == destParentPath) {
            return renameFile(treeUri, source, destName)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false

        val startedAt = nowMs()
        val sourceUri = getDocumentUri(treeUri, source) ?: return false
        val sourceParentUri = getDocumentUri(treeUri, sourceParentPath) ?: return false
        val destParentUri = getDocumentUri(treeUri, destParentPath) ?: return false
        val lags = providerListingMayLag(treeUri)
        // Read before the move: afterwards the source no longer exists to ask.
        val movedSnapshot = if (lags) snapshotEntry(sourceUri, destName) else null
        return try {
            val movedUri = DocumentsContract.moveDocument(
                context.contentResolver,
                sourceUri,
                sourceParentUri,
                destParentUri,
            ) ?: return false
            val movedDocId = runCatching { DocumentsContract.getDocumentId(movedUri) }.getOrNull()

            // Some providers (RSAF) move server-side behind their own listing
            // cache, which keeps answering with the old folders for a few
            // seconds. Remember the outcome so every lookup -- listing and
            // path resolution alike -- reflects it until the provider agrees.
            if (lags) {
                val expiresAt = nowMs() + PENDING_LISTING_TTL_MS
                withPending(treeUri, sourceParentPath) { it.expectRemoved(sourceName, expiresAt) }
                if (movedSnapshot != null) {
                    val entry = if (movedDocId != null) movedSnapshot.copy(docId = movedDocId) else movedSnapshot
                    withPending(treeUri, destParentPath) { it.expectAdded(entry, expiresAt) }
                }
            }

            // Only the old location is invalid now (for a directory, everything
            // below it). Wiping the whole tree's cache here would also drop the
            // ids of files moved just before this one in the same batch, which
            // could then no longer be found at their new path.
            invalidateSubtree(treeUri, source)
            dirListingCache.remove(cacheKey(treeUri, sourceParentPath))
            dirListingCache.remove(cacheKey(treeUri, destParentPath))
            if (movedDocId != null) pathDocumentIdCache[cacheKey(treeUri, dest)] = movedDocId

            // Providers that support it re-read both folders; ones that do not
            // (the call returns false) rely on the pending changes above.
            val sourceRefresh = resolveDocumentId(treeUri, sourceParentPath)?.let { requestProviderRefresh(treeUri, it) }
            val destRefresh = resolveDocumentId(treeUri, destParentPath)?.let { requestProviderRefresh(treeUri, it) }
            VeLog.i(TAG) {
                "$PENDING_TAG moveFile '$source' -> '$dest': lags=$lags snapshot=${movedSnapshot != null} " +
                    "size=${movedSnapshot?.size} movedDocId=${movedDocId != null} " +
                    "refresh(src=$sourceRefresh,dest=$destRefresh) in ${nowMs() - startedAt}ms"
            }
            true
        } catch (e: Exception) {
            VeLog.w(TAG) { "moveFile failed for " + sourcePath + ": " + e.message }
            false
        }
    }

    fun deleteRecursively(treeUri: Uri, relativePath: String): Boolean {
        val clean = normalizePath(relativePath)
        val docId = resolveDocumentId(treeUri, clean) ?: return false
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)

        // Check if directory
        val isDir = try {
            context.contentResolver.query(docUri, arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    idx >= 0 && c.getString(idx) == DocumentsContract.Document.MIME_TYPE_DIR
                } else false
            } ?: false
        } catch (_: Exception) { false }

        if (isDir) {
            val children = listDirectory(treeUri, clean)
            for (child in children) {
                val childPath = if (clean.isEmpty()) child.name else "$clean/${child.name}"
                deleteRecursively(treeUri, childPath)
            }
        }

        return try {
            val deleted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val parentPath = if (clean.contains('/')) clean.substringBeforeLast('/') else ""
                val parentUri = getDocumentUri(treeUri, parentPath)
                if (parentUri != null) {
                    try {
                        DocumentsContract.removeDocument(context.contentResolver, docUri, parentUri)
                    } catch (_: UnsupportedOperationException) {
                        DocumentsContract.deleteDocument(context.contentResolver, docUri)
                    }
                } else {
                    DocumentsContract.deleteDocument(context.contentResolver, docUri)
                }
            } else {
                DocumentsContract.deleteDocument(context.contentResolver, docUri)
            }
            invalidateCache(treeUri, clean)
            deleted
        } catch (e: Exception) {
            VeLog.w(TAG) { "deleteRecursively failed for $relativePath: ${e.message}" }
            false
        }
    }

    fun getSpaceInfo(treeUri: Uri): List<Long>? {
        return try {
            VaultPathUtils.querySafSpaceInfo(context, treeUri)?.toList()
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Extracts an image or video thumbnail directly from SAF storage.
     */
    fun getThumbnail(
        treeUri: Uri,
        relativePath: String,
        targetSize: Int,
        quality: Int,
        isVideo: Boolean,
        preserveAlpha: Boolean = false,
        strategy: String = "hybrid",
        framePosition: Double = 0.12,
        explicitTimeUs: Long? = null,
    ): Map<String, Any>? {
        val startedAt = nowMs()
        val thumb = extractThumbnail(
            treeUri, relativePath, targetSize, quality, isVideo, preserveAlpha,
            strategy, framePosition, explicitTimeUs,
        )
        if (thumb == null) {
            VeLog.w(TAG) {
                "getThumbnail: nothing for '$relativePath' (video=$isVideo) after ${nowMs() - startedAt}ms, " +
                    "folders with pending changes=${pendingListingChanges.size}"
            }
        }
        return thumb
    }

    private fun extractThumbnail(
        treeUri: Uri,
        relativePath: String,
        targetSize: Int,
        quality: Int,
        isVideo: Boolean,
        preserveAlpha: Boolean,
        strategy: String,
        framePosition: Double,
        explicitTimeUs: Long?,
    ): Map<String, Any>? {
        val docUri = getDocumentUri(treeUri, relativePath) ?: run {
            VeLog.w(TAG) { "getThumbnail: '$relativePath' did not resolve to a document" }
            return null
        }

        if (isVideo) {
            return try {
                context.contentResolver.openFileDescriptor(docUri, "r")?.use { pfd ->
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(pfd.fileDescriptor)
                        val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        val durationMs = durationStr?.toLongOrNull() ?: 0L
                        var frame = tryExtractVideoFrame(retriever, durationMs, targetSize, strategy, framePosition, explicitTimeUs) ?: return null
                        if (explicitTimeUs == null && strategy == "hybrid" && VideoThumbnailCoordinator.isLikelyBlankFrame(frame) && durationMs > 0L) {
                            val alternateUs = (durationMs * 1000L * framePosition.coerceIn(0.05, 0.90)).toLong()
                            val alternate = runCatching {
                                retriever.getFrameAtTime(alternateUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                            }.getOrNull()
                            if (alternate != null && !VideoThumbnailCoordinator.isLikelyBlankFrame(alternate)) {
                                frame.recycle()
                                frame = alternate
                            } else {
                                alternate?.recycle()
                            }
                        }
                         val scaled = scaledToFit(frame, targetSize)
                        val stream = ByteArrayOutputStream(32768)
                        scaled.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), stream)
                        val bytes = stream.toByteArray()
                        val w = frame.width
                        val h = frame.height
                        if (scaled != frame) scaled.recycle()
                        frame.recycle()
                        mapOf("bytes" to bytes, "width" to w, "height" to h)
                    } finally {
                        retriever.release()
                    }
                }
            } catch (e: Exception) {
                VeLog.w(TAG) { "getVideoThumbnail failed for $relativePath: ${e.message}" }
                null
            }
        }

        // Image thumbnail
        // 1. Try DocumentsContract.getDocumentThumbnail
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val point = Point(targetSize, targetSize)
                val thumb = DocumentsContract.getDocumentThumbnail(context.contentResolver, docUri, point, null)
                if (thumb != null) {
                    val scaled = scaledToFit(thumb, targetSize)
                    val stream = ByteArrayOutputStream()
                    val format = if (preserveAlpha) {
                        Bitmap.CompressFormat.WEBP
                    } else {
                        Bitmap.CompressFormat.JPEG
                    }
                    scaled.compress(format, quality.coerceIn(1, 100), stream)
                    val bytes = stream.toByteArray()
                    val w = thumb.width
                    val h = thumb.height
                    if (scaled != thumb) scaled.recycle()
                    thumb.recycle()
                    return mapOf("bytes" to bytes, "width" to w, "height" to h)
                }
            } catch (_: Exception) {}
        }

        // 2. Decode from stream with EXIF correction
        return try {
            val exifOrientation = context.contentResolver.openInputStream(docUri)?.use { stream ->
                runCatching {
                    ExifInterface(stream).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL
                    )
                }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
            } ?: ExifInterface.ORIENTATION_NORMAL

            val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(docUri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, boundsOptions)
            }
            val srcW = boundsOptions.outWidth
            val srcH = boundsOptions.outHeight
            if (srcW <= 0 || srcH <= 0) return null

            // See ImageDecodeGuard: inSampleSize doesn't bound decoder memory
            // for a huge source, and OOM isn't an Exception.
            val permit = try {
                ImageDecodeGuard.admit(context, srcW, srcH)
            } catch (e: ImageDecodeGuard.RefusedException) {
                VeLog.w(TAG) { "getImageThumbnail refused for $relativePath: ${e.message}" }
                return null
            }
            try {
                val decodeOptions = BitmapFactory.Options().apply {
                    inSampleSize = calculateInSampleSize(srcW, srcH, targetSize)
                    inPreferredConfig = if (preserveAlpha) {
                        Bitmap.Config.ARGB_8888
                    } else {
                        Bitmap.Config.RGB_565
                    }
                }

                val decoded = context.contentResolver.openInputStream(docUri)?.use { stream ->
                    BitmapFactory.decodeStream(stream, null, decodeOptions)
                } ?: return null

                  val orientationMatrix = exifOrientationMatrix(exifOrientation)
                val dW = decoded.width
                val dH = decoded.height
                val maxDim = maxOf(dW, dH)
                val needsScale = maxDim > targetSize && maxDim > 0
                val scale = if (needsScale) targetSize.toFloat() / maxDim else 1f
                val scaled = if (needsScale && (dW * scale < 1f || dH * scale < 1f)) {
                    val oriented = applyExifOrientation(decoded, orientationMatrix)
                    scaledToFit(oriented, targetSize).also {
                        if (it != oriented) oriented.recycle()
                    }
                } else {
                    val combined = Matrix(orientationMatrix)
                    if (needsScale) combined.preScale(scale, scale)
                    if (combined.isIdentity) {
                        decoded
                    } else {
                        Bitmap.createBitmap(decoded, 0, 0, dW, dH, combined, true).also {
                            if (it != decoded) decoded.recycle()
                        }
                    }
                }
                val stream = ByteArrayOutputStream(32768)
                val format = if (preserveAlpha) {
                    Bitmap.CompressFormat.WEBP
                } else {
                    Bitmap.CompressFormat.JPEG
                }
                scaled.compress(format, quality.coerceIn(1, 100), stream)
                val bytes = stream.toByteArray()
                scaled.recycle()

                mapOf("bytes" to bytes, "width" to srcW, "height" to srcH)
            } finally {
                permit.close()
            }
        } catch (e: OutOfMemoryError) {
            VeLog.w(TAG) { "getImageThumbnail out of memory for $relativePath" }
            null
        } catch (e: Exception) {
            VeLog.w(TAG) { "getImageThumbnail failed for $relativePath: ${e.message}" }
            null
        }
    }

    private fun tryExtractVideoFrame(
        retriever: MediaMetadataRetriever,
        durationMs: Long,
        targetSize: Int,
        strategy: String,
        framePosition: Double,
        explicitTimeUs: Long?,
    ): Bitmap? {
        val positionUs = explicitTimeUs ?: if (strategy == "frameAtPercentage" && durationMs > 0L) {
            (durationMs * 1000L * framePosition.coerceIn(0.05, 0.90)).toLong()
        } else 0L
        val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            runCatching {
                retriever.getScaledFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, targetSize, targetSize)
            }.getOrNull() ?: retriever.getFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        } else {
            retriever.getFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        }
        if (frame != null) return frame

        if (explicitTimeUs == null && strategy == "hybrid" && durationMs > 0L) {
            val candidateUs = (durationMs * 1000L * framePosition.coerceIn(0.05, 0.90)).toLong()
            return retriever.getFrameAtTime(candidateUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        }
        return null
    }

    private fun calculateInSampleSize(width: Int, height: Int, targetSize: Int): Int {
        var inSampleSize = 1
        val maxDim = maxOf(width, height)
        if (maxDim > targetSize) {
            val halfMax = maxDim / 2
            while ((halfMax / inSampleSize) >= targetSize) {
                inSampleSize *= 2
            }
        }
        return inSampleSize.coerceAtLeast(1)
    }

    private fun scaledToFit(src: Bitmap, targetSize: Int): Bitmap {
        val w = src.width
        val h = src.height
        if (w <= 0 || h <= 0) return src
        val maxDim = maxOf(w, h)
        if (maxDim <= targetSize) return src
        val scale = targetSize.toFloat() / maxDim
        val dstW = (w * scale).toInt().coerceAtLeast(1)
        val dstH = (h * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, dstW, dstH, true)
    }

    private fun exifOrientationMatrix(orientation: Int): Matrix {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
        }
        return matrix
    }

    private fun applyExifOrientation(src: Bitmap, matrix: Matrix): Bitmap {
        if (matrix.isIdentity) return src
        val rotated = Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
        if (rotated != src) src.recycle()
        return rotated
    }

    fun openWithApp(
        treeUri: Uri,
        relativePath: String,
        mimeTypeOverride: String?,
        packageName: String?,
        requestId: String? = null,
    ): Boolean {
        val docUri = getDocumentUri(treeUri, relativePath) ?: return false
        val fileName = relativePath.substringAfterLast('/')
        val mime = mimeTypeOverride ?: MimeTypeHelper.getMimeType(fileName)

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(docUri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            if (!packageName.isNullOrEmpty()) {
                setPackage(packageName)
            }
        }

        return try {
            if (!packageName.isNullOrEmpty()) {
                try {
                    context.startActivity(intent)
                    return true
                } catch (e: Exception) {
                    OpenWithChooser.logReplayFailure(packageName, e)
                    intent.setPackage(null)
                }
            }
            val chooser = OpenWithChooser.build(
                context,
                intent,
                "Open with…",
                fileName.substringAfterLast('.', ""),
                requestId
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(chooser)
            true
        } catch (e: Exception) {
            VeLog.w(TAG) { "openWithApp failed for $relativePath: ${e.message}" }
            false
        }
    }

    /**
     * Shares [relativePaths] through the system share sheet. Entries named in
     * [directoryPaths] are folders: the share sheet can't carry a directory,
     * so each goes out as one zip served by [StorageFolderShareProvider].
     * Files keep using their SAF document URI directly.
     */
    fun shareFiles(
        treeUri: Uri,
        relativePaths: List<String>,
        directoryPaths: Set<String> = emptySet(),
    ): Boolean {
        if (relativePaths.isEmpty()) return false
        val uris = ArrayList<Uri>()
        // The path each URI came from, in step with [uris], so the single-item
        // MIME type below describes the item that was actually kept.
        val kept = ArrayList<String>()
        for (rel in relativePaths) {
            val uri = if (rel in directoryPaths) {
                // The root folder's own document id is resolved here, from the
                // same cache the listing the person just picked it from filled
                // -- the provider then never has to look a folder up by name.
                resolveDocumentId(treeUri, rel)?.let { docId ->
                    StorageFolderShareProvider.buildSafUri(context, treeUri, docId, rel)
                }
            } else {
                getDocumentUri(treeUri, rel)
            }
            if (uri != null) {
                uris.add(uri)
                kept.add(rel)
            }
        }
        if (uris.isEmpty()) return false

        val intent = if (uris.size == 1) {
            val fileName = kept[0].substringAfterLast('/')
            Intent(Intent.ACTION_SEND).apply {
                putExtra(Intent.EXTRA_STREAM, uris[0])
                type = if (kept[0] in directoryPaths) "application/zip" else MimeTypeHelper.getMimeType(fileName)
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                type = "*/*"
            }
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        return try {
            val chooser = Intent.createChooser(intent, null).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(chooser)
            true
        } catch (e: Exception) {
            VeLog.w(TAG) { "shareFiles failed: ${e.message}" }
            false
        }
    }

    /**
     * Fast native copy between SAF documents or between SAF and local storage.
     */
    fun copyFile(
        srcTreeUri: Uri?,
        srcPath: String,
        destTreeUri: Uri?,
        destPath: String
    ): Boolean {
        // Source and destination can be two different "mounts" of one physical
        // file (a folder added as storage *and* browsed as plain local storage,
        // or the same folder added twice). Copying a file onto itself is a
        // no-op, but the streaming fallback below opens the destination with
        // "wt", which truncates it -- and would do so before the source is
        // read, silently turning the file into 0 bytes. Never go further.
        if (isSameRealFile(srcTreeUri, srcPath, destTreeUri, destPath)) {
            VeLog.w(TAG) { "copyFile: source and destination are the same file; nothing to copy" }
            return true
        }

        if (srcTreeUri != null && destTreeUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            srcTreeUri.authority == destTreeUri.authority
        ) {
            val srcDocUri = getDocumentUri(srcTreeUri, srcPath)
            val destParentPath = if (destPath.contains('/')) destPath.substringBeforeLast('/') else ""
            val destParentUri = getDocumentUri(destTreeUri, destParentPath)
            if (srcDocUri != null && destParentUri != null) {
                try {
                    val destName = destPath.substringAfterLast('/')
                    val copiedSnapshot =
                        if (providerListingMayLag(destTreeUri)) snapshotEntry(srcDocUri, destName) else null
                    val copied = DocumentsContract.copyDocument(context.contentResolver, srcDocUri, destParentUri)
                    if (copied != null) {
                        // A rename can change the document id: keep the Uri it returns.
                        var finalUri: Uri = copied
                        val copiedName = getFileNameFromUri(copied)
                        if (copiedName != null && copiedName != destName) {
                            DocumentsContract.renameDocument(context.contentResolver, copied, destName)
                                ?.let { finalUri = it }
                        }
                        invalidateCache(destTreeUri, destPath)
                        val copiedDocId = runCatching { DocumentsContract.getDocumentId(finalUri) }.getOrNull()
                        if (copiedDocId != null) {
                            pathDocumentIdCache[cacheKey(destTreeUri, normalizePath(destPath))] = copiedDocId
                        }
                        // A server-side copy can leave the provider's folder
                        // listing stale, like a move (see moveFile).
                        if (copiedSnapshot != null) {
                            val entry = copiedSnapshot.copy(docId = copiedDocId ?: copiedSnapshot.docId)
                            val expiresAt = nowMs() + PENDING_LISTING_TTL_MS
                            withPending(destTreeUri, destParentPath) { it.expectAdded(entry, expiresAt) }
                        }
                        VeLog.i(TAG) {
                            "$PENDING_TAG copyFile -> '$destPath': snapshot=${copiedSnapshot != null} " +
                                "size=${copiedSnapshot?.size} copiedDocId=${copiedDocId != null}"
                        }
                        return true
                    }
                } catch (_: UnsupportedOperationException) {}
            }
        }

        // Streaming copy fallback
        //
        // Opening either end can throw: a provider reports a document that has
        // vanished (or a stale cached document id) as FileNotFoundException,
        // SecurityException or -- ExternalStorageProvider's "Failed to determine
        // if X is child of Y" -- IllegalArgumentException. This runs on a bare
        // executor thread, so an escaped exception kills the whole process.
        val inStream: InputStream? = try {
            if (srcTreeUri != null) {
                val docUri = getDocumentUri(srcTreeUri, srcPath) ?: return false
                context.contentResolver.openInputStream(docUri)
            } else {
                val file = File(srcPath)
                if (file.exists()) FileInputStream(file) else null
            }
        } catch (e: Exception) {
            VeLog.w(TAG) { "copyFile: could not open source: ${e.message}" }
            null
        }
        if (inStream == null) return false

        val outStream: java.io.OutputStream? = try {
            if (destTreeUri != null) {
                createFile(destTreeUri, destPath)
                val docUri = getDocumentUri(destTreeUri, destPath)
                if (docUri == null) null else context.contentResolver.openOutputStream(docUri, "wt")
            } else {
                val destFile = File(destPath)
                destFile.parentFile?.mkdirs()
                FileOutputStream(destFile)
            }
        } catch (e: Exception) {
            VeLog.w(TAG) { "copyFile: could not open destination: ${e.message}" }
            null
        }
        if (outStream == null) {
            try { inStream.close() } catch (_: Exception) {}
            return false
        }

        return try {
            inStream.use { input ->
                outStream.use { output ->
                    val buffer = ByteArray(1024 * 1024) // 1 MB buffer
                    var read: Int
                    while (input.read(buffer).also { read = it } != -1) {
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            }
            if (destTreeUri != null) invalidateCache(destTreeUri, destPath)
            true
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "copyFile streaming failed: ${e.message}" }
            false
        }
    }

    /**
     * Writes a sequential stream to a SAF document. Some cloud providers
     * (including Google Drive) do not support the seekable `rw` descriptors
     * required by [writeFileChunk], so vault exports to SAF must use one
     * output stream for the entire file.
     */
    fun writeStreamToFile(treeUri: Uri, relativePath: String, inputStream: InputStream): Boolean {
        val clean = normalizePath(relativePath)
        var shouldDeletePartial = false
        var succeeded = false
        try {
            val documentUri = getDocumentUri(treeUri, clean) ?: run {
                if (!createFile(treeUri, clean)) return false
                shouldDeletePartial = true
                getDocumentUri(treeUri, clean) ?: return false
            }

            val outputStream = context.contentResolver.openOutputStream(documentUri, "wt")
                ?: throw java.io.IOException("Could not open SAF destination for writing")
            shouldDeletePartial = true
            inputStream.use { input ->
                outputStream.use { output ->
                    val buffer = ByteArray(256 * 1024)
                    try {
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (count > 0) output.write(buffer, 0, count)
                        }
                        output.flush()
                    } finally {
                        buffer.fill(0)
                    }
                }
            }
            succeeded = true
            invalidateCache(treeUri, clean)
            return true
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "writeStreamToFile failed for $relativePath: ${e.message}" }
            return false
        } finally {
            runCatching { inputStream.close() }
            invalidateCache(treeUri, clean)
            if (shouldDeletePartial && !succeeded) {
                runCatching { deleteRecursively(treeUri, clean) }
            }
        }
    }

    /**
     * True when both ends of a copy are the very same file on disk, however
     * they are addressed (see [getRealPath]), or the same entry of the same
     * tree for providers that have no real path. Unknown means false.
     */
    private fun isSameRealFile(
        srcTreeUri: Uri?,
        srcPath: String,
        destTreeUri: Uri?,
        destPath: String
    ): Boolean {
        if (srcTreeUri != null && destTreeUri != null && srcTreeUri == destTreeUri &&
            normalizePath(srcPath) == normalizePath(destPath)
        ) return true
        val src = getRealPath(srcTreeUri, srcPath) ?: return false
        val dest = getRealPath(destTreeUri, destPath) ?: return false
        return src == dest
    }

    /**
     * Canonical absolute filesystem path behind an entry, or null when there
     * is no such path.
     *
     * With a null [treeUri], [path] is already an absolute path and is only
     * canonicalised. With a tree URI, [path] is relative to the tree and the
     * mapping is only possible for the built-in ExternalStorageProvider, whose
     * document ids are "<volume>:<relative path>"; cloud and virtual providers
     * (Drive, Filen, this app's own provider, ...) have no real path.
     *
     * This is what lets the same folder -- added as a storage location through
     * SAF, and also reachable as plain local storage -- be recognised as one
     * place instead of two unrelated ones.
     */
    @Suppress("DEPRECATION")
    fun getRealPath(treeUri: Uri?, path: String): String? {
        val raw: String = if (treeUri == null) {
            if (path.isBlank()) return null
            path
        } else {
            if (treeUri.authority != EXTERNAL_STORAGE_AUTHORITY) return null
            val rootDocId = try {
                DocumentsContract.getTreeDocumentId(treeUri)
            } catch (_: Exception) {
                return null
            }
            val colon = rootDocId.indexOf(':')
            if (colon <= 0) return null
            val volume = rootDocId.substring(0, colon)
            val rootSub = rootDocId.substring(colon + 1).trim('/')
            val volumeRoot = when (volume) {
                "primary" -> Environment.getExternalStorageDirectory().absolutePath
                // ExternalStorageProvider's "Documents" shortcut root.
                "home" -> Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOCUMENTS
                ).absolutePath
                else -> "/storage/$volume"
            }
            var f = if (rootSub.isEmpty()) File(volumeRoot) else File(volumeRoot, rootSub)
            val rel = normalizePath(path)
            if (rel.isNotEmpty()) f = File(f, rel)
            f.path
        }
        val file = File(raw)
        return try {
            file.canonicalPath
        } catch (_: java.io.IOException) {
            file.absolutePath
        }
    }

    private fun getFileNameFromUri(uri: Uri): String? {
        return try {
            context.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    if (idx >= 0) c.getString(idx) else null
                } else null
            }
        } catch (_: Exception) { null }
    }

    /**
     * Auto-discovers all mounted storage volumes (Primary, SD Cards, USB OTG).
     */
    fun getStorageVolumes(): List<Map<String, Any?>> {
        val sm = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            ?: return emptyList()
        val volumes = mutableListOf<Map<String, Any?>>()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                for (vol in sm.storageVolumes) {
                    try {
                        val isPrimary = vol.isPrimary
                        val isRemovable = vol.isRemovable
                        val state = vol.state
                        val desc = vol.getDescription(context)
                        val uuid = vol.uuid
                        val dir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) vol.directory else null
                        val path = dir?.absolutePath
                            ?: (if (isPrimary) Environment.getExternalStorageDirectory().absolutePath else (if (uuid != null) "/storage/$uuid" else null))
                        val canRead = path != null && File(path).canRead()
                        // Must be stable across calls: the Dart side keys the volIds it
                        // has already handed to open tabs on this id, so a value that
                        // changes per call (e.g. a timestamp) would renumber the volume
                        // on every refresh. A volume with no UUID is identified by its
                        // mount path, falling back to its description.
                        val fallback = path ?: desc ?: "unknown"
                        val stableId = uuid ?: if (isPrimary) "primary" else
                            "volume_" + fallback.replace(Regex("[^A-Za-z0-9._-]"), "_")

                        volumes.add(mapOf(
                            "id" to stableId,
                            "description" to desc,
                            "isPrimary" to isPrimary,
                            "isRemovable" to isRemovable,
                            "state" to state,
                            "path" to (path ?: ""),
                            "hasDirectAccess" to canRead,
                        ))
                    } catch (_: Throwable) {
                        // Skip individual problematic volume on quirky OEM ROMs
                    }
                }
            } else {
                // Pre-Nougat fallback
                val primaryDir = Environment.getExternalStorageDirectory()
                volumes.add(mapOf(
                    "id" to "primary",
                    "description" to "Internal Storage",
                    "isPrimary" to true,
                    "isRemovable" to false,
                    "state" to Environment.getExternalStorageState(),
                    "path" to primaryDir.absolutePath,
                    "hasDirectAccess" to primaryDir.canRead(),
                ))
            }
        } catch (_: Throwable) {
            // Return any volumes collected before failure
        }

        return volumes
    }
}