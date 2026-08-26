#pragma once
#include <cstdint>
#include <cstddef>
#include <atomic>
#include <functional>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define HAVE_ARM64_AES_INTRINSICS 1
#endif

#include <openssl/aes.h>

struct AesCtxPair {
    int rounds = 14;
#if defined(HAVE_ARM64_AES_INTRINSICS)
    uint8x16_t arm_enc_rk[15];
    uint8x16_t arm_dec_rk[15];
#else
    AES_KEY enc;
    AES_KEY dec;
#endif
};

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
    // 4608 bytes required to safely hold TwofishInstance (4256 bytes) and all other ciphers
    alignas(16) unsigned char scheduleStorage[4608]; 
};

bool blockCipherSetKey(BlockCipherContext& ctx, CipherId id,
                        const unsigned char* key, size_t keyLen = 32);

void blockCipherEncryptBlock(const BlockCipherContext& ctx,
                              const unsigned char in[kBlockSizeBytes],
                              unsigned char out[kBlockSizeBytes]);
void blockCipherDecryptBlock(const BlockCipherContext& ctx,
                              const unsigned char in[kBlockSizeBytes],
                              unsigned char out[kBlockSizeBytes]);

// ── Hash identity (for PBKDF2-HMAC) ──────────────────────────────────────

enum class HashId : uint8_t {
    kSha512 = 0,
    kSha256 = 1,
    kWhirlpool = 2,
    kStreebog = 3,
    kBlake2s256 = 4,
    kArgon2id = 5,
};

static constexpr size_t kMaxHashOutputBytes = 64;

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

// Argon2i variant (data-independent addressing) -- distinct KDF output from
// argon2id for identical password/salt/cost params. LUKS2 keyslots record
// which of the two was used to derive them (kdf.type == "argon2i" vs
// "argon2id"); calling the wrong one silently derives the wrong key.
bool argon2iDeriveKey(const unsigned char* password, size_t passwordLen,
                       const unsigned char* salt, size_t saltLen,
                       uint32_t memoryKiB, uint32_t timeCost, uint32_t parallelism,
                       unsigned char* out, size_t outLen);

void argon2ParamsForPim(int clampedPim, uint32_t& memoryKiB, uint32_t& timeCost, uint32_t& parallelism);