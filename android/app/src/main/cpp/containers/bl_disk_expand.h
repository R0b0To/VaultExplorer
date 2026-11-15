// Expand BitLocker volumes that live inside a virtual disk image (fixed/dynamic VHD, VHDX).
//
// A BitLocker volume in a disk image sits inside a partition of the virtual disk, so growing it means growing four
// layers, in this order, each of which leaves a valid (just not yet larger) structure if interrupted:
//   1. the virtual disk itself          (containers/vdisk.cpp: footer / BAT / headers)
//   2. the last partition               (containers/disk_partition.h: MBR entry or GPT entries + backup GPT)
//   3. the BitLocker volume's metadata  (containers/bl_expand.h, shifted by the partition's start)
//   4. NTFS                             (done by the caller with the existing fsGrowToFit)
//
// Nothing is modified until every layer has passed its read-only checks. Re-running with the same target after an
// interruption continues where the previous run stopped (each layer skips work it has already done).
#pragma once

#include <cstddef>
#include <cstdint>

#include "vdisk.h"

enum class BlDiskResult {
    kOk,
    kNothingToDo,           // disk, partition and BitLocker volume are already at the requested size
    kNotBitLocker,          // no BitLocker volume found in the image
    kNotExpandable,         // BitLocker volume of a kind this tool refuses (To Go, encrypt-on-write, (de)crypting, ...)
    kInvalidMetadata,       // BitLocker metadata failed verification
    kDiskUnsupported,       // the virtual disk cannot be grown (differencing, pending log, no BAT room, 4K sectors, ...)
    kPartitionUnsupported,  // partition table unsupported, or the BitLocker partition is not the last one
    kIoError,
};

struct BlDiskLocation {
    VdiskKind kind = VdiskKind::kNone;
    uint64_t diskBytes = 0;        // current virtual disk size
    bool wholeDisk = false;        // no partition table: the volume starts at byte 0 of the virtual disk
    uint64_t startLba = 0;         // BitLocker partition start (512-byte sectors); unused when wholeDisk
    uint64_t partStartBytes = 0;
    uint64_t partBytes = 0;
};

struct BlDiskExpandResult {
    uint64_t newDiskBytes = 0;
    uint64_t newPartBytes = 0;     // size of the partition / disk the volume now fills
    uint64_t oldVolumeBytes = 0;   // BitLocker encrypted_volume_size before / after
    uint64_t newVolumeBytes = 0;
};

// Read-only. Opens the image and finds the BitLocker volume the unlock path would open (first partition, in table
// order, whose first sector is a BitLocker volume header).
BlDiskResult blDiskLocate(int fd, uint64_t fileSize, BlDiskLocation* loc);

// Grows disk, partition and BitLocker metadata to [requestedDiskBytes] (rounded down to 1 MiB). [vmk] is the unlocked
// Volume Master Key of the volume found by blDiskLocate. The caller must hold no VDisk / session open on [fd].
BlDiskResult blDiskExpand(int fd, const BlDiskLocation& loc, const unsigned char* vmk, size_t vmkLen,
                          uint64_t requestedDiskBytes, uint64_t fileTime, BlDiskExpandResult* out);

// Read-only. The encrypted volume size recorded in the BitLocker metadata of the located volume (what the NTFS grow
// step may use), for retrying only the file-system step. kNotExpandable if it exceeds the partition.
BlDiskResult blDiskReadVolumeSize(int fd, const BlDiskLocation& loc, uint64_t* volumeBytes);
