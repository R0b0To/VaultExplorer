#include "crypto/cryfs_block_cipher.h"
#include "crypto/xchacha20poly1305.h"
#include "mbedtls/gcm.h"
#include "mbedtls/aes.h"
#include "mbedtls/platform_util.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include <cstdio>
#include <cstring>
#include <mutex>

namespace {

constexpr size_t kIvSize = 16;   // == AES block size
constexpr size_t kTagSize = 16;  // GCM/Poly1305 tag size


struct Drbg {
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
    std::mutex mutex;
    bool seeded;

    Drbg() : seeded(false) {
        mbedtls_entropy_init(&entropy);
        mbedtls_ctr_drbg_init(&ctr_drbg);
        static const unsigned char kPersonalization[] = "cryfs_block_cipher";
        seeded = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy,
                                        kPersonalization, sizeof(kPersonalization) - 1) == 0;
    }

    ~Drbg() {
        mbedtls_ctr_drbg_free(&ctr_drbg);
        mbedtls_entropy_free(&entropy);
    }
};

// C++11 guarantees thread-safe one-time initialization of function-local
// statics, so no separate init-guard is needed for construction itself --
// only the per-call mbedtls_ctr_drbg_random() invocation needs the mutex.
Drbg& drbg() {
    static Drbg instance;
    return instance;
}

bool randomBytes(uint8_t* buf, size_t len) {
    Drbg& d = drbg();
    if (!d.seeded) return false;
    std::lock_guard<std::mutex> lock(d.mutex);
    return mbedtls_ctr_drbg_random(&d.ctr_drbg, buf, len) == 0;
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

        bool ok = xchacha20Poly1305Seal(key, out.data(), nullptr, 0, plaintext, plaintextLen, out.data() + kNonceLen);
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
        bool ok = xchacha20Poly1305Open(key, nonce24, nullptr, 0, body, bodyLen, tag, out.data());
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