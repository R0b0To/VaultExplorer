#include "carrier_profiler.h"
#include <cstring>
#include <algorithm>
#include <sys/stat.h>
#include <android/log.h>

#undef min
#undef max

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_Composite", __VA_ARGS__)

namespace {
constexpr uint32_t kSectorSize = 512;
static constexpr uint64_t kCompositeMagic = 0x5658434F4D504F53ULL; // "VXCOMPOS"

uint64_t readBe64(const unsigned char* p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v = (v << 8) | p[i];
    return v;
}

uint64_t alignDownToSector(uint64_t bytes) {
    return (bytes / kSectorSize) * kSectorSize;
}

// Scans for JPEG End-Of-Image marker (0xFF 0xD9)
int64_t findJpegEoi(int fd, uint64_t fileSize) {
    if (fileSize < 4) return -1;
    constexpr size_t kBufSize = 64 * 1024;
    std::vector<unsigned char> buf(kBufSize);
    
    // Check first 1MB from start to locate the end of the original photo
    uint64_t searchLimit = std::min<uint64_t>(fileSize, 64ULL * 1024 * 1024);
    uint64_t offset = 2; // skip 0xFF 0xD8 (SOI)

    while (offset < searchLimit) {
        size_t toRead = static_cast<size_t>(std::min<uint64_t>(kBufSize, searchLimit - offset));
        ssize_t n = ::pread64(fd, buf.data(), toRead, static_cast<off64_t>(offset));
        if (n <= 1) break;

        for (ssize_t i = 0; i < n - 1; ++i) {
            if (buf[i] == 0xFF && buf[i + 1] == 0xD9) {
                return static_cast<int64_t>(offset + i);
            }
        }
        offset += (n - 1);
    }
    return -1;
}

// Scans for PNG IEND marker
int64_t findPngIend(int fd, uint64_t fileSize) {
    if (fileSize < 12) return -1;
    constexpr size_t kBufSize = 64 * 1024;
    std::vector<unsigned char> buf(kBufSize);
    uint64_t searchLimit = std::min<uint64_t>(fileSize, 64ULL * 1024 * 1024);
    uint64_t offset = 8; // skip PNG signature

    while (offset < searchLimit) {
        size_t toRead = static_cast<size_t>(std::min<uint64_t>(kBufSize, searchLimit - offset));
        ssize_t n = ::pread64(fd, buf.data(), toRead, static_cast<off64_t>(offset));
        if (n <= 7) break;

        for (ssize_t i = 0; i <= n - 8; ++i) {
            if (std::memcmp(&buf[i], "IEND", 4) == 0) {
                return static_cast<int64_t>(offset + i);
            }
        }
        offset += (n - 7);
    }
    return -1;
}
}

CarrierBudget CarrierProfiler::inspectSingleCarrier(
    int fd, uint32_t fileIndex, const std::string& path, bool allocateMode, unsigned safetyMarginPct
) {
    CarrierBudget budget;
    budget.fileIndex = fileIndex;
    budget.path = path;
    budget.detectedFormat = "generic";
    budget.tier = CarrierTier::Low;
    budget.alreadyAllocated = false;

    if (fd < 0) return budget;

    struct stat st{};
    if (::fstat(fd, &st) != 0 || st.st_size <= 0) return budget;
    budget.fileSize = static_cast<uint64_t>(st.st_size);

    // ── 1. Check for 16-byte Composite Trailer: [8-byte offset | 8-byte 'VXCOMPOS'] ──
    if (budget.fileSize >= 16 + kSectorSize) {
        unsigned char trailer[16] = {0};
        if (::pread64(fd, trailer, 16, static_cast<off64_t>(budget.fileSize - 16)) == 16) {
            uint64_t magic = readBe64(trailer + 8);
            uint64_t savedOffset = readBe64(trailer);
            if (magic == kCompositeMagic && savedOffset < budget.fileSize - 16) {
                uint64_t storedLength = (budget.fileSize - 16) - savedOffset;
                if (storedLength >= kSectorSize) {
                    budget.alreadyAllocated = true;
                    budget.payloadOffset = savedOffset;
                    budget.allocatableBytes = alignDownToSector(storedLength);
                    budget.tier = CarrierTier::High;
                    budget.detectedFormat = "composite_carrier";
                    LOGI("[Profiler] Carrier %u: detected existing composite trailer! offset=%llu len=%llu",
                         fileIndex, (unsigned long long)budget.payloadOffset, (unsigned long long)budget.allocatableBytes);
                    return budget;
                }
            }
        }
    }

    unsigned char header[64] = {0};
    ssize_t n = ::pread64(fd, header, sizeof(header), 0);
    if (n < 16) {
        budget.payloadOffset = budget.fileSize;
        return budget;
    }

    // ── 2. Check JPEG: FF D8 FF ──
    if (header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF) {
        budget.detectedFormat = "jpeg";
        budget.tier = CarrierTier::Medium;

        int64_t eoi = findJpegEoi(fd, budget.fileSize);
        if (eoi > 0 && static_cast<uint64_t>(eoi + 2 + kSectorSize) <= budget.fileSize) {
            // Already contains an appended payload!
            budget.alreadyAllocated = true;
            budget.payloadOffset = static_cast<uint64_t>(eoi + 2);
            budget.allocatableBytes = alignDownToSector(budget.fileSize - budget.payloadOffset);
            LOGI("[Profiler] Carrier %u (JPEG): detected payload after EOI! offset=%llu len=%llu",
                 fileIndex, (unsigned long long)budget.payloadOffset, (unsigned long long)budget.allocatableBytes);
            return budget;
        }

        budget.payloadOffset = budget.fileSize;
        uint64_t raw = (budget.fileSize * safetyMarginPct) / 100;
        budget.allocatableBytes = alignDownToSector(std::max<uint64_t>(kSectorSize, raw));
        return budget;
    }

    // ── 3. Check PNG: 89 50 4E 47 0D 0A 1A 0A ──
    static const unsigned char kPngMagic[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
    if (std::memcmp(header, kPngMagic, 8) == 0) {
        budget.detectedFormat = "png";
        budget.tier = CarrierTier::High;

        int64_t iend = findPngIend(fd, budget.fileSize);
        // IEND chunk is 4 bytes length + 4 bytes 'IEND' + 4 bytes CRC = 12 bytes
        if (iend >= 4 && static_cast<uint64_t>(iend + 8 + kSectorSize) <= budget.fileSize) {
            budget.alreadyAllocated = true;
            budget.payloadOffset = static_cast<uint64_t>(iend + 8);
            budget.allocatableBytes = alignDownToSector(budget.fileSize - budget.payloadOffset);
            LOGI("[Profiler] Carrier %u (PNG): detected payload after IEND! offset=%llu len=%llu",
                 fileIndex, (unsigned long long)budget.payloadOffset, (unsigned long long)budget.allocatableBytes);
            return budget;
        }

        budget.payloadOffset = budget.fileSize + 8;
        uint64_t raw = (budget.fileSize * safetyMarginPct) / 100;
        budget.allocatableBytes = alignDownToSector(std::max<uint64_t>(kSectorSize, raw));
        return budget;
    }

    // ── 4. Check ISO-BMFF (MP4, MOV, M4A) ──
    if (std::memcmp(header + 4, "ftyp", 4) == 0) {
        budget.detectedFormat = "isobmff";
        budget.tier = CarrierTier::High;
        budget.payloadOffset = budget.fileSize + 8;
        uint64_t raw = (budget.fileSize * safetyMarginPct) / 100;
        budget.allocatableBytes = alignDownToSector(std::max<uint64_t>(kSectorSize, raw));
        return budget;
    }

    // ── 5. Generic fallback ──
    budget.detectedFormat = "generic";
    budget.tier = CarrierTier::Low;
    budget.payloadOffset = budget.fileSize;
    uint64_t raw = (budget.fileSize * safetyMarginPct) / 100;
    budget.allocatableBytes = alignDownToSector(std::max<uint64_t>(kSectorSize, raw));
    return budget;
}

CapacityProfile CarrierProfiler::profileForAllocation(
    const std::vector<CarrierTarget>& carriers, unsigned safetyMarginPct
) {
    CapacityProfile profile;
    profile.totalAllocatableBytes = 0;

    for (uint32_t i = 0; i < carriers.size(); ++i) {
        int fd = carriers[i].fd;
        bool openedHere = false;
        if (fd < 0 && !carriers[i].path.empty()) {
            fd = ::open(carriers[i].path.c_str(), O_RDONLY);
            openedHere = true;
        }

        CarrierBudget b = inspectSingleCarrier(fd, i, carriers[i].path, true, safetyMarginPct);
        if (openedHere && fd >= 0) ::close(fd);

        profile.totalAllocatableBytes += b.allocatableBytes;
        profile.perFile.push_back(b);
    }
    return profile;
}

CapacityProfile CarrierProfiler::profileForRecovery(
    const std::vector<CarrierTarget>& carriers
) {
    CapacityProfile profile;
    profile.totalAllocatableBytes = 0;

    for (uint32_t i = 0; i < carriers.size(); ++i) {
        int fd = carriers[i].fd;
        bool openedHere = false;
        if (fd < 0 && !carriers[i].path.empty()) {
            fd = ::open(carriers[i].path.c_str(), O_RDONLY);
            openedHere = true;
        }

        CarrierBudget b = inspectSingleCarrier(fd, i, carriers[i].path, false, 90);
        if (openedHere && fd >= 0) ::close(fd);

        profile.totalAllocatableBytes += b.allocatableBytes;
        profile.perFile.push_back(b);
    }
    return profile;
}