#include "vdisk.h"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <vector>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <android/log.h>

#include "vhd_image.h"
#include "vhdx_image.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_VDISK", __VA_ARGS__)

namespace {

constexpr uint64_t kMiB = 1024ull * 1024ull;
constexpr size_t kVhdFooterSize = 512;
constexpr size_t kVhdDynHeaderSize = 1024;

// ── byte helpers ─────────────────────────────────────────────────────────

uint32_t rdBE32(const unsigned char* p) {
    return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | uint32_t(p[3]);
}
uint64_t rdBE64(const unsigned char* p) { return (uint64_t(rdBE32(p)) << 32) | rdBE32(p + 4); }
void wrBE32(unsigned char* p, uint32_t v) {
    p[0] = v >> 24; p[1] = (v >> 16) & 0xFF; p[2] = (v >> 8) & 0xFF; p[3] = v & 0xFF;
}
void wrBE64(unsigned char* p, uint64_t v) { wrBE32(p, uint32_t(v >> 32)); wrBE32(p + 4, uint32_t(v)); }

uint16_t rdLE16(const unsigned char* p) { return uint16_t(p[0] | (p[1] << 8)); }
uint32_t rdLE32(const unsigned char* p) {
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}
uint64_t rdLE64(const unsigned char* p) { return uint64_t(rdLE32(p)) | (uint64_t(rdLE32(p + 4)) << 32); }
void wrLE32(unsigned char* p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (v >> (8 * i)) & 0xFF; }
void wrLE64(unsigned char* p, uint64_t v) { for (int i = 0; i < 8; i++) p[i] = (v >> (8 * i)) & 0xFF; }

bool preadFull(int fd, uint64_t off, void* buf, size_t len) {
    unsigned char* p = static_cast<unsigned char*>(buf);
    size_t done = 0;
    while (done < len) {
        const ssize_t n = ::pread(fd, p + done, len - done, static_cast<off_t>(off + done));
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        done += size_t(n);
    }
    return true;
}
bool pwriteFull(int fd, uint64_t off, const void* buf, size_t len) {
    const unsigned char* p = static_cast<const unsigned char*>(buf);
    size_t done = 0;
    while (done < len) {
        const ssize_t n = ::pwrite(fd, p + done, len - done, static_cast<off_t>(off + done));
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        done += size_t(n);
    }
    return true;
}
bool syncFd(int fd) { return ::fsync(fd) == 0; }

uint64_t roundUp(uint64_t v, uint64_t a) { return (v + a - 1) / a * a; }

// CRC-32C (Castagnoli, reflected 0x82F63B78): the VHDX header / region table checksum.
uint32_t crc32c(const unsigned char* data, size_t len) {
    static uint32_t table[256];
    static bool ready = false;
    if (!ready) {
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int k = 0; k < 8; k++) c = (c & 1) ? (0x82F63B78u ^ (c >> 1)) : (c >> 1);
            table[i] = c;
        }
        ready = true;
    }
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++) crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    return ~crc;
}

bool fillRandom(unsigned char* out, size_t len) {
    const int fd = ::open("/dev/urandom", O_RDONLY);
    if (fd < 0) return false;
    size_t done = 0;
    bool ok = true;
    while (done < len) {
        const ssize_t n = ::read(fd, out + done, len - done);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { ok = false; break; }
        done += size_t(n);
    }
    ::close(fd);
    return ok;
}

// ── legacy VHD ───────────────────────────────────────────────────────────

const unsigned char kVhdCookie[8] = {'c', 'o', 'n', 'e', 'c', 't', 'i', 'x'};
const unsigned char kVhdDynCookie[8] = {'c', 'x', 's', 'p', 'a', 'r', 's', 'e'};

// One's complement of the byte sum, the checksum field itself counted as zero (footer: bytes 64..67, dynamic
// header: bytes 36..39).
uint32_t vhdChecksum(const unsigned char* data, size_t len, size_t checksumOffset) {
    uint32_t sum = 0;
    for (size_t i = 0; i < len; i++)
        if (i < checksumOffset || i >= checksumOffset + 4) sum += data[i];
    return ~sum;
}

// CHS geometry from the VHD specification's appendix (what Virtual PC / Windows write into the footer).
uint32_t vhdGeometry(uint64_t sizeBytes) {
    uint64_t totalSectors = sizeBytes / 512;
    if (totalSectors > 65535ull * 16 * 255) totalSectors = 65535ull * 16 * 255;
    uint64_t spt, heads, cylTimesHeads;
    if (totalSectors >= 65535ull * 16 * 63) {
        spt = 255; heads = 16; cylTimesHeads = totalSectors / spt;
    } else {
        spt = 17;
        cylTimesHeads = totalSectors / spt;
        heads = (cylTimesHeads + 1023) / 1024;
        if (heads < 4) heads = 4;
        if (cylTimesHeads >= heads * 1024 || heads > 16) {
            spt = 31; heads = 16; cylTimesHeads = totalSectors / spt;
        }
        if (cylTimesHeads >= heads * 1024) {
            spt = 63; heads = 16; cylTimesHeads = totalSectors / spt;
        }
    }
    const uint64_t cylinders = cylTimesHeads / heads;
    return (uint32_t(cylinders & 0xFFFF) << 16) | (uint32_t(heads) << 8) | uint32_t(spt);
}

// Sets the current size (the size the virtual machine sees), refreshes the CHS geometry and the checksum. The
// "original size" field is informational (size at creation) and stays as it was.
void vhdFooterSetSize(unsigned char footer[kVhdFooterSize], uint64_t newSize) {
    wrBE64(footer + 48, newSize);
    wrBE32(footer + 56, vhdGeometry(newSize));
    wrBE32(footer + 64, 0);
    wrBE32(footer + 64, vhdChecksum(footer, kVhdFooterSize, 64));
}

VdiskGrowStatus growVhdFixed(int fd, uint64_t fileSize, uint64_t requested, VdiskGrowReport* rep) {
    unsigned char footer[kVhdFooterSize];
    if (fileSize < kVhdFooterSize || !preadFull(fd, fileSize - kVhdFooterSize, footer, sizeof(footer)))
        return VdiskGrowStatus::kIoError;
    if (std::memcmp(footer, kVhdCookie, 8) != 0 || rdBE32(footer + 60) != 2) {
        rep->reason = "not a fixed VHD";
        return VdiskGrowStatus::kUnsupported;
    }
    const uint64_t oldSize = fileSize - kVhdFooterSize;
    if (rdBE64(footer + 48) != oldSize) {
        rep->reason = "fixed VHD footer size does not match the file size";
        return VdiskGrowStatus::kUnsupported;
    }
    const uint64_t newSize = requested / kVdiskGrowAlign * kVdiskGrowAlign;
    rep->oldSize = oldSize;
    rep->newSize = newSize;
    if (newSize <= oldSize) return VdiskGrowStatus::kNotLarger;

    // Footer first, at the new end (this single write also extends the file): an interruption afterwards leaves a
    // valid footer at the end of the file. Then the old footer, now inside the disk, is cleared.
    vhdFooterSetSize(footer, newSize);
    if (!pwriteFull(fd, newSize, footer, sizeof(footer)) || !syncFd(fd)) return VdiskGrowStatus::kIoError;
    const unsigned char zeros[kVhdFooterSize] = {0};
    if (!pwriteFull(fd, oldSize, zeros, sizeof(zeros)) || !syncFd(fd)) return VdiskGrowStatus::kIoError;
    return VdiskGrowStatus::kOk;
}

VdiskGrowStatus growVhdDynamic(int fd, uint64_t fileSize, uint64_t requested, VdiskGrowReport* rep) {
    unsigned char footer[kVhdFooterSize];
    if (fileSize < kVhdFooterSize || fileSize % 512 != 0 ||
        !preadFull(fd, fileSize - kVhdFooterSize, footer, sizeof(footer)))
        return VdiskGrowStatus::kIoError;
    if (std::memcmp(footer, kVhdCookie, 8) != 0 || rdBE32(footer + 60) != 3) {
        rep->reason = "not a dynamic VHD";
        return VdiskGrowStatus::kUnsupported;
    }
    const uint64_t oldSize = rdBE64(footer + 48);
    const uint64_t newSize = requested / kVdiskGrowAlign * kVdiskGrowAlign;
    rep->oldSize = oldSize;
    rep->newSize = newSize;
    if (newSize <= oldSize) return VdiskGrowStatus::kNotLarger;

    const uint64_t dynOffset = rdBE64(footer + 16);
    unsigned char dyn[kVhdDynHeaderSize];
    if (dynOffset % 512 != 0 || dynOffset + sizeof(dyn) > fileSize || !preadFull(fd, dynOffset, dyn, sizeof(dyn)))
        return VdiskGrowStatus::kIoError;
    if (std::memcmp(dyn, kVhdDynCookie, 8) != 0) {
        rep->reason = "bad dynamic disk header";
        return VdiskGrowStatus::kUnsupported;
    }
    const uint64_t batOffset = rdBE64(dyn + 16);
    const uint32_t maxEntries = rdBE32(dyn + 28);
    const uint32_t blockSize = rdBE32(dyn + 32);
    if (batOffset % 512 != 0 || blockSize == 0 || blockSize % 512 != 0 || (blockSize & (blockSize - 1)) != 0 ||
        batOffset + uint64_t(maxEntries) * 4 > fileSize) {
        rep->reason = "implausible dynamic VHD layout";
        return VdiskGrowStatus::kUnsupported;
    }
    const uint64_t oldNeeded = (oldSize + blockSize - 1) / blockSize;
    const uint64_t newBlocks = (newSize + blockSize - 1) / blockSize;
    if (maxEntries < oldNeeded) {
        rep->reason = "dynamic VHD BAT is smaller than its disk size requires";
        return VdiskGrowStatus::kUnsupported;
    }
    if (newBlocks > 0xFFFFFFFEull) {
        rep->reason = "too many blocks for a VHD";
        return VdiskGrowStatus::kNoRoom;
    }

    unsigned char newFooter[kVhdFooterSize];
    std::memcpy(newFooter, footer, sizeof(footer));
    vhdFooterSetSize(newFooter, newSize);

    // The copy of the footer at the start of the file (identical to the trailing one in files written by Windows and
    // qemu); refreshed along with it when present.
    unsigned char first[kVhdFooterSize];
    const bool hasFirstCopy = fileSize >= 2 * kVhdFooterSize && preadFull(fd, 0, first, sizeof(first)) &&
                              std::memcmp(first, kVhdCookie, 8) == 0;

    if (newBlocks <= maxEntries) {   // the BAT already advertises enough entries: only the size changes
        if (!pwriteFull(fd, fileSize - kVhdFooterSize, newFooter, sizeof(newFooter))) return VdiskGrowStatus::kIoError;
        if (hasFirstCopy && !pwriteFull(fd, 0, newFooter, sizeof(newFooter))) return VdiskGrowStatus::kIoError;
        return syncFd(fd) ? VdiskGrowStatus::kOk : VdiskGrowStatus::kIoError;
    }

    const uint64_t oldBatBytes = roundUp(uint64_t(maxEntries) * 4, 512);
    const uint64_t newBatBytes = roundUp(newBlocks * 4, 512);
    unsigned char newDyn[kVhdDynHeaderSize];
    std::memcpy(newDyn, dyn, sizeof(dyn));
    wrBE32(newDyn + 28, uint32_t(newBlocks));

    if (newBatBytes <= oldBatBytes) {
        // In place: the BAT's sector padding has room. Entries first, then the header that announces them, then size.
        std::vector<unsigned char> fill((newBlocks - maxEntries) * 4, 0xFF);
        if (!pwriteFull(fd, batOffset + uint64_t(maxEntries) * 4, fill.data(), fill.size()) || !syncFd(fd))
            return VdiskGrowStatus::kIoError;
        wrBE32(newDyn + 36, 0);
        wrBE32(newDyn + 36, vhdChecksum(newDyn, sizeof(newDyn), 36));
        if (!pwriteFull(fd, dynOffset, newDyn, sizeof(newDyn)) || !syncFd(fd)) return VdiskGrowStatus::kIoError;
        if (!pwriteFull(fd, fileSize - kVhdFooterSize, newFooter, sizeof(newFooter))) return VdiskGrowStatus::kIoError;
        if (hasFirstCopy && !pwriteFull(fd, 0, newFooter, sizeof(newFooter))) return VdiskGrowStatus::kIoError;
        return syncFd(fd) ? VdiskGrowStatus::kOk : VdiskGrowStatus::kIoError;
    }

    // Relocate the BAT behind the existing data: [..data..][old footer][new BAT][footer]. The new BAT and a verbatim copy
    // of the old footer land past the current end of file first, so every intermediate state is a valid disk.
    std::vector<unsigned char> bat(newBatBytes, 0xFF);
    if (!preadFull(fd, batOffset, bat.data(), size_t(maxEntries) * 4)) return VdiskGrowStatus::kIoError;
    const uint64_t newBatOffset = fileSize;
    const uint64_t newFooterOffset = newBatOffset + newBatBytes;
    if (!pwriteFull(fd, newBatOffset, bat.data(), bat.size())) return VdiskGrowStatus::kIoError;
    if (!pwriteFull(fd, newFooterOffset, footer, sizeof(footer)) || !syncFd(fd)) return VdiskGrowStatus::kIoError;

    wrBE64(newDyn + 16, newBatOffset);
    wrBE32(newDyn + 36, 0);
    wrBE32(newDyn + 36, vhdChecksum(newDyn, sizeof(newDyn), 36));
    if (!pwriteFull(fd, dynOffset, newDyn, sizeof(newDyn)) || !syncFd(fd)) return VdiskGrowStatus::kIoError;

    if (!pwriteFull(fd, newFooterOffset, newFooter, sizeof(newFooter))) return VdiskGrowStatus::kIoError;
    if (hasFirstCopy && !pwriteFull(fd, 0, newFooter, sizeof(newFooter))) return VdiskGrowStatus::kIoError;
    if (!syncFd(fd)) return VdiskGrowStatus::kIoError;

    // The old trailing footer is dead space now; clear it so nothing mistakes it for a footer.
    const unsigned char zeros[kVhdFooterSize] = {0};
    if (!pwriteFull(fd, fileSize - kVhdFooterSize, zeros, sizeof(zeros)) || !syncFd(fd)) return VdiskGrowStatus::kIoError;
    return VdiskGrowStatus::kOk;
}

// ── VHDX ─────────────────────────────────────────────────────────────────

constexpr uint64_t kVhdxHeader1 = 64 * 1024ull;
constexpr uint64_t kVhdxHeader2 = 128 * 1024ull;
constexpr uint64_t kVhdxRegionTable1 = 192 * 1024ull;
constexpr uint64_t kVhdxRegionTable2 = 256 * 1024ull;
constexpr size_t kVhdxHeaderSize = 4096;
constexpr size_t kVhdxRegionTableSize = 64 * 1024;

const unsigned char kGuidBatRegion[16] = {0x66, 0x77, 0xc2, 0x2d, 0x23, 0xf6, 0x00, 0x42,
                                          0x9d, 0x64, 0x11, 0x5e, 0x9b, 0xfd, 0x4a, 0x08};
const unsigned char kGuidMetadataRegion[16] = {0x06, 0xa2, 0x7c, 0x8b, 0x90, 0x47, 0x9a, 0x4b,
                                               0xb8, 0xfe, 0x57, 0x5f, 0x05, 0x0f, 0x88, 0x6e};
const unsigned char kGuidFileParams[16] = {0x37, 0x67, 0xa1, 0xca, 0x36, 0xfa, 0x43, 0x4d,
                                           0xb3, 0xb6, 0x33, 0xf0, 0xaa, 0x44, 0xe7, 0x6b};
const unsigned char kGuidVirtualDiskSize[16] = {0x24, 0x42, 0xa5, 0x2f, 0x1b, 0xcd, 0x76, 0x48,
                                                0xb2, 0x11, 0x5d, 0xbe, 0xd8, 0x3b, 0xf4, 0xb8};
const unsigned char kGuidLogicalSector[16] = {0x1d, 0xbf, 0x41, 0x81, 0x6f, 0xa9, 0x09, 0x47,
                                              0xba, 0x47, 0xf2, 0x33, 0xa8, 0xfa, 0xab, 0x5f};

constexpr uint64_t kBatPayloadFullyPresent = 6;

bool allZero(const unsigned char* p, size_t n) {
    for (size_t i = 0; i < n; i++) if (p[i]) return false;
    return true;
}

VdiskGrowStatus growVhdx(int fd, uint64_t fileSize, uint64_t requested, VdiskGrowReport* rep) {
    // Headers: two copies, the valid one with the higher sequence number is current.
    unsigned char hdr[2][kVhdxHeaderSize];
    bool hdrValid[2] = {false, false};
    const uint64_t hdrOff[2] = {kVhdxHeader1, kVhdxHeader2};
    for (int i = 0; i < 2; i++) {
        if (!preadFull(fd, hdrOff[i], hdr[i], kVhdxHeaderSize)) continue;
        if (std::memcmp(hdr[i], "head", 4) != 0) continue;
        unsigned char tmp[kVhdxHeaderSize];
        std::memcpy(tmp, hdr[i], sizeof(tmp));
        wrLE32(tmp + 4, 0);
        hdrValid[i] = crc32c(tmp, sizeof(tmp)) == rdLE32(hdr[i] + 4);
    }
    int cur = -1;
    if (hdrValid[0] && hdrValid[1]) cur = rdLE64(hdr[0] + 8) >= rdLE64(hdr[1] + 8) ? 0 : 1;
    else if (hdrValid[0]) cur = 0;
    else if (hdrValid[1]) cur = 1;
    if (cur < 0) { rep->reason = "no valid VHDX header"; return VdiskGrowStatus::kUnsupported; }
    if (!allZero(hdr[cur] + 48, 16)) {   // LogGuid: a pending log would have to be replayed before any change
        rep->reason = "VHDX has a pending log";
        return VdiskGrowStatus::kUnsupported;
    }

    // Region table (two copies, first valid wins) -> BAT and metadata regions.
    std::vector<unsigned char> rt(kVhdxRegionTableSize);
    bool rtOk = false;
    for (uint64_t off : {kVhdxRegionTable1, kVhdxRegionTable2}) {
        if (!preadFull(fd, off, rt.data(), rt.size())) continue;
        if (std::memcmp(rt.data(), "regi", 4) != 0) continue;
        std::vector<unsigned char> tmp = rt;
        wrLE32(tmp.data() + 4, 0);
        if (crc32c(tmp.data(), tmp.size()) != rdLE32(rt.data() + 4)) continue;
        rtOk = true;
        break;
    }
    if (!rtOk) { rep->reason = "no valid VHDX region table"; return VdiskGrowStatus::kUnsupported; }
    const uint32_t regionCount = rdLE32(rt.data() + 8);
    if (regionCount > 2047) { rep->reason = "bad VHDX region count"; return VdiskGrowStatus::kUnsupported; }
    uint64_t batOff = 0, metaOff = 0;
    uint32_t batLen = 0, metaLen = 0;
    for (uint32_t i = 0; i < regionCount; i++) {
        const unsigned char* e = rt.data() + 16 + size_t(i) * 32;
        if (std::memcmp(e, kGuidBatRegion, 16) == 0) { batOff = rdLE64(e + 16); batLen = rdLE32(e + 24); }
        else if (std::memcmp(e, kGuidMetadataRegion, 16) == 0) { metaOff = rdLE64(e + 16); metaLen = rdLE32(e + 24); }
        else if (rdLE32(e + 28) & 1) { rep->reason = "VHDX needs an unknown required region"; return VdiskGrowStatus::kUnsupported; }
    }
    if (batOff == 0 || metaOff == 0 || batLen == 0 || metaLen < 64 * 1024) {
        rep->reason = "VHDX BAT or metadata region missing";
        return VdiskGrowStatus::kUnsupported;
    }

    // Metadata items.
    std::vector<unsigned char> meta(metaLen);
    if (!preadFull(fd, metaOff, meta.data(), meta.size())) return VdiskGrowStatus::kIoError;
    if (std::memcmp(meta.data(), "metadata", 8) != 0) { rep->reason = "bad VHDX metadata table"; return VdiskGrowStatus::kUnsupported; }
    const uint16_t itemCount = rdLE16(meta.data() + 10);
    if (itemCount > 2047 || 32 + size_t(itemCount) * 32 > meta.size()) { rep->reason = "bad VHDX metadata count"; return VdiskGrowStatus::kUnsupported; }
    uint64_t vdsFileOffset = 0, oldSize = 0;
    uint32_t blockSize = 0, logicalSector = 0, fileFlags = 0;
    bool haveParams = false, haveVds = false, haveSector = false;
    for (uint16_t i = 0; i < itemCount; i++) {
        const unsigned char* e = meta.data() + 32 + size_t(i) * 32;
        const uint32_t off = rdLE32(e + 16), len = rdLE32(e + 20);
        if (uint64_t(off) + len > meta.size()) continue;
        if (std::memcmp(e, kGuidFileParams, 16) == 0 && len >= 8) {
            blockSize = rdLE32(meta.data() + off); fileFlags = rdLE32(meta.data() + off + 4); haveParams = true;
        } else if (std::memcmp(e, kGuidVirtualDiskSize, 16) == 0 && len >= 8) {
            oldSize = rdLE64(meta.data() + off); vdsFileOffset = metaOff + off; haveVds = true;
        } else if (std::memcmp(e, kGuidLogicalSector, 16) == 0 && len >= 4) {
            logicalSector = rdLE32(meta.data() + off); haveSector = true;
        }
    }
    if (!haveParams || !haveVds || !haveSector) { rep->reason = "VHDX metadata items missing"; return VdiskGrowStatus::kUnsupported; }
    if (fileFlags & 2) { rep->reason = "differencing VHDX"; return VdiskGrowStatus::kUnsupported; }
    if (logicalSector != 512) { rep->reason = "VHDX logical sector size is not 512"; return VdiskGrowStatus::kUnsupported; }
    if (blockSize < kMiB || blockSize > 256 * kMiB || (blockSize & (blockSize - 1)) != 0) {
        rep->reason = "VHDX block size out of range";
        return VdiskGrowStatus::kUnsupported;
    }
    const bool fixed = (fileFlags & 1) != 0;

    const uint64_t newSize = requested / kVdiskGrowAlign * kVdiskGrowAlign;
    rep->oldSize = oldSize;
    rep->newSize = newSize;
    if (newSize <= oldSize) return VdiskGrowStatus::kNotLarger;

    // BAT geometry (same formula VhdxImage uses): payload entries with one sector-bitmap entry after every chunk.
    uint64_t chunkRatio = (uint64_t(1) << 23) * logicalSector / blockSize;
    if (chunkRatio == 0) chunkRatio = 1;
    const uint64_t oldPayload = (oldSize + blockSize - 1) / blockSize;
    const uint64_t newPayload = (newSize + blockSize - 1) / blockSize;
    auto entriesFor = [&](uint64_t payload) { return payload == 0 ? 0 : payload + (payload - 1) / chunkRatio; };
    const uint64_t oldEntries = entriesFor(oldPayload);
    const uint64_t newEntries = entriesFor(newPayload);
    if (uint64_t(batLen) < newEntries * 8) {
        rep->reason = "VHDX BAT region has no room for the added blocks";
        return VdiskGrowStatus::kNoRoom;
    }
    if (batOff + oldEntries * 8 > fileSize) { rep->reason = "VHDX BAT lies outside the file"; return VdiskGrowStatus::kUnsupported; }

    // 1. Payload (fixed disks only): new blocks appended at the end of the file, 1 MiB aligned.
    std::vector<unsigned char> batAdd(size_t((newEntries - oldEntries) * 8), 0);   // zero = NOT_PRESENT (dynamic / bitmap)
    if (fixed) {
        const uint64_t dataEnd = roundUp(fileSize, kMiB);
        const uint64_t newFileSize = dataEnd + (newPayload - oldPayload) * blockSize;
        if (::ftruncate(fd, static_cast<off_t>(newFileSize)) != 0) return VdiskGrowStatus::kIoError;
        for (uint64_t b = oldPayload; b < newPayload; b++) {
            const uint64_t fileOffset = dataEnd + (b - oldPayload) * blockSize;
            const uint64_t entryIndex = b + b / chunkRatio;
            wrLE64(batAdd.data() + (entryIndex - oldEntries) * 8, (fileOffset / kMiB) << 20 | kBatPayloadFullyPresent);
        }
        if (!syncFd(fd)) return VdiskGrowStatus::kIoError;
    }
    // 2. BAT entries (explicitly zeroed for dynamic disks so stale bytes in the spare region cannot be misread).
    if (!batAdd.empty() && (!pwriteFull(fd, batOff + oldEntries * 8, batAdd.data(), batAdd.size()) || !syncFd(fd)))
        return VdiskGrowStatus::kIoError;
    // 3. Virtual disk size metadata item (8 bytes, no checksum on the metadata region).
    unsigned char sizeBytes[8];
    wrLE64(sizeBytes, newSize);
    if (!pwriteFull(fd, vdsFileOffset, sizeBytes, sizeof(sizeBytes)) || !syncFd(fd)) return VdiskGrowStatus::kIoError;
    // 4. Header: a new sequence number and fresh write GUIDs, written to the non-current slot.
    unsigned char nh[kVhdxHeaderSize];
    std::memcpy(nh, hdr[cur], sizeof(nh));
    uint64_t seq = rdLE64(hdr[cur] + 8);
    if (hdrValid[1 - cur]) seq = std::max(seq, rdLE64(hdr[1 - cur] + 8));
    wrLE64(nh + 8, seq + 1);
    unsigned char guids[32];
    if (!fillRandom(guids, sizeof(guids))) return VdiskGrowStatus::kIoError;
    for (int g = 0; g < 2; g++) {   // random (version 4) GUIDs in the on-disk byte order
        guids[g * 16 + 7] = (guids[g * 16 + 7] & 0x0F) | 0x40;
        guids[g * 16 + 8] = (guids[g * 16 + 8] & 0x3F) | 0x80;
    }
    std::memcpy(nh + 16, guids, 16);        // FileWriteGuid
    std::memcpy(nh + 32, guids + 16, 16);   // DataWriteGuid
    wrLE32(nh + 4, 0);
    wrLE32(nh + 4, crc32c(nh, sizeof(nh)));
    if (!pwriteFull(fd, hdrOff[1 - cur], nh, sizeof(nh)) || !syncFd(fd)) return VdiskGrowStatus::kIoError;
    return VdiskGrowStatus::kOk;
}

}  // namespace

// ── public API ───────────────────────────────────────────────────────────

VdiskKind probeVdiskKind(int fd, uint64_t fileSize) {
    if (fd < 0) return VdiskKind::kNone;
    if (isVhdxContainer(fd)) return VdiskKind::kVhdx;
    switch (probeVhdDiskKind(fd, fileSize)) {
        case VhdDiskKind::kFixed: return VdiskKind::kVhdFixed;
        case VhdDiskKind::kDynamic: return VdiskKind::kVhdDynamic;
        default: return VdiskKind::kNone;
    }
}

VDisk::VDisk() = default;
VDisk::~VDisk() = default;

bool VDisk::open(int fd, uint64_t fileSize, bool requestReadWrite) {
    fd_ = fd;
    readWrite_ = requestReadWrite;
    kind_ = probeVdiskKind(fd, fileSize);
    switch (kind_) {
        case VdiskKind::kVhdx: {
            vhdx_.reset(new VhdxImage());
            if (!vhdx_->open(fd, requestReadWrite)) { lastError_ = vhdx_->lastError(); kind_ = VdiskKind::kNone; return false; }
            if (requestReadWrite && vhdx_->isReadOnly()) { lastError_ = "VHDX cannot be opened for writing"; kind_ = VdiskKind::kNone; return false; }
            size_ = vhdx_->virtualDiskSize();
            return true;
        }
        case VdiskKind::kVhdDynamic: {
            vhd_.reset(new VhdImage());
            if (!vhd_->open(fd, fileSize, requestReadWrite)) { lastError_ = vhd_->lastError(); kind_ = VdiskKind::kNone; return false; }
            size_ = vhd_->virtualDiskSize();
            return true;
        }
        case VdiskKind::kVhdFixed:
            size_ = fileSize - kVhdFooterSize;
            return true;
        case VdiskKind::kNone:
            break;
    }
    lastError_ = "not a supported virtual disk image";
    return false;
}

bool VDisk::pread(uint64_t offset, unsigned char* out, size_t len) {
    if (offset > size_ || len > size_ - offset) return false;
    switch (kind_) {
        case VdiskKind::kVhdx: return vhdx_->pread(offset, out, len);
        case VdiskKind::kVhdDynamic: return vhd_->pread(offset, out, len);
        case VdiskKind::kVhdFixed: return preadFull(fd_, offset, out, len);
        case VdiskKind::kNone: break;
    }
    return false;
}

bool VDisk::pwrite(uint64_t offset, const unsigned char* data, size_t len) {
    if (!readWrite_ || offset > size_ || len > size_ - offset) return false;
    switch (kind_) {
        case VdiskKind::kVhdx: return vhdx_->pwrite(offset, data, len);
        case VdiskKind::kVhdDynamic: return vhd_->pwrite(offset, data, len);
        case VdiskKind::kVhdFixed: return pwriteFull(fd_, offset, data, len);
        case VdiskKind::kNone: break;
    }
    return false;
}

VdiskGrowStatus vdiskGrow(int fd, uint64_t fileSize, uint64_t requestedBytes, VdiskGrowReport* report) {
    VdiskGrowReport local;
    VdiskGrowReport* rep = report ? report : &local;
    *rep = VdiskGrowReport{};
    switch (probeVdiskKind(fd, fileSize)) {
        case VdiskKind::kVhdFixed: return growVhdFixed(fd, fileSize, requestedBytes, rep);
        case VdiskKind::kVhdDynamic: return growVhdDynamic(fd, fileSize, requestedBytes, rep);
        case VdiskKind::kVhdx: return growVhdx(fd, fileSize, requestedBytes, rep);
        case VdiskKind::kNone: break;
    }
    rep->reason = "not a supported virtual disk image";
    return VdiskGrowStatus::kUnsupported;
}
