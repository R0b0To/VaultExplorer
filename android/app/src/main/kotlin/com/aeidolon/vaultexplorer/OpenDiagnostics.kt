package com.aeidolon.vaultexplorer

import android.os.Build
import android.os.Environment
import android.os.Process
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import java.io.File
import java.io.FileDescriptor
import java.util.concurrent.atomic.AtomicInteger

/**
 * Privacy-safe facts about how a container file was opened, for always-on
 * ([VeLog.diag]) log lines.
 *
 * "Container opens and lists fine, but every write fails" cannot be told apart
 * from the exported log without these: which route opened the file, whether the
 * descriptor is really read-write, who owns the file relative to this app, and
 * whether All files access is actually granted. Nothing here ever returns a
 * path, a file name or an exception message (those carry full paths).
 */
internal object OpenDiagnostics {

    // Whitelist, not a pattern: a loose "E[A-Z]+" would also match a file named EXAMPLE.hc.
    private val errnoNames = Regex(
        """\b(EACCES|EPERM|EROFS|ENOENT|EIO|EBADF|EISDIR|ENOSPC|EFBIG|EDQUOT|EBUSY|ENODEV|ENXIO|""" +
            """ESTALE|ETXTBSY|EINVAL|EMFILE|ENFILE|ESPIPE|EOPNOTSUPP|ENOTSUP|ENOSYS|EAGAIN)\b"""
    )

    /**
     * "ExceptionClass/ERRNO" for a failed open or write, e.g. "FileNotFoundException/EACCES".
     * The errno comes from [ErrnoException] when available, else from a whitelisted
     * token in the message. The message itself is never included.
     */
    fun failureTag(e: Throwable): String {
        val errno: String? = if (e is ErrnoException) {
            OsConstants.errnoName(e.errno)
        } else {
            errnoNames.find(e.message.orEmpty())?.value
        }
        val cls = e.javaClass.simpleName
        return if (errno != null) "$cls/$errno" else cls
    }

    /** True for the first few calls on [counter], then only for powers of two (8, 16, ...). */
    fun shouldLogOccurrence(counter: AtomicInteger): Boolean {
        val n = counter.incrementAndGet()
        return n <= 5 || (n and (n - 1)) == 0
    }

    /** "RDONLY", "WRONLY", "RDWR", or "?" when the descriptor cannot be queried. */
    fun fdAccess(fd: FileDescriptor): String = try {
        when (Os.fcntlInt(fd, OsConstants.F_GETFL, 0) and OsConstants.O_ACCMODE) {
            OsConstants.O_RDONLY -> "RDONLY"
            OsConstants.O_WRONLY -> "WRONLY"
            OsConstants.O_RDWR -> "RDWR"
            else -> "?"
        }
    } catch (_: Exception) {
        "?"
    }

    /** `uid=10234(self|other) mode=660 size=...` for an open descriptor or, failing that, a file. */
    fun ownership(fd: FileDescriptor?, file: File?): String {
        val st: StructStat = try {
            when {
                fd != null -> Os.fstat(fd)
                file != null -> Os.stat(file.path)
                else -> return "stat=none"
            }
        } catch (e: Exception) {
            return "stat=" + failureTag(e)
        }
        val self = Process.myUid()
        val who = if (st.st_uid == self) "self" else "other"
        return "uid=${st.st_uid}($who) appUid=$self mode=${Integer.toOctalString(st.st_mode and 0xFFF)}"
    }

    /** "true" / "false" from API 30, "n/a" before it (All files access does not exist there). */
    fun allFilesAccess(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager().toString() else "n/a"

    /**
     * One always-on line describing how a container was opened. Never throws.
     *
     * @param route "raw-fd" (direct path open), "saf-direct" (provider descriptor) or "proxy"
     *              (SplitFuseCallback in between).
     */
    fun logOpenSnapshot(
        tag: String,
        route: String,
        scheme: String?,
        authority: String?,
        partCount: Int,
        requestedReadOnly: Boolean,
        effectiveReadOnly: Boolean,
        readOnlyReason: String?,
        fd: FileDescriptor?,
        file: File?,
        note: String? = null,
    ) {
        try {
            VeLog.diag(tag) {
                "open snapshot: route=$route scheme=${scheme ?: "-"} authority=${authority ?: "-"} parts=$partCount " +
                    "requestedRO=$requestedReadOnly effectiveRO=$effectiveReadOnly reason=${readOnlyReason ?: "-"} " +
                    "fdAccess=${if (fd != null) fdAccess(fd) else "n/a"} ${ownership(fd, file)} " +
                    "allFilesAccess=${allFilesAccess()} sdk=${Build.VERSION.SDK_INT}" +
                    (if (note != null) " note=$note" else "")
            }
        } catch (_: Exception) {
            // Diagnostics must never break an unlock.
        }
    }
}
