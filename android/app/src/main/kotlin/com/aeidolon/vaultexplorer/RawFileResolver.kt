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
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

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

    private const val TAG = "RawFileResolver"

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
     * Raw-path access for a directory-vault root, confirmed by a REAL read
     * rather than inferred from permission state.
     *
     * [getRawFileFromUri] decides from the storage-permission flag plus
     * [File.canRead]/[File.canWrite] -- but those report POSIX mode bits /
     * access(2), not what the kernel or the scoped-storage layer will
     * actually allow on open(2). On some devices and storage states
     * (notably files created through the SAF provider by another uid) the
     * heuristics say "yes" and the very first real open then fails with
     * `EACCES (Permission denied)`, which a directory vault's unlock hits
     * when it reads its config file.
     *
     * So, for a root that [getRawFileFromUri] would hand back as raw, this
     * also opens [sentinelName] (a file every vault of that format has,
     * e.g. `gocryptfs.conf`) and reads one byte. Returns the raw root only
     * if that works; returns null -- meaning "use SAF / the mirror instead"
     * -- when the root is not raw-accessible at all, when the sentinel is
     * absent from the raw view, or when opening it fails.
     *
     * With [probeWrite] (the default) it additionally verifies that a file
     * can be staged and renamed in the root -- see [canStageWrite]. Pass
     * `false` for a read-only open, which must not touch the folder.
     */
    fun getVerifiedRawVaultRoot(
        context: Context,
        vaultRootUri: Uri,
        sentinelName: String,
        probeWrite: Boolean = true,
    ): File? {
        val root = getRawFileFromUri(context, vaultRootUri) ?: return null
        val sentinel = File(root, sentinelName)
        return try {
            if (!sentinel.isFile) {
                VeLog.w(TAG) { "raw view of ${root.absolutePath} has no readable $sentinelName; using SAF instead" }
                null
            } else {
                FileInputStream(sentinel).use { it.read() }
                if (probeWrite && !canStageWrite(root)) {
                    VeLog.w(TAG) { "raw write probe in ${root.absolutePath} failed despite storage permission; using SAF instead" }
                    null
                } else {
                    root
                }
            }
        } catch (e: IOException) {
            VeLog.w(TAG, e) {
                "raw read of $sentinelName in ${root.absolutePath} failed despite storage permission; using SAF instead"
            }
            null
        } catch (e: SecurityException) {
            VeLog.w(TAG, e) {
                "raw read of $sentinelName in ${root.absolutePath} was denied; using SAF instead"
            }
            null
        }
    }

    /**
     * Write-side counterpart of the sentinel read in
     * [getVerifiedRawVaultRoot]: does the same create -> write -> rename ->
     * delete sequence `SafDocumentOps.writeWhole` and the mirror's push use
     * to stage a file next to its target, using a throwaway hidden file in
     * [dir]. A read can succeed where this fails (the mode bits that
     * [File.canWrite] reports say nothing about what open(2)/rename(2) will
     * be allowed to do), and a vault that passes only the read probe would
     * then fail on its first write instead of falling back to SAF.
     *
     * The probe file is removed again before returning. If the process is
     * killed in the middle, a stray `.ve_rawprobe_*` file can be left
     * behind. It is not part of any vault format: gocryptfs's listing skips
     * names it cannot decrypt, and CryFS addresses blocks by computed path
     * rather than by listing the folder, so normal operation never trips
     * over it.
     */
    private fun canStageWrite(dir: File): Boolean {
        val probe = try {
            File.createTempFile(".ve_rawprobe_", ".tmp", dir)
        } catch (e: IOException) {
            VeLog.w(TAG, e) { "could not create a probe file in ${dir.absolutePath}" }
            return false
        } catch (e: SecurityException) {
            VeLog.w(TAG, e) { "creating a probe file in ${dir.absolutePath} was denied" }
            return false
        }
        val renamed = File(dir, probe.name + ".ok")
        return try {
            FileOutputStream(probe).use { it.write(0) }
            probe.renameTo(renamed) && renamed.delete()
        } catch (e: IOException) {
            VeLog.w(TAG, e) { "raw write probe in ${dir.absolutePath} failed: ${e.message}" }
            false
        } catch (e: SecurityException) {
            VeLog.w(TAG, e) { "raw write probe in ${dir.absolutePath} was denied" }
            false
        } finally {
            probe.delete()   // no-op once the rename above has moved it
            renamed.delete() // no-op once the delete above has removed it
        }
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
        return try {
            when {
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
        } catch (_: Throwable) {
            false
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