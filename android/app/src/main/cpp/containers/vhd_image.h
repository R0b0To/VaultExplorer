#pragma once

#include <cstddef>
#include <cstdint>

// Minimal legacy VHD ("Microsoft Virtual Hard Disk", the pre-Hyper-V format
// also known as "Connectix"/VPC) reader/writer for *dynamic* (a.k.a.
// "expandable") disks.
//
// This app already supports FIXED-format VHD -- see
// usableFileBytesExcludingVhdFooter() in session_prepare.cpp -- by simply
// treating the file as raw disk bytes with a trailing 512-byte footer
// excluded from the scan, because a fixed VHD's "byte N of file" really is
// "byte N of the virtual disk". A dynamic VHD has no such shape: like VHDX
// (see vhdx_image.h, which this module deliberately mirrors), it addresses
// its payload through a Block Allocation Table (BAT) -- here, a flat array
// of 32-bit sector offsets that map each fixed-size "data block" of the
// *virtual* disk to wherever that block actually lives in the *file*. This
// module owns that translation, exposing the same pread/pwrite-at-a-
// virtual-offset shape VhdxImage does, so the rest of the app (partition
// scan, BitLocker's IoContext) can treat a VhdImage exactly like it already
// treats a VhdxImage or a plain fd.
//
// KEY FORMAT DIFFERENCE FROM VHDX: every multi-byte field in the legacy VHD
// footer/dynamic-header/BAT is BIG-ENDIAN ("network byte order"), unlike
// VHDX which is little-endian throughout. Getting this backwards silently
// produces wildly wrong offsets/sizes rather than a clean parse failure, so
// every field read in the .cpp goes through readU32BE/readU64BE -- never
// the little-endian helpers vhdx_image.cpp uses for its own fields.
//
// Legacy VHD also has a per-data-block "sector bitmap" (one bit per
// 512-byte sector of the block, stored immediately before the block's data)
// that VHDX only carries for *differencing* images -- a plain dynamic VHDX
// has no equivalent (see vhdx_image.cpp's chunkRatio_ doc comment). This
// module honors that bitmap on read (a 0 bit reads back as zero, per spec)
// and keeps it correct on write (a newly allocated block gets a fully-1
// bitmap; writing into an already-allocated block sets any 0 bits the
// write touches to 1), so a file this module writes to stays correct if
// later reopened by a real VHD tool. If a write only partially covers a
// sector whose bit was previously 0, the untouched remainder of that
// sector is not separately zero-filled first -- this module only ever
// touches the bytes the caller actually writes, same scope as
// VhdxImage::pwrite.
//
// SUPPORTED: dynamic VHD (single file, no parent).
// NOT SUPPORTED: differencing VHD (Disk Type 4) -- requires resolving a
// separate parent .vhd file and merging its payload for blocks this file
// doesn't have, a materially different feature, same scoping decision as
// vhdx_image.h's differencing exclusion. open() rejects these cleanly.
// NOT SUPPORTED: fixed-format VHD (Disk Type 2) -- already handled by the
// existing flat-file path (see usableFileBytesExcludingVhdFooter()); open()
// rejects these too, so callers fall back to that path instead of getting
// silently-wrong BAT-translated addressing for a file that doesn't have a
// BAT at all.

enum class VhdDiskKind { kNotVhd, kFixed, kDynamic, kDifferencing };

// Cheap, signature-only probe: reads just the trailing 512-byte footer and
// reports which legacy-VHD shape (if any) the file has, without touching
// the dynamic-header/BAT structures VhdImage::open() goes on to parse.
// Mirrors isVhdxContainer()'s role as a hard format signal checked before a
// full parse is attempted -- callers use this to route kFixed to the
// existing flat-file scan, kDynamic to this module, and kDifferencing away
// from both (see session_prepare.cpp's dispatch chain for exactly this).
VhdDiskKind probeVhdDiskKind(int fd, uint64_t fileSize);

class VhdImage {
public:
    VhdImage();
    ~VhdImage();

    VhdImage(const VhdImage&) = delete;
    VhdImage& operator=(const VhdImage&) = delete;

    // Parses the footer/dynamic-header/BAT structures from `fd`. Does NOT
    // take ownership of `fd` -- caller manages its lifetime for as long as
    // this VhdImage is in use, same contract as VhdxImage::open().
    //
    // Fails outright if probeVhdDiskKind() reports anything other than
    // kDynamic: kFixed means the caller should be using the existing
    // flat-file path instead, and kDifferencing is out of scope (see class
    // doc comment above) -- either way, no partial/wrong-shaped VhdImage is
    // ever handed back.
    //
    // `requestReadWrite`: if true, the returned image supports write()/
    // allocation of new blocks. Unlike VHDX there's no "pending log replay"
    // concept in the legacy VHD format that could force read-only even
    // when the caller asked for read-write.
    bool open(int fd, uint64_t fileSize, bool requestReadWrite);

    // Virtual-disk-address-space I/O, analogous to pread/pwrite but backed
    // by the BAT (and per-block sector bitmap) translation instead of a
    // flat file. Same contract as VhdxImage::pread/pwrite: returns false on
    // any out-of-bounds access or I/O error; no write atomicity guarantee
    // across multiple data blocks beyond plain pwrite's own.
    bool pread(uint64_t virtualOffset, unsigned char* outBuf, size_t len);
    bool pwrite(uint64_t virtualOffset, const unsigned char* inBuf, size_t len);

    uint64_t virtualDiskSize() const { return virtualDiskSize_; }
    bool isReadOnly() const { return readOnly_; }
    uint32_t blockSize() const { return blockSizeBytes_; }

    // Human-readable reason open() failed. Empty if open() succeeded.
    const char* lastError() const { return lastError_; }

private:
    int fd_ = -1;
    uint64_t virtualDiskSize_ = 0;
    uint32_t blockSizeBytes_ = 0;
    uint32_t bitmapSizeBytes_ = 0; // per-block sector bitmap, rounded up to a 512-byte sector
    bool readOnly_ = true;
    const char* lastError_ = "";

    // BAT, loaded fully into memory -- one 32-bit sector-offset entry per
    // data block (host byte order; converted from on-disk big-endian at
    // open() time). Legacy VHD BATs are tiny even for large disks (a 127GB
    // dynamic disk at the default 2MB block size is ~65K entries / 256KB of
    // BAT), so an in-memory array keeps every read/write a single lookup,
    // mirroring VhdxImage's own bat_.
    uint32_t* bat_ = nullptr;
    uint64_t batEntryCount_ = 0;
    // On-disk byte offset of the BAT itself, stashed at open() time so a
    // write-path block allocation can persist its updated entry (see
    // resolveBlock()).
    uint64_t batRegionOffset_ = 0;

    // Raw, unmodified 512-byte footer bytes, cached at open() time. A block
    // allocation copies these verbatim to the new end-of-file location
    // instead of recomputing the footer's checksum -- no footer field ever
    // changes across a block allocation, only where it physically sits.
    unsigned char footerBytes_[512] = {};
    // Current on-disk byte offset of the single, authoritative footer --
    // always the last 512 bytes of the file. Advances every time a new
    // block is appended (see resolveBlock()).
    uint64_t footerOffset_ = 0;

    // Finds (or, for a write, allocates) the physical file offset of
    // blockIndex's *data* region (i.e. immediately past its sector bitmap).
    // Returns 0 and sets *outPresent=false if the block has no backing data
    // yet (BAT entry unallocated) and allocation wasn't requested.
    bool resolveBlock(uint64_t blockIndex, bool allocateIfMissing,
                      uint64_t* outDataFileOffset, bool* outPresent);
};
