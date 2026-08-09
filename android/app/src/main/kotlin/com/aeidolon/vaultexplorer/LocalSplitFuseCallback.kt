package com.aeidolon.vaultexplorer

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.provider.DocumentsContract
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Log
import com.aeidolon.vaultexplorer.saf.SafFolderGrants
import com.aeidolon.vaultexplorer.saf.UriToPath
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile

data class SplitPartInfo(
    val uri: Uri,
    val sizeBytes: Long,
    val file: File? = null,
)

object SafSplitResolver {
    private val partSuffixRegex = Regex("""^(.*)\.(\d+|part\d+)$""", RegexOption.IGNORE_CASE)

    fun isSplitFileName(fileName: String): Boolean {
        return partSuffixRegex.containsMatchIn(fileName)
    }

    fun resolveParts(context: Context, firstUri: Uri, displayName: String): List<SplitPartInfo> {
        val rawFile = UriToPath.getRawFile(context, firstUri)
        Log.i("VaultExplorer_C++", "SafSplitResolver: rawFile=${rawFile?.absolutePath ?: "null"} for $firstUri")
        if (rawFile != null) {
            val localParts = SplitPartResolver.resolvePartSequence(rawFile)
            Log.i("VaultExplorer_C++", "SafSplitResolver: local resolvePartSequence found ${localParts.size} part(s)")
            if (localParts.size > 1) {
                return localParts.map { SplitPartInfo(Uri.fromFile(it), it.length(), it) }
            }
        }

        val fileName = if (displayName.isNotEmpty()) displayName else firstUri.lastPathSegment ?: ""
        val match = partSuffixRegex.find(fileName)
        Log.i("VaultExplorer_C++", "SafSplitResolver: fileName='$fileName' matchesSplitPattern=${match != null}")
        if (match == null) return emptyList()

        val base = match.groupValues[1]
        val suffix = match.groupValues[2]
        val isPartWord = suffix.startsWith("part", ignoreCase = true)
        val padWidth = if (isPartWord) suffix.substring(4).length else suffix.length

        fun formatName(n: Int): String {
            return if (isPartWord) {
                if (padWidth > 0) "$base.part%0${padWidth}d".format(n) else "$base.part$n"
            } else {
                if (padWidth > 0) "$base.%0${padWidth}d".format(n) else "$base.$n"
            }
        }

        val parts = mutableListOf<SplitPartInfo>()

        // Strategy 0: use a persisted tree-level grant covering this
        // file's parent folder, if one exists (obtained via the
        // ACTION_OPEN_DOCUMENT_TREE follow-up prompt in
        // VaultPickerHandlers.pickContainerLauncher the first time a
        // cloud-hosted split part is picked -- see SafFolderGrants).
        // Queries within that tree, backed by real tree permission, so it
        // works against providers (Round-Sync/rclone, Drive, pCloud, ...)
        // that correctly enforce per-document SAF scoping and silently
        // reject Strategy 1/2's permission-less guesses -- which is why
        // local containers always worked (no SAF ACL involved at all, see
        // the rawFile branch above) while cloud ones didn't.
        //
        // Two ways to land on a tree here, tried in order:
        //  (a) an explicit recorded mapping for this exact file (see
        //      SafFolderGrants.recordTreeForFile) -- the picker guarantees
        //      the user chose *this file's own* containing folder, so the
        //      tree's own root doc ID IS the parent; no doc-ID relationship
        //      between file and folder is needed, which is the only thing
        //      that works for providers with fully opaque doc IDs (Drive's
        //      doc IDs share no structure with their parent folder's).
        //  (b) the doc-ID-prefix heuristic, for providers that happen to
        //      use path-shaped doc IDs (Round-Sync/rclone-style mounts)
        //      even without ever having explicitly recorded a grant for
        //      this exact file -- here we still need to compute the real
        //      parentDocId since the matched tree may be an ancestor
        //      folder rather than the immediate parent.
        try {
            val recordedTreeUri = SafFolderGrants.findRecordedTreeUri(context, firstUri)
            Log.i("VaultExplorer_C++", "SafSplitResolver Strategy0: recordedTreeUri=${recordedTreeUri ?: "null"}")

            fun queryChildrenAndMatch(treeUri: Uri, parentDocId: String): List<SplitPartInfo> {
                val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
                val byName = mutableMapOf<String, Pair<Uri, Long>>()
                context.contentResolver.query(
                    childrenUri,
                    arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_SIZE,
                    ),
                    null, null, null,
                )?.use { cursor ->
                    val idIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                    val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                    while (cursor.moveToNext()) {
                        val cId = if (idIdx >= 0) cursor.getString(idIdx) else null ?: continue
                        val cName = if (nameIdx >= 0) cursor.getString(nameIdx) else null ?: continue
                        val cSize = if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) cursor.getLong(sizeIdx) else 0L
                        byName[cName.lowercase()] = DocumentsContract.buildDocumentUriUsingTree(treeUri, cId) to cSize
                    }
                }
                Log.i("VaultExplorer_C++", "SafSplitResolver Strategy0: children of $parentDocId returned ${byName.size} entries: ${byName.keys}")
                if (byName.isEmpty()) return emptyList()

                val startN = if (byName.containsKey(formatName(0).lowercase())) 0 else 1
                var n = startN
                val found = mutableListOf<SplitPartInfo>()
                while (true) {
                    val (partUri, partSize) = byName[formatName(n).lowercase()] ?: break
                    found.add(SplitPartInfo(partUri, partSize, null))
                    n++
                }
                return found
            }

            if (recordedTreeUri != null) {
                val rootDocId = DocumentsContract.getTreeDocumentId(recordedTreeUri)
                val found = queryChildrenAndMatch(recordedTreeUri, rootDocId)
                Log.i("VaultExplorer_C++", "SafSplitResolver Strategy0 (recorded): matched ${found.size} part(s)")
                if (found.size > 1) return found
            }

            val prefixTreeUri = SafFolderGrants.findCoveringTreeUriByDocIdPrefix(context, firstUri)
            Log.i("VaultExplorer_C++", "SafSplitResolver Strategy0: prefixTreeUri=${prefixTreeUri ?: "null"}")
            if (prefixTreeUri != null && prefixTreeUri != recordedTreeUri) {
                val docId = if (DocumentsContract.isTreeUri(firstUri)) {
                    DocumentsContract.getTreeDocumentId(firstUri)
                } else {
                    DocumentsContract.getDocumentId(firstUri)
                }
                val parentDocId = if (docId.contains("/")) {
                    docId.substringBeforeLast("/")
                } else if (docId.contains(":")) {
                    val volume = docId.substringBefore(":")
                    val path = docId.substringAfter(":")
                    if (path.contains("/")) "$volume:${path.substringBeforeLast("/")}" else "$volume:"
                } else {
                    null
                }
                Log.i("VaultExplorer_C++", "SafSplitResolver Strategy0 (prefix): docId=$docId parentDocId=${parentDocId ?: "null"}")
                if (parentDocId != null) {
                    val found = queryChildrenAndMatch(prefixTreeUri, parentDocId)
                    Log.i("VaultExplorer_C++", "SafSplitResolver Strategy0 (prefix): matched ${found.size} part(s)")
                    if (found.size > 1) return found
                }
            }
        } catch (e: Exception) {
            Log.i("VaultExplorer_C++", "SafSplitResolver Strategy0: threw ${e.javaClass.simpleName}: ${e.message}")
        }

        // Strategy 1: Query SAF parent directory for sibling document URIs
        try {
            val docId = if (DocumentsContract.isTreeUri(firstUri)) {
                DocumentsContract.getTreeDocumentId(firstUri)
            } else {
                DocumentsContract.getDocumentId(firstUri)
            }

            val parentDocId = if (docId.contains("/")) {
                docId.substringBeforeLast("/")
            } else if (docId.contains(":")) {
                val volume = docId.substringBefore(":")
                val path = docId.substringAfter(":")
                if (path.contains("/")) "$volume:${path.substringBeforeLast("/")}" else "$volume:"
            } else {
                null
            }
            Log.i("VaultExplorer_C++", "SafSplitResolver Strategy1: docId=$docId parentDocId=${parentDocId ?: "null"}")

            if (parentDocId != null) {
                val childrenUri = DocumentsContract.buildChildDocumentsUri(firstUri.authority, parentDocId)
                val projection = arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_SIZE,
                )
                val mapByName = mutableMapOf<String, Pair<String, Long>>()
                context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                    val idIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                    val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                    while (cursor.moveToNext()) {
                        val cId = if (idIdx >= 0) cursor.getString(idIdx) else null ?: continue
                        val cName = if (nameIdx >= 0) cursor.getString(nameIdx) else null ?: continue
                        val cSize = if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) cursor.getLong(sizeIdx) else 0L
                        mapByName[cName.lowercase()] = cId to cSize
                    }
                }
                Log.i("VaultExplorer_C++", "SafSplitResolver Strategy1: children query returned ${mapByName.size} entries: ${mapByName.keys}")

                if (mapByName.isNotEmpty()) {
                    val startN = if (mapByName.containsKey(formatName(0).lowercase())) 0 else 1
                    var n = startN
                    while (true) {
                        val nameToLook = formatName(n).lowercase()
                        val found = mapByName[nameToLook] ?: break
                        val childUri = DocumentsContract.buildDocumentUri(firstUri.authority, found.first)
                        parts.add(SplitPartInfo(childUri, found.second, null))
                        n++
                    }
                }
            }
        } catch (e: Exception) {
            Log.i("VaultExplorer_C++", "SafSplitResolver Strategy1: threw ${e.javaClass.simpleName}: ${e.message}")
        }

        Log.i("VaultExplorer_C++", "SafSplitResolver Strategy1: matched ${parts.size} part(s)")
        if (parts.size > 1) return parts

        // Strategy 2: Probe candidate document URIs by document ID pattern
        try {
            val docId = DocumentsContract.getDocumentId(firstUri)
            Log.i("VaultExplorer_C++", "SafSplitResolver Strategy2: docId=$docId")
            if (docId.contains("/") || docId.contains(":")) {
                fun buildCandidateUri(n: Int): Uri {
                    val targetName = formatName(n)
                    val newDocId = docId.replace(fileName, targetName)
                    return DocumentsContract.buildDocumentUri(firstUri.authority, newDocId)
                }

                fun getPartSize(u: Uri): Long? {
                    return try {
                        context.contentResolver.openAssetFileDescriptor(u, "r")?.use { afd ->
                            if (afd.length >= 0) afd.length else null
                        }
                    } catch (_: Exception) {
                        null
                    }
                }

                val start0Uri = buildCandidateUri(0)
                val start0Size = getPartSize(start0Uri)
                val startN = if (start0Size != null) 0 else 1
                var n = startN
                val probedParts = mutableListOf<SplitPartInfo>()
                while (true) {
                    val candUri = buildCandidateUri(n)
                    val size = getPartSize(candUri) ?: break
                    probedParts.add(SplitPartInfo(candUri, size, null))
                    n++
                }
                Log.i("VaultExplorer_C++", "SafSplitResolver Strategy2: probed ${probedParts.size} part(s)")
                if (probedParts.size > 1) return probedParts
            }
        } catch (e: Exception) {
            Log.i("VaultExplorer_C++", "SafSplitResolver Strategy2: threw ${e.javaClass.simpleName}: ${e.message}")
        }

        Log.i("VaultExplorer_C++", "SafSplitResolver: all strategies exhausted, no split detected")
        return emptyList()
    }
}

class SplitFuseCallback(
    private val context: Context,
    private val parts: List<SplitPartInfo>,
    private val readOnly: Boolean = false,
    private val onReleased: () -> Unit,
) : ProxyFileDescriptorCallback() {
    init {
        require(parts.isNotEmpty()) { "SplitFuseCallback needs at least one part" }
    }

    private val partStarts: LongArray = run {
        var acc = 0L
        LongArray(parts.size) { i -> acc.also { acc += parts[i].sizeBytes } }
    }

    private val totalSizeBytes: Long = partStarts.last() + parts.last().sizeBytes
    private val openRafs = arrayOfNulls<RandomAccessFile>(parts.size)
    private val openPfds = arrayOfNulls<ParcelFileDescriptor>(parts.size)
    private val openForWrite = BooleanArray(parts.size)

    // Fallback forward-only streams for SAF parts whose fd doesn't support
    // real random access (see readFromPart). Mirrors the ReadHandle
    // approach in engine/ChunkedFileEngine.kt, which folder-vault formats
    // (Cryptomator/gocryptfs/cryfs) already rely on for the same cloud
    // providers -- pread/lseek are tried first as a fast path, and only
    // degrade to this when the transport genuinely can't seek.
    private val partStreams = arrayOfNulls<java.io.InputStream>(parts.size)
    private val partStreamPos = LongArray(parts.size)
    // Once pread fails/times out for a part, stop retrying it on every
    // subsequent read -- some providers don't fail fast on an
    // out-of-range/out-of-order request, they hang until a network
    // timeout, which would otherwise make every single read pay that
    // cost before falling back to the stream that actually works.
    private val partPreadUnsupported = BooleanArray(parts.size)

    override fun onGetSize(): Long = totalSizeBytes

    @Synchronized
    override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
        if (offset < 0 || size < 0) fail("invalid read range")
        if (offset >= totalSizeBytes || size == 0) return 0
        val requested = minOf(size.toLong(), totalSizeBytes - offset).toInt()
        var remaining = requested
        var sourceOffset = offset
        var outputOffset = 0

        while (remaining > 0) {
            val partIndex = partIndexFor(sourceOffset)
            val offsetInPart = sourceOffset - partStarts[partIndex]
            val bytesInThisPart = minOf(remaining.toLong(), parts[partIndex].sizeBytes - offsetInPart).toInt()
            if (bytesInThisPart <= 0) fail("read beyond part $partIndex")

            readFromPart(partIndex, offsetInPart, data, outputOffset, bytesInThisPart)

            remaining -= bytesInThisPart
            sourceOffset += bytesInThisPart
            outputOffset += bytesInThisPart
        }
        return requested
    }

    @Synchronized
    override fun onWrite(offset: Long, size: Int, data: ByteArray): Int {
        if (readOnly) fail("container is read-only")
        if (offset < 0 || size < 0) fail("invalid write range")
        if (offset >= totalSizeBytes || size == 0) return 0
        val requested = minOf(size.toLong(), totalSizeBytes - offset).toInt()
        var remaining = requested
        var targetOffset = offset
        var inputOffset = 0

        while (remaining > 0) {
            val partIndex = partIndexFor(targetOffset)
            val offsetInPart = targetOffset - partStarts[partIndex]
            val bytesInThisPart = minOf(remaining.toLong(), parts[partIndex].sizeBytes - offsetInPart).toInt()
            if (bytesInThisPart <= 0) fail("write beyond part $partIndex")

            writeToPart(partIndex, offsetInPart, data, inputOffset, bytesInThisPart)

            remaining -= bytesInThisPart
            targetOffset += bytesInThisPart
            inputOffset += bytesInThisPart
        }
        return requested
    }

    private fun readFromPart(index: Int, offsetInPart: Long, data: ByteArray, outOffset: Int, len: Int) {
        val part = parts[index]
        if (part.file != null) {
            val raf = openLocalRaf(index, forWrite = false)
            raf.seek(offsetInPart)
            var readInPart = 0
            while (readInPart < len) {
                val n = raf.read(data, outOffset + readInPart, len - readInPart)
                if (n < 0) fail("part $index ended unexpectedly")
                readInPart += n
            }
        } else {
            // Fast path: real random access (works for providers that
            // hand back a genuinely seekable fd, e.g. locally-cached
            // Drive documents). Skipped entirely once we've already
            // learned this part's fd can't do it.
            if (!partPreadUnsupported[index]) {
                val pfd = openSafPfd(index, forWrite = false)
                val fd = pfd.fileDescriptor
                var readInPart = 0
                var preadFailed = false
                while (readInPart < len) {
                    val n = try {
                        android.system.Os.pread(
                            fd, data, outOffset + readInPart, len - readInPart,
                            offsetInPart + readInPart
                        )
                    } catch (e: Exception) {
                        preadFailed = true
                        break
                    }
                    if (n <= 0) { preadFailed = true; break }
                    readInPart += n
                }
                if (readInPart == len) return
                if (preadFailed) partPreadUnsupported[index] = true

                // Slow path: the fd doesn't support real random access (a
                // forward-only network stream, e.g. Round-Sync/rclone or a
                // streamed cloud document) -- pread either threw or
                // returned less than requested. Fall back to a persistent
                // forward-only stream, skipping ahead or reopening-from-
                // zero exactly like ChunkedFileEngine.readRange does for
                // folder vaults on the same providers.
                readFromPartStream(
                    index, offsetInPart + readInPart, data,
                    outOffset + readInPart, len - readInPart
                )
            } else {
                readFromPartStream(index, offsetInPart, data, outOffset, len)
            }
        }
    }

    private fun readFromPartStream(index: Int, offsetInPart: Long, data: ByteArray, outOffset: Int, len: Int) {
        var stream = partStreams[index]
        var pos = partStreamPos[index]

        if (stream == null || pos > offsetInPart) {
            try { stream?.close() } catch (_: Exception) {}
            stream = context.contentResolver.openInputStream(parts[index].uri)
                ?: fail("could not open part $index as a stream")
            pos = 0L
            partStreams[index] = stream
        }

        var toSkip = offsetInPart - pos
        if (toSkip > 0) {
            val skipBuf = ByteArray(minOf(toSkip, 256L * 1024).toInt())
            while (toSkip > 0) {
                val n = stream.read(skipBuf, 0, minOf(toSkip, skipBuf.size.toLong()).toInt())
                if (n <= 0) fail("part $index ended unexpectedly while seeking to $offsetInPart")
                toSkip -= n
                pos += n
            }
        }

        var readInPart = 0
        while (readInPart < len) {
            val n = stream.read(data, outOffset + readInPart, len - readInPart)
            if (n <= 0) fail("part $index ended unexpectedly (stream read=$n)")
            readInPart += n
            pos += n
        }
        partStreamPos[index] = pos
    }

    private fun writeToPart(index: Int, offsetInPart: Long, data: ByteArray, inOffset: Int, len: Int) {
        val part = parts[index]
        if (part.file != null) {
            val raf = openLocalRaf(index, forWrite = true)
            raf.seek(offsetInPart)
            raf.write(data, inOffset, len)
        } else {
            val pfd = openSafPfd(index, forWrite = true)
            val fd = pfd.fileDescriptor
            var writtenInPart = 0
            while (writtenInPart < len) {
                val n = try {
                    android.system.Os.pwrite(
                        fd, data, inOffset + writtenInPart, len - writtenInPart,
                        offsetInPart + writtenInPart
                    )
                } catch (e: Exception) {
                    fail("pwrite failed on part $index at $offsetInPart: ${e.message}")
                }
                if (n <= 0) fail("write failed on part $index (written=$n)")
                writtenInPart += n
            }
        }
    }

    private fun openLocalRaf(index: Int, forWrite: Boolean): RandomAccessFile {
        val existing = openRafs[index]
        if (existing != null) {
            if (!forWrite || openForWrite[index]) return existing
            try { existing.close() } catch (_: Exception) {}
            openRafs[index] = null
            openForWrite[index] = false
        }
        val mode = if (forWrite || !readOnly) "rw" else "r"
        var openedForWrite = false
        val raf = try {
            val f = RandomAccessFile(parts[index].file!!, mode)
            openedForWrite = (mode == "rw")
            f
        } catch (e: Exception) {
            if (mode == "rw" && !forWrite) {
                openedForWrite = false
                RandomAccessFile(parts[index].file!!, "r")
            } else {
                fail("could not open part ${parts[index].file!!.name}: ${e.message}")
            }
        }
        openRafs[index] = raf
        openForWrite[index] = openedForWrite
        return raf
    }

    private fun openSafPfd(index: Int, forWrite: Boolean): ParcelFileDescriptor {
        val existing = openPfds[index]
        if (existing != null) {
            if (!forWrite || openForWrite[index]) return existing
            try { existing.close() } catch (_: Exception) {}
            openPfds[index] = null
            openForWrite[index] = false
        }
        val mode = if (forWrite || !readOnly) "rw" else "r"
        var openedForWrite = false
        val pfd = try {
            val p = context.contentResolver.openFileDescriptor(parts[index].uri, mode)
                ?: throw Exception("openFileDescriptor returned null")
            openedForWrite = (mode == "rw")
            p
        } catch (e: Exception) {
            if (mode == "rw" && !forWrite) {
                openedForWrite = false
                context.contentResolver.openFileDescriptor(parts[index].uri, "r")
                    ?: fail("could not open part $index for read")
            } else {
                fail("could not open part $index: ${e.message}")
            }
        }
        openPfds[index] = pfd
        openForWrite[index] = openedForWrite
        return pfd
    }

    @Synchronized
    override fun onFsync() {
        for (raf in openRafs) {
            try { raf?.fd?.sync() } catch (_: Exception) {}
        }
        for (pfd in openPfds) {
            try { pfd?.fileDescriptor?.sync() } catch (_: Exception) {}
        }
    }

    @Synchronized
    override fun onRelease() {
        for (raf in openRafs) {
            try { raf?.close() } catch (_: Exception) {}
        }
        for (pfd in openPfds) {
            try { pfd?.close() } catch (_: Exception) {}
        }
        for (stream in partStreams) {
            try { stream?.close() } catch (_: Exception) {}
        }
        openRafs.fill(null)
        openPfds.fill(null)
        openForWrite.fill(false)
        partStreams.fill(null)
        partStreamPos.fill(0L)
        partPreadUnsupported.fill(false)
        onReleased()
    }

    private fun partIndexFor(byteOffset: Long): Int {
        for (i in parts.indices.reversed()) {
            if (byteOffset >= partStarts[i]) return i
        }
        fail("offset $byteOffset before first part")
    }

    private fun fail(message: String): Nothing {
        Log.e("SplitFuseCallback", "FAIL: $message")
        throw ErrnoException(message, OsConstants.EIO)
    }
}

// Retained for backward-compatibility with tests/invocations that construct LocalSplitFuseCallback
typealias LocalSplitFuseCallback = SplitFuseCallback