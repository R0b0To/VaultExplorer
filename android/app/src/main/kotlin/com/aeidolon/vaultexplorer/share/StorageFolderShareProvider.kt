package com.aeidolon.vaultexplorer.share

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.FolderZipWriter
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves a *folder* on device storage -- a plain directory in the decoy's
 * local storage explorer, or a folder inside a Storage Access Framework
 * tree -- as a single `<name>.zip`, so it can go through the system share
 * sheet like any file.
 *
 * Counterpart of [com.aeidolon.vaultexplorer.container.ContainerShareProvider],
 * which does the same for folders inside an unlocked vault. The two split
 * along what they can see: that one reaches decrypted vault content through
 * a live session, this one reaches storage the app already has plain access
 * to. Files on device storage don't need a provider of ours at all (a
 * FileProvider or the SAF document URI already covers them); only the
 * folder case does, because the share sheet can't carry a directory.
 *
 * A plain ContentProvider, deliberately not a DocumentsProvider, for the
 * reason [com.aeidolon.vaultexplorer.container.ContainerShareProvider]'s
 * class doc gives: its URI must not be mistakable for a SAF document URI.
 * Read-only, `exported=false`: only apps handed a specific URI by a share
 * intent can open it, and a URI grant matches that exact URI, so a receiver
 * can't edit one into pointing somewhere else.
 *
 * URI shapes (every dynamic part is a single percent-encoded path segment,
 * and the last segment is the display name so receivers that fall back to
 * `lastPathSegment` still show "Camera.zip"):
 *
 *   `/local/<absolute folder path>/<name>.zip`
 *   `/saf/<tree uri>/<root document id>/<path relative to tree>/<name>.zip`
 *
 * The SAF form carries the root folder's document id, resolved by the share
 * action from the listing the person just picked it from, rather than
 * re-resolving the relative path here -- that lookup matches names
 * case-insensitively (see [SafFolderSource]).
 */
class StorageFolderShareProvider : ContentProvider() {

    companion object {
        private const val TAG = "StorageFolderShare"
        private const val KIND_LOCAL = "local"
        private const val KIND_SAF = "saf"

        fun authority(context: Context): String = "${context.packageName}.foldershare"

        /** URI for sharing the directory at [absolutePath] as a zip, or null if it has no name to archive under. */
        fun buildLocalUri(context: Context, absolutePath: String): Uri? {
            val name = leafName(absolutePath) ?: return null
            return Uri.Builder()
                .scheme("content")
                .authority(authority(context))
                .appendPath(KIND_LOCAL)
                .appendPath(absolutePath)
                .appendPath("$name.zip")
                .build()
        }

        /**
         * URI for sharing the folder at [relativePath] inside [treeUri] as a
         * zip. [rootDocId] is that folder's own document id. Null if
         * [relativePath] is the tree root, which has no name to archive under.
         */
        fun buildSafUri(context: Context, treeUri: Uri, rootDocId: String, relativePath: String): Uri? {
            val name = leafName(relativePath) ?: return null
            return Uri.Builder()
                .scheme("content")
                .authority(authority(context))
                .appendPath(KIND_SAF)
                .appendPath(treeUri.toString())
                .appendPath(rootDocId)
                .appendPath(relativePath.trim('/'))
                .appendPath("$name.zip")
                .build()
        }

        private fun leafName(path: String): String? =
            path.trimEnd('/').substringAfterLast('/').ifEmpty { null }
    }

    private sealed class Target {
        abstract val displayName: String

        data class Local(val path: String, override val displayName: String) : Target()
        data class Saf(
            val treeUri: Uri,
            val rootDocId: String,
            val relativePath: String,
            override val displayName: String,
        ) : Target()
    }

    private fun parse(uri: Uri): Target {
        val seg = uri.pathSegments
        return when {
            seg.size == 3 && seg[0] == KIND_LOCAL -> Target.Local(path = seg[1], displayName = seg[2])
            seg.size == 5 && seg[0] == KIND_SAF -> Target.Saf(
                treeUri = Uri.parse(seg[1]),
                rootDocId = seg[2],
                relativePath = seg[3],
                displayName = seg[4],
            )
            else -> throw FileNotFoundException("Malformed folder share URI")
        }
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
        val target = try {
            parse(uri)
        } catch (e: Exception) {
            return cursor
        }
        val row = cursor.newRow()
        for (col in columns) {
            when (col) {
                OpenableColumns.DISPLAY_NAME -> row.add(target.displayName)
                // The archive is generated while it's read; no length to give.
                OpenableColumns.SIZE -> row.add(null)
                "mime_type" -> row.add("application/zip")
                else -> row.add(null)
            }
        }
        return cursor
    }

    override fun getType(uri: Uri): String = "application/zip"

    override fun getStreamTypes(uri: Uri, mimeTypeFilter: String): Array<String>? =
        if (android.content.ClipDescription.compareMimeTypes("application/zip", mimeTypeFilter)) {
            arrayOf("application/zip")
        } else {
            null
        }

    @Throws(FileNotFoundException::class)
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val parsedMode = try {
            ParcelFileDescriptor.parseMode(mode)
        } catch (e: IllegalArgumentException) {
            throw FileNotFoundException("Invalid mode: $mode")
        }
        if (parsedMode != ParcelFileDescriptor.MODE_READ_ONLY) {
            throw SecurityException("StorageFolderShareProvider is read-only")
        }
        val ctx = context ?: throw FileNotFoundException("No context")

        val (writer, rootPath) = when (val target = parse(uri)) {
            is Target.Local -> {
                if (!File(target.path).isDirectory) throw FileNotFoundException("Folder no longer exists")
                FolderZipWriter(RawFolderSource()) to target.path
            }
            is Target.Saf -> {
                val root = target.relativePath.trim('/')
                if (root.isEmpty()) throw FileNotFoundException("Cannot archive a storage root")
                FolderZipWriter(SafFolderSource(ctx, target.treeUri, root, target.rootDocId)) to root
            }
        }
        VeLog.d(TAG) { "opening folder zip" }
        return FolderZipPipe.open(writer, rootPath, "ve_share_zip_${System.nanoTime()}")
    }

    @Throws(FileNotFoundException::class)
    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? =
        AssetFileDescriptor(openFile(uri, mode), 0, AssetFileDescriptor.UNKNOWN_LENGTH)

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
