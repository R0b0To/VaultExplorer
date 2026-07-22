#pragma once

#include <cstddef>
#include <cstdint>

// Minimal VHDX (Hyper-V "Virtual Hard Disk v2") reader/writer.
//
// Unlike legacy fixed-format VHD -- which this app already supports by
// treating the file as raw disk bytes plus a trailing 512-byte footer (see
// usableFileBytesExcludingVhdFooter() in session_prepare.cpp) -- VHDX has no
// shape where "byte N of the file" trivially equals "byte N of the virtual
// disk". Every VHDX (fixed or dynamic) addresses its payload through a
// Block Allocation Table (BAT): a flat array of 64-bit entries that map
// each fixed-size "payload block" of the *virtual* disk to wherever that
// block's bytes actually live in the *file*. This module owns that
// translation so the rest of the app (partition scan, BitLocker's
// IoContext) can treat a VhdxImage exactly like it already treats a plain
// fd: read/write at a virtual byte offset, get real disk bytes back.
//
// SUPPORTED: fixed and dynamic VHDX (single file, no parent).
// NOT SUPPORTED: differencing VHDX (has_parent metadata bit set) -- these
// require resolving a separate parent .vhdx file and merging its payload
// for blocks this file doesn't have, which is a materially different
// feature (parent-chain resolution, path relocation, recursive opens) and
// is intentionally out of scope for this module. detect()/open() reject
// these cleanly rather than silently returning wrong data.
// NOT SUPPORTED: replaying a pending log. A VHDX whose header LogGuid is
// non-zero has metadata/payload updates recorded in its log that a real
// implementation (Hyper-V, or a full replay-capable reader) would apply
// before trusting the BAT/metadata region. We don't implement log replay,
// so such a file is treated as unsafe to open for write (silently ignoring
// a pending log could corrupt data) and is only opened read-only, with a
// warning available via lastError().

class VhdxImage {
public:
    VhdxImage();
    ~VhdxImage();

    VhdxImage(const VhdxImage&) = delete;
    VhdxImage& operator=(const VhdxImage&) = delete;

    // Cheap signature-only probe: checks for the 8-byte "vhdxfile" cookie
    // at byte 0. Mirrors bitlockerDetectFile()/isLuksContainer()'s role --
    // a hard format signal checked before attempting a full parse.
    static bool detect(int fd);

    // Parses the header/region-table/metadata/BAT structures from `fd`.
    // Does NOT take ownership of `fd` -- caller manages its lifetime for as
    // long as this VhdxImage is in use (matches how bitlocker_backend.cpp's
    // IoContext::fd works: same fd shared across layers, closed exactly
    // once by whoever ultimately owns the session).
    //
    // `requestReadWrite`: if true and the image is safe to write (fixed or
    // dynamic, no pending log), the returned image supports write()/
    // allocation of new blocks. If the image is differencing, open() fails
    // outright regardless of requestReadWrite. If a log replay is pending,
    // open() succeeds but forces read-only (see isReadOnly()).
    bool open(int fd, bool requestReadWrite);

    // Virtual-disk-address-space I/O, analogous to pread/pwrite but backed
    // by the BAT translation instead of a flat file. Returns false on any
    // out-of-bounds access or I/O error. Never partially applies a write
    // that spans multiple payload blocks -- either every block in range is
    // written or none are (an error partway through leaves earlier blocks
    // in this call already written, matching plain pwrite's own partial-
    // write semantics; there is no atomicity guarantee across blocks, only
    // within the call's control flow).
    bool pread(uint64_t virtualOffset, unsigned char* outBuf, size_t len);
    bool pwrite(uint64_t virtualOffset, const unsigned char* inBuf, size_t len);

    uint64_t virtualDiskSize() const { return virtualDiskSize_; }
    bool isReadOnly() const { return readOnly_; }
    bool isDynamic() const { return isDynamic_; }
    uint32_t blockSize() const { return blockSizeBytes_; }
    uint32_t logicalSectorSize() const { return logicalSectorSize_; }

    // Human-readable reason open() failed, or why write was force-disabled
    // (e.g. "pending log replay"). Empty if open() succeeded cleanly.
    const char* lastError() const { return lastError_; }

private:
    int fd_ = -1;
    uint64_t virtualDiskSize_ = 0;
    uint32_t blockSizeBytes_ = 0;
    uint32_t logicalSectorSize_ = 0;
    bool isDynamic_ = false;
    bool readOnly_ = true;
    const char* lastError_ = "";

    // BAT, loaded fully into memory. VHDX BATs are small in practice (a
    // 64 TB dynamic disk at the max 256 MB block size is ~2M entries / 16
    // MB of BAT; typical multi-GB/TB images with the default 32 MB block
    // size are far smaller), so an in-memory array keeps every read/write
    // a single BAT lookup with no extra I/O, mirroring how dislocker/NTFS-3G
    // already keep their own metadata resident for this app's containers.
    uint64_t* bat_ = nullptr;
    uint64_t batEntryCount_ = 0;
    // Entries per chunk (payload-block run between each interleaved sector-
    // bitmap BAT entry) -- see chunkRatio_ doc in the .cpp for the formula.
    uint64_t chunkRatio_ = 0;
    // On-disk byte offset of the BAT region itself, stashed from the
    // region table at open() time so a write-path block allocation can
    // persist its updated BAT entry back to the file (see resolveBlock()).
    uint64_t batRegionOffset_ = 0;

    // Finds (or, for a dynamic image being written to, allocates) the
    // physical file offset backing payload block `blockIndex`. Returns 0
    // and sets *present=false if the block has no backing data yet
    // (PAYLOAD_BLOCK_NOT_PRESENT/ZERO/UNMAPPED) and allocation wasn't
    // requested.
    bool resolveBlock(uint64_t blockIndex, bool allocateIfMissing,
                      uint64_t* outFileOffset, bool* outPresent);

    // Index into bat_ of the payload-block entry for `blockIndex` (skips
    // over the interleaved sector-bitmap entries -- see .cpp).
    uint64_t payloadBatIndex(uint64_t blockIndex) const;
};

// Convenience free function mirroring bitlockerDetectFile()'s shape, for
// call sites that only need the signature check without constructing a
// full VhdxImage (e.g. session_prepare.cpp's format-dispatch chain).
bool isVhdxContainer(int fd);
