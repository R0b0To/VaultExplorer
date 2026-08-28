package com.aeidolon.vaultexplorer.streaming

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.os.storage.StorageManager
import android.provider.OpenableColumns
import android.system.ErrnoException
import android.system.OsConstants
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.saf.VaultPathUtils
import java.io.FileNotFoundException
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap

class VaultStreamProvider : ContentProvider() {
    companion object {
        private const val TAG = "VaultStreamProvider"
        const val AUTHORITY = "com.aeidolon.vaultexplorer.stream"
        private const val STREAM_TIMEOUT_MS = 300_000L // 5 minutes validity
        private const val MAX_CONCURRENT_STREAMS = 16
        private const val READ_CACHE_CAPACITY = 1024 * 1024 // 1 MB in-memory read buffer
        private val secureRandom = SecureRandom()

        data class StreamSession(
            val volId: Int,
            val vaultPath: String,
            val fileSize: Long,
            val displayName: String,
            val mimeType: String,
            val createdAt: Long,
        )

        private val activeSessions = ConcurrentHashMap<String, StreamSession>()

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
            ?: throw FileNotFoundException("Stream session not found or has expired")
        if (System.currentTimeMillis() - session.createdAt > STREAM_TIMEOUT_MS) {
            activeSessions.remove(token)
            throw FileNotFoundException("Stream session has expired")
        }

        val storageManager = context?.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            ?: throw FileNotFoundException("Could not obtain StorageManager")

        val handlerThread = HandlerThread("vault_stream_${session.volId}_${System.nanoTime()}").apply { start() }
        val handler = Handler(handlerThread.looper)

        return try {
            val callback = StreamProxyCallback(session.volId, session.vaultPath, session.fileSize, handlerThread)
            storageManager.openProxyFileDescriptor(
                ParcelFileDescriptor.MODE_READ_ONLY, callback, handler
            )
        } catch (e: Exception) {
            handlerThread.quitSafely()
            VeLog.e(TAG, e) { "Failed to open proxy file descriptor for ${session.vaultPath}" }
            throw FileNotFoundException("Failed to open stream: ${e.message}")
        }
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

    private class StreamProxyCallback(
        private val volId: Int,
        private val vaultPath: String,
        private val fileSize: Long,
        private val handlerThread: HandlerThread,
    ) : ProxyFileDescriptorCallback() {
        private var streamPtr: Long = 0L
        private val readCache = ByteArray(READ_CACHE_CAPACITY)
        private var readCacheOffset: Long = -1L
        private var readCacheLength: Int = 0

        init {
            try {
                ContainerFileSystem.withReadLock(volId) {
                    streamPtr = ContainerFileSystem.openStream(volId, vaultPath)
                }
            } catch (e: Exception) {
                handlerThread.quitSafely()
                throw FileNotFoundException("Stream init failed for $vaultPath: ${e.message}")
            }
        }

        override fun onGetSize(): Long = fileSize

        @Synchronized
        override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
            if (offset >= fileSize || streamPtr == 0L) return 0
            val readSize = minOf(size.toLong(), fileSize - offset).toInt()
            if (readSize <= 0) return 0

            // 1. Check in-memory read cache
            if (offset >= readCacheOffset && offset + readSize <= readCacheOffset + readCacheLength) {
                val relativeOffset = (offset - readCacheOffset).toInt()
                System.arraycopy(readCache, relativeOffset, data, 0, readSize)
                return readSize
            }

            // 2. Buffer ahead if small read
            if (readSize <= READ_CACHE_CAPACITY) {
                val fetchSize = minOf(READ_CACHE_CAPACITY.toLong(), fileSize - offset).toInt()
                val actualRead = ContainerFileSystem.withReadLock(volId) {
                    ContainerFileSystem.readStream(volId, streamPtr, offset, readCache, fetchSize)
                }
                if (actualRead < 0) throw ErrnoException("onRead", OsConstants.EIO)
                readCacheOffset = offset
                readCacheLength = actualRead
                val copySize = minOf(readSize, readCacheLength)
                if (copySize > 0) System.arraycopy(readCache, 0, data, 0, copySize)
                return copySize
            }

            // 3. Direct read for large chunks
            val actualRead = ContainerFileSystem.withReadLock(volId) {
                ContainerFileSystem.readStream(volId, streamPtr, offset, data, readSize)
            }
            if (actualRead < 0) throw ErrnoException("onRead", OsConstants.EIO)
            return actualRead
        }

        override fun onWrite(offset: Long, size: Int, data: ByteArray): Int {
            throw ErrnoException("onWrite", OsConstants.EROFS)
        }

        override fun onFsync() {}

        @Synchronized
        override fun onRelease() {
            try {
                ContainerFileSystem.withReadLock(volId) {
                    if (streamPtr != 0L) {
                        ContainerFileSystem.closeStream(volId, streamPtr)
                        streamPtr = 0L
                    }
                }
            } catch (e: Exception) {
                VeLog.w(TAG, e) { "Failed to close stream for $vaultPath" }
            }
            handlerThread.quitSafely()
        }
    }
}