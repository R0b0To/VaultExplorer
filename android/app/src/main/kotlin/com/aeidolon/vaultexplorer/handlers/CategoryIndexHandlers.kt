package com.aeidolon.vaultexplorer.handlers

import android.content.ContentResolver
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import com.aeidolon.vaultexplorer.DirEntryWire
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Paths
import java.nio.file.attribute.BasicFileAttributes
import java.util.concurrent.ExecutorService

/**
 * Answers "which files of this kind are under this folder?" for the category
 * and gallery views of plain phone storage from MediaStore, Android's own
 * file index, in one query -- instead of the Dart side walking every folder
 * to find them.
 *
 * MediaStore is used only as a list of *candidate paths*. Each candidate is
 * confirmed with a single `stat`, and its size and date come from the file
 * itself, so a row left behind by a file that was deleted (or never finished
 * being written) is dropped and what is returned agrees with what a walk
 * would have reported. A directory, a symbolic link or anything else that is
 * not a regular file is dropped too.
 *
 * Answers only on Android 11+. Before that, the index is not kept in step
 * with files written through plain file APIs, so a result could silently miss
 * recent files; the call then answers null and the Dart side walks.
 *
 * Reply: `{"entries": [wire entries relative to rootPath], "truncated": bool}`
 * (wire format: see [DirEntryWire]), or null when the index cannot be used.
 * Any failure is also null, never an error: the Dart side treats null as
 * "walk instead".
 */
class CategoryIndexHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    companion object {
        private const val TAG = "CategoryIndexHandlers"
        private const val DEFAULT_LIMIT = 50_000
        private const val MAX_LIMIT = 200_000
        private const val DATA_COLUMN = MediaStore.Files.FileColumns.DATA
    }

    fun handleQueryCategoryIndex(call: MethodCall, result: MethodChannel.Result) {
        val rootPath = call.argument<String>("rootPath")
        val extensions = call.argument<List<String>>("extensions")
        val limit = (call.argument<Number>("limit")?.toInt() ?: DEFAULT_LIMIT).coerceIn(1, MAX_LIMIT)
        if (rootPath.isNullOrEmpty() || extensions == null) {
            result.error("INVALID_ARGS", "rootPath and extensions are required", null)
            return
        }
        ioExecutor.execute {
            val response: Map<String, Any>? = try {
                query(rootPath, extensions, limit)
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "category index query failed: ${e.message}" }
                null
            }
            activity.runOnUiThread { result.success(response) }
        }
    }

    private fun query(rootPath: String, rawExtensions: List<String>, limit: Int): Map<String, Any>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val extensions = CategoryIndexQuery.sanitizeExtensions(rawExtensions)
        if (extensions.isEmpty()) return mapOf("entries" to emptyList<String>(), "truncated" to false)

        val root = canonicalRoot(rootPath)
        val args = Bundle().apply {
            putString(
                ContentResolver.QUERY_ARG_SQL_SELECTION,
                CategoryIndexQuery.selection(DATA_COLUMN, extensions.size),
            )
            putStringArray(
                ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
                CategoryIndexQuery.selectionArgs(root, extensions),
            )
        }

        val entries = ArrayList<String>()
        var truncated = false
        val cursor = activity.contentResolver.query(
            MediaStore.Files.getContentUri("external"),
            arrayOf(DATA_COLUMN),
            args,
            null,
        ) ?: return null
        cursor.use {
            val dataIndex = it.getColumnIndexOrThrow(DATA_COLUMN)
            while (it.moveToNext()) {
                val path = it.getString(dataIndex) ?: continue
                val relative = CategoryIndexQuery.relativePath(root, path) ?: continue
                val attrs = regularFileAttributes(path) ?: continue
                if (entries.size >= limit) {
                    truncated = true
                    break
                }
                entries.add(
                    DirEntryWire.encode(
                        name = relative,
                        isDir = false,
                        sizeBytes = attrs.size(),
                        mtimeUnixSecs = attrs.lastModifiedTime().toMillis() / 1000,
                    ),
                )
            }
        }
        return mapOf("entries" to entries, "truncated" to truncated)
    }

    /**
     * [path]'s attributes if it is a regular file that exists right now, else
     * null. Symbolic links are not followed, like the Dart-side walk, which
     * ignores them.
     */
    private fun regularFileAttributes(path: String): BasicFileAttributes? =
        try {
            Files.readAttributes(Paths.get(path), BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS)
                .takeIf { it.isRegularFile }
        } catch (e: IOException) {
            null
        } catch (e: RuntimeException) {
            // An odd path (InvalidPathException) or a denied read.
            null
        }

    /** [rootPath] with symbolic links resolved (`/sdcard` -> `/storage/emulated/0`), as MediaStore spells paths. */
    private fun canonicalRoot(rootPath: String): String =
        try {
            File(rootPath).canonicalPath
        } catch (e: IOException) {
            rootPath
        }
}
