#include "cascade.h"
#include "cipher_shim.h"
#include "xts_tweak.h"
#include <cstring>
#include <algorithm>

#if defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>

static inline uint8x16_t xts_tweak_step_armv8(uint8x16_t t) {
    uint64x2_t t64 = vreinterpretq_u64_u8(t);
    uint64_t low = vgetq_lane_u64(t64, 0);
    uint64_t high = vgetq_lane_u64(t64, 1);

    uint64_t carry = low >> 63;
    uint64_t msb = high >> 63;

    uint64x2_t shifted = vcombine_u64(
        vcreate_u64(low << 1),
        vcreate_u64((high << 1) | carry)
    );

    uint8x16_t res = vreinterpretq_u8_u64(shifted);
    if (msb) {
        res = vsetq_lane_u8(vgetq_lane_u8(res, 0) ^ 0x87, res, 0);
    }
    return res;
}

static inline uint8x16_t aes_encrypt_block_armv8_inline(uint8x16_t b, const uint8x16_t* rk, int rounds) {
    for (int i = 0; i < rounds - 1; i++) {
        b = vaesmcq_u8(vaeseq_u8(b, rk[i]));
    }
    b = vaeseq_u8(b, rk[rounds - 1]);
    b = veorq_u8(b, rk[rounds]);
    return b;
}

static inline uint8x16_t aes_decrypt_block_armv8_inline(uint8x16_t b, const uint8x16_t* rk, int rounds) {
    for (int i = 0; i < rounds - 1; i++) {
        b = vaesimcq_u8(vaesdq_u8(b, rk[i]));
    }
    b = vaesdq_u8(b, rk[rounds - 1]);
    b = veorq_u8(b, rk[rounds]);
    return b;
}
#endif

CascadeSpec cascadeSpecFor(CascadeId id) {
    CascadeSpec spec;
    spec.layerCount = 0;
    spec.layers.fill(CipherId::kAes);
    
    if (id == CascadeId::kAes) {
        spec.layerCount = 1;
        spec.layers[0] = CipherId::kAes;
    } else if (id == CascadeId::kSerpent) {
        spec.layerCount = 1;
        spec.layers[0] = CipherId::kSerpent;
    } else if (id == CascadeId::kTwofish) {
        spec.layerCount = 1;
        spec.layers[0] = CipherId::kTwofish;
    } else if (id == CascadeId::kAesTwofish) {
        spec.layerCount = 2;
        spec.layers[0] = CipherId::kAes;
        spec.layers[1] = CipherId::kTwofish;
    } else if (id == CascadeId::kSerpentAes) {
        spec.layerCount = 2;
        spec.layers[0] = CipherId::kSerpent;
        spec.layers[1] = CipherId::kAes;
    } else if (id == CascadeId::kTwofishSerpent) {
        spec.layerCount = 2;
        spec.layers[0] = CipherId::kTwofish;
        spec.layers[1] = CipherId::kSerpent;
    } else if (id == CascadeId::kAesTwofishSerpent) {
        spec.layerCount = 3;
        spec.layers[0] = CipherId::kAes;
        spec.layers[1] = CipherId::kTwofish;
        spec.layers[2] = CipherId::kSerpent;
    } else if (id == CascadeId::kSerpentTwofishAes) {
        spec.layerCount = 3;
        spec.layers[0] = CipherId::kSerpent;
        spec.layers[1] = CipherId::kTwofish;
        spec.layers[2] = CipherId::kAes;
    } else if (id == CascadeId::kCamellia) {
        spec.layerCount = 1;
        spec.layers[0] = CipherId::kCamellia;
    } else if (id == CascadeId::kKuznyechik) {
        spec.layerCount = 1;
        spec.layers[0] = CipherId::kKuznyechik;
    } else if (id == CascadeId::kCamelliaKuznyechik) {
        spec.layerCount = 2;
        spec.layers[0] = CipherId::kCamellia;
        spec.layers[1] = CipherId::kKuznyechik;
    } else if (id == CascadeId::kCamelliaSerpent) {
        spec.layerCount = 2;
        spec.layers[0] = CipherId::kCamellia;
        spec.layers[1] = CipherId::kSerpent;
    } else if (id == CascadeId::kKuznyechikAes) {
        spec.layerCount = 2;
        spec.layers[0] = CipherId::kKuznyechik;
        spec.layers[1] = CipherId::kAes;
    } else if (id == CascadeId::kKuznyechikSerpentCamellia) {
        spec.layerCount = 3;
        spec.layers[0] = CipherId::kKuznyechik;
        spec.layers[1] = CipherId::kSerpent;
        spec.layers[2] = CipherId::kCamellia;
    } else if (id == CascadeId::kKuznyechikTwofish) {
        spec.layerCount = 2;
        spec.layers[0] = CipherId::kKuznyechik;
        spec.layers[1] = CipherId::kTwofish;
    }
    return spec;
}

bool cascadeSetKeys(CascadeContext& ctx, CascadeId id,
                     const unsigned char* keyMaterial, size_t keyMaterialLen) {
    ctx.id = id;
    CascadeSpec spec = cascadeSpecFor(id);
    ctx.layerCount = spec.layerCount;

    if (ctx.layerCount <= 0) {
        ctx.initialized = false;
        return false;
    }

    const size_t bytesPerLayer = 64;
    const size_t cipherKeyBytes = bytesPerLayer / 2;

    if (keyMaterialLen < static_cast<size_t>(ctx.layerCount) * bytesPerLayer) {
        return false;
    }

    const unsigned char* dataKeysBase  = keyMaterial;
    const unsigned char* tweakKeysBase = keyMaterial + static_cast<size_t>(ctx.layerCount) * cipherKeyBytes;

    for (int i = 0; i < ctx.layerCount; i++) {
        CipherId cipher = spec.layers[i];
        int vcIndex = ctx.layerCount - 1 - i;
        
        const unsigned char* dataKey  = dataKeysBase  + vcIndex * cipherKeyBytes;
        const unsigned char* tweakKey = tweakKeysBase + vcIndex * cipherKeyBytes;

        if (!blockCipherSetKey(ctx.layers[i].dataKeyEnc, cipher, dataKey, cipherKeyBytes)) return false;
        if (!blockCipherSetKey(ctx.layers[i].dataKeyDec, cipher, dataKey, cipherKeyBytes)) return false;
        if (!blockCipherSetKey(ctx.layers[i].tweakKey, cipher, tweakKey, cipherKeyBytes)) return false;
    }

    ctx.aesXtsFastPathReady = (ctx.layerCount == 1 && id == CascadeId::kAes);
    ctx.initialized = true;
    return true;
}

static inline void setTweak(unsigned char* tweak, uint64_t sectorNum) {
    *reinterpret_cast<uint64_t*>(tweak)   = sectorNum;
    *reinterpret_cast<uint64_t*>(tweak+8) = 0ULL;
}

void cascadeDecryptSector(const CascadeContext& ctx, uint64_t sectorNumber,
                           const unsigned char in[512], unsigned char out[512]) {
#if defined(__aarch64__) || defined(_M_ARM64)
    if (ctx.aesXtsFastPathReady) {
        const auto* dataPair = reinterpret_cast<const AesCtxPair*>(ctx.layers[0].dataKeyDec.scheduleStorage);
        const auto* tweakPair = reinterpret_cast<const AesCtxPair*>(ctx.layers[0].tweakKey.scheduleStorage);
        const int nr = dataPair->rounds;

        uint64_t secTweak[2] = { sectorNumber, 0 };
        uint8x16_t T = vld1q_u8(reinterpret_cast<const uint8_t*>(secTweak));
        T = aes_encrypt_block_armv8_inline(T, tweakPair->arm_enc_rk, nr);

        const uint8_t* inPtr = in;
        uint8_t* outPtr = out;

        for (int b = 0; b < 32; b++) {
            uint8x16_t block = vld1q_u8(inPtr);
            block = veorq_u8(block, T);
            block = aes_decrypt_block_armv8_inline(block, dataPair->arm_dec_rk, nr);
            block = veorq_u8(block, T);
            vst1q_u8(outPtr, block);

            T = xts_tweak_step_armv8(T);
            inPtr += 16;
            outPtr += 16;
        }
        return;
    }
#endif

    unsigned char temp[512];
    std::memcpy(temp, in, 512);

    for (int i = 0; i < ctx.layerCount; i++) {
        const XtsLayerKey& layer = ctx.layers[i];
        unsigned char tweakBuf[16];
        setTweak(tweakBuf, sectorNumber);
        unsigned char T[16];
        blockCipherEncryptBlock(layer.tweakKey, tweakBuf, T);
        for (int block = 0; block < 32; block++) {
            unsigned char* blockOut = out + block * 16;
            const unsigned char* blockIn = temp + block * 16;
            unsigned char tmp[16];
            for (int j = 0; j < 16; j++) tmp[j] = blockIn[j] ^ T[j];
            blockCipherDecryptBlock(layer.dataKeyDec, tmp, tmp);
            for (int j = 0; j < 16; j++) blockOut[j] = tmp[j] ^ T[j];
            xtsMultiplyTweak(T);
        }
        if (i < ctx.layerCount - 1) std::memcpy(temp, out, 512);
    }
}

void cascadeEncryptSector(const CascadeContext& ctx, uint64_t sectorNumber,
                           const unsigned char in[512], unsigned char out[512]) {
#if defined(__aarch64__) || defined(_M_ARM64)
    if (ctx.aesXtsFastPathReady) {
        const auto* dataPair = reinterpret_cast<const AesCtxPair*>(ctx.layers[0].dataKeyEnc.scheduleStorage);
        const auto* tweakPair = reinterpret_cast<const AesCtxPair*>(ctx.layers[0].tweakKey.scheduleStorage);
        const int nr = dataPair->rounds;

        uint64_t secTweak[2] = { sectorNumber, 0 };
        uint8x16_t T = vld1q_u8(reinterpret_cast<const uint8_t*>(secTweak));
        T = aes_encrypt_block_armv8_inline(T, tweakPair->arm_enc_rk, nr);

        const uint8_t* inPtr = in;
        uint8_t* outPtr = out;

        for (int b = 0; b < 32; b++) {
            uint8x16_t block = vld1q_u8(inPtr);
            block = veorq_u8(block, T);
            block = aes_encrypt_block_armv8_inline(block, dataPair->arm_enc_rk, nr);
            block = veorq_u8(block, T);
            vst1q_u8(outPtr, block);

            T = xts_tweak_step_armv8(T);
            inPtr += 16;
            outPtr += 16;
        }
        return;
    }
#endif

    unsigned char temp[512];
    std::memcpy(temp, in, 512);

    for (int i = ctx.layerCount - 1; i >= 0; i--) {
        const XtsLayerKey& layer = ctx.layers[i];
        unsigned char tweakBuf[16];
        setTweak(tweakBuf, sectorNumber);
        unsigned char T[16];
        blockCipherEncryptBlock(layer.tweakKey, tweakBuf, T);
        for (int block = 0; block < 32; block++) {
            unsigned char* blockOut = out + block * 16;
            const unsigned char* blockIn = temp + block * 16;
            unsigned char tmp[16];
            for (int j = 0; j < 16; j++) tmp[j] = blockIn[j] ^ T[j];
            blockCipherEncryptBlock(layer.dataKeyEnc, tmp, tmp);
            for (int j = 0; j < 16; j++) blockOut[j] = tmp[j] ^ T[j];
            xtsMultiplyTweak(T);
        }
        if (i > 0) std::memcpy(temp, out, 512);
    }
}