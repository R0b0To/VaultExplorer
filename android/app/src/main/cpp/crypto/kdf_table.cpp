#include "cipher_shim.h"
#include <algorithm>

struct KdfParams {
    HashId hash;
    int baselineIterations;   // pim == 0
    int pimBase;               // additive base when pim > 0
    int pimStep;                // per-PIM-unit multiplier
};

static const KdfParams kKdfTable[] = {
    { HashId::kSha512,     500000, 15000, 1000 },
    { HashId::kWhirlpool,  500000, 15000, 1000 },
    { HashId::kSha256,     500000, 15000, 1000 },
    { HashId::kStreebog,   500000, 15000, 1000 },
    { HashId::kBlake2s256, 500000, 15000, 1000 },
};

int iterationsForHash(HashId hash, int clampedPim) {
    for (const auto& row : kKdfTable) {
        if (row.hash == hash) {
            return clampedPim > 0
                ? (row.pimBase + clampedPim * row.pimStep)
                : row.baselineIterations;
        }
    }
    return 500000; // conservative fallback, should be unreachable
}

int clampPim(int pim) {
    if (pim < 0) return 0;
    if (pim > 2000) return 2000;
    return pim;
}

void argon2ParamsForPim(int clampedPim, uint32_t& memoryKiB,
                        uint32_t& timeCost, uint32_t& parallelism) {
    // VeraCrypt 1.26.29's get_argon2_params(): PIM 0 means its default 12.
    int pim = clampedPim > 0 ? clampedPim : 12;
    const int memoryMiB = std::min(64 + (pim - 1) * 32, 1024);
    memoryKiB = static_cast<uint32_t>(memoryMiB) * 1024;
    timeCost = static_cast<uint32_t>(pim <= 31 ? 3 + (pim - 1) / 3
                                               : 13 + (pim - 31));
    parallelism = 1;
}