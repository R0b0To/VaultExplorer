package com.aeidolon.vaultexplorer.reader

import android.os.ParcelFileDescriptor
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.FileInputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.util.zip.DataFormatException
import java.util.zip.Inflater

/**
 * Random-access ZIP reading for the comic (.cbz) and e-book (.epub) readers.
 *
 * Why this exists instead of going through the libarchive engine: the engine's
 * single-entry extraction re-opens the archive and walks it from the start,
 * and for folder vaults (gocryptfs / Cryptomator / CryFS) it first copies the
 * *whole archive* into a plaintext temp file. A reader asks for one page or one
 * chapter resource at a time, many times over, so that is both slow and leaves
 * plaintext on disk. Here the central directory is parsed once and every entry
 * is then read with a handful of ranged reads straight from the decrypted
 * stream ([ContainerFileSystem.readFileChunk]); nothing is written to disk.
 *
 * Scope is deliberately the two methods EPUB and CBZ use in practice (stored
 * and deflate). Encrypted entries and exotic methods raise [BookFormatException]
 * so the caller can fall back to the full archive browser.
 */
enum class BookError { NOT_ZIP, ENCRYPTED, UNSUPPORTED, TOO_LARGE, CORRUPT, NOT_FOUND }

class BookFormatException(val error: BookError, message: String) : IOException(message)

/** Ranged reads over the bytes of one file. Implementations are thread-safe. */
interface BookByteSource : Closeable {
    val size: Long

    /** Identity used to cache a parsed directory; changes if the file does. */
    val cacheKey: String

    /** Reads up to [length] bytes at [offset]; shorter only at end of file. */
    fun read(offset: Long, length: Int): ByteArray
}

/** A file inside an unlocked vault, read through the container's own engine. */
class VaultByteSource(
    private val volId: Int,
    private val fatPath: String,
) : BookByteSource {
    override val size: Long = ContainerFileSystem.getFileSize(volId, fatPath)
    override val cacheKey: String = "v:$volId:$fatPath:$size"

    override fun read(offset: Long, length: Int): ByteArray {
        if (length <= 0 || offset < 0 || offset >= size) return ByteArray(0)
        val want = minOf(length.toLong(), size - offset).toInt()
        val out = ByteArray(want)
        var filled = 0
        while (filled < want) {
            val chunk = ContainerFileSystem.readFileChunk(volId, fatPath, offset + filled, want - filled)
            if (chunk == null || chunk.isEmpty()) break
            val n = minOf(chunk.size, want - filled)
            System.arraycopy(chunk, 0, out, filled, n)
            filled += n
        }
        return if (filled == want) out else out.copyOf(filled)
    }

    override fun close() {}
}

/** A plain file on the device (Local Storage), raw path or SAF document. */
class FileByteSource(
    private val pfd: ParcelFileDescriptor,
    identity: String,
) : BookByteSource {
    private val input = FileInputStream(pfd.fileDescriptor)
    private val channel: FileChannel = input.channel
    override val size: Long = channel.size()
    override val cacheKey: String = "f:$identity:$size"

    override fun read(offset: Long, length: Int): ByteArray {
        if (length <= 0 || offset < 0 || offset >= size) return ByteArray(0)
        val want = minOf(length.toLong(), size - offset).toInt()
        val buf = ByteBuffer.allocate(want)
        var pos = offset
        while (buf.hasRemaining()) {
            val n = channel.read(buf, pos)
            if (n <= 0) break
            pos += n
        }
        return if (buf.position() == want) buf.array() else buf.array().copyOf(buf.position())
    }

    override fun close() {
        runCatching { input.close() }
        runCatching { pfd.close() }
    }
}

class ZipEntryInfo(
    val name: String,
    val method: Int,
    val flags: Int,
    val compressedSize: Long,
    val size: Long,
    val localHeaderOffset: Long,
) {
    val isDirectory: Boolean get() = name.endsWith("/")
    val isEncrypted: Boolean get() = (flags and 0x1) != 0
}

class ZipDirectory(val entries: List<ZipEntryInfo>) {
    private val byName = HashMap<String, ZipEntryInfo>(entries.size * 2)
    private val byLowerName = HashMap<String, ZipEntryInfo>(entries.size * 2)

    init {
        for (e in entries) {
            byName.putIfAbsent(e.name, e)
            byLowerName.putIfAbsent(e.name.lowercase(), e)
        }
    }

    /** Exact match first, then case-insensitive (publishers get href case wrong). */
    fun find(name: String): ZipEntryInfo? = byName[name] ?: byLowerName[name.lowercase()]
}

object ZipReader {
    private const val SIG_EOCD = 0x06054b50
    private const val SIG_ZIP64_LOCATOR = 0x07064b50
    private const val SIG_ZIP64_EOCD = 0x06064b50
    private const val SIG_CENTRAL = 0x02014b50
    private const val SIG_LOCAL = 0x04034b50

    private const val MAX_COMMENT = 65535
    private const val EOCD_MIN = 22
    private const val ZIP64_LOCATOR_SIZE = 20
    private const val ZIP64_EOCD_SIZE = 56
    private const val LOCAL_HEADER_SIZE = 30

    /** A central directory above this is not a book, it is something hostile. */
    const val MAX_DIRECTORY_BYTES = 64L * 1024 * 1024
    /** Largest single entry handed out (a page image or a chapter resource). */
    const val MAX_ENTRY_BYTES = 48L * 1024 * 1024
    private const val READ_CHUNK = 256 * 1024

    private fun u16(b: ByteBuffer, at: Int) = b.getShort(at).toInt() and 0xFFFF
    private fun u32(b: ByteBuffer, at: Int) = b.getInt(at).toLong() and 0xFFFFFFFFL

    fun readDirectory(src: BookByteSource): ZipDirectory {
        val size = src.size
        if (size < EOCD_MIN) throw BookFormatException(BookError.NOT_ZIP, "File too small to be a ZIP")

        val tailLen = minOf(size, (EOCD_MIN + MAX_COMMENT).toLong()).toInt()
        val tailStart = size - tailLen
        val tail = src.read(tailStart, tailLen)
        if (tail.size < EOCD_MIN) throw BookFormatException(BookError.CORRUPT, "Short read at end of file")
        val tb = ByteBuffer.wrap(tail).order(ByteOrder.LITTLE_ENDIAN)

        var eocd = -1
        for (i in tail.size - EOCD_MIN downTo 0) {
            if (tb.getInt(i) == SIG_EOCD && i + EOCD_MIN + u16(tb, i + 20) <= tail.size) {
                eocd = i
                break
            }
        }
        if (eocd < 0) throw BookFormatException(BookError.NOT_ZIP, "No end-of-central-directory record")

        var entryCount = u16(tb, eocd + 10).toLong()
        var cdSize = u32(tb, eocd + 12)
        var cdOffset = u32(tb, eocd + 16)

        if (entryCount == 0xFFFFL || cdSize == 0xFFFFFFFFL || cdOffset == 0xFFFFFFFFL) {
            val locatorAt = tailStart + eocd - ZIP64_LOCATOR_SIZE
            if (locatorAt >= 0) {
                val loc = src.read(locatorAt, ZIP64_LOCATOR_SIZE)
                if (loc.size == ZIP64_LOCATOR_SIZE) {
                    val lb = ByteBuffer.wrap(loc).order(ByteOrder.LITTLE_ENDIAN)
                    if (lb.getInt(0) == SIG_ZIP64_LOCATOR) {
                        val z64 = src.read(lb.getLong(8), ZIP64_EOCD_SIZE)
                        if (z64.size == ZIP64_EOCD_SIZE) {
                            val zb = ByteBuffer.wrap(z64).order(ByteOrder.LITTLE_ENDIAN)
                            if (zb.getInt(0) == SIG_ZIP64_EOCD) {
                                entryCount = zb.getLong(32)
                                cdSize = zb.getLong(40)
                                cdOffset = zb.getLong(48)
                            }
                        }
                    }
                }
            }
        }

        if (cdOffset < 0 || cdSize < 0 || cdOffset > size || cdSize > size - cdOffset) {
            throw BookFormatException(BookError.CORRUPT, "Central directory is out of range")
        }
        if (cdSize > MAX_DIRECTORY_BYTES) {
            throw BookFormatException(BookError.TOO_LARGE, "Central directory is too large")
        }

        val cd = readFully(src, cdOffset, cdSize.toInt())
        val cb = ByteBuffer.wrap(cd).order(ByteOrder.LITTLE_ENDIAN)
        val out = ArrayList<ZipEntryInfo>(minOf(entryCount, 65535L).toInt().coerceAtLeast(16))
        var p = 0
        while (p + 46 <= cd.size && cb.getInt(p) == SIG_CENTRAL) {
            val flags = u16(cb, p + 8)
            val method = u16(cb, p + 10)
            var comp = u32(cb, p + 20)
            var usize = u32(cb, p + 24)
            val nameLen = u16(cb, p + 28)
            val extraLen = u16(cb, p + 30)
            val commentLen = u16(cb, p + 32)
            var localOffset = u32(cb, p + 42)
            val nameStart = p + 46
            val extraStart = nameStart + nameLen
            val next = extraStart + extraLen + commentLen
            if (next > cd.size) throw BookFormatException(BookError.CORRUPT, "Truncated central directory")

            // Always UTF-8: it is what every current EPUB/CBZ tool writes, and
            // the legacy CP437 default only differs for non-ASCII names.
            val name = String(cd, nameStart, nameLen, Charsets.UTF_8)

            var ep = extraStart
            val extraEnd = extraStart + extraLen
            while (ep + 4 <= extraEnd) {
                val id = u16(cb, ep)
                val len = u16(cb, ep + 2)
                if (id == 0x0001) {
                    var q = ep + 4
                    val end = minOf(ep + 4 + len, extraEnd)
                    if (usize == 0xFFFFFFFFL && q + 8 <= end) { usize = cb.getLong(q); q += 8 }
                    if (comp == 0xFFFFFFFFL && q + 8 <= end) { comp = cb.getLong(q); q += 8 }
                    if (localOffset == 0xFFFFFFFFL && q + 8 <= end) { localOffset = cb.getLong(q) }
                }
                ep += 4 + len
            }

            out.add(ZipEntryInfo(name, method, flags, comp, usize, localOffset))
            p = next
        }
        if (out.isEmpty() && entryCount > 0) {
            throw BookFormatException(BookError.CORRUPT, "Central directory has no readable entries")
        }
        return ZipDirectory(out)
    }

    /** Whole content of [entry], decompressed. Throws [BookFormatException]. */
    fun readEntry(src: BookByteSource, entry: ZipEntryInfo, maxBytes: Long = MAX_ENTRY_BYTES): ByteArray {
        if (entry.isEncrypted) throw BookFormatException(BookError.ENCRYPTED, "Entry is encrypted")
        if (entry.size < 0 || entry.compressedSize < 0 ||
            entry.size > maxBytes || entry.compressedSize > maxBytes
        ) {
            throw BookFormatException(BookError.TOO_LARGE, "Entry is too large to open")
        }

        val head = src.read(entry.localHeaderOffset, LOCAL_HEADER_SIZE)
        if (head.size < LOCAL_HEADER_SIZE) throw BookFormatException(BookError.CORRUPT, "Truncated local header")
        val hb = ByteBuffer.wrap(head).order(ByteOrder.LITTLE_ENDIAN)
        if (hb.getInt(0) != SIG_LOCAL) throw BookFormatException(BookError.CORRUPT, "Bad local header")
        val dataStart = entry.localHeaderOffset + LOCAL_HEADER_SIZE + u16(hb, 26) + u16(hb, 28)

        return when (entry.method) {
            0 -> readFully(src, dataStart, entry.compressedSize.toInt())
            8 -> inflate(src, dataStart, entry.compressedSize, entry.size, maxBytes)
            else -> throw BookFormatException(BookError.UNSUPPORTED, "Unsupported compression method ${entry.method}")
        }
    }

    private fun inflate(src: BookByteSource, start: Long, compressed: Long, expected: Long, maxBytes: Long): ByteArray {
        val inflater = Inflater(true)
        try {
            val out = ByteArrayOutputStream(expected.coerceIn(32L, maxBytes).toInt())
            val buf = ByteArray(64 * 1024)
            var pos = start
            var remaining = compressed
            while (!inflater.finished()) {
                if (inflater.needsInput()) {
                    if (remaining <= 0) break
                    val chunk = src.read(pos, minOf(remaining, READ_CHUNK.toLong()).toInt())
                    if (chunk.isEmpty()) throw BookFormatException(BookError.CORRUPT, "Truncated entry data")
                    inflater.setInput(chunk)
                    pos += chunk.size
                    remaining -= chunk.size
                }
                val n = inflater.inflate(buf)
                if (n > 0) {
                    out.write(buf, 0, n)
                    if (out.size() > maxBytes) throw BookFormatException(BookError.TOO_LARGE, "Entry is too large to open")
                } else if (inflater.needsDictionary()) {
                    throw BookFormatException(BookError.CORRUPT, "Unexpected preset dictionary")
                } else if (inflater.needsInput() && remaining <= 0) {
                    break
                }
            }
            return out.toByteArray()
        } catch (e: DataFormatException) {
            throw BookFormatException(BookError.CORRUPT, "Corrupt compressed data")
        } finally {
            inflater.end()
        }
    }

    private fun readFully(src: BookByteSource, offset: Long, length: Int): ByteArray {
        if (length == 0) return ByteArray(0)
        val out = ByteArray(length)
        var filled = 0
        while (filled < length) {
            val chunk = src.read(offset + filled, minOf(length - filled, READ_CHUNK * 4))
            if (chunk.isEmpty()) throw BookFormatException(BookError.CORRUPT, "Unexpected end of file")
            System.arraycopy(chunk, 0, out, filled, chunk.size)
            filled += chunk.size
        }
        return out
    }
}
