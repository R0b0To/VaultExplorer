#include "crypto/cryfs_block_cipher.h"
#include "mbedtls/gcm.h"
#include "mbedtls/aes.h"
#include "mbedtls/chachapoly.h"
#include "mbedtls/platform_util.h"
#include <cstdio>
#include <cstring>

namespace {

constexpr size_t kIvSize = 16;   // == AES block size
constexpr size_t kTagSize = 16;  // GCM/Poly1305 tag size

bool randomBytes(uint8_t* buf, size_t len) {
    FILE* urnd = fopen("/dev/urandom", "rb");
    if (!urnd) return false;
    bool ok = (fread(buf, 1, len, urnd) == len);
    fclose(urnd);
    return ok;
}

size_t keyBitsFor(CryfsCipherId cipher) {
    switch (cipher) {
        case CryfsCipherId::kAes256Gcm:
        case CryfsCipherId::kAes256Cfb:
        case CryfsCipherId::kXChaCha20Poly1305:
            return 256;
        case CryfsCipherId::kAes128Gcm:
        case CryfsCipherId::kAes128Cfb:
            return 128;
        default:
            return 0;
    }
}

bool isGcm(CryfsCipherId cipher) {
    return cipher == CryfsCipherId::kAes256Gcm || cipher == CryfsCipherId::kAes128Gcm;
}

bool isCfb(CryfsCipherId cipher) {
    return cipher == CryfsCipherId::kAes256Cfb || cipher == CryfsCipherId::kAes128Cfb;
}

static inline uint32_t rotl32(uint32_t x, int n) {
    return (x << n) | (x >> (32 - n));
}

static inline uint32_t readU32LE(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) |
          (static_cast<uint32_t>(p[1]) << 8) |
          (static_cast<uint32_t>(p[2]) << 16) |
          (static_cast<uint32_t>(p[3]) << 24);
}

static inline void writeU32LE(uint8_t* p, uint32_t v) {
    p[0] = static_cast<uint8_t>(v & 0xFF);
    p[1] = static_cast<uint8_t>((v >> 8) & 0xFF);
    p[2] = static_cast<uint8_t>((v >> 16) & 0xFF);
    p[3] = static_cast<uint8_t>((v >> 24) & 0xFF);
}

// HChaCha20 subkey derivation function (draft-irtf-cfrg-xchacha-03)
// "expand 32-byte k" in Little-Endian 32-bit integers:
// 0x61707865 ("expa"), 0x3320646e ("nd 3"), 0x79622d32 ("2-by"), 0x6b206574 ("tey ")
static void hchacha20(const uint8_t key[32], const uint8_t nonce[16], uint8_t outSubkey[32]) {
    static const uint32_t sigma[4] = {
        0x61707865, 0x3320646e, 0x79622d32, 0x6b206574
    };

    uint32_t x[16];
    x[0] = sigma[0];
    x[1] = sigma[1];
    x[2] = sigma[2];
    x[3] = sigma[3];

    for (int i = 0; i < 8; i++) {
        x[4 + i] = readU32LE(key + i * 4);
    }
    for (int i = 0; i < 4; i++) {
        x[12 + i] = readU32LE(nonce + i * 4);
    }

    auto quarterRound = [](uint32_t state[16], int a, int b, int c, int d) {
        state[a] += state[b]; state[d] = rotl32(state[d] ^ state[a], 16);
        state[c] += state[d]; state[b] = rotl32(state[b] ^ state[c], 12);
        state[a] += state[b]; state[d] = rotl32(state[d] ^ state[a], 8);
        state[c] += state[d]; state[b] = rotl32(state[b] ^ state[c], 7);
    };

    for (int i = 0; i < 10; i++) {
        quarterRound(x, 0, 4, 8, 12);
        quarterRound(x, 1, 5, 9, 13);
        quarterRound(x, 2, 6, 10, 14);
        quarterRound(x, 3, 7, 11, 15);

        quarterRound(x, 0, 5, 10, 15);
        quarterRound(x, 1, 6, 11, 12);
        quarterRound(x, 2, 7, 8, 13);
        quarterRound(x, 3, 4, 9, 14);
    }

    for (int i = 0; i < 4; i++) writeU32LE(outSubkey + i * 4, x[i]);
    for (int i = 0; i < 4; i++) writeU32LE(outSubkey + 16 + i * 4, x[12 + i]);
}

bool xchacha20Poly1305Encrypt(const uint8_t key[32], const uint8_t nonce24[24],
                              const uint8_t* plaintext, size_t plaintextLen,
                              uint8_t* outCiphertextAndTag) {
    uint8_t subkey[32];
    hchacha20(key, nonce24, subkey);

    uint8_t nonce12[12] = {0};
    std::memcpy(nonce12 + 4, nonce24 + 16, 8);

    mbedtls_chachapoly_context ctx;
    mbedtls_chachapoly_init(&ctx);
    if (mbedtls_chachapoly_setkey(&ctx, subkey) != 0) {
        mbedtls_chachapoly_free(&ctx);
        mbedtls_platform_zeroize(subkey, sizeof(subkey));
        return false;
    }

    int ret = mbedtls_chachapoly_encrypt_and_tag(
        &ctx, plaintextLen, nonce12,
        nullptr, 0,
        plaintext,
        outCiphertextAndTag,
        outCiphertextAndTag + plaintextLen
    );

    mbedtls_chachapoly_free(&ctx);
    mbedtls_platform_zeroize(subkey, sizeof(subkey));
    return ret == 0;
}

bool xchacha20Poly1305Decrypt(const uint8_t key[32], const uint8_t nonce24[24],
                              const uint8_t* ciphertext, size_t bodyLen,
                              const uint8_t tag[16],
                              uint8_t* outPlaintext) {
    uint8_t subkey[32];
    hchacha20(key, nonce24, subkey);

    uint8_t nonce12[12] = {0};
    std::memcpy(nonce12 + 4, nonce24 + 16, 8);

    mbedtls_chachapoly_context ctx;
    mbedtls_chachapoly_init(&ctx);
    if (mbedtls_chachapoly_setkey(&ctx, subkey) != 0) {
        mbedtls_chachapoly_free(&ctx);
        mbedtls_platform_zeroize(subkey, sizeof(subkey));
        return false;
    }

    int ret = mbedtls_chachapoly_auth_decrypt(
        &ctx, bodyLen, nonce12,
        nullptr, 0,
        tag,
        ciphertext,
        outPlaintext
    );

    mbedtls_chachapoly_free(&ctx);
    mbedtls_platform_zeroize(subkey, sizeof(subkey));
    return ret == 0;
}

} // namespace

CryfsCipherId cryfsCipherIdFromName(const char* name) {
    if (name == nullptr) return CryfsCipherId::kUnknown;
    if (std::strcmp(name, "aes-256-gcm") == 0) return CryfsCipherId::kAes256Gcm;
    if (std::strcmp(name, "aes-256-cfb") == 0) return CryfsCipherId::kAes256Cfb;
    if (std::strcmp(name, "aes-128-gcm") == 0) return CryfsCipherId::kAes128Gcm;
    if (std::strcmp(name, "aes-128-cfb") == 0) return CryfsCipherId::kAes128Cfb;
    if (std::strcmp(name, "xchacha20-poly1305") == 0) return CryfsCipherId::kXChaCha20Poly1305;
    return CryfsCipherId::kUnknown;
}

std::vector<uint8_t> cryfsBlockEncrypt(CryfsCipherId cipher,
                                        const uint8_t* key, size_t keyLen,
                                        const uint8_t* plaintext, size_t plaintextLen) {
    const size_t keyBits = keyBitsFor(cipher);
    if (keyBits == 0 || keyLen * 8 != keyBits) return {};

    if (cipher == CryfsCipherId::kXChaCha20Poly1305) {
        constexpr size_t kNonceLen = 24;
        constexpr size_t kTagLen = 16;
        std::vector<uint8_t> out(kNonceLen + plaintextLen + kTagLen);
        if (!randomBytes(out.data(), kNonceLen)) return {};

        bool ok = xchacha20Poly1305Encrypt(key, out.data(), plaintext, plaintextLen, out.data() + kNonceLen);
        if (!ok) return {};
        return out;
    }

    uint8_t iv[kIvSize];
    if (!randomBytes(iv, kIvSize)) return {};

    if (isGcm(cipher)) {
        std::vector<uint8_t> out(kIvSize + plaintextLen + kTagSize);
        std::memcpy(out.data(), iv, kIvSize);

        mbedtls_gcm_context ctx;
        mbedtls_gcm_init(&ctx);
        bool ok = mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, key, static_cast<unsigned>(keyBits)) == 0;
        if (ok) {
            ok = mbedtls_gcm_crypt_and_tag(
                     &ctx, MBEDTLS_GCM_ENCRYPT, plaintextLen,
                     iv, kIvSize,
                     nullptr, 0,
                     plaintext, out.data() + kIvSize,
                     kTagSize, out.data() + kIvSize + plaintextLen) == 0;
        }
        mbedtls_gcm_free(&ctx);
        if (!ok) return {};
        return out;
    }

    if (isCfb(cipher)) {
        std::vector<uint8_t> out(kIvSize + plaintextLen);
        std::memcpy(out.data(), iv, kIvSize);

        mbedtls_aes_context aes;
        mbedtls_aes_init(&aes);
        bool ok = mbedtls_aes_setkey_enc(&aes, key, static_cast<unsigned>(keyBits)) == 0;
        if (ok) {
            uint8_t ivCopy[kIvSize];
            std::memcpy(ivCopy, iv, kIvSize);
            size_t ivOff = 0;
            ok = mbedtls_aes_crypt_cfb128(&aes, MBEDTLS_AES_ENCRYPT, plaintextLen, &ivOff,
                                           ivCopy, plaintext, out.data() + kIvSize) == 0;
        }
        mbedtls_aes_free(&aes);
        if (!ok) return {};
        return out;
    }

    return {};
}

bool cryfsBlockDecrypt(CryfsCipherId cipher,
                        const uint8_t* key, size_t keyLen,
                        const uint8_t* ciphertext, size_t ciphertextLen,
                        std::vector<uint8_t>& out) {
    const size_t keyBits = keyBitsFor(cipher);
    if (keyBits == 0 || keyLen * 8 != keyBits) return false;

    if (cipher == CryfsCipherId::kXChaCha20Poly1305) {
        constexpr size_t kNonceLen = 24;
        constexpr size_t kTagLen = 16;
        if (ciphertextLen < kNonceLen + kTagLen) return false;

        const size_t bodyLen = ciphertextLen - kNonceLen - kTagLen;
        const uint8_t* nonce24 = ciphertext;
        const uint8_t* body = ciphertext + kNonceLen;
        const uint8_t* tag = ciphertext + kNonceLen + bodyLen;

        out.assign(bodyLen, 0);
        bool ok = xchacha20Poly1305Decrypt(key, nonce24, body, bodyLen, tag, out.data());
        if (!ok) {
            mbedtls_platform_zeroize(out.data(), out.size());
            out.clear();
            return false;
        }
        return true;
    }

    if (isGcm(cipher)) {
        if (ciphertextLen < kIvSize + kTagSize) return false;
        const size_t bodyLen = ciphertextLen - kIvSize - kTagSize;
        out.assign(bodyLen, 0);

        mbedtls_gcm_context ctx;
        mbedtls_gcm_init(&ctx);
        bool ok = mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, key, static_cast<unsigned>(keyBits)) == 0;
        if (ok) {
            ok = mbedtls_gcm_auth_decrypt(
                     &ctx, bodyLen,
                     ciphertext, kIvSize,
                     nullptr, 0,
                     ciphertext + kIvSize + bodyLen, kTagSize,
                     ciphertext + kIvSize, out.data()) == 0;
        }
        mbedtls_gcm_free(&ctx);
        if (!ok) {
            mbedtls_platform_zeroize(out.data(), out.size());
            out.clear();
            return false;
        }
        return true;
    }

    if (isCfb(cipher)) {
        if (ciphertextLen < kIvSize) return false;
        const size_t bodyLen = ciphertextLen - kIvSize;
        out.assign(bodyLen, 0);

        mbedtls_aes_context aes;
        mbedtls_aes_init(&aes);
        bool ok = mbedtls_aes_setkey_enc(&aes, key, static_cast<unsigned>(keyBits)) == 0;
        if (ok) {
            uint8_t ivCopy[kIvSize];
            std::memcpy(ivCopy, ciphertext, kIvSize);
            size_t ivOff = 0;
            ok = mbedtls_aes_crypt_cfb128(&aes, MBEDTLS_AES_DECRYPT, bodyLen, &ivOff,
                                           ivCopy, ciphertext + kIvSize, out.data()) == 0;
        }
        mbedtls_aes_free(&aes);
        if (!ok) {
            out.clear();
            return false;
        }
        return true;
    }

    return false;
}

long cryfsBlockCleartextSize(CryfsCipherId cipher, size_t ciphertextLen) {
    if (isGcm(cipher)) {
        if (ciphertextLen < kIvSize + kTagSize) return -1;
        return static_cast<long>(ciphertextLen - kIvSize - kTagSize);
    }
    if (isCfb(cipher)) {
        if (ciphertextLen < kIvSize) return -1;
        return static_cast<long>(ciphertextLen - kIvSize);
    }
    if (cipher == CryfsCipherId::kXChaCha20Poly1305) {
        if (ciphertextLen < 24 + 16) return -1;
        return static_cast<long>(ciphertextLen - 24 - 16);
    }
    return -1;
}