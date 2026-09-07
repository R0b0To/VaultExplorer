#include "carrier_profiler.h"
#include <cstring>
#include <algorithm>
#include <vector>
#include <sys/stat.h>
#include <openssl/sha.h>
#include <android/log.h>

#undef min
#undef max

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "VaultExplorer_Composite", __VA_ARGS__)

namespace {
constexpr uint32_t kSectorSize = 512;
constexpr uint64_t kBlindTagConstA = 0xBF58476D1CE4E5B9ULL;
constexpr uint64_t kBlindTagConstB = 0x94D049BB133111EBULL;

uint64_t readBe64(const unsigned char* p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v = (v << 8) | p[i];
    return v;
}

uint64_t alignDownToSector(uint64_t bytes) {
    return (bytes / kSectorSize) * kSectorSize;
}

void computeHeaderDigest(int fd, unsigned char outDigest[SHA256_DIGEST_LENGTH]) {
    unsigned char buffer[4096] = {0};
    ssize_t n = ::pread64(fd, buffer, sizeof(buffer), 0);
    SHA256(buffer, n > 0 ? static_cast<size_t>(n) : 0, outDigest);
}

// Probes for the high-entropy blind trailer at EOF (zero plaintext signatures, maximal entropy)
bool probeBlindTrailer(int fd, uint64_t fileSize, uint64_t& outPayloadOffset, uint64_t& outPayloadLength) {
    if (fileSize < 16 + kSectorSize) return false;

    unsigned char tr[16] = {0};
    if (::pread64(fd, tr, 16, static_cast<off64_t>(fileSize - 16)) != 16) return false;

    unsigned char digest[SHA256_DIGEST_LENGTH];
    computeHeaderDigest(fd, digest);

    uint64_t maskKey1 = readBe64(digest);
    uint64_t maskKey2 = readBe64(digest + 8);

    uint64_t encOff = readBe64(tr);
    uint64_t encTag = readBe64(tr + 8);

    uint64_t candOff = encOff ^ maskKey1;
    uint64_t expectedTag = (candOff * kBlindTagConstA + kBlindTagConstB) ^ maskKey2;

    if (encTag == expectedTag && candOff < fileSize - 16) {
        uint64_t storedLen = (fileSize - 16) - candOff;
        if (storedLen >= kSectorSize) {
            outPayloadOffset = candOff;
            outPayloadLength = alignDownToSector(storedLen);
            return true;
        }
    }
    return false;
}
} // namespace

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

    // ── 1. Check for Existing Cryptographic Blind Trailer ──
    uint64_t existingOffset = 0;
    uint64_t existingLength = 0;

    if (probeBlindTrailer(fd, budget.fileSize, existingOffset, existingLength)) {
        budget.alreadyAllocated = true;
        budget.payloadOffset = existingOffset;
        budget.allocatableBytes = existingLength;
        budget.tier = CarrierTier::High;
        budget.detectedFormat = "composite_carrier";
        LOGI("[Profiler] Carrier %u: verified allocated blind trailer! offset=%llu len=%llu",
             fileIndex, (unsigned long long)budget.payloadOffset, (unsigned long long)budget.allocatableBytes);
        return budget;
    }

    // ── 2. Recovery Mode Check ──
    if (!allocateMode) {
        budget.alreadyAllocated = false;
        budget.payloadOffset = 0;
        budget.allocatableBytes = 0;
        budget.detectedFormat = "unknown";
        budget.tier = CarrierTier::Low;
        return budget;
    }

    // ── 3. Allocation Mode (Fresh Carrier) ──
    // Determine growth percentage:
    // If safetyMarginPct >= 50 (e.g. 90% reserved margin), allocate (100 - safetyMarginPct) = 10%
    // If safetyMarginPct < 50 (e.g. 10% growth), allocate 10% directly
    unsigned growthPct = (safetyMarginPct >= 50) ? (100 - safetyMarginPct) : safetyMarginPct;
    if (growthPct == 0 || growthPct > 50) growthPct = 10; // Default to stealthy 10% expansion

    budget.alreadyAllocated = false;

    unsigned char header[64] = {0};
    ssize_t n = ::pread64(fd, header, sizeof(header), 0);
    if (n < 16) {
        budget.payloadOffset = budget.fileSize;
        uint64_t raw = (budget.fileSize * growthPct) / 100;
        budget.allocatableBytes = alignDownToSector(std::max<uint64_t>(kSectorSize, raw));
        return budget;
    }

    // ISO-BMFF: reserve 16 bytes for compliant 'free' box header
    if (std::memcmp(header + 4, "ftyp", 4) == 0) {
        budget.detectedFormat = "isobmff";
        budget.tier = CarrierTier::High;
        budget.payloadOffset = budget.fileSize + 16;
        uint64_t raw = (budget.fileSize * growthPct) / 100;
        budget.allocatableBytes = alignDownToSector(std::max<uint64_t>(kSectorSize, raw));
        return budget;
    }

    // PNG: strictly appended after the original PNG (keeping original IEND and CRC untouched)
    static const unsigned char kPngMagic[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
    if (std::memcmp(header, kPngMagic, 8) == 0) {
        budget.detectedFormat = "png";
        budget.tier = CarrierTier::High;
        budget.payloadOffset = budget.fileSize;
        uint64_t raw = (budget.fileSize * growthPct) / 100;
        budget.allocatableBytes = alignDownToSector(std::max<uint64_t>(kSectorSize, raw));
        return budget;
    }

    // JPEG: strictly appended after natural EOF (preserves all EXIF, gainmaps, and motion photo streams)
    if (header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF) {
        budget.detectedFormat = "jpeg";
        budget.tier = CarrierTier::Medium;
        budget.payloadOffset = budget.fileSize;
        uint64_t raw = (budget.fileSize * growthPct) / 100;
        budget.allocatableBytes = alignDownToSector(std::max<uint64_t>(kSectorSize, raw));
        return budget;
    }

    // Generic fallback
    budget.detectedFormat = "generic";
    budget.tier = CarrierTier::Low;
    budget.payloadOffset = budget.fileSize;
    uint64_t raw = (budget.fileSize * growthPct) / 100;
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

        if (b.alreadyAllocated) {
            profile.totalAllocatableBytes += b.allocatableBytes;
        }
        profile.perFile.push_back(b);
    }
    return profile;
}