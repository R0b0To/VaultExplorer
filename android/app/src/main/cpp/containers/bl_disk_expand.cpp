#include "bl_disk_expand.h"

#include <cstring>
#include <sys/stat.h>
#include <unistd.h>

#include <android/log.h>

#include "bl_expand.h"
#include "disk_partition.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_BDE_Disk", __VA_ARGS__)

namespace {

DiskIo diskIoOf(VDisk& disk) {
    DiskIo io;
    io.read = [&disk](uint64_t off, unsigned char* out, size_t len) { return disk.pread(off, out, len); };
    io.write = [&disk](uint64_t off, const unsigned char* data, size_t len) { return disk.pwrite(off, data, len); };
    return io;
}

// Same I/O, but writes are accepted and dropped: lets ptGrowPartition() run all its checks as a dry run.
DiskIo dryRunIoOf(VDisk& disk) {
    DiskIo io = diskIoOf(disk);
    io.write = [](uint64_t, const unsigned char*, size_t) { return true; };
    return io;
}

BlExpandIo volumeIoOf(VDisk& disk, uint64_t partStart, int fd) {
    BlExpandIo io;
    io.readAt = [&disk, partStart](uint64_t off, unsigned char* out, size_t len) { return disk.pread(partStart + off, out, len); };
    io.writeAt = [&disk, partStart](uint64_t off, const unsigned char* data, size_t len) { return disk.pwrite(partStart + off, data, len); };
    io.setSize = [](uint64_t) { return false; };   // the disk and partition were grown beforehand; the volume never grows the host
    io.sync = [fd]() { return fsync(fd) == 0; };
    return io;
}

BlDiskResult fromBl(BlExpandResult r) {
    switch (r) {
        case BlExpandResult::kOk: return BlDiskResult::kOk;
        case BlExpandResult::kNotBitLocker: return BlDiskResult::kNotBitLocker;
        case BlExpandResult::kNotExpandable: return BlDiskResult::kNotExpandable;
        case BlExpandResult::kInvalidMetadata: return BlDiskResult::kInvalidMetadata;
        case BlExpandResult::kNotLarger: return BlDiskResult::kNothingToDo;
        case BlExpandResult::kIoError: break;
    }
    return BlDiskResult::kIoError;
}

bool isBitLockerSector(const unsigned char* s, bool* toGo) {
    if (std::memcmp(s + 3, "-FVE-FS-", 8) == 0) { *toGo = false; return true; }
    if (std::memcmp(s + 3, "MSWIN4.1", 8) == 0 && s[510] == 0x55 && s[511] == 0xAA) { *toGo = true; return true; }
    return false;
}

uint64_t currentFileSize(int fd) {
    struct stat st{};
    return fstat(fd, &st) == 0 ? static_cast<uint64_t>(st.st_size) : 0;
}

}  // namespace

BlDiskResult blDiskLocate(int fd, uint64_t fileSize, BlDiskLocation* loc) {
    *loc = BlDiskLocation{};
    VDisk disk;
    if (!disk.open(fd, fileSize, /*requestReadWrite=*/false)) {
        LOGI("not a supported disk image: %s", disk.lastError());
        return disk.kind() == VdiskKind::kNone && std::strstr(disk.lastError(), "not a supported") != nullptr
                   ? BlDiskResult::kNotBitLocker
                   : BlDiskResult::kDiskUnsupported;
    }
    loc->kind = disk.kind();
    loc->diskBytes = disk.size();
    const DiskIo io = diskIoOf(disk);

    // A BitLocker volume header also ends in 55 AA, so check for it before reading sector 0 as a partition table:
    // a volume that starts at byte 0 of the virtual disk has no partition table at all.
    bool toGo = false;
    unsigned char s0[512];
    if (!disk.pread(0, s0, sizeof(s0))) return BlDiskResult::kIoError;
    if (isBitLockerSector(s0, &toGo)) {
        if (toGo) return BlDiskResult::kNotExpandable;
        loc->wholeDisk = true;
        loc->partBytes = disk.size();
        return BlDiskResult::kOk;
    }

    std::vector<DiskPartition> parts;
    bool gpt = false;
    const PtResult scanned = ptScan(io, parts, gpt);
    if (scanned == PtResult::kNoTable || (scanned == PtResult::kOk && parts.empty())) return BlDiskResult::kNotBitLocker;
    if (scanned == PtResult::kIoError) return BlDiskResult::kIoError;
    if (scanned != PtResult::kOk) return BlDiskResult::kPartitionUnsupported;

    for (const DiskPartition& p : parts) {
        const uint64_t start = p.startLba * 512, bytes = p.sectors * 512;
        if (start >= disk.size() || bytes > disk.size() - start) continue;
        unsigned char s[512];
        if (!disk.pread(start, s, sizeof(s)) || !isBitLockerSector(s, &toGo)) continue;
        if (toGo) return BlDiskResult::kNotExpandable;
        loc->startLba = p.startLba;
        loc->partStartBytes = start;
        loc->partBytes = bytes;
        return BlDiskResult::kOk;
    }
    return BlDiskResult::kNotBitLocker;
}

BlDiskResult blDiskExpand(int fd, const BlDiskLocation& loc, const unsigned char* vmk, size_t vmkLen,
                          uint64_t requestedDiskBytes, uint64_t fileTime, BlDiskExpandResult* out) {
    BlDiskExpandResult local;
    BlDiskExpandResult* res = out ? out : &local;
    *res = BlDiskExpandResult{};

    const uint64_t newDisk = requestedDiskBytes / kVdiskGrowAlign * kVdiskGrowAlign;
    if (newDisk < loc.diskBytes) return BlDiskResult::kNothingToDo;   // never shrinks

    // ---- Phase 1: read-only checks of every layer. Nothing is modified if any of them refuses. ----
    {
        VDisk ro;
        if (!ro.open(fd, currentFileSize(fd), false)) return BlDiskResult::kDiskUnsupported;
        BlExpandPlan plan;
        const BlExpandResult planned =
            blPlanExpand(vmk, vmkLen, loc.partBytes, volumeIoOf(ro, loc.partStartBytes, fd), plan);
        if (planned != BlExpandResult::kOk) {
            LOGI("BitLocker pre-check failed: %d", static_cast<int>(planned));
            return fromBl(planned);
        }
        if (!loc.wholeDisk) {
            uint64_t dryNewSectors = 0;
            const PtResult dry = ptGrowPartition(dryRunIoOf(ro), newDisk, loc.startLba, &dryNewSectors);
            if (dry == PtResult::kIoError) return BlDiskResult::kIoError;
            if (dry != PtResult::kOk && dry != PtResult::kNothingToDo) {
                LOGI("partition pre-check failed: %d", static_cast<int>(dry));
                return BlDiskResult::kPartitionUnsupported;
            }
        }
    }   // the read-only VDisk (and its cached BAT) is closed before the image is modified

    // ---- Phase 2: grow the virtual disk. ----
    bool changed = false;
    VdiskGrowReport grow;
    const VdiskGrowStatus grown = vdiskGrow(fd, currentFileSize(fd), newDisk, &grow);
    switch (grown) {
        case VdiskGrowStatus::kOk: changed = true; break;
        case VdiskGrowStatus::kNotLarger: break;   // already that big: resume
        case VdiskGrowStatus::kIoError: return BlDiskResult::kIoError;
        case VdiskGrowStatus::kUnsupported:
        case VdiskGrowStatus::kNoRoom:
            LOGI("virtual disk cannot be grown: %s", grow.reason);
            return BlDiskResult::kDiskUnsupported;
    }

    // ---- Phase 3: partition, then BitLocker metadata, through a fresh read-write view of the grown image. ----
    VDisk rw;
    if (!rw.open(fd, currentFileSize(fd), true)) {
        LOGI("grown image cannot be reopened: %s", rw.lastError());
        return BlDiskResult::kIoError;
    }
    res->newDiskBytes = rw.size();
    res->newPartBytes = rw.size();
    if (!loc.wholeDisk) {
        uint64_t newSectors = 0;
        const PtResult pt = ptGrowPartition(diskIoOf(rw), rw.size(), loc.startLba, &newSectors);
        if (pt == PtResult::kOk) changed = true;
        else if (pt != PtResult::kNothingToDo) return pt == PtResult::kIoError ? BlDiskResult::kIoError : BlDiskResult::kPartitionUnsupported;
        res->newPartBytes = newSectors * 512;
    }

    const BlExpandIo vio = volumeIoOf(rw, loc.partStartBytes, fd);
    BlExpandPlan plan;
    const BlExpandResult replanned = blPlanExpand(vmk, vmkLen, res->newPartBytes, vio, plan);
    if (replanned != BlExpandResult::kOk) return fromBl(replanned);
    const BlExpandResult applied = blApplyExpand(vmk, vmkLen, res->newPartBytes, res->newPartBytes, fileTime, vio, plan,
                                                 &res->oldVolumeBytes, &res->newVolumeBytes);
    if (applied == BlExpandResult::kOk) return BlDiskResult::kOk;
    if (applied == BlExpandResult::kNotLarger) {
        res->oldVolumeBytes = res->newVolumeBytes = plan.oldVolumeSize;
        return changed ? BlDiskResult::kOk : BlDiskResult::kNothingToDo;
    }
    return fromBl(applied);
}

BlDiskResult blDiskReadVolumeSize(int fd, const BlDiskLocation& loc, uint64_t* volumeBytes) {
    VDisk ro;
    if (!ro.open(fd, currentFileSize(fd), false)) return BlDiskResult::kDiskUnsupported;
    uint32_t sectorSize = 0;
    const BlExpandResult r =
        blReadEncryptedVolumeSize(volumeIoOf(ro, loc.partStartBytes, fd), loc.partBytes, *volumeBytes, sectorSize);
    if (r != BlExpandResult::kOk) return fromBl(r);
    return *volumeBytes > loc.partBytes ? BlDiskResult::kNotExpandable : BlDiskResult::kOk;
}
