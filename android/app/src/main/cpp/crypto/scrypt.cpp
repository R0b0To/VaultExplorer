#include "crypto/scrypt.h"
#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/platform_util.h"
#include <cstdlib>
#include <cstring>
#include <vector>

#define ROTL(a, b) (((a) << (b)) | ((a) >> (32 - (b))))

static inline void salsa20_8(uint8_t B[64]) {
    uint32_t B32[16];
    uint32_t x[16];

    for (int i = 0; i < 16; i++) {
        B32[i] = ((uint32_t)B[i * 4 + 0]) |
                 ((uint32_t)B[i * 4 + 1] << 8) |
                 ((uint32_t)B[i * 4 + 2] << 16) |
                 ((uint32_t)B[i * 4 + 3] << 24);
        x[i] = B32[i];
    }

    for (int i = 8; i > 0; i -= 2) {
        x[ 4] ^= ROTL(x[ 0] + x[12],  7);
        x[ 8] ^= ROTL(x[ 4] + x[ 0],  9);
        x[12] ^= ROTL(x[ 8] + x[ 4], 13);
        x[ 0] ^= ROTL(x[12] + x[ 8], 18);

        x[ 9] ^= ROTL(x[ 5] + x[ 1],  7);
        x[13] ^= ROTL(x[ 9] + x[ 5],  9);
        x[ 1] ^= ROTL(x[13] + x[ 9], 13);
        x[ 5] ^= ROTL(x[ 1] + x[13], 18);

        x[14] ^= ROTL(x[10] + x[ 6],  7);
        x[ 2] ^= ROTL(x[14] + x[10],  9);
        x[ 6] ^= ROTL(x[ 2] + x[14], 13);
        x[10] ^= ROTL(x[ 6] + x[ 2], 18);

        x[ 3] ^= ROTL(x[15] + x[11],  7);
        x[ 7] ^= ROTL(x[ 3] + x[15],  9);
        x[11] ^= ROTL(x[ 7] + x[ 3], 13);
        x[15] ^= ROTL(x[11] + x[ 7], 18);

        x[ 1] ^= ROTL(x[ 0] + x[ 3],  7);
        x[ 2] ^= ROTL(x[ 1] + x[ 0],  9);
        x[ 3] ^= ROTL(x[ 2] + x[ 1], 13);
        x[ 0] ^= ROTL(x[ 3] + x[ 2], 18);

        x[ 6] ^= ROTL(x[ 5] + x[ 4],  7);
        x[ 7] ^= ROTL(x[ 6] + x[ 5],  9);
        x[ 4] ^= ROTL(x[ 7] + x[ 6], 13);
        x[ 5] ^= ROTL(x[ 4] + x[ 7], 18);

        x[11] ^= ROTL(x[10] + x[ 9],  7);
        x[ 8] ^= ROTL(x[11] + x[10],  9);
        x[ 9] ^= ROTL(x[ 8] + x[11], 13);
        x[10] ^= ROTL(x[ 9] + x[ 8], 18);

        x[12] ^= ROTL(x[15] + x[14],  7);
        x[13] ^= ROTL(x[12] + x[15],  9);
        x[14] ^= ROTL(x[13] + x[12], 13);
        x[15] ^= ROTL(x[14] + x[13], 18);
    }

    for (int i = 0; i < 16; i++) {
        B32[i] += x[i];
        B[i * 4 + 0] = (uint8_t)(B32[i] & 0xFF);
        B[i * 4 + 1] = (uint8_t)((B32[i] >> 8) & 0xFF);
        B[i * 4 + 2] = (uint8_t)((B32[i] >> 16) & 0xFF);
        B[i * 4 + 3] = (uint8_t)((B32[i] >> 24) & 0xFF);
    }
}

static inline void blockxor(const uint8_t* s, size_t si, uint8_t* d, size_t di, size_t len) {
    for (size_t i = 0; i < len; i++) {
        d[di + i] ^= s[si + i];
    }
}

static inline void blockmixSalsa8(uint8_t* BY, size_t bi, size_t yi, size_t r) {
    uint8_t X[64];
    std::memcpy(X, &BY[bi + (2 * r - 1) * 64], 64);

    for (size_t i = 0; i < 2 * r; i++) {
        blockxor(BY, bi + i * 64, X, 0, 64);
        salsa20_8(X);
        std::memcpy(&BY[yi + i * 64], X, 64);
    }

    for (size_t i = 0; i < r; i++) {
        std::memcpy(&BY[bi + i * 64], &BY[yi + (i * 2) * 64], 64);
    }
    for (size_t i = 0; i < r; i++) {
        std::memcpy(&BY[bi + (i + r) * 64], &BY[yi + (i * 2 + 1) * 64], 64);
    }
}

static inline uint32_t integerify(const uint8_t* B, size_t bi0, size_t r) {
    size_t bi = bi0 + (2 * r - 1) * 64;
    return ((uint32_t)B[bi + 0]) |
           ((uint32_t)B[bi + 1] << 8) |
           ((uint32_t)B[bi + 2] << 16) |
           ((uint32_t)B[bi + 3] << 24);
}

static inline void smix(uint8_t* B, size_t bi, size_t r, uint32_t N, uint8_t* V, uint8_t* XY) {
    size_t blockLen = 128 * r;
    size_t xi = 0;
    size_t yi = 128 * r;

    std::memcpy(&XY[xi], &B[bi], blockLen);

    for (uint32_t i = 0; i < N; i++) {
        std::memcpy(&V[(size_t)i * blockLen], &XY[xi], blockLen);
        blockmixSalsa8(XY, xi, yi, r);
    }

    for (uint32_t i = 0; i < N; i++) {
        uint32_t j = integerify(XY, xi, r) & (N - 1);
        blockxor(V, (size_t)j * blockLen, XY, xi, blockLen);
        blockmixSalsa8(XY, xi, yi, r);
    }

    std::memcpy(&B[bi], &XY[xi], blockLen);
}

static bool pbkdf2_sha256(const uint8_t* password, size_t passwordLen,
                          const uint8_t* salt, size_t saltLen,
                          uint32_t iterations,
                          uint8_t* out, size_t outLen) {
    const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
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
}

bool scrypt_crypto(const uint8_t* passphrase, size_t passphraseLen,
                   const uint8_t* salt, size_t saltLen,
                   uint32_t N, uint32_t r, uint32_t p,
                   uint8_t* out, size_t outLen) {
    if (N < 2 || (N & (N - 1)) != 0) return false;
    if (r == 0 || p == 0) return false;

    size_t blockLen = 128 * r;
    size_t bLen = blockLen * p;

    std::vector<uint8_t> B(bLen);
    std::vector<uint8_t> XY(256 * r);

    // Allocated on native C heap - bypasses JVM 256MB limit!
    size_t vLen = blockLen * (size_t)N;
    uint8_t* V = static_cast<uint8_t*>(std::malloc(vLen));
    if (!V) {
        return false;
    }

    if (!pbkdf2_sha256(passphrase, passphraseLen, salt, saltLen, 1, B.data(), bLen)) {
        std::free(V);
        return false;
    }

    for (uint32_t i = 0; i < p; i++) {
        smix(&B[i * blockLen], 0, r, N, V, XY.data());
    }

    bool ok = pbkdf2_sha256(passphrase, passphraseLen, B.data(), bLen, 1, out, outLen);

    mbedtls_platform_zeroize(V, vLen);
    std::free(V);
    mbedtls_platform_zeroize(B.data(), B.size());
    mbedtls_platform_zeroize(XY.data(), XY.size());

    return ok;
}