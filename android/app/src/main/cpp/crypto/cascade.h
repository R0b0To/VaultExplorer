#pragma once
#include "cipher_shim.h"
#include "mbedtls/aes.h" 
#include <cstdint>
#include <array>


static constexpr int kMaxCascadeLayers = 3;

struct CascadeSpec {
    int layerCount;
    std::array<CipherId, kMaxCascadeLayers> layers;
};

enum class CascadeId : uint8_t {
    kAes,
    kSerpent,
    kTwofish,
    kAesTwofish,
    kSerpentAes,
    kTwofishSerpent,
    kAesTwofishSerpent,
    kSerpentTwofishAes,
    kCamellia,
    kKuznyechik,
    kCamelliaKuznyechik,
    kCamelliaSerpent,
    kKuznyechikAes,
    kKuznyechikSerpentCamellia,
    kKuznyechikTwofish,
};

CascadeSpec cascadeSpecFor(CascadeId id);
struct XtsLayerKey {
    BlockCipherContext dataKeyEnc;
    BlockCipherContext dataKeyDec;
    BlockCipherContext tweakKey;  
};


struct CascadeContext {
    CascadeId id;
    int layerCount;
    std::array<XtsLayerKey, kMaxCascadeLayers> layers;
    mbedtls_aes_xts_context aesXtsEncCtx;
    mbedtls_aes_xts_context aesXtsDecCtx;
    bool aesXtsFastPathReady = false;

    bool initialized = false;
};


bool cascadeSetKeys(CascadeContext& ctx, CascadeId id,
                     const unsigned char* keyMaterial, size_t keyMaterialLen);

void cascadeEncryptSector(const CascadeContext& ctx, uint64_t sectorNumber,
                           const unsigned char in[512], unsigned char out[512]);
void cascadeDecryptSector(const CascadeContext& ctx, uint64_t sectorNumber,
                           const unsigned char in[512], unsigned char out[512]);

// LUKS XTS data unit helper. Unlike VeraCrypt's fixed 512-byte units, LUKS2
// may use 512..4096-byte sector sizes. [sectorNumber] is the 512-byte-based
// plain64 tweak value used by the mounted-volume path; [dataLen] is one LUKS
// data unit and must be a multiple of 16. Only single-cipher LUKS contexts
// are accepted. Returns false for invalid geometry/context.
bool cascadeCryptLuksXtsUnit(const CascadeContext& ctx, bool encrypt, uint64_t sectorNumber,
                             size_t dataLen, const unsigned char* in, unsigned char* out);
