package com.aeidolon.vaultexplorer.engine

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.util.concurrent.ConcurrentHashMap



interface ChunkedEngineDelegate<H> {
    val context: Context
    val readOnly: Boolean
    val cryptor: VaultChunkCryptor<H>
    var batchWriteActive: Boolean

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

    private fun readFullyPartial(stream: java.io.InputStream, buffer: ByteArray, offset: Int, length: Int): Int {
        var total = 0
        while (total < length) {
            val count = stream.read(buffer, offset + total, length - total)
            if (count <= 0) break
            total += count
        }
        return total
    }

    /**
     * Streams [input] into [virtualPath] as a sequence of 2 MB batches.
     *
     * Only the JNI batch encryption and the physical file write for each
     * batch are done under [com.aeidolon.vaultexplorer.ContainerFileSystem.withWriteLock] --
     * the (potentially slow, SAF-backed) stream read for the *next* batch
     * happens outside any lock, and the lock is released between batches
     * (with a [Thread.yield] to give a waiting UI read lock a fair chance
     * to run) rather than held continuously for the whole transfer. Holding
     * it continuously is what used to block `listDirectory`/`getSpaceInfo`
     * for the full multi-second duration of a large import; see the
     * class-level bug this fixes.
     *
     * [getOrCreatePhysicalFileForWrite] and the post-write
     * [ChunkedEngineDelegate.invalidateCacheAfterWrite] call are also each
     * wrapped in their own short-lived [com.aeidolon.vaultexplorer.ContainerFileSystem.withWriteLock]
     * call even though they're not part of the streamed batch loop: both
     * mutate the backend's virtual-tree caches (which, for at least the
     * Gocryptfs backend, are plain non-thread-safe `HashMap`s), so a
     * concurrent `listDirectory` read must still be excluded while they run.
     * They're each fast, one-shot operations, so this doesn't reintroduce
     * the freeze -- only the streamed encrypt/write loop needed splitting.
     */
    fun writeBackStream(virtualPath: String, input: java.io.InputStream, volId: Int): Boolean {
        if (delegate.readOnly) return false
        val normalized = normalize(virtualPath)
        openReads.remove(normalized)
        openWrites.remove(normalized)?.abort()

        return try {
            val physicalTarget = com.aeidolon.vaultexplorer.ContainerFileSystem.withWriteLock(volId) {
                delegate.getOrCreatePhysicalFileForWrite(normalized)
            }
            val rawFile = com.aeidolon.vaultexplorer.RawFileResolver.getRawFile(delegate.context, physicalTarget)
            val cryptor = delegate.cryptor
            val header = cryptor.createHeader()
            var nextChunkNumber = 0L

            val startTime = System.currentTimeMillis()
            var totalBytesRead = 0L
            var timeSpentReadingMs = 0L
            var timeSpentCryptoMs = 0L
            var timeSpentWritingMs = 0L

            val rawOut = if (rawFile != null) {
                java.io.FileOutputStream(rawFile)
            } else {
                delegate.context.contentResolver.openOutputStream(physicalTarget.uri, "w")
            } ?: throw Exception("Could not open ${physicalTarget.uri} for writing")

            java.io.BufferedOutputStream(rawOut, 2 * 1024 * 1024).use { out ->
                com.aeidolon.vaultexplorer.ContainerFileSystem.withWriteLock(volId) {
                    out.write(cryptor.encodeHeader(header))
                }
                val chunkSize = cryptor.cleartextChunkSize
                val blockMultiplier = maxOf(1, (2 * 1024 * 1024) / chunkSize)
                val batchBufSize = blockMultiplier * chunkSize
                val batchBuf = ByteArray(batchBufSize)

                while (true) {
                    // Stream read happens outside the lock -- this is the
                    // part that can block on slow/SAF-backed I/O, and it
                    // touches nothing shared across volId's sessions.
                    val t0 = System.nanoTime()
                    val read = readFullyPartial(input, batchBuf, 0, batchBufSize)
                    val t1 = System.nanoTime()
                    timeSpentReadingMs += (t1 - t0) / 1_000_000

                    if (read <= 0) break
                    totalBytesRead += read

                    val cleartextSlice = if (read == batchBufSize) batchBuf else batchBuf.copyOf(read)

                    com.aeidolon.vaultexplorer.ContainerFileSystem.withWriteLock(volId) {
                        // Polymorphic fast-path dispatch straight to VaultChunkCryptor.encryptStream
                        val t2 = System.nanoTime()
                        val encryptedBatch = cryptor.encryptStream(cleartextSlice, nextChunkNumber, header)
                        val t3 = System.nanoTime()
                        timeSpentCryptoMs += (t3 - t2) / 1_000_000

                        out.write(encryptedBatch)
                        val t4 = System.nanoTime()
                        timeSpentWritingMs += (t4 - t3) / 1_000_000
                    }

                    val chunksInBatch = (read + chunkSize - 1) / chunkSize
                    nextChunkNumber += chunksInBatch

                    // Give a waiting UI read lock (listDirectory/getSpaceInfo)
                    // a context-switch window now that the write lock for
                    // this batch has been released.
                    Thread.yield()
                }

                val tf0 = System.nanoTime()
                com.aeidolon.vaultexplorer.ContainerFileSystem.withWriteLock(volId) {
                    out.flush()
                }
                val tf1 = System.nanoTime()
                val flushMs = (tf1 - tf0) / 1_000_000

                val totalMs = System.currentTimeMillis() - startTime
                val totalMb = totalBytesRead / (1024.0 * 1024.0)
                val mbps = if (totalMs > 0) (totalMb / (totalMs / 1000.0)) else 0.0

                android.util.Log.i("VaultProfiling", String.format(
                    """
                    ========== WRITE_BACK_STREAM PROFILING ==========
                    File Size                 : %.2f MB (%d bytes)
                    Total Time                : %d ms (Overall Throughput: %.2f MB/s)
                    --------------------------------------------------
                    1. Source Input Read Time : %d ms
                    2. Crypto / JNI Time      : %d ms
                    3. Target Disk Write Time : %d ms
                    4. Final Storage Flush    : %d ms
                    ==================================================
                    """.trimIndent(),
                    totalMb, totalBytesRead, totalMs, mbps,
                    timeSpentReadingMs, timeSpentCryptoMs, timeSpentWritingMs, flushMs
                ))
            }

            if (!delegate.batchWriteActive) {
                com.aeidolon.vaultexplorer.ContainerFileSystem.withWriteLock(volId) {
                    delegate.invalidateCacheAfterWrite(normalized)
                }
            }
            true
        } catch (e: Exception) {
            android.util.Log.e("ChunkedFileEngine", "writeBackStream failed", e)
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
            if (!delegate.batchWriteActive) {
                delegate.invalidateCacheAfterWrite(normalized)
            }
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
            if (!delegate.batchWriteActive) {
                delegate.invalidateCacheAfterWrite(normalized)
            }
            true
       } catch (e: Exception) {
            android.util.Log.e("ChunkedFileEngine", "writeBackFile failed (pathLen=${virtualPath.length})", e)
            false
        }
    }

    fun extractFile(virtualPath: String, destinationPath: String): Boolean {
        return try {
            val physicalFile = delegate.getPhysicalFileForRead(normalize(virtualPath)) ?: return false
            val rawFile = com.aeidolon.vaultexplorer.RawFileResolver.getRawFile(delegate.context, physicalFile)
            val startTime = System.currentTimeMillis()
            java.io.BufferedOutputStream(File(destinationPath).outputStream(), 1024 * 1024).use { out ->
                val rawIn = if (rawFile != null) {
                    android.util.Log.d("ChunkedFileEngine", "extractFile FAST-PATH using FileInputStream: ${rawFile.absolutePath}")
                    java.io.FileInputStream(rawFile)
                } else {
                    android.util.Log.w("ChunkedFileEngine", "extractFile SLOW-PATH using SAF ContentResolver: ${physicalFile.uri}")
                    delegate.context.contentResolver.openInputStream(physicalFile.uri)
                } ?: return false

                java.io.BufferedInputStream(rawIn, 1024 * 1024).use { rawStream ->
                    val cryptor = delegate.cryptor
                    val headerBytes = ByteArray(cryptor.headerSize)
                    if (readFully(rawStream, headerBytes) < cryptor.headerSize) return true
                    val header = cryptor.decodeHeader(headerBytes)
                    var chunkNumber = 0L

                    val ctChunkSize = cryptor.ciphertextChunkSize
                    val blockMultiplier = maxOf(1, (1024 * 1024) / ctChunkSize)
                    val batchBufSize = blockMultiplier * ctChunkSize
                    val batchBuf = ByteArray(batchBufSize)

                    while (true) {
                        val read = readFullyPartial(rawStream, batchBuf, 0, batchBufSize)
                        if (read <= 0) break

                        val ciphertextSlice = if (read == batchBufSize) batchBuf else batchBuf.copyOf(read)
                        
                        // Polymorphic fast-path dispatch straight to VaultChunkCryptor.decryptStream
                        val cleartextBatch = cryptor.decryptStream(ciphertextSlice, chunkNumber, header)

                        out.write(cleartextBatch)
                        val chunksInBatch = (read + ctChunkSize - 1) / ctChunkSize
                        chunkNumber += chunksInBatch
                    }
                }
            }
            val elapsed = System.currentTimeMillis() - startTime
            android.util.Log.d("ChunkedFileEngine", "extractFile COMPLETED ($virtualPath) in ${elapsed}ms (FastPath=${rawFile != null})")
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
        
        private val physicalTarget = delegate.getOrCreatePhysicalFileForWrite(virtualPath)
        private val directFile: File? = com.aeidolon.vaultexplorer.RawFileResolver.getRawFile(delegate.context, physicalTarget)

        private val tempFile: File? = if (directFile == null) {
            File.createTempFile("vault_write_", ".tmp", delegate.context.cacheDir)
        } else null

        private val targetOut = java.io.BufferedOutputStream(
            if (directFile != null) java.io.FileOutputStream(directFile)
            else java.io.FileOutputStream(tempFile!!),
            1024 * 1024
        )
        private var committed = false

        init {
            if (directFile != null) {
                targetOut.write(delegate.cryptor.encodeHeader(header))
            }
        }

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
                targetOut.write(delegate.cryptor.encryptChunk(chunk, nextChunkNumber, header))
                nextChunkNumber += 1
                offset += chunkSize
            }
            val remainder = buffered.copyOfRange(offset, buffered.size)
            pendingCleartext = java.io.ByteArrayOutputStream().apply { write(remainder) }
            if (finalFlush && remainder.isNotEmpty()) {
                targetOut.write(delegate.cryptor.encryptChunk(remainder, nextChunkNumber, header))
                nextChunkNumber += 1
                pendingCleartext = java.io.ByteArrayOutputStream()
            }
        }

        fun commit() {
            try {
                flushFullChunks(finalFlush = true)
                targetOut.flush()
                targetOut.close()

                if (directFile == null) {
                    val rawOut = delegate.context.contentResolver.openOutputStream(physicalTarget.uri, "wt")
                        ?: throw Exception("Could not open ${physicalTarget.uri} for writing")
                    java.io.BufferedOutputStream(rawOut, 1024 * 1024).use { out ->
                        out.write(delegate.cryptor.encodeHeader(header))
                        tempFile!!.inputStream().use { it.copyTo(out) }
                    }
                }
                committed = true
            } finally {
                tempFile?.delete()
            }
        }

        fun abort() {
            try {
                if (!committed) targetOut.close()
            } catch (_: Exception) { }
            tempFile?.delete()
            if (!committed) {
                directFile?.delete()
            }
        }
    }

    private fun beginWrite(virtualPath: String): WriteHandle = WriteHandle(virtualPath)
}