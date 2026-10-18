package com.aeidolon.vaultexplorer.share

import android.os.ParcelFileDescriptor
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.FolderZipWriter
import java.io.FileNotFoundException
import java.io.IOException

/**
 * Hands a [FolderZipWriter] archive to a ContentProvider client as a plain
 * file descriptor: a background thread writes the zip into a pipe and the
 * read end is what `openFile` returns, so the archive is never staged on
 * disk and the receiver can start consuming immediately.
 *
 * Shared by every provider that serves a folder as a zip
 * ([com.aeidolon.vaultexplorer.container.ContainerShareProvider] for vault
 * folders, [StorageFolderShareProvider] for SAF and device storage) so the
 * failure behavior can't drift between them.
 *
 * A *reliable* pipe is used so that failure reaches the receiver as an error
 * ([ParcelFileDescriptor.closeWithError]) instead of an ordinary
 * end-of-stream. [FolderZipWriter] separately guarantees a failed archive is
 * never finalized, so even a receiver that ignores the error sees a corrupt
 * zip, never a plausible-looking partial one.
 */
object FolderZipPipe {
    private const val TAG = "FolderZipPipe"

    /**
     * Starts writing the archive for [rootPath] and returns the read end.
     *
     * [onFinished] runs exactly once, on whichever thread finishes the work
     * -- including when this function itself fails before the writer thread
     * starts, in which case it runs before the exception is thrown. It is
     * where a caller releases whatever it held for the duration (the vault
     * provider's I/O lease), so callers never need their own cleanup for the
     * failure paths in here.
     */
    @Throws(FileNotFoundException::class)
    fun open(
        writer: FolderZipWriter,
        rootPath: String,
        threadName: String,
        onFinished: () -> Unit = {},
    ): ParcelFileDescriptor {
        val pipe = try {
            ParcelFileDescriptor.createReliablePipe()
        } catch (e: IOException) {
            onFinished()
            throw FileNotFoundException("Could not create a pipe for the folder archive")
        }
        val readSide = pipe[0]
        val writeSide = pipe[1]

        val thread = Thread({
            try {
                val out = ParcelFileDescriptor.AutoCloseOutputStream(writeSide)
                writer.write(rootPath, out)
                out.close()
            } catch (e: FolderZipWriter.AbortedException) {
                VeLog.d(TAG) { "folder share aborted" }
                try { writeSide.closeWithError("Folder share aborted") } catch (_: Exception) {}
            } catch (e: Exception) {
                // Includes the receiver hanging up mid-stream (EPIPE) -- an
                // ordinary cancel, not worth more than a debug line. Paths
                // are left out of the message on purpose.
                VeLog.d(TAG) { "folder share stopped: ${e.javaClass.simpleName}" }
                try { writeSide.closeWithError(e.message ?: "Folder archive failed") } catch (_: Exception) {}
            } finally {
                onFinished()
            }
        }, threadName)
        thread.isDaemon = true
        try {
            thread.start()
        } catch (e: Throwable) {
            try { writeSide.close() } catch (_: Exception) {}
            try { readSide.close() } catch (_: Exception) {}
            onFinished()
            throw FileNotFoundException("Could not start the folder archive")
        }
        return readSide
    }
}
