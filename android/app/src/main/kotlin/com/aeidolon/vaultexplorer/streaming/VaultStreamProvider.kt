package com.aeidolon.vaultexplorer.streaming

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.saf.VaultPathUtils
import java.io.FileNotFoundException
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Zero-disk streaming ContentProvider for decrypted container files.
 *
 * Serves decrypted bytes directly into an in-memory [ParcelFileDescriptor] pipe
 * upon request by external authorized consumers (such as Termux, SAF consumers, etc.).
 *
 * Data Flow & Memory Bound:
 * - Chunk-by-chunk C++ decryption (64 KB) directly written to the pipe.
 * - Kernel pipe backpressure naturally throttles decryption if the consumer reads slowly.
 * - Memory footprint is bounded to ~64-128 KB regardless of file size (multi-gigabyte safe).
 * - Zero plaintext data is cached, staged, or written to flash storage.
 *
 * Security:
 * - `exported="false"`, `grantUriPermissions="true"`.
 * - Ephemeral, 128-bit cryptographically secure random session tokens.
 * - Single-use consumption (marked consumed upon first `openFile`).
 * - Hard timeout (5 minutes default) after which unconsumed sessions expire.
 * - Maximum concurrent active streams bounded to prevent thread/resource exhaustion.
 */
class VaultStreamProvider : ContentProvider() {

    companion object {
        private const val TAG = "VaultStreamProvider"
        const val AUTHORITY = "com.aeidolon.vaultexplorer.stream"
        private const val STREAM_TIMEOUT_MS = 300_000L // 5 minutes
        private const val MAX_CONCURRENT_STREAMS = 8
        private const val CHUNK_SIZE = 64 * 1024       // 64 KB per chunk

        private val streamExecutor = Executors.newCachedThreadPool()
        private val secureRandom = SecureRandom()

        data class StreamSession(
            val volId: Int,
            val vaultPath: String,
            val fileSize: Long,
            val displayName: String,
            val mimeType: String,
            val createdAt: Long,
            @Volatile var consumed: Boolean = false,
        )

        private val activeSessions = ConcurrentHashMap<String, StreamSession>()

        /**
         * Registers a new zero-disk streaming session for [vaultPath] inside [volId].
         * Returns an ephemeral content URI if successful, or null if capacity exceeded.
         */
        fun registerStream(volId: Int, vaultPath: String): Uri? {
            purgeExpired()
            if (activeSessions.size >= MAX_CONCURRENT_STREAMS) {
                VeLog.w(TAG) { "Max concurrent streams ($MAX_CONCURRENT_STREAMS) reached" }
                return null
            }

            val size = ContainerFileSystem.getFileSize(volId, vaultPath)
            if (size < 0) {
                VeLog.w(TAG) { "Cannot stream non-existent file: $vaultPath in volId=$volId" }
                return null
            }

            val displayName = VaultPathUtils.nameOf(VaultPathUtils.normalize(vaultPath))
            val mimeType = MimeTypeHelper.getMimeType(displayName) ?: "application/octet-stream"

            val tokenBytes = ByteArray(16)
            secureRandom.nextBytes(tokenBytes)
            val token = tokenBytes.joinToString("") { "%02x".format(it) }

            val session = StreamSession(
                volId = volId,
                vaultPath = vaultPath,
                fileSize = size,
                displayName = displayName,
                mimeType = mimeType,
                createdAt = System.currentTimeMillis(),
            )
            activeSessions[token] = session

            return Uri.parse("content://$AUTHORITY/stream/$token")
        }

        fun purgeExpired() {
            val now = System.currentTimeMillis()
            val iterator = activeSessions.entries.iterator()
            while (iterator.hasNext()) {
                val entry = iterator.next()
                if (now - entry.value.createdAt > STREAM_TIMEOUT_MS) {
                    iterator.remove()
                }
            }
        }

        fun getActiveSessionCount(): Int = activeSessions.size

        fun clearAllSessions() {
            activeSessions.clear()
        }
    }

    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") {
            throw SecurityException("VaultStreamProvider only supports read mode ('r')")
        }

        val token = uri.lastPathSegment
            ?: throw FileNotFoundException("Invalid stream URI: missing token")

        val session = activeSessions[token]
            ?: throw FileNotFoundException("Stream session not found or already consumed")

        if (session.consumed) {
            throw FileNotFoundException("Stream session already consumed")
        }

        if (System.currentTimeMillis() - session.createdAt > STREAM_TIMEOUT_MS) {
            activeSessions.remove(token)
            throw FileNotFoundException("Stream session has expired")
        }

        session.consumed = true

        val pipe = ParcelFileDescriptor.createPipe()
        val readEnd = pipe[0]
        val writeEnd = pipe[1]

        streamExecutor.execute {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(writeEnd).use { out ->
                    var offset = 0L
                    val totalSize = session.fileSize
                    while (offset < totalSize) {
                        val remaining = (totalSize - offset).coerceAtMost(CHUNK_SIZE.toLong()).toInt()
                        val chunk = ContainerFileSystem.readFileChunk(
                            session.volId,
                            session.vaultPath,
                            offset,
                            remaining
                        ) ?: break
                        if (chunk.isEmpty()) break
                        out.write(chunk)
                        offset += chunk.size
                    }
                    out.flush()
                }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "Streaming pipe interrupted for ${session.vaultPath}" }
                runCatching { writeEnd.close() }
            } finally {
                activeSessions.remove(token)
            }
        }

        return readEnd
    }

    override fun getType(uri: Uri): String? {
        val token = uri.lastPathSegment ?: return null
        return activeSessions[token]?.mimeType ?: "application/octet-stream"
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val token = uri.lastPathSegment
            ?: throw FileNotFoundException("Invalid stream URI")
        val session = activeSessions[token]
            ?: throw FileNotFoundException("Stream session not found")

        val cols = projection ?: arrayOf(
            OpenableColumns.DISPLAY_NAME,
            OpenableColumns.SIZE
        )
        val cursor = MatrixCursor(cols, 1)
        val row = cursor.newRow()
        for (col in cols) {
            when (col) {
                OpenableColumns.DISPLAY_NAME -> row.add(session.displayName)
                OpenableColumns.SIZE -> row.add(session.fileSize)
                else -> row.add(null)
            }
        }
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException("Insert not supported on VaultStreamProvider")

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException("Update not supported on VaultStreamProvider")

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException("Delete not supported on VaultStreamProvider")
}
