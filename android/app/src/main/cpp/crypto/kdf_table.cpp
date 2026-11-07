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

// Upstream's MAX_PIM_VALUE (Common/Password.h): the largest PIM for which the
// PBKDF2 formula 15000 + PIM * 1000 still fits a positive 32-bit int. The old
// ceiling of 2000 silently turned any larger PIM into 2000, so a volume made
// with e.g. PIM 5000 could never be unlocked here (and a volume created here
// with PIM 5000 would not open anywhere else).
static constexpr int kMaxPim = 2147468;

int clampPim(int pim) {
    if (pim < 0) return 0;
    if (pim > kMaxPim) return kMaxPim;
    return pim;
}

// Shared by two callers with different relationships to "PIM":
//  - VeraCrypt volumes, where this formula IS VeraCrypt's own spec
//    (get_argon2_params() in 1.26.29) and clampedPim is a real,
//    user-facing value.
//  - LUKS2 container creation, where LUKS has no PIM concept at all --
//    clampedPim is 0 there today, and this function is reused purely as
//    a convenient memory/time/parallelism dial, not because cryptsetup
//    defines or expects these particular numbers. cryptsetup's own
//    default is a device-benchmark targeting ~2s at creation time, which
//    this app doesn't attempt to replicate; PIM=0 -> PIM=12's fixed
//    values (416 MiB, 6 passes, parallelism 1) are used instead as a
//    deliberate, reasonable-for-mobile substitute. LUKS2 stores whatever
//    parameters are chosen here in its own JSON keyslot metadata, so this
//    choice only affects containers this app creates -- it has no effect
//    on opening containers created elsewhere.
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