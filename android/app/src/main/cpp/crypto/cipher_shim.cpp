// crypto/cipher_shim.cpp
#include "cipher_shim.h"
#include "mbedtls/aes.h"
#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
#include "Serpent.h"
#include "Twofish.h"
#include "Whirlpool.h"
#include "Streebog.h"
#include "blake2s.h"
#include <cstring>
#include <algorithm>

struct AesCtxPair {
    mbedtls_aes_context enc;
    mbedtls_aes_context dec;
};

bool blockCipherSetKey(BlockCipherContext& ctx, CipherId id,
                        const unsigned char key[kBlockCipherKeyBytes]) {
    ctx.id = id;
    if (id == CipherId::kAes) {
        AesCtxPair* pair = reinterpret_cast<AesCtxPair*>(ctx.scheduleStorage);
        mbedtls_aes_init(&pair->enc);
        mbedtls_aes_init(&pair->dec);
        if (mbedtls_aes_setkey_enc(&pair->enc, key, 256) != 0) return false;
        if (mbedtls_aes_setkey_dec(&pair->dec, key, 256) != 0) return false;
        return true;
    } else if (id == CipherId::kSerpent) {
        serpent_set_key(key, ctx.scheduleStorage);
        return true;
    } else if (id == CipherId::kTwofish) {
        TwofishInstance* inst = reinterpret_cast<TwofishInstance*>(ctx.scheduleStorage);
        twofish_set_key(inst, reinterpret_cast<const u4byte*>(key));
        return true;
    }
    return false;
}

void blockCipherEncryptBlock(const BlockCipherContext& ctx,
                              const unsigned char in[kBlockSizeBytes],
                              unsigned char out[kBlockSizeBytes]) {
    if (ctx.id == CipherId::kAes) {
        const AesCtxPair* pair = reinterpret_cast<const AesCtxPair*>(ctx.scheduleStorage);
        mbedtls_aes_context* encMutable = const_cast<mbedtls_aes_context*>(&pair->enc);
        mbedtls_aes_crypt_ecb(encMutable, MBEDTLS_AES_ENCRYPT, in, out);
    } else if (ctx.id == CipherId::kSerpent) {
        unsigned char* ks = const_cast<unsigned char*>(ctx.scheduleStorage);
        serpent_encrypt(in, out, ks);
    } else if (ctx.id == CipherId::kTwofish) {
        TwofishInstance* inst = const_cast<TwofishInstance*>(reinterpret_cast<const TwofishInstance*>(ctx.scheduleStorage));
        u4byte blockIn[4];
        u4byte blockOut[4];
        std::memcpy(blockIn, in, 16);
        twofish_encrypt(inst, blockIn, blockOut);
        std::memcpy(out, blockOut, 16);
    }
}

void blockCipherDecryptBlock(const BlockCipherContext& ctx,
                              const unsigned char in[kBlockSizeBytes],
                              unsigned char out[kBlockSizeBytes]) {
    if (ctx.id == CipherId::kAes) {
        const AesCtxPair* pair = reinterpret_cast<const AesCtxPair*>(ctx.scheduleStorage);
        mbedtls_aes_context* decMutable = const_cast<mbedtls_aes_context*>(&pair->dec);
        mbedtls_aes_crypt_ecb(decMutable, MBEDTLS_AES_DECRYPT, in, out);
    } else if (ctx.id == CipherId::kSerpent) {
        unsigned char* ks = const_cast<unsigned char*>(ctx.scheduleStorage);
        serpent_decrypt(in, out, ks);
    } else if (ctx.id == CipherId::kTwofish) {
        TwofishInstance* inst = const_cast<TwofishInstance*>(reinterpret_cast<const TwofishInstance*>(ctx.scheduleStorage));
        u4byte blockIn[4];
        u4byte blockOut[4];
        std::memcpy(blockIn, in, 16);
        twofish_decrypt(inst, blockIn, blockOut);
        std::memcpy(out, blockOut, 16);
    }
}

// ── Custom HMAC & PBKDF2 Implementation for Whirlpool, Streebog, Blake2s ──

union HashCtx {
    WHIRLPOOL_CTX whirlpool;
    STREEBOG_CTX streebog;
    blake2s_state blake2s;
};

static void hashInit(HashId hash, HashCtx* ctx) {
    if (hash == HashId::kWhirlpool) {
        WHIRLPOOL_init(&ctx->whirlpool);
    } else if (hash == HashId::kStreebog) {
        STREEBOG_init(&ctx->streebog);
    } else if (hash == HashId::kBlake2s256) {
        blake2s_init(&ctx->blake2s);
    }
}

static void hashUpdate(HashId hash, HashCtx* ctx, const unsigned char* data, size_t len) {
    if (hash == HashId::kWhirlpool) {
        WHIRLPOOL_add(data, len, &ctx->whirlpool);
    } else if (hash == HashId::kStreebog) {
        STREEBOG_add(&ctx->streebog, data, len);
    } else if (hash == HashId::kBlake2s256) {
        blake2s_update(&ctx->blake2s, data, len);
    }
}

static void hashFinal(HashId hash, HashCtx* ctx, unsigned char* out) {
    if (hash == HashId::kWhirlpool) {
        WHIRLPOOL_finalize(&ctx->whirlpool, out);
    } else if (hash == HashId::kStreebog) {
        STREEBOG_finalize(&ctx->streebog, out);
    } else if (hash == HashId::kBlake2s256) {
        blake2s_final(&ctx->blake2s, out);
    }
}

static size_t hashDigestSize(HashId hash) {
    if (hash == HashId::kWhirlpool) return 64;
    if (hash == HashId::kStreebog) return 64;
    if (hash == HashId::kBlake2s256) return 32;
    return 0;
}

static void hashHmac(HashId hash, const unsigned char* key, size_t keyLen,
                     const unsigned char* data, size_t dataLen, unsigned char* out) {
    size_t digestSize = hashDigestSize(hash);
    size_t blockSize = 64;
    
    unsigned char k_ipad[64];
    unsigned char k_opad[64];
    std::memset(k_ipad, 0x36, 64);
    std::memset(k_opad, 0x5C, 64);
    
    unsigned char preparedKey[64] = {0};
    if (keyLen > blockSize) {
        HashCtx ctx;
        hashInit(hash, &ctx);
        hashUpdate(hash, &ctx, key, keyLen);
        hashFinal(hash, &ctx, preparedKey);
    } else {
        std::memcpy(preparedKey, key, keyLen);
    }
    
    for (size_t i = 0; i < blockSize; i++) {
        k_ipad[i] ^= preparedKey[i];
        k_opad[i] ^= preparedKey[i];
    }
    
    HashCtx innerCtx;
    hashInit(hash, &innerCtx);
    hashUpdate(hash, &innerCtx, k_ipad, blockSize);
    hashUpdate(hash, &innerCtx, data, dataLen);
    unsigned char innerDigest[64];
    hashFinal(hash, &innerCtx, innerDigest);
    
    HashCtx outerCtx;
    hashInit(hash, &outerCtx);
    hashUpdate(hash, &outerCtx, k_opad, blockSize);
    hashUpdate(hash, &outerCtx, innerDigest, digestSize);
    hashFinal(hash, &outerCtx, out);
}

static bool pbkdf2HmacCustom(HashId hash,
                            const unsigned char* password, size_t passwordLen,
                            const unsigned char* salt, size_t saltLen,
                            unsigned int iterations,
                            unsigned char* out, size_t outLen) {
    size_t digestSize = hashDigestSize(hash);
    if (digestSize == 0) return false;
    
    unsigned int blockCount = (outLen + digestSize - 1) / digestSize;
    unsigned char U[64];
    unsigned char T[64];
    unsigned char saltWithIndex[256];
    if (saltLen + 4 > sizeof(saltWithIndex)) return false;
    std::memcpy(saltWithIndex, salt, saltLen);
    
    size_t outOffset = 0;
    for (unsigned int block = 1; block <= blockCount; block++) {
        saltWithIndex[saltLen]     = (block >> 24) & 0xFF;
        saltWithIndex[saltLen + 1] = (block >> 16) & 0xFF;
        saltWithIndex[saltLen + 2] = (block >> 8)  & 0xFF;
        saltWithIndex[saltLen + 3] = block         & 0xFF;
        
        hashHmac(hash, password, passwordLen, saltWithIndex, saltLen + 4, U);
        std::memcpy(T, U, digestSize);
        
        for (unsigned int iter = 1; iter < iterations; iter++) {
            hashHmac(hash, password, passwordLen, U, digestSize, U);
            for (size_t i = 0; i < digestSize; i++) {
                T[i] ^= U[i];
            }
        }
        
        size_t copyLen = std::min(digestSize, outLen - outOffset);
        std::memcpy(out + outOffset, T, copyLen);
        outOffset += copyLen;
    }
    return true;
}

bool pbkdf2Hmac(HashId hash,
                 const unsigned char* password, size_t passwordLen,
                 const unsigned char* salt, size_t saltLen,
                 unsigned int iterations,
                 unsigned char* out, size_t outLen) {
    if (hash == HashId::kSha512 || hash == HashId::kSha256) {
        mbedtls_md_type_t mdType = (hash == HashId::kSha512) ? MBEDTLS_MD_SHA512 : MBEDTLS_MD_SHA256;
        const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(mdType);
        if (!mdInfo) return false;
        mbedtls_md_context_t ctx;
        mbedtls_md_init(&ctx);
        if (mbedtls_md_setup(&ctx, mdInfo, 1) != 0) {
            mbedtls_md_free(&ctx);
            return false;
        }
        int ret = mbedtls_pkcs5_pbkdf2_hmac(&ctx, password, passwordLen, salt, saltLen, iterations, outLen, out);
        mbedtls_md_free(&ctx);
        return ret == 0;
    } else {
        return pbkdf2HmacCustom(hash, password, passwordLen, salt, saltLen, iterations, out, outLen);
    }
}
