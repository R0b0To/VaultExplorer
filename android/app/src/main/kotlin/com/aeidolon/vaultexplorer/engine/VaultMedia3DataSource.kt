package com.aeidolon.vaultexplorer.engine

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import com.aeidolon.vaultexplorer.ContainerFileSystem

/**
 * Media3 [BaseDataSource] that reads decrypted bytes directly from the C++
 * filesystem layer via [ContainerFileSystem], bypassing SAF/ContentProvider
 * IPC entirely.
 *
 * Uses the streaming API ([ContainerFileSystem.openStream] /
 * [ContainerFileSystem.readStream] / [ContainerFileSystem.closeStream]) for
 * reads. This matches the hot-path optimization already present in the C++
 * layer: [fsReadStream] skips [ensureMounted()] on every call because a
 * stream handle can only exist if the volume was already mounted
 * successfully. Thread safety is provided by [ContainerFileSystem]'s
 * per-volume [ReentrantReadWriteLock].
 *
 * ExoPlayer's [ProgressiveMediaSource] calls [open], then pumps [read] until
 * EOF or a seek triggers [close] + re-[open] at a new position. The C++
 * stream's [fsReadStream] already accepts an explicit offset per call, so we
 * don't need to close/reopen the stream for seeks within the same open —
 * we simply update [readPosition].
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class VaultMedia3DataSource(
    private val volId: Int,
    private val filePath: String,
) : BaseDataSource(/* isNetwork= */ false) {

    private var streamPtr: Long = 0L
    private var fileSize: Long = C.LENGTH_UNSET.toLong()
    private var readPosition: Long = 0L
    private var bytesRemaining: Long = 0L
    private var opened: Boolean = false

    override fun open(dataSpec: DataSpec): Long {
        transferInitializing(dataSpec)

        fileSize = ContainerFileSystem.getFileSize(volId, filePath)
        if (fileSize < 0) fileSize = 0L

        streamPtr = ContainerFileSystem.openStream(volId, filePath)
        if (streamPtr == 0L) {
            throw java.io.IOException("Failed to open native stream for $filePath (volId=$volId)")
        }

        readPosition = dataSpec.position
        bytesRemaining = if (dataSpec.length != C.LENGTH_UNSET.toLong()) {
            dataSpec.length
        } else {
            fileSize - readPosition
        }
        if (bytesRemaining < 0) bytesRemaining = 0

        opened = true
        transferStarted(dataSpec)
        return bytesRemaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (bytesRemaining <= 0) return C.RESULT_END_OF_INPUT

        val toRead = minOf(length.toLong(), bytesRemaining).toInt()

        // Read directly into ExoPlayer's buffer at the specified offset.
        // ContainerFileSystem.readStream wraps the call with withReadLock.
        val bytesRead = ContainerFileSystem.readStream(
            volId, streamPtr, readPosition, buffer, toRead, offset
        )
        if (bytesRead <= 0) return C.RESULT_END_OF_INPUT

        readPosition += bytesRead
        bytesRemaining -= bytesRead
        bytesTransferred(bytesRead)
        return bytesRead
    }

    override fun getUri(): Uri? {
        return if (opened) Uri.parse("vault://$volId/$filePath") else null
    }

    override fun close() {
        if (streamPtr != 0L) {
            try {
                ContainerFileSystem.closeStream(volId, streamPtr)
            } catch (_: Exception) {
                // Best-effort close; stream may already be invalid if the
                // container was locked while playback was active.
            }
            streamPtr = 0L
        }
        if (opened) {
            opened = false
            transferEnded()
        }
    }
}
