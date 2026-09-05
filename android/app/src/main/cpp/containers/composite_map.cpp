#include "composite_map.h"
#include <algorithm>
#include <cstring>
#include <openssl/sha.h>
#include <unistd.h>

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
}

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

    uint64_t allocatedSoFar = 0;
    for (size_t i = 0; i < budgets.size(); ++i) {
        const auto& b = budgets[i];
        if (b.allocatableBytes < 512) continue;

        uint64_t len = b.allocatableBytes;
        if (requestedTotalBytes > 0 && allocatedSoFar + len > requestedTotalBytes) {
            uint64_t remaining = requestedTotalBytes - allocatedSoFar;
            len = (remaining / 512) * 512;
        }

        if (len >= 512) {
            extents.push_back({static_cast<uint32_t>(i), b.payloadOffset, len});
            allocatedSoFar += len;
        }

        if (requestedTotalBytes > 0 && allocatedSoFar >= requestedTotalBytes) {
            break;
        }
    }
    return extents;
}