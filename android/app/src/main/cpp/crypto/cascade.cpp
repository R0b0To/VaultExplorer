// crypto/cascade.cpp
#include "cascade.h"
#include <cstring>
#include <algorithm>

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
    }
    return spec;
}

bool cascadeSetKeys(CascadeContext& ctx, CascadeId id,
                     const unsigned char* keyMaterial, size_t keyMaterialLen) {
    ctx.id = id;
    CascadeSpec spec = cascadeSpecFor(id);
    ctx.layerCount = spec.layerCount;
    
    if (keyMaterialLen < static_cast<size_t>(ctx.layerCount) * 64) {
        return false;
    }
    
    for (int i = 0; i < ctx.layerCount; i++) {
        CipherId cipher = spec.layers[i];
        const unsigned char* layerKey = keyMaterial + i * 64;
        
        if (!blockCipherSetKey(ctx.layers[i].dataKeyEnc, cipher, layerKey)) return false;
        if (!blockCipherSetKey(ctx.layers[i].dataKeyDec, cipher, layerKey)) return false;
        if (!blockCipherSetKey(ctx.layers[i].tweakKey, cipher, layerKey + 32)) return false;
    }
    // FIX (perf): single-layer AES also gets a real mbedTLS XTS context.
    // mbedtls_aes_crypt_xts wants a 512-bit key = 32-byte data key +
    // 32-byte tweak key concatenated — exactly what keyMaterial[0..63]
    // already is for layer 0, same bytes the generic path above just used.
    ctx.aesXtsFastPathReady = false;
    if (ctx.layerCount == 1 && id == CascadeId::kAes) {
        mbedtls_aes_xts_init(&ctx.aesXtsEncCtx);
        mbedtls_aes_xts_init(&ctx.aesXtsDecCtx);
        bool ok = (mbedtls_aes_xts_setkey_enc(&ctx.aesXtsEncCtx, keyMaterial, 512) == 0) &&
                  (mbedtls_aes_xts_setkey_dec(&ctx.aesXtsDecCtx, keyMaterial, 512) == 0);
        ctx.aesXtsFastPathReady = ok;
        if (!ok) return false;
    }

    ctx.initialized = true;
    return true;
}

static inline void setTweak(unsigned char* tweak, uint64_t sectorNum) {
    *reinterpret_cast<uint64_t*>(tweak)   = sectorNum;
    *reinterpret_cast<uint64_t*>(tweak+8) = 0ULL;
}

static void multiplyTweak(unsigned char T[16]) {
    unsigned char carry = 0;
    for (int i = 0; i < 16; i++) {
        unsigned char nextCarry = (T[i] & 0x80) ? 1 : 0;
        T[i] = (T[i] << 1) | carry;
        carry = nextCarry;
    }
    if (carry) {
        T[0] ^= 0x87;
    }
}

void cascadeDecryptSector(const CascadeContext& ctx, uint64_t sectorNumber,
                           const unsigned char in[512], unsigned char out[512]) {
    if (ctx.aesXtsFastPathReady) {
        unsigned char tweakBuf[16];
        setTweak(tweakBuf, sectorNumber);
        mbedtls_aes_xts_context* decCtx = const_cast<mbedtls_aes_xts_context*>(&ctx.aesXtsDecCtx);
        mbedtls_aes_crypt_xts(decCtx, MBEDTLS_AES_DECRYPT, 512, tweakBuf, in, out);
        return;
    }

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
            blockCipherDecryptBlock(layer.dataKeyDec, tmp, tmp);
            for (int j = 0; j < 16; j++) blockOut[j] = tmp[j] ^ T[j];
            
            multiplyTweak(T);
        }
        if (i > 0) {
            std::memcpy(temp, out, 512);
        }
    }
}

void cascadeEncryptSector(const CascadeContext& ctx, uint64_t sectorNumber,
                           const unsigned char in[512], unsigned char out[512]) {
    if (ctx.aesXtsFastPathReady) {
        unsigned char tweakBuf[16];
        setTweak(tweakBuf, sectorNumber);
        mbedtls_aes_xts_context* encCtx = const_cast<mbedtls_aes_xts_context*>(&ctx.aesXtsEncCtx);
        mbedtls_aes_crypt_xts(encCtx, MBEDTLS_AES_ENCRYPT, 512, tweakBuf, in, out);
        return;
    }

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
            blockCipherEncryptBlock(layer.dataKeyEnc, tmp, tmp);
            for (int j = 0; j < 16; j++) blockOut[j] = tmp[j] ^ T[j];
            
            multiplyTweak(T);
        }
        if (i < ctx.layerCount - 1) {
            std::memcpy(temp, out, 512);
        }
    }
}
