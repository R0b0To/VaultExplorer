#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>

// One virtual-disk view over the disk-image shapes the app can open -- fixed VHD, dynamic VHD and VHDX -- plus the
// format-level "grow the virtual disk" operation used by the Expand BitLocker container tool.
//
// I/O goes through the existing VhdImage / VhdxImage block-allocation-table code (or flat pread/pwrite for a fixed
// VHD), so a VDisk reads and writes exactly the bytes the unlock path sees. Growing is separate (vdiskGrow) because it
// rewrites the format's own structures (footers, BAT, headers) and must run with no VDisk open on the file: a VDisk
// caches the BAT in memory, so open a fresh one after growing.

enum class VdiskKind {
    kNone,         // not a supported disk image (raw file, differencing VHD, unknown)
    kVhdFixed,     // legacy VHD, fixed: raw disk bytes followed by one 512-byte footer
    kVhdDynamic,   // legacy VHD, dynamic: BAT-indexed blocks, footer at both ends
    kVhdx,         // VHDX (fixed or dynamic; differencing is rejected by open())
};

// Cheap signature probe ("vhdxfile" cookie or "conectix" footer). Differencing VHD reports kNone.
VdiskKind probeVdiskKind(int fd, uint64_t fileSize);

class VhdxImage;
class VhdImage;

class VDisk {
public:
    VDisk();
    ~VDisk();
    VDisk(const VDisk&) = delete;
    VDisk& operator=(const VDisk&) = delete;

    // Does not take ownership of [fd]. With [requestReadWrite], fails (rather than silently going read-only) when the
    // image cannot be written safely, e.g. a VHDX with a pending log.
    bool open(int fd, uint64_t fileSize, bool requestReadWrite);

    bool pread(uint64_t offset, unsigned char* out, size_t len);
    bool pwrite(uint64_t offset, const unsigned char* data, size_t len);

    uint64_t size() const { return size_; }
    VdiskKind kind() const { return kind_; }
    const char* lastError() const { return lastError_; }

private:
    int fd_ = -1;
    VdiskKind kind_ = VdiskKind::kNone;
    uint64_t size_ = 0;
    bool readWrite_ = false;
    const char* lastError_ = "";
    std::unique_ptr<VhdxImage> vhdx_;
    std::unique_ptr<VhdImage> vhd_;
};

enum class VdiskGrowStatus {
    kOk,
    kNotLarger,     // the virtual disk is already at least that big
    kUnsupported,   // differencing disk, pending VHDX log, 4096-byte logical sectors, malformed structures, ...
    kNoRoom,        // the format's allocation table has no room for the added range
    kIoError,
};

struct VdiskGrowReport {
    uint64_t oldSize = 0;
    uint64_t newSize = 0;
    const char* reason = "";   // short English reason for kUnsupported / kNoRoom (for logs)
};

// Smallest unit the new virtual disk size is rounded down to (1 MiB: what Hyper-V's Resize-VHD requires and what
// keeps partitions aligned).
constexpr uint64_t kVdiskGrowAlign = 1024ull * 1024ull;

// Grows the virtual disk of the image in [fd] (opened read-write; [fileSize] its current size) to [requestedBytes],
// rounded down to kVdiskGrowAlign. Every step is ordered so that an interruption leaves a valid image of either the old
// or the new size. Fixed disks gain real payload blocks (the file grows); dynamic disks only gain allocation-table
// entries. Nothing is written when the result would be kNotLarger / kUnsupported / kNoRoom.
VdiskGrowStatus vdiskGrow(int fd, uint64_t fileSize, uint64_t requestedBytes, VdiskGrowReport* report);
