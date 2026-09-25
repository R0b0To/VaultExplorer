package com.aeidolon.vaultexplorer.container

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.OpenableColumns
import java.io.FileNotFoundException
import com.aeidolon.vaultexplorer.DocumentId
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.VeLog

/**
 * Plain ContentProvider -- deliberately NOT a DocumentsProvider -- used only
 * to build the outgoing Intent.EXTRA_STREAM URI when the user shares a file
 * out of an unlocked vault (see
 * [com.aeidolon.vaultexplorer.handlers.SystemPermissionHandlers.handleShareFile]).
 * [ContainerDocumentsProvider] stays the provider of record for SAF tree
 * browsing -- the Files app, "Open with", a file manager's own
 * document-tree picker -- since that surface needs
 * android.permission.MANAGE_DOCUMENTS / the DOCUMENTS_PROVIDER
 * intent-filter to be discoverable as an SAF root at all.
 *
 * That exact registration is what breaks a class of Android sharing code
 * that tries to resolve a received content:// URI down to a real
 * java.io.File path. DocumentsContract.isDocumentUri() doesn't just check
 * the URI shape -- it also checks whether the authority is registered as a
 * documents provider. Helpers like share_handler_android's
 * FileDirectory.getAbsolutePath() (bundled inside LocalSend, among many
 * other apps) special-case exactly three system authorities
 * (ExternalStorageProvider, DownloadsProvider, MediaProvider) inside the
 * "this is a documents URI" branch and, for any other documents-provider
 * authority, silently fall through to `return uri.path` -- never reaching
 * the *other*, generic "query _display_name, then
 * ContentResolver.openInputStream + copy" fallback those same helpers
 * already have for an ordinary content:// URI. `uri.path` for a document
 * URI looks like "/document/0:file:name.jpg", which such code then feeds
 * straight into java.io.File as if it were a real filesystem path --
 * exactly the PathNotFoundException this provider exists to route around.
 *
 * This provider's authority is never registered as a documents provider,
 * and its URI shape ("/vaultshare/<id>", not "/document/<id>") can't be
 * mistaken for one either, so DocumentsContract.isDocumentUri() returns
 * false immediately and that class of helper takes its generic, working
 * path instead.
 *
 * Read-only: this exists purely to hand a byte stream to whatever app the
 * user picked from the share sheet, never to accept writes back. Reuses
 * the same [ContainerProxyCallback] proxy-file-descriptor bridge as
 * [ContainerDocumentsProvider], so nothing decrypted is written to disk
 * here either -- the bytes only touch disk once they reach the *receiving*
 * app's own sandboxed storage, which is the expected, unavoidable result of
 * the user deliberately sharing the file out in the first place.
 */
class ContainerShareProvider : ContentProvider() {

    companion object {
        const val AUTHORITY = "com.aeidolon.vaultexplorer.shareprovider"
        private const val TAG = "ContainerShareProvider"

          /**
         * Builds the URI to hand to Intent.EXTRA_STREAM for [docId] -- the
         * same "<rootId>:file:<fatPath>" wire format [DocumentId] already
         * uses for [ContainerDocumentsProvider]. Deliberately shaped so it
         * can never be mistaken for a SAF document URI (see class doc).
         */
        fun buildUri(docId: String): Uri =
            Uri.Builder()
                .scheme("content")
                .authority(AUTHORITY)
                .appendPath("vaultshare")
                .appendPath(docId)
                .build()

        fun buildUri(volId: Int, fatPath: String): Uri =
            buildUri(DocumentId(volId, "file", fatPath).toString())
    }

    private fun docIdOf(uri: Uri): String {
        val segments = uri.pathSegments
        if (segments.isEmpty() || segments[0] != "vaultshare") {
            throw FileNotFoundException("Missing share document ID: $uri")
        }
        val docId = segments.drop(1).joinToString("/")
        if (docId.isEmpty()) {
            throw FileNotFoundException("Missing share document ID: $uri")
        }
        return docId
    }

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns)

        val doc = try {
            DocumentId.parse(docIdOf(uri), "share document")
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "query failed parsing $uri: ${e.message}" }
            return cursor
        }
        if (ContainerSessionRegistry.activeSessions[doc.volId] == null) {
            VeLog.w(TAG) { "query for $uri: volume ${doc.volId} is not mounted" }
            return cursor
        }

        val displayName = doc.fatPath.substringAfterLast("/")
        val size = try {
            ContainerFileSystem.getFileSize(doc.volId, doc.fatPath)
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "getFileSize failed for ${doc.fatPath}: ${e.message}" }
            -1L
        }

      val row = cursor.newRow()
        for (col in columns) {
            when (col) {
                OpenableColumns.DISPLAY_NAME -> row.add(displayName)
                OpenableColumns.SIZE -> row.add(if (size >= 0) size else null)
                "_id" -> row.add(doc.hashCode())
                "mime_type" -> row.add(getType(uri))
                else -> row.add(null)
            }
        }
        return cursor
    }

    override fun getType(uri: Uri): String {
        val doc = try {
            DocumentId.parse(docIdOf(uri), "share document")
        } catch (e: Exception) {
            return "application/octet-stream"
        }
        return doc.mimeTypeOverride
            ?: MimeTypeHelper.getMimeType(doc.fatPath.substringAfterLast("/"))
            ?: "application/octet-stream"
    }

    override fun getStreamTypes(uri: Uri, mimeTypeFilter: String): Array<String>? {
        val mimeType = getType(uri)
        return if (android.content.ClipDescription.compareMimeTypes(mimeType, mimeTypeFilter)) {
            arrayOf(mimeType)
        } else {
            null
        }
    }

    @Throws(FileNotFoundException::class)
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        VeLog.d(TAG) { "openFile called (uri=$uri, mode=$mode)" }
        val parcelMode = try {
            ParcelFileDescriptor.parseMode(mode)
        } catch (e: IllegalArgumentException) {
            throw FileNotFoundException("Invalid mode: $mode")
        }
        if (parcelMode != ParcelFileDescriptor.MODE_READ_ONLY) {
            throw SecurityException("ContainerShareProvider is read-only")
        }

        val doc = DocumentId.parse(docIdOf(uri), "share document")
        val volId = doc.volId
        val session = ContainerFileSystem.requireSession(volId)
        val fatPath = doc.fatPath

        val storageManager = context?.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            ?: throw FileNotFoundException("Could not obtain StorageManager")

        val handlerThread = HandlerThread("vc_share_proxy_${volId}_${System.nanoTime()}").apply { start() }
        val handler = Handler(handlerThread.looper)
        val callback = ContainerProxyCallback(context, volId, session, fatPath, isWrite = false, handlerThread)

        return try {
            storageManager.openProxyFileDescriptor(parcelMode, callback, handler)
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "openProxyFileDescriptor failed for $fatPath: ${e.message}" }
            handlerThread.quitSafely()
            throw FileNotFoundException("Failed to open proxy file descriptor: ${e.message}")
        }
    }

    @Throws(FileNotFoundException::class)
    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        val pfd = openFile(uri, mode)
        val doc = try {
            DocumentId.parse(docIdOf(uri), "share document")
        } catch (_: Exception) {
            return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
        }
        val size = try {
            ContainerFileSystem.getFileSize(doc.volId, doc.fatPath).coerceAtLeast(0L)
        } catch (_: Exception) {
            AssetFileDescriptor.UNKNOWN_LENGTH
        }
        val length = if (size > 0L) size else AssetFileDescriptor.UNKNOWN_LENGTH
        return AssetFileDescriptor(pfd, 0, length)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
