package com.aeidolon.vaultexplorer

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.provider.DocumentsContract
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Log
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
        if (rawFile != null) {
            val localParts = SplitPartResolver.resolvePartSequence(rawFile)
            if (localParts.size > 1) {
                return localParts.map { SplitPartInfo(Uri.fromFile(it), it.length(), it) }
            }
        }

        val fileName = if (displayName.isNotEmpty()) displayName else firstUri.lastPathSegment ?: ""
        val match = partSuffixRegex.find(fileName) ?: return emptyList()

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
        } catch (_: Exception) {}

        if (parts.size > 1) return parts

        // Strategy 2: Probe candidate document URIs by document ID pattern
        try {
            val docId = DocumentsContract.getDocumentId(firstUri)
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
                if (probedParts.size > 1) return probedParts
            }
        } catch (_: Exception) {}

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
            val pfd = openSafPfd(index, forWrite = false)
            val fd = pfd.fileDescriptor
            try {
                android.system.Os.lseek(fd, offsetInPart, android.system.OsConstants.SEEK_SET)
            } catch (e: Exception) {
                if (offsetInPart != 0L) {
                    fail("seek failed on part $index: ${e.message}")
                }
            }
            var readInPart = 0
            while (readInPart < len) {
                val n = android.system.Os.read(fd, data, outOffset + readInPart, len - readInPart)
                if (n <= 0) fail("part $index ended unexpectedly (read=$n)")
                readInPart += n
            }
        }
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
            try {
                android.system.Os.lseek(fd, offsetInPart, android.system.OsConstants.SEEK_SET)
            } catch (e: Exception) {
                if (offsetInPart != 0L) {
                    fail("seek failed on part $index for write: ${e.message}")
                }
            }
            var writtenInPart = 0
            while (writtenInPart < len) {
                val n = android.system.Os.write(fd, data, inOffset + writtenInPart, len - writtenInPart)
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
        openRafs.fill(null)
        openPfds.fill(null)
        openForWrite.fill(false)
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