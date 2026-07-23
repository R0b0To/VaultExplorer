package com.aeidolon.vaultexplorer.engine

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.util.concurrent.ConcurrentHashMap

interface ChunkedEngineDelegate<H> {
    val context: Context
    val readOnly: Boolean
    val cryptor: VaultChunkCryptor<H>

    fun getPhysicalFileForRead(virtualPath: String): DocumentFile?
    fun getOrCreatePhysicalFileForWrite(virtualPath: String): DocumentFile
    fun invalidateCacheAfterWrite(virtualPath: String)
}

class ChunkedFileEngine<H>(private val delegate: ChunkedEngineDelegate<H>) {
    
    private val openWrites = ConcurrentHashMap<String, WriteHandle>()

    private inner class ReadHandle(
        val pfd: android.os.ParcelFileDescriptor?,
        val stream: java.io.InputStream,
        val header: Any,
        var currentPos: Long
    ) {
        var cachedChunkIndex: Long = -1L
        var cachedChunkCleartext: ByteArray? = null

        fun close() {
            try { stream.close() } catch (_: Exception) {}
            try { pfd?.close() } catch (_: Exception) {}
        }
        @Suppress("UNCHECKED_CAST")
        fun typedHeader(): H = header as H
    }

    private val openReads = object : android.util.LruCache<String, ReadHandle>(8) {
        override fun entryRemoved(evicted: Boolean, key: String, oldValue: ReadHandle, newValue: ReadHandle?) {
            oldValue.close()
        }
    }

    fun close() {
        openWrites.values.forEach { it.abort() }
        openWrites.clear()
        openReads.evictAll()
    }

    /**
     * Drops any cached read handle for [virtualPath]. Callers (renameFile,
     * deleteFile) must invoke this whenever a path's underlying physical
     * file is about to change identity or disappear — otherwise a later
     * readFileChunk() could keep reading from a stale, now-dangling
     * ParcelFileDescriptor/InputStream instead of noticing the file moved.
     */
    fun invalidateRead(virtualPath: String) {
        openReads.remove(normalize(virtualPath))
    }

    private fun normalize(path: String): String = path.trim('/')

    // ---- file content read/write ----------------------------------------------

    fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? {
        val normalized = normalize(virtualPath)
        return try {
            val physicalFileProvider = {
                delegate.getPhysicalFileForRead(normalized) ?: throw Exception("Path not found: $normalized")
            }
            readRange(physicalFileProvider, offset, length, normalized)
        } catch (e: Exception) {
            openReads.remove(normalized)
            null
        }
    }

    private fun readRange(resolvePhysicalFile: () -> DocumentFile, offset: Long, length: Int, normalizedPath: String): ByteArray? {
        val cryptor = delegate.cryptor
        val chunkSize = cryptor.cleartextChunkSize
        val cipherChunkSize = cryptor.ciphertextChunkSize
        val headerSize = cryptor.headerSize

        var handle = openReads.get(normalizedPath)

        if (handle == null) {
            val physicalFile = resolvePhysicalFile()
            var pfd: android.os.ParcelFileDescriptor? = null
            var stream: java.io.InputStream? = null
            try {
                pfd = delegate.context.contentResolver.openFileDescriptor(physicalFile.uri, "r")
                if (pfd != null) {
                    stream = java.io.FileInputStream(pfd.fileDescriptor)
                }
            } catch (e: Exception) { }

            if (stream == null) {
                stream = delegate.context.contentResolver.openInputStream(physicalFile.uri)
            }
            if (stream == null) return null

            val headerBytes = ByteArray(headerSize)
            if (readFully(stream, headerBytes) < headerSize) {
                try { stream.close() } catch (_: Exception) {}
                try { pfd?.close() } catch (_: Exception) {}
                return ByteArray(0)
            }
            val header = cryptor.decodeHeader(headerBytes)
            handle = ReadHandle(pfd, stream, header as Any, headerSize.toLong())
            openReads.put(normalizedPath, handle)
        }

        val startChunk = offset / chunkSize
        val endOffsetExclusive = offset + length
        var chunkNumber = startChunk
        var producedSoFar = startChunk * chunkSize
        val out = java.io.ByteArrayOutputStream(length.coerceAtMost(4 * 1024 * 1024))

        while (producedSoFar < endOffsetExclusive) {
            val cleartext: ByteArray
            if (handle!!.cachedChunkIndex == chunkNumber && handle!!.cachedChunkCleartext != null) {
                cleartext = handle!!.cachedChunkCleartext!!
            } else {
                val desiredPos = headerSize.toLong() + chunkNumber * cipherChunkSize
                
                if (handle!!.currentPos != desiredPos) {
                    var positioned = false
                    if (handle!!.pfd != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                        try {
                            android.system.Os.lseek(handle!!.pfd!!.fileDescriptor, desiredPos, android.system.OsConstants.SEEK_SET)
                            handle!!.currentPos = desiredPos
                            positioned = true
                        } catch (e: Exception) {}
                    }
                    if (!positioned && handle!!.stream is java.io.FileInputStream) {
                        try {
                            handle!!.stream.channel.position(desiredPos)
                            handle!!.currentPos = desiredPos
                            positioned = true
                        } catch (e: Exception) {}
                    }
                    if (!positioned) {
                        if (handle!!.currentPos > desiredPos) {
                            openReads.remove(normalizedPath)
                            return readRange(resolvePhysicalFile, offset, length, normalizedPath)
                        } else {
                            var remaining = desiredPos - handle!!.currentPos
                            val skipBuf = ByteArray(64 * 1024)
                            while (remaining > 0L) {
                                val toSkip = minOf(remaining, skipBuf.size.toLong()).toInt()
                                val actuallyRead = handle!!.stream.read(skipBuf, 0, toSkip)
                                if (actuallyRead <= 0) break
                                remaining -= actuallyRead
                                handle!!.currentPos += actuallyRead
                            }
                        }
                    }
                }

                val cipherBuf = ByteArray(cipherChunkSize)
                val n = readFully(handle!!.stream, cipherBuf)
                if (n <= 0) break
                handle!!.currentPos += n
                val actualCiphertext = if (n == cipherBuf.size) cipherBuf else cipherBuf.copyOf(n)
                
                cleartext = cryptor.decryptChunk(actualCiphertext, chunkNumber, handle!!.typedHeader())
                handle!!.cachedChunkIndex = chunkNumber
                handle!!.cachedChunkCleartext = cleartext
            }

            val chunkStart = producedSoFar
            val chunkEnd = chunkStart + cleartext.size
            val wantStart = maxOf(offset, chunkStart)
            val wantEnd = minOf(endOffsetExclusive, chunkEnd)
            if (wantStart < wantEnd) {
                out.write(cleartext, (wantStart - chunkStart).toInt(), (wantEnd - wantStart).toInt())
            }

            producedSoFar = chunkEnd
            chunkNumber += 1
            if (cleartext.size < chunkSize) break // Short chunk means EOF
        }
        return out.toByteArray()
    }



    private fun readFully(stream: java.io.InputStream, buf: ByteArray): Int {
        var total = 0
        while (total < buf.size) {
            val n = stream.read(buf, total, buf.size - total)
            if (n < 0) break
            total += n
        }
        return total
    }

    fun writeBackStream(virtualPath: String, input: java.io.InputStream): Boolean {
        if (delegate.readOnly) return false
        val normalized = normalize(virtualPath)
        openReads.remove(normalized)
        openWrites.remove(normalized)?.abort()

        return try {
            val physicalTarget = delegate.getOrCreatePhysicalFileForWrite(normalized)
            val cryptor = delegate.cryptor
            val header = cryptor.createHeader()
            var nextChunkNumber = 0L

            val rawOut = if (physicalTarget.uri.scheme == "content") {
                delegate.context.contentResolver.openOutputStream(physicalTarget.uri, "w")
            } else {
                java.io.FileOutputStream(File(physicalTarget.uri.path!!))
            } ?: throw Exception("Could not open ${physicalTarget.uri} for writing")

            java.io.BufferedOutputStream(rawOut, 256 * 1024).use { out ->
                out.write(cryptor.encodeHeader(header))

                val chunkSize = cryptor.cleartextChunkSize
                val buf = ByteArray(chunkSize)
                var bytesInBuf = 0

                while (true) {
                    val read = input.read(buf, bytesInBuf, chunkSize - bytesInBuf)
                    if (read <= 0) break
                    bytesInBuf += read

                    if (bytesInBuf == chunkSize) {
                        val encrypted = cryptor.encryptChunk(buf, nextChunkNumber, header)
                        out.write(encrypted)
                        nextChunkNumber++
                        bytesInBuf = 0
                    }
                }

                if (bytesInBuf > 0) {
                    val partial = buf.copyOf(bytesInBuf)
                    val encrypted = cryptor.encryptChunk(partial, nextChunkNumber, header)
                    out.write(encrypted)
                }
                out.flush()
            }
            delegate.invalidateCacheAfterWrite(normalized)
            true
        } catch (e: Exception) {
            android.util.Log.e("ChunkedFileEngine", "writeBackStream failed for $virtualPath", e)
            false
        }
    }

    fun writeFileChunk(virtualPath: String, offset: Long, data: ByteArray): Boolean {
        if (delegate.readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            openReads.remove(normalized)
            val handle = openWrites.getOrPut(normalized) { beginWrite(normalized) }
            if (offset != handle.bytesWrittenSoFar) {
                handle.abort()
                openWrites.remove(normalized)
                return false
            }
            handle.append(data)
            true
        } catch (e: Exception) {
            openWrites.remove(virtualPath)?.abort()
            false
        }
    }

    fun finishWrite(virtualPath: String): Boolean {
        val normalized = normalize(virtualPath)
        openReads.remove(normalized)
        val handle = openWrites.remove(normalized) ?: return true
        return try {
            handle.commit()
            delegate.invalidateCacheAfterWrite(normalized)
            true
        } catch (e: Exception) {
            handle.abort()
            false
        }
    }

    fun writeBackFile(virtualPath: String, sourcePath: String): Boolean {
        if (delegate.readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            openReads.remove(normalized)
            openWrites.remove(normalized)?.abort()
            val handle = beginWrite(normalized)
            File(sourcePath).inputStream().use { input ->
                val buf = ByteArray(delegate.cryptor.cleartextChunkSize)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    handle.append(if (n == buf.size) buf else buf.copyOf(n))
                }
            }
            handle.commit()
            delegate.invalidateCacheAfterWrite(normalized)
            true
       } catch (e: Exception) {
            android.util.Log.e("ChunkedFileEngine", "writeBackFile failed for $virtualPath", e)
            false
        }
    }

    fun extractFile(virtualPath: String, destinationPath: String): Boolean {
        return try {
            val physicalFile = delegate.getPhysicalFileForRead(normalize(virtualPath)) ?: return false
            File(destinationPath).outputStream().use { out ->
                delegate.context.contentResolver.openInputStream(physicalFile.uri)?.use { rawStream ->
                    val cryptor = delegate.cryptor
                    val headerBytes = ByteArray(cryptor.headerSize)
                    if (readFully(rawStream, headerBytes) < cryptor.headerSize) return true
                    val header = cryptor.decodeHeader(headerBytes)
                    var chunkNumber = 0L
                    val cipherBuf = ByteArray(cryptor.ciphertextChunkSize)
                    while (true) {
                        val n = readFully(rawStream, cipherBuf)
                        if (n <= 0) break
                        val actual = if (n == cipherBuf.size) cipherBuf else cipherBuf.copyOf(n)
                        val cleartext = cryptor.decryptChunk(actual, chunkNumber, header)
                        out.write(cleartext)
                        chunkNumber += 1
                        if (n < cipherBuf.size) break
                    }
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    // ---- write-handle: buffers cleartext, flushes full ciphertext chunks -----

    private inner class WriteHandle(private val virtualPath: String) {
        private var pendingCleartext = java.io.ByteArrayOutputStream()
        var bytesWrittenSoFar = 0L
            private set
        private val header = delegate.cryptor.createHeader()
        private var nextChunkNumber = 0L
        private val tempFile = File.createTempFile("vault_write_", ".tmp", delegate.context.cacheDir)
        private val tempOut = java.io.BufferedOutputStream(java.io.FileOutputStream(tempFile))
        private var committed = false

        fun append(data: ByteArray) {
            pendingCleartext.write(data)
            bytesWrittenSoFar += data.size
            flushFullChunks(finalFlush = false)
        }

        private fun flushFullChunks(finalFlush: Boolean) {
            val buffered = pendingCleartext.toByteArray()
            val chunkSize = delegate.cryptor.cleartextChunkSize
            var offset = 0
            while (buffered.size - offset >= chunkSize) {
                val chunk = buffered.copyOfRange(offset, offset + chunkSize)
                tempOut.write(delegate.cryptor.encryptChunk(chunk, nextChunkNumber, header))
                nextChunkNumber += 1
                offset += chunkSize
            }
            val remainder = buffered.copyOfRange(offset, buffered.size)
            pendingCleartext = java.io.ByteArrayOutputStream().apply { write(remainder) }
            if (finalFlush && remainder.isNotEmpty()) {
                tempOut.write(delegate.cryptor.encryptChunk(remainder, nextChunkNumber, header))
                nextChunkNumber += 1
                pendingCleartext = java.io.ByteArrayOutputStream()
            }
        }

        fun commit() {
            try {
                flushFullChunks(finalFlush = true)
                tempOut.flush()
                tempOut.close()

                val physicalTarget = delegate.getOrCreatePhysicalFileForWrite(virtualPath)

                delegate.context.contentResolver.openOutputStream(physicalTarget.uri, "wt")?.use { out ->
                    out.write(delegate.cryptor.encodeHeader(header))
                    tempFile.inputStream().use { it.copyTo(out) }
                } ?: throw Exception("Could not open ${physicalTarget.uri} for writing")
                committed = true
            } finally {
                tempFile.delete()
            }
        }

        fun abort() {
            try {
                if (!committed) tempOut.close()
            } catch (_: Exception) { }
            tempFile.delete()
        }
    }

    private fun beginWrite(virtualPath: String): WriteHandle = WriteHandle(virtualPath)
}