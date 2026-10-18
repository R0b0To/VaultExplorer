package com.aeidolon.vaultexplorer.share

import android.content.Context
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import com.aeidolon.vaultexplorer.DirEntryWire
import com.aeidolon.vaultexplorer.container.FolderZipWriter
import java.io.FileInputStream
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * [FolderZipWriter.Source] over a Storage Access Framework tree -- SD cards,
 * USB storage and document providers the user granted a folder from.
 *
 * Deliberately does *not* go through `SafStorageManager`'s path-based
 * helpers. Those resolve a relative path to a document id by matching names
 * case-insensitively and swallow provider errors into an empty listing --
 * fine for browsing, but for an archive an empty-looking listing would
 * silently drop a whole subfolder. Here the only path -> id lookups are for
 * paths this class itself handed out from a listing, every child is
 * addressed by the exact document id its provider reported, and any provider
 * failure throws.
 *
 * The writer builds child paths itself (`"$dir/$name"`), so [docIds] records
 * the id of every entry each listing returns; [rootPath] is the writer's
 * root and [rootDocId] its id, resolved by the caller from the same listing
 * the user just picked the folder from. Two siblings with the same display
 * name (a cloud provider allows it) make the zip fail loudly with a
 * duplicate-entry error rather than silently keeping one.
 *
 * Files are read front to back, which is all the writer asks for, so cloud
 * providers that hand out a non-seekable descriptor work too; for those the
 * size is [FolderZipWriter.UNKNOWN_SIZE] and the archive reads to end of
 * stream.
 */
class SafFolderSource(
    private val context: Context,
    private val treeUri: Uri,
    rootPath: String,
    rootDocId: String,
) : FolderZipWriter.Source {

    private companion object {
        val PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )

        // A cloud provider may answer a listing with "still loading"; wait
        // for it rather than archive the partial (often empty) first answer.
        const val LOADING_WAIT_MS = 8_000L
    }

    private val docIds = HashMap<String, String>().apply { put(rootPath.trimEnd('/'), rootDocId) }

    override fun list(dirPath: String): Array<String>? {
        val parentId = docIds[dirPath] ?: return null
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val lines = ArrayList<String>()
        queryChildren(childrenUri).use { c ->
            val idIdx = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIdx = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIdx = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            val modIdx = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (c.moveToNext()) {
                // A row we can't identify can't be archived; skipping it would
                // quietly hand over an incomplete folder.
                val id = c.getString(idIdx) ?: throw IOException("Storage provider returned an unidentifiable entry")
                val name = c.getString(nameIdx) ?: throw IOException("Storage provider returned an unnamed entry")
                val isDir = c.getString(mimeIdx) == DocumentsContract.Document.MIME_TYPE_DIR
                val size = if (c.isNull(sizeIdx)) 0L else c.getLong(sizeIdx)
                val modMs = if (c.isNull(modIdx)) 0L else c.getLong(modIdx)
                docIds["$dirPath/$name"] = id
                lines.add(DirEntryWire.encode(name, isDir, if (isDir) 0L else size, modMs / 1000L))
            }
        }
        return lines.toTypedArray()
    }

    override fun openFile(path: String): FolderZipWriter.FileReader {
        val docId = docIds[path] ?: throw IOException("Unknown file in shared folder")
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        val pfd = try {
            context.contentResolver.openFileDescriptor(docUri, "r")
        } catch (e: Exception) {
            throw IOException("Could not open a file to archive", e)
        } ?: throw IOException("Could not open a file to archive")

        val input = FileInputStream(pfd.fileDescriptor)
        // statSize is -1 for anything that isn't a regular file (pipes,
        // sockets) -- exactly the "provider can't say" case.
        val fileLength = pfd.statSize.let { if (it >= 0) it else FolderZipWriter.UNKNOWN_SIZE }
        var position = 0L
        return object : FolderZipWriter.FileReader {
            override val size: Long = fileLength

            override fun read(offset: Long, buffer: ByteArray, length: Int): Int {
                // Streams can't seek; the writer only reads front to back, so
                // anything else is a bug worth failing on, not papering over.
                if (offset != position) throw IOException("Non-sequential read from a storage provider")
                val n = input.read(buffer, 0, length)
                if (n < 0) return 0
                position += n
                return n
            }

            override fun close() {
                try { input.close() } catch (_: IOException) {}
                try { pfd.close() } catch (_: IOException) {}
            }
        }
    }

    /** Queries [uri], waiting out a provider that reports it is still loading. */
    private fun queryChildren(uri: Uri): Cursor {
        var cursor = rawQuery(uri)
        if (!isLoading(cursor)) return cursor

        val latch = CountDownLatch(1)
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { latch.countDown() }
        }
        try {
            cursor.registerContentObserver(observer)
            latch.await(LOADING_WAIT_MS, TimeUnit.MILLISECONDS)
        } finally {
            runCatching { cursor.unregisterContentObserver(observer) }
            cursor.close()
        }
        cursor = rawQuery(uri)
        if (isLoading(cursor)) {
            cursor.close()
            throw IOException("Storage provider is still loading a folder")
        }
        return cursor
    }

    private fun rawQuery(uri: Uri): Cursor =
        try {
            context.contentResolver.query(uri, PROJECTION, null, null, null)
        } catch (e: Exception) {
            throw IOException("Could not list a folder to share", e)
        } ?: throw IOException("Could not list a folder to share")

    private fun isLoading(cursor: Cursor): Boolean =
        cursor.extras?.getBoolean(DocumentsContract.EXTRA_LOADING, false) == true
}
