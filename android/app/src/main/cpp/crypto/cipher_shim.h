#pragma once
#include <cstdint>
#include <cstddef>
#include <atomic>
#include <functional>

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

// cancelCheck: optional cooperative early-exit, checked periodically inside
// the custom PBKDF2 loop. Used by deriveAndValidateHeader's per-hash worker 
// threads to stop as soon as another thread has already found the matching 
// hash, or if the user cancelled the unlock entirely.
bool pbkdf2Hmac(HashId hash,
                 const unsigned char* password, size_t passwordLen,
                 const unsigned char* salt, size_t saltLen,
                 unsigned int iterations,
                 unsigned char* out, size_t outLen,
                 std::function<bool()> cancelCheck = nullptr);

int iterationsForHash(HashId hash, int clampedPim);

size_t genericHashOneShot(HashId hash,
                           const unsigned char* data1, size_t len1,
                           const unsigned char* data2, size_t len2,
                           unsigned char* out);

int clampPim(int pim);

bool argon2idDeriveKey(const unsigned char* password, size_t passwordLen,
                        const unsigned char* salt, size_t saltLen,
                        uint32_t memoryKiB, uint32_t timeCost, uint32_t parallelism,
                        unsigned char* out, size_t outLen);

void argon2ParamsForPim(int clampedPim, uint32_t& memoryKiB, uint32_t& timeCost, uint32_t& parallelism);