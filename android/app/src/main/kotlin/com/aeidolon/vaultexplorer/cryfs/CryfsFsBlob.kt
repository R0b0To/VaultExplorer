package com.aeidolon.vaultexplorer.cryfs

import com.aeidolon.vaultexplorer.crypto.LittleEndian

/**
 * The blob-level envelope real cryfs wraps around every blob's tree content —
 * confirmed against cryfs-main's
 * `crates/fsblobstore/src/fsblobstore/fsblob/layout.rs`.
 *
 * Every blob — whether it holds a directory's entry list, a file's bytes, or
 * a symlink's target — is a [CryfsDataTree] blob whose reconstructed byte
 * stream (`dataTree.readAll(blobId)`) starts with a 19-byte header,
 * little-endian:
 *   bytes 0-1:  format_version_header, u16, must be 1
 *   byte 2:     blob_type (0 = Dir, 1 = File, 2 = Symlink — same wire values
 *               as [CryfsEntryType], reused here rather than duplicating them)
 *   bytes 3-18: parent blob id (16 raw bytes) — the *containing directory's*
 *               blob id. The reference implementation doesn't currently
 *               validate this on load (its own source has a "TODO" saying
 *               so), so it's informational rather than load-bearing; still
 *               set correctly here in case a future version starts checking it.
 * — followed by the type-specific payload: a Dir blob's payload is the
 * directory's entry list (see [CryfsDirBlob]), a File blob's payload is the
 * raw file bytes, and a Symlink blob's payload is the raw UTF-8 target path.
 *
 * This header was previously missing from this app entirely: every read of
 * a directory or file treated `dataTree.readAll(blobId)` as if it were
 * already the type-specific payload, which doesn't match any real `cryfs`
 * vault (and meant a directory's entries, once actually reachable, would
 * still fail to parse — the first 19 bytes aren't entries at all).
 */
object CryfsFsBlob {
    const val HEADER_SIZE = 2 + 1 + CryfsBlockId.SIZE_BYTES // 19 bytes
    private const val FORMAT_VERSION_HEADER = 1

    data class Header(val type: CryfsEntryType, val parent: CryfsBlockId)

    class CorruptBlobException(message: String) : Exception(message)

    private fun parseHeader(raw: ByteArray): Header {
        if (raw.size < HEADER_SIZE) {
            throw CorruptBlobException("Blob is too short to contain a valid header (${raw.size} bytes).")
        }
        val formatVersion = LittleEndian.readU16(raw, 0)
        if (formatVersion != FORMAT_VERSION_HEADER) {
            throw CorruptBlobException("Blob has format version $formatVersion, expected $FORMAT_VERSION_HEADER.")
        }
        val type = try {
            CryfsEntryType.fromWire(raw[2].toInt() and 0xFF)
        } catch (e: Exception) {
            throw CorruptBlobException("Blob has unknown type byte ${raw[2].toInt() and 0xFF}.")
        }
        return Header(type, CryfsBlockId(raw.copyOfRange(3, 3 + CryfsBlockId.SIZE_BYTES)))
    }

    /** Splits a blob's full reconstructed byte stream into its header and payload. */
    fun unwrap(raw: ByteArray): Pair<Header, ByteArray> {
        val header = parseHeader(raw)
        val payload = raw.copyOfRange(HEADER_SIZE, raw.size)
        return header to payload
    }

    /** Builds a blob's full byte stream (header + payload), ready to hand to
     *  [CryfsDataTree.writeWholeBlob]. */
    fun wrap(type: CryfsEntryType, parent: CryfsBlockId, payload: ByteArray): ByteArray {
        val out = ByteArray(HEADER_SIZE + payload.size)
        LittleEndian.writeU16(out, 0, FORMAT_VERSION_HEADER)
        out[2] = type.wireValue.toByte()
        System.arraycopy(parent.bytes, 0, out, 3, CryfsBlockId.SIZE_BYTES)
        System.arraycopy(payload, 0, out, HEADER_SIZE, payload.size)
        return out
    }

    // ---- convenience wrappers used by CryfsVaultTree/CryfsSession/CryfsVault ---------------

    /** Re-points an already-published blob's embedded parent pointer, in place. */
    fun updateParent(dataTree: CryfsDataTree, blobId: CryfsBlockId, newParent: CryfsBlockId) {
        dataTree.patchFirstLeafBytes(blobId, 3, newParent.bytes) // offset 3 = where wrap() puts it
    }
    /** Reads a blob's parsed header + payload directly from the data tree. */
    fun readWhole(dataTree: CryfsDataTree, blobId: CryfsBlockId): Pair<Header, ByteArray> =
        unwrap(dataTree.readAll(blobId))

    /**
     * Reads and parses just a blob's [HEADER_SIZE]-byte header. Unlike
     * [readWhole]/[unwrap], this never touches the blob's payload, so it's
     * safe to call on a File blob of any size -- a multi-gigabyte file's
     * data tree is exactly as cheap to check here as an empty one. Callers
     * that only need to know a blob's type (e.g. FolderVaultChecker.kt's
     * connectivity walk, which must decide whether to descend into
     * something as a directory before it knows what that something even
     * is) should always prefer this over [readWhole].
     */
    fun readHeader(dataTree: CryfsDataTree, blobId: CryfsBlockId): Header =
        parseHeader(dataTree.read(blobId, 0, HEADER_SIZE))

    /** Writes [payload] as the whole content of the blob at [rootId] (or creates a brand-new
     *  blob if [rootId] is null), wrapping it with an fsblob header for [type]/[parent]. */
    fun writeWhole(
        dataTree: CryfsDataTree, rootId: CryfsBlockId?, type: CryfsEntryType, parent: CryfsBlockId, payload: ByteArray,
    ): CryfsBlockId = dataTree.writeWholeBlob(rootId, wrap(type, parent, payload))

    /** Payload size in bytes (blob size minus this header) — for a File blob this is the file's
     *  actual byte length, without needing to reload+unwrap the whole blob just to measure it. */
    fun payloadSize(dataTree: CryfsDataTree, blobId: CryfsBlockId): Long =
        (dataTree.size(blobId) - HEADER_SIZE).coerceAtLeast(0L)

    /** Reads a slice of a File blob's payload (the actual file bytes), automatically shifting
     *  past the fsblob header so callers can use plain file-relative offsets. */
    fun readPayload(dataTree: CryfsDataTree, blobId: CryfsBlockId, offset: Long, length: Int): ByteArray =
        dataTree.read(blobId, HEADER_SIZE.toLong() + offset, length)
}