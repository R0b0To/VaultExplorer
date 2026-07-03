// crypto/kdf_table.cpp
#include "cipher_shim.h"

// Baseline (pim == 0) iteration counts, per hash, for STANDARD CONTAINERS
// (non-system-encryption path — which is the only path this app uses).
//
// SOURCE OF TRUTH: cross-check these against
//   <veracrypt_upstream>/src/Common/Pkcs5Kdf.cpp — look for
//   Pkcs5Kdf::GetPkcs5IterationCount() implementations, one per KDF class
//   (Pkcs5HmacSha512, Pkcs5HmacSha256, Pkcs5HmacWhirlpool, Pkcs5HmacStreebog,
//   Pkcs5HmacBlake2s). Do not ship this table without diffing it against
//   that file — the numbers below are from public documentation, not from
//   having read the current source myself, and VeraCrypt has changed
//   defaults across versions.
//
// Known-public reference points (Wikipedia, veracrypt.io docs, as of the
// current stable release line):
//   SHA-512, Whirlpool         -> 500,000 baseline iterations
//   SHA-256, BLAKE2s-256, Streebog -> 500,000 baseline iterations for
//                                     STANDARD CONTAINERS (the lower
//                                     200,000 baseline is specific to
//                                     SYSTEM encryption, which this app
//                                     does not implement)
//
// PIM formula for non-system volumes (per hash) — VeraCrypt's convention:
//   iter = baseline + pim * step
// where `step` also varies by hash family in real VeraCrypt. Your existing
// AES/SHA-512 code uses:
//   iter = (pim > 0) ? (15000 + pim*1000) : 500000
// which is the SHA-512/Whirlpool-family formula. SHA-256/BLAKE2s/Streebog
// use a DIFFERENT step value in real VeraCrypt — confirm exact constants
// against Pkcs5Kdf.cpp before shipping, then fill in below.

struct KdfParams {
    HashId hash;
    int baselineIterations;   // pim == 0
    int pimBase;               // additive base when pim > 0
    int pimStep;                // per-PIM-unit multiplier
};

// TODO: verify pimBase/pimStep per hash against Pkcs5Kdf.cpp before use.
// Values for Sha512/Whirlpool are carried over from this app's existing,
// already-working AES+SHA512 formula. Sha256/Streebog/Blake2s rows are
// PLACEHOLDERS ONLY (currently mirror the Sha512 row) and MUST be
// corrected — shipping them as-is will make containers created by this
// app with those hashes unreadable by real VeraCrypt.
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