package com.aeidolon.vaultexplorer.engine

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.bridge.CopyProgressBridge
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

    // Capacity: sized above the app's actual worst-case concurrent distinct-path
    // reader count (imageExecutor 2 + videoExecutor 1 + ioExecutor 4 + fullResExecutor 2
    // + pdfExecutor 2 = 11, plus any live SAF openDocument() proxy sessions, each on its
    // own HandlerThread) rather than at the old value of 8, which sat *below* that count.
    // Kept generous even after the fix below: a bigger cache still means fewer evictions
    // in the first place, which means less traffic through the pendingClose handoff.
    //
    // entryRemoved() runs synchronously inside the LruCache's own internal lock,
    // triggered by whatever thread's put()/remove() pushed this path out (almost always
    // a *different* path's fresh open, not this path's). That thread does not hold
    // lockFor(key) for the evicted path, so closing oldValue directly here would race
    // against a thread that's still inside readRange() for `key` -- the exact hazard
    // pathLocks below exists to prevent. Making entryRemoved() acquire lockFor(key)
    // itself doesn't work either: readRange() acquires lockFor(path) *before* calling
    // into openReads (pathLock outer, LruCache-internal-lock inner), so entryRemoved()
    // trying to acquire lockFor(key) while already holding the LruCache's internal lock
    // would take that same pair in the opposite order -- a textbook lock-order inversion
    // that can deadlock two threads evicting each other's paths at once.
    //
    // Instead: entryRemoved() only closes immediately when `evicted == false`, i.e. an
    // explicit put()-replace or remove() call -- which per LruCache's contract is always
    // made by a thread that already holds lockFor(key), since every remove()/put() call
    // site in this file is inside `synchronized(lockFor(normalized))`. When
    // `evicted == true` (an async LRU trim triggered by some *other* path's put()), the
    // handle is handed off to pendingClose instead of closed. It gets closed the next time
    // anything touches that path under its own pathLock (readRange, invalidateRead,
    // invalidateAll) -- which can never overlap with a concurrent reader of that same
    // path, because both require holding the same lockFor(key).
    private val pendingClose = ConcurrentHashMap<String, ReadHandle>()

    private val openReads = object : android.util.LruCache<String, ReadHandle>(32) {
        override fun entryRemoved(evicted: Boolean, key: String, oldValue: ReadHandle, newValue: ReadHandle?) {
            if (evicted) {
                pendingClose[key] = oldValue
            } else {
                oldValue.close()
            }
        }
    }

    // Per-path monitors guarding openReads. A ReadHandle is a single mutable cursor
    // (currentPos + cachedChunk) shared across every readFileChunk() call for a given
    // path. Backends with skipsPerVolumeLock == true (gocryptfs, Cryptomator) let reads
    // bypass the outer per-volume lock so listDirectory/getSpaceInfo don't stall behind
    // a large read -- but that also means two threads can legitimately be inside
    // readRange() for the *same* path at once (e.g. the in-app thumbnail pipeline and a
    // SAF client's openDocumentThumbnail racing on the same video). Without a guard here
    // they race on the same seek+read+cursor-update sequence, or one thread's exception
    // path can close() the handle out from under a different thread mid-read, producing
    // garbled or truncated plaintext with no exception raised. synchronized(..) is
    // reentrant per-thread, so the recursive reopen inside readRange() stays safe.
    // Different paths get different monitors, so unrelated files are never serialized
    // against each other -- only concurrent access to the same path is.
    //
    // This per-path lock now also fully covers openReads' own LRU eviction: see the
    // pendingClose handoff on entryRemoved() above. A handle is only ever closed while
    // some thread holds lockFor(its path) -- whether that's the thread actively using
    // it, or a later thread cleaning up a stale pendingClose entry -- so the two can
    // never run concurrently.
    private val pathLocks = ConcurrentHashMap<String, Any>()
    private fun lockFor(normalizedPath: String): Any = pathLocks.computeIfAbsent(normalizedPath) { Any() }

    // Drops whatever handle currently exists for normalizedPath, wherever it lives --
    // still live in openReads, or already evicted into pendingClose by a concurrent
    // put() for a different path. Caller must already hold lockFor(normalizedPath);
    // every call site below does.
    private fun closeAnyHandleFor(normalizedPath: String) {
        openReads.remove(normalizedPath)
        pendingClose.remove(normalizedPath)?.close()
    }

    fun close() {
        openWrites.values.forEach { it.abort() }
        openWrites.clear()
        invalidateAll()
        pathLocks.clear()
    }

    fun invalidateRead(virtualPath: String) {
        val normalized = normalize(virtualPath)
        synchronized(lockFor(normalized)) {
            closeAnyHandleFor(normalized)
        }
    }

    fun invalidateAll() {
        // Acquire each path's own lock in turn (never two at once -- that would
        // reintroduce the ABBA risk the pendingClose design avoids) rather than calling
        // openReads.evictAll(), which would route every entry through entryRemoved()
        // while holding the LruCache's internal lock and defer all of them to
        // pendingClose instead of actually closing anything.
        val paths = openReads.snapshot().keys + pendingClose.keys
        for (path in paths) {
            synchronized(lockFor(path)) {
                closeAnyHandleFor(path)
            }
        }
    }

    private fun normalize(path: String): String = path.trim('/')

    // ---- file content read/write ----------------------------------------------

    fun readFileChunk(virtualPath: String, offset: Long, length: Int): ByteArray? {
        val normalized = normalize(virtualPath)
        return synchronized(lockFor(normalized)) {
            try {
                val physicalFileProvider = {
                    val pf = delegate.getPhysicalFileForRead(normalized)
                    if (pf == null) {
                        throw Exception("Path not found")
                    }
                    pf
                }
                readRange(physicalFileProvider, offset, length, normalized)
            } catch (e: Exception) {
                closeAnyHandleFor(normalized)
                null
            }
        }
    }

    private fun readRange(resolvePhysicalFile: () -> DocumentFile, offset: Long, length: Int, normalizedPath: String): ByteArray? {
        // Always called while holding lockFor(normalizedPath) (from readFileChunk(), or
        // recursively from this function). Safe to close a stale evicted handle for this
        // exact path here -- see the pendingClose handoff on entryRemoved() above.
        pendingClose.remove(normalizedPath)?.close()

        val cryptor = delegate.cryptor
        val chunkSize = cryptor.cleartextChunkSize
        val cipherChunkSize = cryptor.ciphertextChunkSize
        val headerSize = cryptor.headerSize

        var handle = openReads.get(normalizedPath)

        if (handle == null) {
            val physicalFile = resolvePhysicalFile()
            var pfd: android.os.ParcelFileDescriptor? = null
            var stream: java.io.InputStream? = null
            var openPathLabel = "UNRESOLVED"

            // Prefer a direct java.io.File over SAF when one is resolvable --
            // avoids a ContentResolver/Binder round trip to open this file,
            // the same fast path extractFile()/WriteHandle below already
            // use. Previously this was the one read path in the engine that
            // always went through SAF even when a raw path was available, so
            // every directory-vault (gocryptfs/Cryptomator) file open --
            // including every image/video thumbnail read -- unconditionally
            // paid that round trip.
            val rawFile = com.aeidolon.vaultexplorer.RawFileResolver.getRawFile(delegate.context, physicalFile)
            if (rawFile != null) {
                try {
                    stream = java.io.FileInputStream(rawFile)
                    openPathLabel = "RAW"
                } catch (e: Exception) { }
            }

            if (stream == null) {
                try {
                    pfd = delegate.context.contentResolver.openFileDescriptor(physicalFile.uri, "r")
                    if (pfd != null) {
                        stream = java.io.FileInputStream(pfd.fileDescriptor)
                        openPathLabel = "SAF_PFD"
                    }
                } catch (e: Exception) { }
            }

            if (stream == null) {
                stream = delegate.context.contentResolver.openInputStream(physicalFile.uri)
                openPathLabel = "SAF_STREAM"
            }
            if (stream == null) return null

            VeLog.d("ChunkedFileEngine") {
                "READ_HANDLE_OPEN path=$openPathLabel virtualPath=$normalizedPath " +
                    "target=${if (rawFile != null) rawFile.absolutePath else physicalFile.uri.toString()}"
            }

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
                            VeLog.d("ChunkedFileEngine") {
                                val kind = when {
                                    handle!!.pfd != null -> "SAF_PFD(seek unavailable/failed)"
                                    handle!!.stream is java.io.FileInputStream -> "RAW(channel.position failed)"
                                    else -> "SAF_STREAM(not seekable)"
                                }
                                "READ_HANDLE_REOPEN path=$kind virtualPath=$normalizedPath " +
                                    "currentPos=${handle!!.currentPos} desiredPos=$desiredPos " +
                                    "(backward seek forces full close+reopen+header re-read)"
                            }
                            openReads.remove(normalizedPath)
                            return readRange(resolvePhysicalFile, offset, length, normalizedPath)
                        } else {
                            val skipStart = System.nanoTime()
                            var remaining = desiredPos - handle!!.currentPos
                            val skipTotal = remaining
                            val skipBuf = ByteArray(64 * 1024)
                            while (remaining > 0L) {
                                val toSkip = minOf(remaining, skipBuf.size.toLong()).toInt()
                                val actuallyRead = handle!!.stream.read(skipBuf, 0, toSkip)
                                if (actuallyRead <= 0) break
                                remaining -= actuallyRead
                                handle!!.currentPos += actuallyRead
                            }
                            VeLog.d("ChunkedFileEngine") {
                                val elapsedMs = (System.nanoTime() - skipStart) / 1_000_000
                                "READ_HANDLE_SKIP_FORWARD virtualPath=$normalizedPath " +
                                    "bytes=$skipTotal elapsedMs=$elapsedMs " +
                                    "(no seekable fd for this stream -- reading and discarding to reach desiredPos)"
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

    fun writeBackStream(virtualPath: String, input: java.io.InputStream, volId: Int): Boolean {
        if (delegate.readOnly) return false
        val normalized = normalize(virtualPath)
        synchronized(lockFor(normalized)) { closeAnyHandleFor(normalized) }
        openWrites.remove(normalized)?.abort()

        return try {
            val physicalTarget = com.aeidolon.vaultexplorer.container.ContainerFileSystem.withWriteLock(volId) {
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

            val pathTypeLog = if (rawFile != null) "RAW" else "SAF"

            val rawOut = if (rawFile != null) {
                java.io.FileOutputStream(rawFile)
            } else {
                delegate.context.contentResolver.openOutputStream(physicalTarget.uri, "w")
            } ?: throw Exception("Could not open target for writing")

            java.io.BufferedOutputStream(rawOut, 2 * 1024 * 1024).use { out ->
                com.aeidolon.vaultexplorer.container.ContainerFileSystem.withWriteLock(volId) {
                    out.write(cryptor.encodeHeader(header))
                }
                val chunkSize = cryptor.cleartextChunkSize
                val blockMultiplier = maxOf(1, (2 * 1024 * 1024) / chunkSize)
                val batchBufSize = blockMultiplier * chunkSize
                val batchBuf = ByteArray(batchBufSize)

                while (true) {
                    val t0 = System.nanoTime()
                    val read = readFullyPartial(input, batchBuf, 0, batchBufSize)
                    val t1 = System.nanoTime()
                    timeSpentReadingMs += (t1 - t0) / 1_000_000

                    if (read <= 0) break
                    totalBytesRead += read

                    val cleartextSlice = if (read == batchBufSize) batchBuf else batchBuf.copyOf(read)

                    com.aeidolon.vaultexplorer.container.ContainerFileSystem.withWriteLock(volId) {
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

                    Thread.yield()
                }

                val tf0 = System.nanoTime()
                com.aeidolon.vaultexplorer.container.ContainerFileSystem.withWriteLock(volId) {
                    out.flush()
                }
                val tf1 = System.nanoTime()
                val flushMs = (tf1 - tf0) / 1_000_000

                val totalMs = System.currentTimeMillis() - startTime
                val totalMb = totalBytesRead / (1024.0 * 1024.0)
                val mbps = if (totalMs > 0) (totalMb / (totalMs / 1000.0)) else 0.0

                VeLog.i("VaultProfiling") {
                    String.format(
                        """
                        ========== WRITE_BACK_STREAM PROFILING ==========
                        Storage Access Path       : %s
                        File Size                 : %.2f MB (%d bytes)
                        Total Time                : %d ms (Overall Throughput: %.2f MB/s)
                        --------------------------------------------------
                        1. Source Input Read Time : %d ms
                        2. Crypto / JNI Time      : %d ms
                        3. Target Disk Write Time : %d ms
                        4. Final Storage Flush    : %d ms
                        ==================================================
                        """.trimIndent(),
                        pathTypeLog,
                        totalMb, totalBytesRead, totalMs, mbps,
                        timeSpentReadingMs, timeSpentCryptoMs, timeSpentWritingMs, flushMs
                    )
                }
            }

            if (!delegate.batchWriteActive) {
                com.aeidolon.vaultexplorer.container.ContainerFileSystem.withWriteLock(volId) {
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
            synchronized(lockFor(normalized)) { closeAnyHandleFor(normalized) }
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
        synchronized(lockFor(normalized)) { closeAnyHandleFor(normalized) }
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

    // Re-encrypts a known, already-complete local file straight into the vault.
    // Previously this routed through beginWrite()/WriteHandle -- the same machinery
    // writeFileChunk() uses for incremental writes arriving in arbitrary pieces over
    // time from a FUSE-style consumer, which necessarily calls cryptor.encryptChunk()
    // one 4KB chunk at a time since it can't know when more data is coming. But
    // writeBackFile() *does* have the whole file up front (same as writeBackStream()),
    // so reusing that incremental path meant paying a full single-chunk native crypto
    // call -- complete with its own fresh CryptoContext construction -- for every
    // single chunk (~86,000 of them for a 337MB file) instead of batching through
    // cryptor.encryptStream() the way writeBackStream() already does. That's the
    // "write-back (encrypt)" side of intra-vault copy's slowdown; see extractFile()
    // below for the matching read-side fix (a missing decryptStream() override).
    fun writeBackFile(virtualPath: String, sourcePath: String, opId: Int = 0): Boolean {
        if (delegate.readOnly) return false
        return try {
            val normalized = normalize(virtualPath)
            synchronized(lockFor(normalized)) { closeAnyHandleFor(normalized) }
            openWrites.remove(normalized)?.abort()

            val physicalTarget = delegate.getOrCreatePhysicalFileForWrite(normalized)
            val rawFile = com.aeidolon.vaultexplorer.RawFileResolver.getRawFile(delegate.context, physicalTarget)
            val cryptor = delegate.cryptor
            val header = cryptor.createHeader()
            var nextChunkNumber = 0L

            val startTime = System.currentTimeMillis()
            var totalBytesRead = 0L
            var timeSpentReadingMs = 0L
            var timeSpentCryptoMs = 0L
            var timeSpentWritingMs = 0L
            val pathTypeLog = if (rawFile != null) "RAW" else "SAF"

            val rawOut = if (rawFile != null) {
                java.io.FileOutputStream(rawFile)
            } else {
                delegate.context.contentResolver.openOutputStream(physicalTarget.uri, "w")
            } ?: throw Exception("Could not open target for writing")

            java.io.BufferedOutputStream(rawOut, 2 * 1024 * 1024).use { out ->
                out.write(cryptor.encodeHeader(header))

                val chunkSize = cryptor.cleartextChunkSize
                val blockMultiplier = maxOf(1, (2 * 1024 * 1024) / chunkSize)
                val batchBufSize = blockMultiplier * chunkSize
                val batchBuf = ByteArray(batchBufSize)

                File(sourcePath).inputStream().use { input ->
                    while (true) {
                        val t0 = System.nanoTime()
                        val read = readFullyPartial(input, batchBuf, 0, batchBufSize)
                        val t1 = System.nanoTime()
                        timeSpentReadingMs += (t1 - t0) / 1_000_000
                        if (read <= 0) break
                        totalBytesRead += read

                        val cleartextSlice = if (read == batchBufSize) batchBuf else batchBuf.copyOf(read)

                        val t2 = System.nanoTime()
                        val encryptedBatch = cryptor.encryptStream(cleartextSlice, nextChunkNumber, header)
                        val t3 = System.nanoTime()
                        timeSpentCryptoMs += (t3 - t2) / 1_000_000

                        out.write(encryptedBatch)
                        val t4 = System.nanoTime()
                        timeSpentWritingMs += (t4 - t3) / 1_000_000

                        // Copy's total-bytes budget on the Dart side is one cleartext
                        // pass (see FileOperationService.measureItemBytes), but a copy
                        // does two passes (decrypt here in extractFile, encrypt here) --
                        // report half from each side so the two together add up to one
                        // file's worth instead of the progress bar hitting 200%.
                        if (opId > 0) CopyProgressBridge.reportProgress(opId, read.toLong() / 2)

                        val chunksInBatch = (read + chunkSize - 1) / chunkSize
                        nextChunkNumber += chunksInBatch
                    }
                }
                out.flush()
            }

            val totalMs = System.currentTimeMillis() - startTime
            val totalMb = totalBytesRead / (1024.0 * 1024.0)
            val mbps = if (totalMs > 0) (totalMb / (totalMs / 1000.0)) else 0.0
            VeLog.i("VaultProfiling") {
                String.format(
                    """
                    ========== WRITE_BACK_FILE PROFILING ==========
                    Storage Access Path       : %s
                    File Size                 : %.2f MB (%d bytes)
                    Total Time                : %d ms (Overall Throughput: %.2f MB/s)
                    --------------------------------------------------
                    1. Source Input Read Time : %d ms
                    2. Crypto / JNI Time      : %d ms
                    3. Target Disk Write Time : %d ms
                    ==================================================
                    """.trimIndent(),
                    pathTypeLog, totalMb, totalBytesRead, totalMs, mbps,
                    timeSpentReadingMs, timeSpentCryptoMs, timeSpentWritingMs
                )
            }

            if (!delegate.batchWriteActive) {
                delegate.invalidateCacheAfterWrite(normalized)
            }
            true
        } catch (e: Exception) {
            android.util.Log.e("ChunkedFileEngine", "writeBackFile failed", e)
            false
        }
    }

    fun extractFile(virtualPath: String, destinationPath: String, opId: Int = 0): Boolean {
        return try {
            val physicalFile = delegate.getPhysicalFileForRead(normalize(virtualPath)) ?: return false
            val rawFile = com.aeidolon.vaultexplorer.RawFileResolver.getRawFile(delegate.context, physicalFile)
            val startTime = System.currentTimeMillis()
            var totalBytesRead = 0L
            var timeSpentReadingMs = 0L
            var timeSpentCryptoMs = 0L
            var timeSpentWritingMs = 0L
            java.io.BufferedOutputStream(File(destinationPath).outputStream(), 1024 * 1024).use { out ->
                val rawIn = if (rawFile != null) {
                    android.util.Log.d("ChunkedFileEngine", "extractFile FAST-PATH using FileInputStream")
                    java.io.FileInputStream(rawFile)
                } else {
                    android.util.Log.w("ChunkedFileEngine", "extractFile SLOW-PATH using SAF ContentResolver")
                    delegate.context.contentResolver.openInputStream(physicalFile.uri)
                } ?: return false

                java.io.BufferedInputStream(rawIn, 1024 * 1024).use { rawStream ->
                    val cryptor = delegate.cryptor
                    val headerBytes = ByteArray(cryptor.headerSize)
                    if (readFully(rawStream, headerBytes) < cryptor.headerSize) return true
                    val header = cryptor.decodeHeader(headerBytes)
                    var chunkNumber = 0L

                    val ctChunkSize = cryptor.ciphertextChunkSize
                    val blockMultiplier = maxOf(1, (2 * 1024 * 1024) / ctChunkSize)
                    val batchBufSize = blockMultiplier * ctChunkSize
                    val batchBuf = ByteArray(batchBufSize)

                    while (true) {
                        val t0 = System.nanoTime()
                        val read = readFullyPartial(rawStream, batchBuf, 0, batchBufSize)
                        val t1 = System.nanoTime()
                        timeSpentReadingMs += (t1 - t0) / 1_000_000
                        if (read <= 0) break
                        totalBytesRead += read

                        val ciphertextSlice = if (read == batchBufSize) batchBuf else batchBuf.copyOf(read)

                        val t2 = System.nanoTime()
                        val cleartextBatch = cryptor.decryptStream(ciphertextSlice, chunkNumber, header)
                        val t3 = System.nanoTime()
                        timeSpentCryptoMs += (t3 - t2) / 1_000_000

                        out.write(cleartextBatch)
                        val t4 = System.nanoTime()
                        timeSpentWritingMs += (t4 - t3) / 1_000_000

                        // Other half of the same accounting described in writeBackFile.
                        if (opId > 0) CopyProgressBridge.reportProgress(opId, cleartextBatch.size.toLong() / 2)

                        val chunksInBatch = (read + ctChunkSize - 1) / ctChunkSize
                        chunkNumber += chunksInBatch
                    }
                }
            }
            val elapsed = System.currentTimeMillis() - startTime
            val totalMb = totalBytesRead / (1024.0 * 1024.0)
            val mbps = if (elapsed > 0) (totalMb / (elapsed / 1000.0)) else 0.0
            VeLog.i("VaultProfiling") {
                String.format(
                    """
                    ========== EXTRACT_FILE PROFILING ==========
                    Storage Access Path       : %s
                    File Size                 : %.2f MB (%d bytes)
                    Total Time                : %d ms (Overall Throughput: %.2f MB/s)
                    --------------------------------------------------
                    1. Source Input Read Time : %d ms
                    2. Crypto / JNI Time      : %d ms
                    3. Target Disk Write Time : %d ms
                    ==============================================
                    """.trimIndent(),
                    if (rawFile != null) "RAW" else "SAF",
                    totalMb, totalBytesRead, elapsed, mbps,
                    timeSpentReadingMs, timeSpentCryptoMs, timeSpentWritingMs
                )
            }
            android.util.Log.d("ChunkedFileEngine", "extractFile COMPLETED in ${elapsed}ms (FastPath=${rawFile != null})")
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
            VeLog.d("ChunkedFileEngine") {
                if (directFile != null) {
                    "WRITE_HANDLE_OPEN path=RAW virtualPath=$virtualPath target=${directFile.absolutePath}"
                } else {
                    "WRITE_HANDLE_OPEN path=SAF virtualPath=$virtualPath uri=${physicalTarget.uri} " +
                        "(RawFileResolver returned null -- buffering to tempFile, will copy via " +
                        "ContentResolver on commit)"
                }
            }
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
                    val startTime = System.currentTimeMillis()
                    val rawOut = delegate.context.contentResolver.openOutputStream(physicalTarget.uri, "wt")
                        ?: throw Exception("Could not open target for writing")
                    java.io.BufferedOutputStream(rawOut, 1024 * 1024).use { out ->
                        out.write(delegate.cryptor.encodeHeader(header))
                        tempFile!!.inputStream().use { it.copyTo(out) }
                    }
                    VeLog.d("ChunkedFileEngine") {
                        val elapsed = System.currentTimeMillis() - startTime
                        "WRITE_HANDLE_COMMIT path=SAF virtualPath=$virtualPath bytes=$bytesWrittenSoFar " +
                            "copyBackMs=$elapsed uri=${physicalTarget.uri}"
                    }
                } else {
                    VeLog.d("ChunkedFileEngine") {
                        "WRITE_HANDLE_COMMIT path=RAW virtualPath=$virtualPath bytes=$bytesWrittenSoFar " +
                            "target=${directFile.absolutePath}"
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