#include "composite_map.h"
#include <algorithm>
#include <cstring>
#include <openssl/sha.h>
#include <unistd.h>
#include <vector>

#undef min
#undef max

namespace {
std::string computeCarrierHeaderDigest(int fd, const std::string& path) {
    bool closeFd = false;
    if (fd < 0 && !path.empty()) {
        fd = ::open(path.c_str(), O_RDONLY);
        closeFd = true;
    }
    if (fd < 0) return path;

    unsigned char buffer[4096] = {0};
    ssize_t n = ::pread64(fd, buffer, sizeof(buffer), 0);
    if (closeFd) ::close(fd);

    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256(buffer, n > 0 ? static_cast<size_t>(n) : 0, digest);

    char hex[SHA256_DIGEST_LENGTH * 2 + 1];
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i) {
        std::snprintf(&hex[i * 2], 3, "%02x", digest[i]);
    }
    return std::string(hex);
}
} // namespace

void CompositeMap::sortCanonical(std::vector<CarrierTarget>& carriers) {
    std::vector<std::pair<std::string, CarrierTarget>> decorated;
    decorated.reserve(carriers.size());

    for (const auto& c : carriers) {
        std::string digest = computeCarrierHeaderDigest(c.fd, c.path);
        decorated.push_back({digest, c});
    }

    std::sort(decorated.begin(), decorated.end(), [](const auto& a, const auto& b) {
        if (a.first != b.first) return a.first < b.first;
        if (a.second.path != b.second.path) return a.second.path < b.second.path;
        return a.second.fd < b.second.fd;
    });

    for (size_t i = 0; i < carriers.size(); ++i) {
        carriers[i] = decorated[i].second;
    }
}

std::vector<CarrierExtent> CompositeMap::deriveExtents(
    const std::vector<CarrierBudget>& budgets, uint64_t requestedTotalBytes
) {
    std::vector<CarrierExtent> extents;
    extents.reserve(budgets.size());
    if (budgets.empty()) return extents;

    uint64_t totalAvailable = 0;
    for (const auto& b : budgets) {
        totalAvailable += (b.allocatableBytes / 512) * 512;
    }
    if (totalAvailable < 512) return extents;

    // Allocate full budgets if no custom total was requested
    if (requestedTotalBytes == 0 || requestedTotalBytes >= totalAvailable) {
        for (size_t i = 0; i < budgets.size(); ++i) {
            const auto& b = budgets[i];
            uint64_t len = (b.allocatableBytes / 512) * 512;
            if (len >= 512) {
                extents.push_back({static_cast<uint32_t>(i), b.payloadOffset, len});
            }
        }
        return extents;
    }

    // Proportional distribution across all carriers:
    // Prevents carriers from doubling in size by sharing the requested container size evenly.
    uint64_t targetTotal = (requestedTotalBytes / 512) * 512;
    uint64_t allocatedSoFar = 0;

    for (size_t i = 0; i < budgets.size(); ++i) {
        const auto& b = budgets[i];
        uint64_t bCap = (b.allocatableBytes / 512) * 512;
        if (bCap < 512) continue;

        uint64_t share = static_cast<uint64_t>((static_cast<__uint128_t>(bCap) * targetTotal) / totalAvailable);
        share = (share / 512) * 512;
        if (share < 512 && targetTotal > allocatedSoFar) share = 512;

        if (allocatedSoFar + share > targetTotal) {
            share = targetTotal - allocatedSoFar;
        }

        if (share >= 512) {
            extents.push_back({static_cast<uint32_t>(i), b.payloadOffset, share});
            allocatedSoFar += share;
        }
    }

    // Distribute remainder sectors across carriers with available headroom
    for (size_t i = 0; i < extents.size() && allocatedSoFar < targetTotal; ++i) {
        uint32_t fileIdx = extents[i].fileIndex;
        uint64_t maxCap = (budgets[fileIdx].allocatableBytes / 512) * 512;
        if (extents[i].lengthBytes + 512 <= maxCap) {
            extents[i].lengthBytes += 512;
            allocatedSoFar += 512;
        }
    }

    return extents;
}

bool CompositeMap::prepareCarrierStructures(
    const std::vector<CarrierBudget>& budgets,
    const std::shared_ptr<CarrierFdCache>& fdCache
) {
    if (!fdCache) return false;

    for (size_t i = 0; i < budgets.size(); ++i) {
        const auto& b = budgets[i];
        if (b.allocatableBytes < 512) continue;

        int fd = fdCache->acquire(static_cast<uint32_t>(i));
        if (fd < 0) return false;

        // ISO-BMFF: write compliant 'free' box header
        if (b.detectedFormat == "isobmff" && b.payloadOffset >= 16) {
            uint64_t totalBoxSize = b.allocatableBytes + 16;
            unsigned char boxHdr[16];
            boxHdr[0] = 0x00; boxHdr[1] = 0x00; boxHdr[2] = 0x00; boxHdr[3] = 0x01;
            boxHdr[4] = 'f'; boxHdr[5] = 'r'; boxHdr[6] = 'e'; boxHdr[7] = 'e';
            for (int bit = 7; bit >= 0; --bit) {
                boxHdr[8 + bit] = static_cast<unsigned char>(totalBoxSize & 0xFF);
                totalBoxSize >>= 8;
            }
            ::pwrite64(fd, boxHdr, 16, static_cast<off_t>(b.payloadOffset - 16));
        }

        uint64_t endPos = b.payloadOffset + b.allocatableBytes;
        unsigned char zero = 0;
        if (::pwrite64(fd, &zero, 1, static_cast<off_t>(endPos - 1)) != 1) {
            ::ftruncate(fd, static_cast<off_t>(endPos));
        }

        fdCache->release(static_cast<uint32_t>(i));
    }
    return true;
}