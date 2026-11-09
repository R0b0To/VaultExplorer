#pragma once
// Host-test stand-in for crypto/cascade.h: one layer, key-dependent transforms.
#include <array>
#include <cstddef>
#include <cstdint>
#include "cipher_shim.h"
enum class CascadeId : uint8_t { kAes };
struct CascadeSpec {
    int layerCount;
};
inline CascadeSpec cascadeSpecFor(CascadeId) { return {1}; }
struct XtsLayerKey {
    BlockCipherContext dataKeyEnc;
    BlockCipherContext tweakKey;
};
struct CascadeContext {
    std::array<XtsLayerKey, 1> layers;
    uint32_t keyHash = 0;
    bool initialized = false;   // present in the real CascadeContext; production code sets it
};
inline uint32_t stubHash(const unsigned char* p, size_t n, uint32_t seed) {
    uint32_t h = 2166136261u ^ seed;
    for (size_t i = 0; i < n; ++i) h = (h ^ p[i]) * 16777619u;
    return h;
}
inline bool cascadeSetKeys(CascadeContext& ctx, CascadeId, const unsigned char* key, size_t len) {
    if (len == 0) return false;
    ctx.keyHash = stubHash(key, len, 0);
    ctx.layers[0].dataKeyEnc.k = stubHash(key, len, 1);
    ctx.layers[0].tweakKey.k = stubHash(key, len, 2);
    return true;
}
inline void cascadeEncryptSector(const CascadeContext& ctx, uint64_t sector, const unsigned char in[512],
                                 unsigned char out[512]) {
    uint32_t s = ctx.keyHash ^ static_cast<uint32_t>(sector * 2654435761u);
    for (int i = 0; i < 512; ++i) {
        s = s * 1664525u + 1013904223u;
        out[i] = static_cast<unsigned char>(in[i] ^ (s >> 24));
    }
}
inline void cascadeDecryptSector(const CascadeContext& ctx, uint64_t sector, const unsigned char in[512],
                                 unsigned char out[512]) {
    cascadeEncryptSector(ctx, sector, in, out);   // XOR stream: its own inverse
}
