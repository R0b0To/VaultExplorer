package com.aeidolon.vaultexplorer

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import java.io.File

/**
 * Centralized resolver for raw `java.io.File` paths from SAF URIs.
 *
 * If the user has granted broad storage permission (All Files Access on
 * API 30+, WRITE_EXTERNAL_STORAGE on API 26-29, READ_EXTERNAL_STORAGE on
 * API <= 25) AND the file is on accessible local storage, the raw `File`
 * is resolved and returned for direct POSIX access.
 *
 * If the user has NOT granted storage permission, or if direct raw path
 * access is technically impossible (e.g. USB OTG drives, cloud providers,
 * virtual SAF trees), this returns `null`.  Callers then cleanly and
 * deterministically use SAF + native POSIX file descriptors (`detachFd()`),
 * which gives 100% native kernel throughput via `pread()`/`pwrite()` in C++
 * without throwing exceptions or causing crashes on Android 10+.
 */
object RawFileResolver {

    fun getRawFile(context: Context, documentFile: DocumentFile): File? {
        return getRawFileFromUri(context, documentFile.uri)
    }

    fun getRawFileFromUri(context: Context, uri: Uri): File? {
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            val file = File(path)
            return if (canAccessRawFile(context, file)) file else null
        }

        if (uri.scheme == "content") {
            val auth = uri.authority
            val docId = try {
                android.provider.DocumentsContract.getDocumentId(uri)
            } catch (_: Exception) {
                try {
                    android.provider.DocumentsContract.getTreeDocumentId(uri)
                } catch (_: Exception) {
                    null
                }
            }

            // Relaxed check: any authority that yields a volume:path ID format.
            if (docId != null && docId.contains(":")) {
                val split = docId.split(":", limit = 2)
                if (split.size == 2) {
                    val type = split[0]
                    val relativePath = Uri.decode(split[1])
                    val file = if (type.equals("primary", ignoreCase = true)) {
                        File(Environment.getExternalStorageDirectory(), relativePath)
                    } else {
                        File("/storage/$type", relativePath)
                    }

                    if (canAccessRawFile(context, file)) {
                        return file
                    }
                }
            }

            if (auth == "com.android.providers.downloads.documents" && docId != null) {
                if (docId.startsWith("raw:")) {
                    val rawPath = Uri.decode(docId.substring(4))
                    val file = File(rawPath)
                    if (canAccessRawFile(context, file)) return file
                }
            }
        }

        return null
    }

    /**
     * Checks whether raw `java.io.File` access is actually possible for
     * [file] on the running Android version with the current permissions.
     */
    private fun canAccessRawFile(context: Context, file: File): Boolean {
        // Files inside the app's own private storage directories are always
        // accessible via raw paths, regardless of external storage permissions.
        if (isAppPrivatePath(context, file)) {
            return try {
                if (file.exists()) file.canRead() else {
                    val parent = file.parentFile
                    parent != null && parent.exists() && parent.canWrite()
                }
            } catch (_: Exception) { false }
        }

        // For external storage paths, check appropriate permissions per API level.
        if (!hasExternalStoragePermission(context)) return false

        return try {
            if (file.exists()) {
                file.canRead() && file.canWrite()
            } else {
                val parent = file.parentFile
                parent != null && parent.exists() && parent.canWrite()
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Returns true when the running process has the broad external-storage
     * permission appropriate for the current API level:
     *
     * - **API 30+ (Android 11+)**: `MANAGE_EXTERNAL_STORAGE` ("All Files Access")
     * - **API 29 (Android 10)**: `WRITE_EXTERNAL_STORAGE` runtime permission
     *   (scoped storage is active, but `requestLegacyExternalStorage=true`
     *   in AndroidManifest.xml enables POSIX path access when granted)
     * - **API <= 28**: `READ_EXTERNAL_STORAGE` runtime permission
     */
    fun hasExternalStoragePermission(context: Context): Boolean {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                Environment.isExternalStorageManager()
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                ContextCompat.checkSelfPermission(
                    context, Manifest.permission.WRITE_EXTERNAL_STORAGE
                ) == PackageManager.PERMISSION_GRANTED
            else ->
                ContextCompat.checkSelfPermission(
                    context, Manifest.permission.READ_EXTERNAL_STORAGE
                ) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Returns true when [file] resides inside one of this app's private
     * storage directories (internal `filesDir` or external `Android/data/...`).
     * Raw file access always works in these directories regardless of
     * external storage permission state.
     */
    private fun isAppPrivatePath(context: Context, file: File): Boolean {
        val path = file.absolutePath
        if (path.startsWith(context.filesDir.absolutePath)) return true
        context.getExternalFilesDirs(null).forEach { extDir ->
            if (extDir != null && path.startsWith(extDir.absolutePath)) return true
        }
        return false
    }
}