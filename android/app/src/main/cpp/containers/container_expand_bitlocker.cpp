// "Expand BitLocker container": orchestration around containers/bl_expand.h (raw files) and
// containers/bl_disk_expand.h (VHD / VHDX disk images).
//
// Flow of expandBitLockerContainer() for a raw BitLocker file:
//   1. Probe sector 0 (must be a "-FVE-FS-" BitLocker volume header at byte 0 of the file).
//   2. Unlock once, read-only, through a scratch volume slot -- this proves the credential and yields the VMK that
//      the metadata's integrity datum is sealed with.
//   3. blExpandVolume(): extend the file, rewrite and re-seal the three FVE metadata copies (last copy first).
//   4. Only when needed, unlock again read-write: the new session reads the new encrypted volume size, which is what
//      lets dislocker write into the added range. Optionally fill it with encrypted zeros, then grow NTFS.
//
// A disk image (fixed/dynamic VHD, VHDX) follows the same shape, but step 3 is blDiskExpand(): it grows the virtual disk,
// then the last partition, then the BitLocker metadata inside that partition (see bl_disk_expand.h), and the unlocks open
// the BitLocker partition through the matching VHD/VHDX session opener.
//
// Why a second unlock instead of patching the live dislocker context: it keeps dislocker's internals untouched (only the
// VMK is read out), at the price of one more key derivation.
#include "container_create.h"

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <unistd.h>

#include <android/log.h>

#include "bl_disk_expand.h"
#include "bl_expand.h"
#include "bitlocker_backend.h"
#include "crypto/keyfile_mixing.h"   // ScopeZeroize
#include "fs_ops.h"
#include "mbedtls/platform_util.h"
#include "virtual_block_device.h"    // ensureMounted / unmountVolume
#include "volume_state.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_BDE_Expand", __VA_ARGS__)

namespace {

constexpr uint64_t kInitBatchBytes = 1024 * 1024;   // multiple of every BitLocker sector size (512..4096)
constexpr size_t kNtfsSectorCountOffset = 0x28;     // u64 "total sectors" in an NTFS boot sector and in the FVE volume header

// ── raw fd helpers ───────────────────────────────────────────────────────

bool preadFull(int fd, uint64_t offset, unsigned char* out, size_t len) {
    size_t done = 0;
    while (done < len) {
        const ssize_t n = pread(fd, out + done, len - done, static_cast<off_t>(offset + done));
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        done += static_cast<size_t>(n);
    }
    return true;
}

bool pwriteFull(int fd, uint64_t offset, const unsigned char* data, size_t len) {
    size_t done = 0;
    while (done < len) {
        const ssize_t n = pwrite(fd, data + done, len - done, static_cast<off_t>(offset + done));
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        done += static_cast<size_t>(n);
    }
    return true;
}

BlExpandIo makeFdIo(int fd) {
    BlExpandIo io;
    io.readAt = [fd](uint64_t off, unsigned char* out, size_t len) { return preadFull(fd, off, out, len); };
    io.writeAt = [fd](uint64_t off, const unsigned char* data, size_t len) { return pwriteFull(fd, off, data, len); };
    io.setSize = [fd](uint64_t n) { return ftruncate(fd, static_cast<off_t>(n)) == 0; };
    io.sync = [fd]() { return fsync(fd) == 0; };
    return io;
}

// Windows FILETIME (100 ns ticks since 1601) -- the first 8 bytes of the metadata AES-CCM nonces.
uint64_t fileTimeNow() {
    return (static_cast<uint64_t>(time(nullptr)) + 11644473600ull) * 10000000ull;
}

// ── scratch volume slots (same claiming convention as the LUKS file-system grow) ─────────

enum class OpenResult { kOk, kBadCredentials, kNoResources };

// Opens the BitLocker volume in a scratch slot. [disk] null: a raw BitLocker file (the whole file is the volume).
// Otherwise the volume lives in a disk image at disk->partStartBytes with disk->partBytes, reached through the opener
// that matches the image format.
OpenResult openScratchSession(int fd, const unsigned char* password, size_t passwordLen, bool readOnly,
                              const BlDiskLocation* disk, int* outSlot) {
    int slot = -1;
    {
        std::lock_guard<std::mutex> allocLock(slotAllocMutex);
        for (int i = 0; i < FF_VOLUMES; ++i) {
            if (!volumes[i].dataCtxInitialized) {
                volumes[i].dataCtxInitialized = true;
                slot = i;
                break;
            }
        }
    }
    if (slot < 0) {
        LOGI("no free volume slots");
        return OpenResult::kNoResources;
    }
    const int sessionFd = dup(fd);   // the session owns (and closes) its own descriptor
    if (sessionFd < 0) {
        volumes[slot].reset();
        return OpenResult::kNoResources;
    }
    bool ok = false;
    if (disk == nullptr) {
        // Raw container: the whole file is the volume (partition offset/size 0), no unlock-progress events.
        ok = prepareBitLockerSession(sessionFd, password, passwordLen, slot, readOnly, 0, 0, /*quietProgress=*/true);
    } else {
        switch (disk->kind) {
            case VdiskKind::kVhdx:
                ok = prepareBitLockerSessionVhdx(sessionFd, password, passwordLen, slot, readOnly,
                                                 disk->partStartBytes, disk->partBytes, /*quietProgress=*/true);
                break;
            case VdiskKind::kVhdDynamic:
                ok = prepareBitLockerSessionVhd(sessionFd, password, passwordLen, slot, readOnly,
                                                disk->partStartBytes, disk->partBytes, /*quietProgress=*/true);
                break;
            case VdiskKind::kVhdFixed:   // flat: the virtual disk is the start of the file
                ok = prepareBitLockerSession(sessionFd, password, passwordLen, slot, readOnly,
                                             disk->partStartBytes, disk->partBytes, /*quietProgress=*/true);
                break;
            case VdiskKind::kNone:
                close(sessionFd);
                break;
        }
    }
    if (!ok) {
        volumes[slot].reset();       // the opener already closed sessionFd
        return OpenResult::kBadCredentials;
    }
    *outSlot = slot;
    return OpenResult::kOk;
}

// ── NTFS grow inside an open read-write session ──────────────────────────

// Reads the NTFS "total sectors" of the decrypted boot sector (logical sector 0), if it is an NTFS boot sector.
bool readNtfsSectorCount(int slot, uint64_t& count) {
    unsigned char sector[512];
    if (!bitlockerRead(slot, 0, sector, sizeof(sector))) return false;
    if (std::memcmp(sector + 3, "NTFS    ", 8) != 0 || sector[510] != 0x55 || sector[511] != 0xAA) return false;
    count = blexp::rd64(sector + kNtfsSectorCountOffset);
    return true;
}

// Grows the NTFS file system of the open session to the BitLocker volume's encrypted size. The caller holds
// volumes[slot].mutex exclusively (ensureMounted and fsGrowToFit expect that, as in the LUKS grow path).
//
// The plaintext FVE volume header at byte 0 is a copy of the NTFS boot sector with a patched OEM id, so its sector
// count mirrors the NTFS one. When it did before the grow, it is kept in step afterwards so the two never disagree.
void growFileSystemInSession(int slot, uint64_t volumeBytes, FsGrowReport* report, bool syncVolumeHeader) {
    report->attempted = true;
    report->status = FsGrowStatus::kFailed;
    VolumeState& v = volumes[slot];

    // The grow must never reach past what BitLocker encrypts, even if the host file is larger than the volume.
    v.dataAreaLengthBytes = volumeBytes;

    uint64_t ntfsBefore = 0, vbrBefore = 0;
    unsigned char vbrCount[8];
    // Only for raw containers: there the plaintext volume header sits at file offset 0. In a disk image it is somewhere
    // inside the virtual disk, so this step is skipped (real Windows volumes keep 0 there anyway).
    const bool vbrMirrors = syncVolumeHeader && readNtfsSectorCount(slot, ntfsBefore) &&
                            preadFull(v.fd, kNtfsSectorCountOffset, vbrCount, sizeof(vbrCount)) &&
                            (vbrBefore = blexp::rd64(vbrCount)) == ntfsBefore;

    if (ensureMounted(slot)) {
        const std::string label = fsGetFilesystemLabel(slot);
        std::snprintf(report->fsLabel, sizeof(report->fsLabel), "%s", label.c_str());
        report->status = fsGrowToFit(slot);
        LOGI("file system %s -> status %d", report->fsLabel, static_cast<int>(report->status));
    } else {
        report->status = FsGrowStatus::kUnsupported;
    }
    unmountVolume(slot);   // flushes the grown boot sector through dislocker

    if (report->status == FsGrowStatus::kGrown && vbrMirrors) {
        uint64_t ntfsAfter = 0;
        if (readNtfsSectorCount(slot, ntfsAfter) && ntfsAfter != vbrBefore) {
            unsigned char updated[8];
            blexp::wr64(updated, ntfsAfter);
            if (!pwriteFull(v.fd, kNtfsSectorCountOffset, updated, sizeof(updated)) || fsync(v.fd) != 0)
                LOGI("could not update the volume header sector count");
        }
    }
}

// Fills [fromByte, toByte) of the volume with encrypted zeros through dislocker (both sector aligned).
bool fillWithEncryptedZeros(int slot, uint64_t fromByte, uint64_t toByte) {
    std::vector<unsigned char> zeros(static_cast<size_t>(kInitBatchBytes), 0);
    for (uint64_t pos = fromByte; pos < toByte;) {
        const uint64_t left = toByte - pos;
        const size_t n = static_cast<size_t>(left < kInitBatchBytes ? left : kInitBatchBytes);
        if (!bitlockerWrite(slot, pos, zeros.data(), n)) return false;
        pos += n;
    }
    return true;
}

ExpandOutcome outcomeFor(BlExpandResult r) {
    switch (r) {
        case BlExpandResult::kOk: return ExpandOutcome::kOk;
        case BlExpandResult::kNotBitLocker: return ExpandOutcome::kNotBitLocker;
        case BlExpandResult::kNotExpandable: return ExpandOutcome::kNotExpandable;
        case BlExpandResult::kInvalidMetadata: return ExpandOutcome::kInvalidHeader;
        case BlExpandResult::kNotLarger: return ExpandOutcome::kNotLarger;
        case BlExpandResult::kIoError: break;
    }
    return ExpandOutcome::kIoError;
}

// Shared pre-checks: the file must carry a BitLocker volume header at byte 0 in the layout this tool supports.
// BitLocker To Go volumes ("MSWIN4.1") and the encrypt-on-write layout are recognised but not expandable.
ExpandOutcome probeVolumeHeader(int fd) {
    if (!bitlockerDetectFile(fd, 0)) return ExpandOutcome::kNotBitLocker;
    unsigned char vbr[blexp::kVbrProbeLen];
    if (!preadFull(fd, 0, vbr, sizeof(vbr))) return ExpandOutcome::kIoError;
    blexp::VolumeInfo info;
    const BlExpandResult parsed = blexp::parseVolumeHeader(vbr, info);
    if (parsed == BlExpandResult::kNotBitLocker) return ExpandOutcome::kNotExpandable;   // BitLocker To Go
    if (parsed == BlExpandResult::kNotExpandable) return ExpandOutcome::kNotExpandable;  // encrypt-on-write layout
    return parsed == BlExpandResult::kOk ? ExpandOutcome::kOk : ExpandOutcome::kInvalidHeader;
}

ExpandOutcome outcomeForDisk(BlDiskResult r) {
    switch (r) {
        case BlDiskResult::kOk: return ExpandOutcome::kOk;
        case BlDiskResult::kNothingToDo: return ExpandOutcome::kNotLarger;
        case BlDiskResult::kNotBitLocker: return ExpandOutcome::kNotBitLocker;
        case BlDiskResult::kNotExpandable: return ExpandOutcome::kNotExpandable;
        case BlDiskResult::kInvalidMetadata: return ExpandOutcome::kInvalidHeader;
        case BlDiskResult::kDiskUnsupported: return ExpandOutcome::kDiskUnsupported;
        case BlDiskResult::kPartitionUnsupported: return ExpandOutcome::kPartitionUnsupported;
        case BlDiskResult::kIoError: break;
    }
    return ExpandOutcome::kIoError;
}

// Step 4 of an expansion, shared by raw files and disk images: in a fresh read-write session fill the added range with
// encrypted zeros and/or grow NTFS. [slot] is an open read-write session; it is reset before returning.
ExpandOutcome finishInSession(int slot, uint64_t oldVolume, uint64_t newVolume, bool initFreeSpace,
                              bool growFileSystem, FsGrowReport* fsReport, bool syncVolumeHeader) {
    ExpandOutcome outcome = ExpandOutcome::kOk;
    std::unique_lock<std::shared_mutex> vlock(volumes[slot].mutex);
    if (initFreeSpace && !fillWithEncryptedZeros(slot, oldVolume, newVolume)) {
        LOGI("free-space initialisation failed");
        outcome = ExpandOutcome::kIoError;   // the metadata already describes the larger volume
    } else if (growFileSystem && fsReport != nullptr) {
        growFileSystemInSession(slot, newVolume, fsReport, syncVolumeHeader);
    }
    volumes[slot].reset();
    return outcome;
}

// Disk image (fixed/dynamic VHD, VHDX): unlock the BitLocker partition read-only for the VMK, grow disk + partition +
// BitLocker metadata (bl_disk_expand.h), then fill / grow NTFS in a read-write session on the grown image.
ExpandOutcome expandDiskImage(int fd, uint64_t hostSize, const unsigned char* pw, size_t pwLen, int64_t newSizeBytes,
                              bool initFreeSpace, bool growFileSystem, FsGrowReport* fsReport) {
    if (pwLen == 0) return ExpandOutcome::kWrongPassword;
    BlDiskLocation loc;
    const BlDiskResult located = blDiskLocate(fd, hostSize, &loc);
    if (located != BlDiskResult::kOk) return outcomeForDisk(located);

    unsigned char vmk[32] = {0};
    ScopeZeroize vmkWiper(vmk, sizeof(vmk));
    size_t vmkLen = 0;
    {
        int slot = -1;
        const OpenResult opened = openScratchSession(fd, pw, pwLen, /*readOnly=*/true, &loc, &slot);
        if (opened == OpenResult::kBadCredentials) return ExpandOutcome::kWrongPassword;
        if (opened != OpenResult::kOk) return ExpandOutcome::kIoError;
        vmkLen = bitlockerExportVmk(slot, vmk, sizeof(vmk));
        volumes[slot].reset();   // closes the read-only view before the image is modified
    }
    if (vmkLen == 0) return ExpandOutcome::kNotExpandable;

    BlDiskExpandResult res;
    const BlDiskResult expanded = blDiskExpand(fd, loc, vmk, vmkLen, static_cast<uint64_t>(newSizeBytes),
                                               fileTimeNow(), &res);
    if (expanded != BlDiskResult::kOk) {
        LOGI("blDiskExpand failed: %d", static_cast<int>(expanded));
        return outcomeForDisk(expanded);
    }
    LOGI("disk image expanded: disk=%llu partition=%llu volume %llu -> %llu", (unsigned long long)res.newDiskBytes,
         (unsigned long long)res.newPartBytes, (unsigned long long)res.oldVolumeBytes,
         (unsigned long long)res.newVolumeBytes);

    if (!initFreeSpace && !(growFileSystem && fsReport != nullptr)) return ExpandOutcome::kOk;
    BlDiskLocation grown = loc;
    grown.diskBytes = res.newDiskBytes;
    grown.partBytes = res.newPartBytes;
    int slot = -1;
    if (openScratchSession(fd, pw, pwLen, /*readOnly=*/false, &grown, &slot) != OpenResult::kOk) {
        LOGI("second unlock failed after the disk image was expanded");
        if (growFileSystem && fsReport != nullptr) { fsReport->attempted = true; fsReport->status = FsGrowStatus::kFailed; }
        return initFreeSpace ? ExpandOutcome::kIoError : ExpandOutcome::kOk;
    }
    return finishInSession(slot, res.oldVolumeBytes, res.newVolumeBytes, initFreeSpace, growFileSystem, fsReport,
                           /*syncVolumeHeader=*/false);
}

ExpandOutcome growFileSystemOfDiskImage(int fd, uint64_t hostSize, const unsigned char* pw, size_t pwLen,
                                        FsGrowReport* fsReport) {
    if (pwLen == 0) return ExpandOutcome::kWrongPassword;
    BlDiskLocation loc;
    const BlDiskResult located = blDiskLocate(fd, hostSize, &loc);
    if (located != BlDiskResult::kOk) return outcomeForDisk(located);
    uint64_t volumeBytes = 0;
    const BlDiskResult sized = blDiskReadVolumeSize(fd, loc, &volumeBytes);
    if (sized != BlDiskResult::kOk) return outcomeForDisk(sized);

    int slot = -1;
    const OpenResult opened = openScratchSession(fd, pw, pwLen, /*readOnly=*/false, &loc, &slot);
    if (opened == OpenResult::kBadCredentials) return ExpandOutcome::kWrongPassword;
    if (opened != OpenResult::kOk) return ExpandOutcome::kIoError;
    std::unique_lock<std::shared_mutex> vlock(volumes[slot].mutex);
    growFileSystemInSession(slot, volumeBytes, fsReport, /*syncVolumeHeader=*/false);
    volumes[slot].reset();
    return ExpandOutcome::kOk;
}

}  // namespace

ExpandOutcome expandBitLockerContainer(int fd, const char* password, int64_t newSizeBytes, bool initFreeSpace,
                                       bool growFileSystem, FsGrowReport* fsReport) {
    std::lock_guard<std::mutex> lifecycleLock(volumeLifecycleMutex);
    if (containerFileIsUnlocked(fd)) {
        if (fd >= 0) close(fd);
        return ExpandOutcome::kContainerInUse;
    }

    ExpandOutcome outcome = ExpandOutcome::kIoError;
    const unsigned char* pw = reinterpret_cast<const unsigned char*>(password ? password : "");
    const size_t pwLen = password ? std::strlen(password) : 0;

    do {
        struct stat st{};
        if (fd < 0 || fstat(fd, &st) != 0 || st.st_size <= 0 || newSizeBytes <= 0) break;
        const uint64_t hostSize = static_cast<uint64_t>(st.st_size);

        // A VHD / VHDX (also a fixed VHD whose disk starts with the BitLocker volume) is a disk image, not a raw volume.
        if (probeVdiskKind(fd, hostSize) != VdiskKind::kNone) {
            outcome = expandDiskImage(fd, hostSize, pw, pwLen, newSizeBytes, initFreeSpace, growFileSystem, fsReport);
            break;
        }

        const ExpandOutcome probe = probeVolumeHeader(fd);
        if (probe != ExpandOutcome::kOk) { outcome = probe; break; }
        if (pwLen == 0) { outcome = ExpandOutcome::kWrongPassword; break; }

        // 2. Unlock read-only: credential check + VMK.
        unsigned char vmk[32] = {0};
        ScopeZeroize vmkWiper(vmk, sizeof(vmk));
        size_t vmkLen = 0;
        {
            int slot = -1;
            const OpenResult opened = openScratchSession(fd, pw, pwLen, /*readOnly=*/true, nullptr, &slot);
            if (opened == OpenResult::kBadCredentials) { outcome = ExpandOutcome::kWrongPassword; break; }
            if (opened != OpenResult::kOk) break;
            vmkLen = bitlockerExportVmk(slot, vmk, sizeof(vmk));
            volumes[slot].reset();
        }
        if (vmkLen == 0) { outcome = ExpandOutcome::kNotExpandable; break; }

        // 3. Rewrite the metadata (and extend the file).
        const BlExpandIo io = makeFdIo(fd);
        uint64_t oldVolume = 0, newVolume = 0;
        const BlExpandResult rewritten = blExpandVolume(vmk, vmkLen, hostSize, static_cast<uint64_t>(newSizeBytes),
                                                        fileTimeNow(), io, &oldVolume, &newVolume);
        if (rewritten != BlExpandResult::kOk) {
            LOGI("blExpandVolume failed: %d", static_cast<int>(rewritten));
            outcome = outcomeFor(rewritten);
            break;
        }
        outcome = ExpandOutcome::kOk;
        LOGI("metadata updated: %llu -> %llu bytes", static_cast<unsigned long long>(oldVolume),
             static_cast<unsigned long long>(newVolume));

        // 4. Free-space initialisation and file system grow, in a fresh read-write session.
        if (!initFreeSpace && !(growFileSystem && fsReport != nullptr)) break;
        int slot = -1;
        const OpenResult reopened = openScratchSession(fd, pw, pwLen, /*readOnly=*/false, nullptr, &slot);
        if (reopened != OpenResult::kOk) {
            LOGI("second unlock failed after the metadata update");
            if (initFreeSpace) outcome = ExpandOutcome::kIoError;
            if (growFileSystem && fsReport != nullptr) { fsReport->attempted = true; fsReport->status = FsGrowStatus::kFailed; }
            break;
        }
        outcome = finishInSession(slot, oldVolume, newVolume, initFreeSpace, growFileSystem, fsReport,
                                  /*syncVolumeHeader=*/true);
    } while (false);

    if (fd >= 0) close(fd);
    return outcome;
}

ExpandOutcome growBitLockerFileSystem(int fd, const char* password, FsGrowReport* fsReport) {
    std::lock_guard<std::mutex> lifecycleLock(volumeLifecycleMutex);
    if (containerFileIsUnlocked(fd)) {
        if (fd >= 0) close(fd);
        return ExpandOutcome::kContainerInUse;
    }

    ExpandOutcome outcome = ExpandOutcome::kIoError;
    const unsigned char* pw = reinterpret_cast<const unsigned char*>(password ? password : "");
    const size_t pwLen = password ? std::strlen(password) : 0;

    do {
        struct stat st{};
        if (fd < 0 || fstat(fd, &st) != 0 || st.st_size <= 0 || fsReport == nullptr) break;
        const uint64_t hostSize = static_cast<uint64_t>(st.st_size);

        if (probeVdiskKind(fd, hostSize) != VdiskKind::kNone) {
            outcome = growFileSystemOfDiskImage(fd, hostSize, pw, pwLen, fsReport);
            break;
        }

        const ExpandOutcome probe = probeVolumeHeader(fd);
        if (probe != ExpandOutcome::kOk) { outcome = probe; break; }
        if (pwLen == 0) { outcome = ExpandOutcome::kWrongPassword; break; }

        uint64_t volumeBytes = 0;
        uint32_t sectorSize = 0;
        const BlExpandIo io = makeFdIo(fd);
        const BlExpandResult sized = blReadEncryptedVolumeSize(io, hostSize, volumeBytes, sectorSize);
        if (sized != BlExpandResult::kOk) { outcome = outcomeFor(sized); break; }
        if (volumeBytes > hostSize) { outcome = ExpandOutcome::kNotExpandable; break; }

        int slot = -1;
        const OpenResult opened = openScratchSession(fd, pw, pwLen, /*readOnly=*/false, nullptr, &slot);
        if (opened == OpenResult::kBadCredentials) { outcome = ExpandOutcome::kWrongPassword; break; }
        if (opened != OpenResult::kOk) break;
        {
            std::unique_lock<std::shared_mutex> vlock(volumes[slot].mutex);
            growFileSystemInSession(slot, volumeBytes, fsReport, /*syncVolumeHeader=*/true);
            volumes[slot].reset();
        }
        outcome = ExpandOutcome::kOk;
    } while (false);

    if (fd >= 0) close(fd);
    return outcome;
}
