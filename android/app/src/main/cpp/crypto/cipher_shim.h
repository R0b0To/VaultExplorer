#pragma once
#include <cstdint>
#include <cstddef>
#include <atomic>

// ── Cipher identity ──────────────────────────────────────────────────────

enum class CipherId : uint8_t {
    kAes = 0,
    kSerpent = 1,
    kTwofish = 2,
    kCamellia = 3,
    kKuznyechik = 4,
};


static constexpr size_t kBlockCipherKeyBytes = 32;   
static constexpr size_t kBlockSizeBytes      = 16;   


struct BlockCipherContext {
    CipherId id;
    alignas(16) unsigned char scheduleStorage[4608]; 
};

bool blockCipherSetKey(BlockCipherContext& ctx, CipherId id,
                        const unsigned char key[kBlockCipherKeyBytes]);


void blockCipherEncryptBlock(const BlockCipherContext& ctx,
                              const unsigned char in[kBlockSizeBytes],
                              unsigned char out[kBlockSizeBytes]);
void blockCipherDecryptBlock(const BlockCipherContext& ctx,
                              const unsigned char in[kBlockSizeBytes],
                              unsigned char out[kBlockSizeBytes]);

// ── Hash identity (for PBKDF2-HMAC) ──────────────────────────────────────

enum class HashId : uint8_t {
    kSha512 = 0,   // already supported via mbedTLS — kept here for uniformity
    kSha256 = 1,   // already supported via mbedTLS
    kWhirlpool = 2,
    kStreebog = 3,
    kBlake2s256 = 4,
    kArgon2id = 5, // memory-hard KDF — NOT PBKDF2-HMAC, see argon2idDeriveKey()
};

static constexpr size_t kMaxHashOutputBytes = 64; // SHA-512/Whirlpool/Streebog = 64B, others less

// abortFlag: optional cooperative early-exit, checked periodically inside
// the custom PBKDF2 loop (Whirlpool/Streebog/Blake2s256 only — see
// pbkdf2Hmac's definition for why SHA-256/SHA-512 can't honor it). Used by
// deriveAndValidateHeader's per-hash worker threads to stop as soon as
// another thread has already found the matching hash, instead of running
// a slow hash's KDF to completion for nothing after the answer is known.
bool pbkdf2Hmac(HashId hash,
                 const unsigned char* password, size_t passwordLen,
                 const unsigned char* salt, size_t saltLen,
                 unsigned int iterations,
                 unsigned char* out, size_t outLen,
                 const std::atomic<bool>* abortFlag = nullptr);

int iterationsForHash(HashId hash, int clampedPim);

// One-shot raw digest (NOT HMAC/PBKDF2) for the three hashes this app
// implements itself rather than getting from mbedTLS — Whirlpool,
// Streebog, Blake2s-256. Hashes [data1,len1] followed by [data2,len2] as
// a single contiguous message (pass len2 = 0 / data2 = nullptr to hash
// just data1). [out] must hold at least the hash's digest size (64 bytes
// for Whirlpool/Streebog, 32 for Blake2s-256 — see kMaxHashOutputBytes).
// Returns the digest size written on success, 0 if [hash] isn't one of
// the three custom hashes (callers should fall back to mbedTLS's own
// digest API for SHA-1/256/512/RIPEMD-160, which this function doesn't
// handle).
//
// Added for luks_header.cpp's afDiffuse(), which needs a raw iterated
// hash (not pbkdf2Hmac's HMAC construction) so that LUKS volumes hashed
// with something other than mbedTLS's four built-ins — most commonly
// real cryptsetup's "whirlpool" — can still have their AF-split keyslot
// material recombined.
size_t genericHashOneShot(HashId hash,
                           const unsigned char* data1, size_t len1,
                           const unsigned char* data2, size_t len2,
                           unsigned char* out);

// Clamps a user-supplied PIM into the range this codebase supports:
// [0, 2000]. 0 means "use the format default" (baseline PBKDF2 iteration
// count, or Argon2id's PIM-12 default — see argon2ParamsForPim below);
// values above 2000 are capped rather than rejected, matching how the rest
// of the unlock path treats an out-of-range PIM as "use the ceiling"
// instead of failing outright. Shared by session establishment
// (deriveAndValidateHeader) and container creation (createContainerNative),
// which both need the same clamping before deriving a header key.
int clampPim(int pim);

// ── Argon2id (separate from the PBKDF2-HMAC family above) ────────────────
//
// Argon2 takes a memory cost and a parallelism (lane count) parameter that
// don't exist in the PBKDF2 world, so it cannot go through pbkdf2Hmac()/
// iterationsForHash(). Callers (vaultexplorer.cpp) special-case
// HashId::kArgon2id and call this instead. See argon2ParamsForPim() in
// kdf_table.cpp for how (memoryKiB, timeCost, parallelism) are derived from
// the user-supplied PIM, mirroring iterationsForHash()'s role for the other
// hashes — deliberately fixed-by-pim rather than stored anywhere in the
// header, since the header's salt region must stay indistinguishable from
// random data for hidden-volume plausible deniability.
bool argon2idDeriveKey(const unsigned char* password, size_t passwordLen,
                        const unsigned char* salt, size_t saltLen,
                        uint32_t memoryKiB, uint32_t timeCost, uint32_t parallelism,
                        unsigned char* out, size_t outLen);

void argon2ParamsForPim(int clampedPim, uint32_t& memoryKiB, uint32_t& timeCost, uint32_t& parallelism);