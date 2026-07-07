#include "cipher_shim.h"

// Baseline (pim == 0) iteration counts, per hash, for STANDARD CONTAINERS
// (non-system-encryption path — which is the only path this app uses).
//
// VERIFIED against upstream VeraCrypt source, Pkcs5.c,
// get_pkcs5_iteration_count(int pkcs5_prf_id, int pim, BOOL bBoot, int*
// pMemoryCost). Quoting the logic (bBoot is the "pre-boot / system
// encryption" flag — always FALSE for this app, since it only ever mounts
// standard file/USB containers, never does full-disk boot encryption):
//
//   SHA512:    (pim==0) ? 500000 : 15000 + pim*1000
//   WHIRLPOOL: (pim==0) ? 500000 : 15000 + pim*1000
//   BLAKE2S:   (pim==0) ? (bBoot?200000:500000) : (bBoot?pim*2048:15000+pim*1000)
//   SHA256:    (pim==0) ? (bBoot?200000:500000) : (bBoot?pim*2048:15000+pim*1000)
//   STREEBOG:  (pim==0) ? (bBoot?200000:500000) : (bBoot?pim*2048:15000+pim*1000)


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