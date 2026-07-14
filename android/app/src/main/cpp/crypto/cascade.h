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
