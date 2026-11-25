package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.looksLikeRwModeUnsupported
import java.io.FileNotFoundException

/**
 * What [SafContainerProbe.open] decided for a single-file SAF container.
 */
internal sealed interface SafContainerAccess {
    /**
     * The provider's own descriptor is a plain seekable file and can be handed
     * to the native layer as is, with no proxy in between. [writable] is false
     * when read-write was requested but the provider refused it (typically a
     * read-only SAF grant); the caller must then mount the container read-only
     * instead of letting every later write fail.
     */
    class Direct(val pfd: ParcelFileDescriptor, val writable: Boolean) : SafContainerAccess

    /**
     * The provider cannot give out a seekable regular file (cloud / network
     * providers), so the caller keeps using SplitFuseCallback. [writeDenied]
     * is true when the provider explicitly refused write access, in which case
     * the proxy must be opened read-only as well.
     */
    class NeedsProxy(val reason: String, val writeDenied: Boolean) : SafContainerAccess
}

internal enum class OpenFailureKind { PERMISSION_DENIED, UNSUPPORTED_MODE, OTHER }

/**
 * Classifies an exception thrown by ContentResolver.openFileDescriptor.
 * Kept free of Android types so it can be unit-tested on the JVM.
 *
 * SecurityException is what a DocumentsProvider throws when the caller's URI
 * grant lacks the requested mode; local providers can also surface the errno
 * text inside a FileNotFoundException.
 */
internal fun classifyOpenFailure(e: Throwable): OpenFailureKind {
    if (e is SecurityException) return OpenFailureKind.PERMISSION_DENIED
    if (looksLikeRwModeUnsupported(e)) return OpenFailureKind.UNSUPPORTED_MODE
    if (e is FileNotFoundException) {
        val msg = e.message.orEmpty()
        if (msg.contains("EACCES") ||
            msg.contains("EPERM") ||
            msg.contains("EROFS") ||
            msg.contains("permission denied", ignoreCase = true) ||
            msg.contains("read-only file system", ignoreCase = true)
        ) {
            return OpenFailureKind.PERMISSION_DENIED
        }
    }
    return OpenFailureKind.OTHER
}

/**
 * Decides how a content:// container is opened.
 *
 * The native block layer wants a seekable descriptor it can pread/pwrite. Most
 * local providers (ExternalStorageProvider, Downloads, MediaProvider) hand out
 * exactly that, so the descriptor can be used directly. Only providers that cannot (cloud / network
 * backed) need SplitFuseCallback and its staging logic.
 *
 * The probe is deliberately non-destructive: it never writes to the file.
 * Writability is taken from the access mode the provider actually opened the
 * descriptor with (fcntl F_GETFL), not from a trial write, because a trial
 * write would touch the container's modification time on every unlock and
 * could trigger a re-upload on sync-backed providers.
 */
internal object SafContainerProbe {
    private const val TAG = "SafContainerProbe"

    private enum class Check { OK, NOT_RANDOM_ACCESS, WRITE_NOT_ALLOWED }

    fun open(context: Context, uri: Uri, wantWrite: Boolean, label: String): SafContainerAccess {
        val resolver = context.contentResolver
        var writeDenied = false

        if (wantWrite) {
            val rw: ParcelFileDescriptor? = try {
                resolver.openFileDescriptor(uri, "rw")
            } catch (e: Exception) {
                when (classifyOpenFailure(e)) {
                    OpenFailureKind.PERMISSION_DENIED -> {
                        writeDenied = true
                        VeLog.w(TAG, e) { "Provider refused rw for $label; will mount read-only" }
                        null
                    }
                    OpenFailureKind.UNSUPPORTED_MODE ->
                        return SafContainerAccess.NeedsProxy("provider does not support rw: ${e.message}", false)
                    OpenFailureKind.OTHER ->
                        return SafContainerAccess.NeedsProxy(
                            "rw open failed: ${e.javaClass.simpleName}: ${e.message}", false,
                        )
                }
            }

            if (rw != null) {
                when (checkRandomAccess(rw, requireWrite = true)) {
                    Check.OK -> return SafContainerAccess.Direct(rw, writable = true)
                    Check.WRITE_NOT_ALLOWED -> {
                        closeQuietly(rw)
                        writeDenied = true
                        VeLog.w(TAG) { "rw descriptor for $label is not opened for writing; will mount read-only" }
                    }
                    Check.NOT_RANDOM_ACCESS -> {
                        closeQuietly(rw)
                        return SafContainerAccess.NeedsProxy("provider descriptor is not a seekable regular file", false)
                    }
                }
            } else if (!writeDenied) {
                return SafContainerAccess.NeedsProxy("provider returned no descriptor for rw", false)
            }
        }

        val ro: ParcelFileDescriptor = try {
            resolver.openFileDescriptor(uri, "r")
        } catch (e: Exception) {
            return SafContainerAccess.NeedsProxy("r open failed: ${e.javaClass.simpleName}: ${e.message}", writeDenied)
        } ?: return SafContainerAccess.NeedsProxy("provider returned no descriptor for r", writeDenied)

        return if (checkRandomAccess(ro, requireWrite = false) == Check.OK) {
            SafContainerAccess.Direct(ro, writable = false)
        } else {
            closeQuietly(ro)
            SafContainerAccess.NeedsProxy("provider descriptor is not a seekable regular file", writeDenied)
        }
    }

    private fun checkRandomAccess(pfd: ParcelFileDescriptor, requireWrite: Boolean): Check {
        val fd = pfd.fileDescriptor
        return try {
            val st = Os.fstat(fd)
            // Pipes, sockets and size-less descriptors (streamed cloud
            // documents) cannot be used for block I/O; the proxy knows the
            // size from the provider's metadata instead.
            if (!OsConstants.S_ISREG(st.st_mode) || st.st_size <= 0L) return Check.NOT_RANDOM_ACCESS
            Os.lseek(fd, 0L, OsConstants.SEEK_CUR)
            if (Os.pread(fd, ByteArray(1), 0, 1, 0L) != 1) return Check.NOT_RANDOM_ACCESS
            if (requireWrite) {
                val accessMode = Os.fcntlInt(fd, OsConstants.F_GETFL, 0) and OsConstants.O_ACCMODE
                if (accessMode != OsConstants.O_RDWR) return Check.WRITE_NOT_ALLOWED
            }
            Check.OK
        } catch (_: ErrnoException) {
            Check.NOT_RANDOM_ACCESS
        } catch (_: Exception) {
            Check.NOT_RANDOM_ACCESS
        }
    }

    private fun closeQuietly(pfd: ParcelFileDescriptor) {
        try { pfd.close() } catch (_: Exception) {}
    }
}
