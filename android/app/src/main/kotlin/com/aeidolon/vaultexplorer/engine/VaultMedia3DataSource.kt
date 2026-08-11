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
 * Thread-safe with internal 256KB buffering to minimize JNI cross-boundary
 * overhead during high-bitrate 4K video playback.
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

    // 256KB internal buffer to reduce JNI boundary crossing overhead for 4K video reads
    private val bufferSize = 256 * 1024
    private val internalBuffer = ByteArray(bufferSize)
    private var bufferOffset: Long = -1L
    private var bufferLength: Int = 0

    @Synchronized
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

        bufferOffset = -1L
        bufferLength = 0
        opened = true
        transferStarted(dataSpec)
        return bytesRemaining
    }

    @Synchronized
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (bytesRemaining <= 0) return C.RESULT_END_OF_INPUT
        val ptr = streamPtr
        if (ptr == 0L || !opened) return C.RESULT_END_OF_INPUT

        val maxToRead = minOf(length.toLong(), bytesRemaining).toInt()
        var bytesCopied = 0

        while (bytesCopied < maxToRead) {
            val currentPos = readPosition + bytesCopied
            // Serve directly from internal buffer if currentPos is buffered
            if (bufferOffset != -1L && currentPos >= bufferOffset && currentPos < bufferOffset + bufferLength) {
                val bufPos = (currentPos - bufferOffset).toInt()
                val availableInBuf = bufferLength - bufPos
                val chunkToCopy = minOf(maxToRead - bytesCopied, availableInBuf)
                System.arraycopy(internalBuffer, bufPos, buffer, offset + bytesCopied, chunkToCopy)
                bytesCopied += chunkToCopy
            } else {
                // Buffer miss: If request is larger than bufferSize, do direct native read
                if (maxToRead - bytesCopied >= bufferSize) {
                    val readFromNative = ContainerFileSystem.readStream(
                        volId, ptr, currentPos, buffer, maxToRead - bytesCopied, offset + bytesCopied
                    )
                    if (readFromNative <= 0) break
                    bytesCopied += readFromNative
                } else {
                    // Refill internal buffer with up to 256KB block
                    val fetchSize = minOf(bufferSize.toLong(), fileSize - currentPos).toInt()
                    if (fetchSize <= 0) break
                    val readFromNative = ContainerFileSystem.readStream(
                        volId, ptr, currentPos, internalBuffer, fetchSize, 0
                    )
                    if (readFromNative <= 0) break
                    bufferOffset = currentPos
                    bufferLength = readFromNative
                }
            }
        }

        if (bytesCopied <= 0) return C.RESULT_END_OF_INPUT

        readPosition += bytesCopied
        bytesRemaining -= bytesCopied
        bytesTransferred(bytesCopied)
        return bytesCopied
    }

    @Synchronized
    override fun getUri(): Uri? {
        return if (opened) Uri.parse("vault://$volId/$filePath") else null
    }

    @Synchronized
    override fun close() {
        val ptr = streamPtr
        if (ptr != 0L) {
            try {
                ContainerFileSystem.closeStream(volId, ptr)
            } catch (_: Exception) {
                // Best-effort close
            }
            streamPtr = 0L
        }
        bufferOffset = -1L
        bufferLength = 0
        if (opened) {
            opened = false
            transferEnded()
        }
    }
}