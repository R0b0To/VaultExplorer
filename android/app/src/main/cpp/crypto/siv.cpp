#include "crypto/siv.h"
#include "mbedtls/aes.h"
#include "mbedtls/platform_util.h"
#include <cstring>
#include <vector>

// Big-endian GF(2^128) doubling for SIV (RFC 5297)
static void sivDouble(uint8_t block[16]) {
    uint8_t carry = 0;
    uint8_t msb = (block[0] & 0x80) ? 0x87 : 0;
    for (int i = 15; i >= 0; i--) {
        uint8_t nextCarry = (block[i] & 0x80) ? 1 : 0;
        block[i] = (block[i] << 1) | carry;
        carry = nextCarry;
    }
    block[15] ^= msb;
}

static void xorBytes(uint8_t* dst, const uint8_t* src, size_t len) {
    for (size_t i = 0; i < len; i++) {
        dst[i] ^= src[i];
    }
}

static bool aesCmac(mbedtls_aes_context* aesCtx, const uint8_t* msg, size_t msgLen, uint8_t out[16]) {
    uint8_t zero[16] = {0};
    uint8_t L[16];
    mbedtls_aes_crypt_ecb(aesCtx, MBEDTLS_AES_ENCRYPT, zero, L);

    uint8_t K1[16], K2[16];
    std::memcpy(K1, L, 16);
    sivDouble(K1);
    std::memcpy(K2, K1, 16);
    sivDouble(K2);

    size_t n = (msgLen == 0) ? 1 : (msgLen + 15) / 16;
    bool lastBlockComplete = (msgLen > 0) && (msgLen % 16 == 0);

    std::vector<uint8_t> mLast(16, 0);
    if (lastBlockComplete) {
        size_t lastStart = (n - 1) * 16;
        std::memcpy(mLast.data(), msg + lastStart, 16);
        xorBytes(mLast.data(), K1, 16);
    } else {
        size_t lastStart = (n - 1) * 16;
        size_t lastLen = msgLen - lastStart;
        if (lastLen > 0) {
            std::memcpy(mLast.data(), msg + lastStart, lastLen);
        }
        mLast[lastLen] = 0x80;
        xorBytes(mLast.data(), K2, 16);
    }

    uint8_t X[16] = {0};
    uint8_t block[16];
    for (size_t i = 0; i < n - 1; i++) {
        std::memcpy(block, msg + i * 16, 16);
        xorBytes(X, block, 16);
        mbedtls_aes_crypt_ecb(aesCtx, MBEDTLS_AES_ENCRYPT, X, X);
    }

    xorBytes(X, mLast.data(), 16);
    mbedtls_aes_crypt_ecb(aesCtx, MBEDTLS_AES_ENCRYPT, X, out);
    return true;
}

static bool s2v(mbedtls_aes_context* macCtx, const std::vector<std::vector<uint8_t>>& elements, uint8_t out[16]) {
    if (elements.empty()) return false;

    uint8_t zero[16] = {0};
    uint8_t D[16];
    aesCmac(macCtx, zero, 16, D);

    for (size_t i = 0; i < elements.size() - 1; i++) {
        sivDouble(D);
        uint8_t cmacElem[16];
        aesCmac(macCtx, elements[i].data(), elements[i].size(), cmacElem);
        xorBytes(D, cmacElem, 16);
    }

    const auto& last = elements.back();
    if (last.size() >= 16) {
        std::vector<uint8_t> T = last;
        size_t offset = T.size() - 16;
        xorBytes(T.data() + offset, D, 16);
        aesCmac(macCtx, T.data(), T.size(), out);
    } else {
        uint8_t padded[16] = {0};
        std::memcpy(padded, last.data(), last.size());
        padded[last.size()] = 0x80;
        sivDouble(D);
        xorBytes(D, padded, 16);
        aesCmac(macCtx, D, 16, out);
    }
    return true;
}

bool siv_encrypt(const uint8_t* encKey, size_t encKeyLen,
                 const uint8_t* macKey, size_t macKeyLen,
                 const uint8_t* plaintext, size_t plaintextLen,
                 const std::vector<std::vector<uint8_t>>& adList,
                 uint8_t* out, size_t outLen) {
    if (outLen != 16 + plaintextLen) return false;

    mbedtls_aes_context macCtx, encCtx;
    mbedtls_aes_init(&macCtx);
    mbedtls_aes_init(&encCtx);

    if (mbedtls_aes_setkey_enc(&macCtx, macKey, macKeyLen * 8) != 0 ||
        mbedtls_aes_setkey_enc(&encCtx, encKey, encKeyLen * 8) != 0) {
        mbedtls_aes_free(&macCtx);
        mbedtls_aes_free(&encCtx);
        return false;
    }

    std::vector<std::vector<uint8_t>> elements = adList;
    elements.push_back(std::vector<uint8_t>(plaintext, plaintext + plaintextLen));

    uint8_t SIV[16];
    if (!s2v(&macCtx, elements, SIV)) {
        mbedtls_aes_free(&macCtx);
        mbedtls_aes_free(&encCtx);
        return false;
    }

    std::memcpy(out, SIV, 16);

    if (plaintextLen > 0) {
        uint8_t Q[16];
        std::memcpy(Q, SIV, 16);
        Q[8] &= 0x7F;
        Q[12] &= 0x7F;

        size_t nc_off = 0;
        uint8_t stream_block[16] = {0};

        mbedtls_aes_crypt_ctr(&encCtx, plaintextLen, &nc_off, Q, stream_block, plaintext, out + 16);
    }

    mbedtls_aes_free(&macCtx);
    mbedtls_aes_free(&encCtx);
    return true;
}

bool siv_decrypt(const uint8_t* encKey, size_t encKeyLen,
                 const uint8_t* macKey, size_t macKeyLen,
                 const uint8_t* ciphertext, size_t ciphertextLen,
                 const std::vector<std::vector<uint8_t>>& adList,
                 uint8_t* out, size_t outLen) {
    if (ciphertextLen < 16 || outLen != ciphertextLen - 16) return false;

    mbedtls_aes_context macCtx, encCtx;
    mbedtls_aes_init(&macCtx);
    mbedtls_aes_init(&encCtx);

    if (mbedtls_aes_setkey_enc(&macCtx, macKey, macKeyLen * 8) != 0 ||
        mbedtls_aes_setkey_enc(&encCtx, encKey, encKeyLen * 8) != 0) {
        mbedtls_aes_free(&macCtx);
        mbedtls_aes_free(&encCtx);
        return false;
    }

    const uint8_t* embeddedSiv = ciphertext;
    const uint8_t* actualCt = ciphertext + 16;
    size_t ctLen = ciphertextLen - 16;

    if (ctLen > 0) {
        uint8_t Q[16];
        std::memcpy(Q, embeddedSiv, 16);
        Q[8] &= 0x7F;
        Q[12] &= 0x7F;

        size_t nc_off = 0;
        uint8_t stream_block[16] = {0};

        mbedtls_aes_crypt_ctr(&encCtx, ctLen, &nc_off, Q, stream_block, actualCt, out);
    }

    std::vector<std::vector<uint8_t>> elements = adList;
    elements.push_back(std::vector<uint8_t>(out, out + outLen));

    uint8_t expectedSiv[16];
    if (!s2v(&macCtx, elements, expectedSiv)) {
        mbedtls_aes_free(&macCtx);
        mbedtls_aes_free(&encCtx);
        return false;
    }

    mbedtls_aes_free(&macCtx);
    mbedtls_aes_free(&encCtx);

    int diff = 0;
    for (int i = 0; i < 16; i++) {
        diff |= (embeddedSiv[i] ^ expectedSiv[i]);
    }
    return diff == 0;
}