package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.documentfile.provider.DocumentFile

/**
 * Helpers for deciding whether a destination path can be written via plain
 * [java.io.File] or must go through the SAF [DocumentFile] fallback — the
 * same raw-path-fast-path / SAF-fallback shape used across
 * [SplitJoinHandlers] and [SingleFileCryptoHandlers].
 */
object ScopedStorageUtils {

    /**
     * Returns true when [path] can be written via plain [java.io.File] /
     * [java.io.FileOutputStream] from this process.
     *
     * On API 30+ (scoped storage), a path outside app-private storage
     * requires `MANAGE_EXTERNAL_STORAGE` ("All Files Access") to be writable
     * — [File.canWrite] reflects POSIX permission bits rather than
     * scoped-storage enforcement and cannot be trusted here. On older APIs
     * the permission model is looser, but [java.io.File.mkdirs] can still
     * fail on some external storage paths — callers should treat a false
     * return from mkdirs() as a signal to fall back to SAF even when this
     * function returned true.
     */
    fun canWriteRawPath(context: Context, path: String): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val isAppPrivate =
                path.startsWith(context.filesDir.absolutePath) ||
                    context.getExternalFilesDirs(null)
                        .any { it != null && path.startsWith(it.absolutePath) }
            if (!isAppPrivate && !Environment.isExternalStorageManager()) return false
        }
        return true
    }

    /**
     * Returns true when [path] looks like a SAF content URI rather than a
     * filesystem path — used to detect the cloud-storage fallback where the
     * Dart side passes the tree URI as the [destinationPath] because no
     * local path could be resolved.
     */
    fun isSafUri(path: String): Boolean = path.startsWith("content://")

    /**
     * Resolves [destinationTreeUri] into a writable [DocumentFile], or null
     * when [destinationTreeUri] is absent / not a valid writable directory.
     * Optionally falls back to treating [pathIfTreeUriMissing] itself as a
     * SAF URI when [destinationTreeUri] is null and [pathIfTreeUriMissing]
     * starts with `content://` (the cloud-storage path fallback case).
     */
    fun resolveTreeDoc(
        context: Context,
        destinationTreeUri: String?,
        pathIfTreeUriMissing: String? = null,
    ): DocumentFile? {
        val rawUri = destinationTreeUri
            ?: (if (pathIfTreeUriMissing != null && isSafUri(pathIfTreeUriMissing)) pathIfTreeUriMissing else null)
            ?: return null
        val doc = DocumentFile.fromTreeUri(context, Uri.parse(rawUri)) ?: return null
        return if (doc.isDirectory && doc.canWrite()) doc else null
    }
}
