#pragma once
#include <cstdint>
#include <cstddef>

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

bool pbkdf2Hmac(HashId hash,
                 const unsigned char* password, size_t passwordLen,
                 const unsigned char* salt, size_t saltLen,
                 unsigned int iterations,
                 unsigned char* out, size_t outLen);

int iterationsForHash(HashId hash, int clampedPim);

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