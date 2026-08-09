#include "crypto/xchacha20poly1305.h"
#include "mbedtls/chachapoly.h"
#include "mbedtls/platform_util.h"
#include <cstring>

namespace {

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

} // namespace

// HChaCha20 subkey derivation function (draft-irtf-cfrg-xchacha-03 §2.2).
// Same ChaCha20 core as RFC 8439, but takes a 16-byte nonce (4 words) in
// place of the 32-bit counter + 12-byte nonce, skips the final
// "add the original input words" step, and only outputs words 0-3 and
// 12-15 of the resulting state.
// "expand 32-byte k" in Little-Endian 32-bit integers:
// 0x61707865 ("expa"), 0x3320646e ("nd 3"), 0x79622d32 ("2-by"), 0x6b206574 ("tey ")
void hchacha20(const uint8_t key[32], const uint8_t nonce16[16], uint8_t outSubkey[32]) {
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
        x[12 + i] = readU32LE(nonce16 + i * 4);
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

bool xchacha20Poly1305Seal(const uint8_t key[32], const uint8_t nonce24[24],
                            const uint8_t* aad, size_t aadLen,
                            const uint8_t* plaintext, size_t plaintextLen,
                            uint8_t* outCiphertextAndTag) {
    uint8_t subkey[32];
    hchacha20(key, nonce24, subkey);

    // Inner 12-byte nonce per draft-irtf-cfrg-xchacha §2.3: 4 zero bytes
    // followed by the last 8 bytes of the 24-byte XChaCha nonce.
    uint8_t nonce12[12] = {0};
    std::memcpy(nonce12 + 4, nonce24 + 16, 8);

    mbedtls_chachapoly_context ctx;
    mbedtls_chachapoly_init(&ctx);
    bool ok = mbedtls_chachapoly_setkey(&ctx, subkey) == 0;
    if (ok) {
        ok = mbedtls_chachapoly_encrypt_and_tag(
            &ctx, plaintextLen, nonce12,
            aad, aadLen,
            plaintext,
            outCiphertextAndTag,
            outCiphertextAndTag + plaintextLen
        ) == 0;
    }

    mbedtls_chachapoly_free(&ctx);
    mbedtls_platform_zeroize(subkey, sizeof(subkey));
    return ok;
}

bool xchacha20Poly1305Open(const uint8_t key[32], const uint8_t nonce24[24],
                            const uint8_t* aad, size_t aadLen,
                            const uint8_t* ciphertext, size_t bodyLen,
                            const uint8_t tag[16],
                            uint8_t* outPlaintext) {
    uint8_t subkey[32];
    hchacha20(key, nonce24, subkey);

    uint8_t nonce12[12] = {0};
    std::memcpy(nonce12 + 4, nonce24 + 16, 8);

    mbedtls_chachapoly_context ctx;
    mbedtls_chachapoly_init(&ctx);
    bool ok = mbedtls_chachapoly_setkey(&ctx, subkey) == 0;
    if (ok) {
        ok = mbedtls_chachapoly_auth_decrypt(
            &ctx, bodyLen, nonce12,
            aad, aadLen,
            tag,
            ciphertext,
            outPlaintext
        ) == 0;
    }

    mbedtls_chachapoly_free(&ctx);
    mbedtls_platform_zeroize(subkey, sizeof(subkey));
    return ok;
}
