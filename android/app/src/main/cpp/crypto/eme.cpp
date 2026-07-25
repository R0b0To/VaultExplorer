#include "crypto/eme.h"
#include "mbedtls/aes.h"
#include "mbedtls/platform_util.h"
#include <cstring>
#include <vector>

// Little-endian GF(2^128) doubling for EME
static inline void emeMultByTwo(uint8_t out[16], const uint8_t inBlock[16]) {
    uint8_t tmp[16];
    uint8_t carry = inBlock[15] >> 7;
    tmp[0] = (inBlock[0] << 1) ^ (carry ? 0x87 : 0);
    for (int j = 1; j < 16; j++) {
        tmp[j] = (inBlock[j] << 1) | (inBlock[j - 1] >> 7);
    }
    std::memcpy(out, tmp, 16);
}

static inline void xor16(uint8_t out[16], const uint8_t in1[16], const uint8_t in2[16]) {
    for (int i = 0; i < 16; i++) {
        out[i] = in1[i] ^ in2[i];
    }
}

bool eme_transform(const uint8_t* key, size_t keyLen,
                   const uint8_t tweak[16],
                   const uint8_t* in, uint8_t* out, size_t len,
                   bool encrypt) {
    if (len == 0 || len % 16 != 0) return false;
    size_t m = len / 16;
    if (m < 1 || m > 128) return false;

    // The L-table mask is always AES(K,0) using the *encrypt* direction,
    // regardless of whether this call is doing an EME encrypt or decrypt --
    // only the core per-block transform below switches direction. So the
    // encrypt-direction schedule is always needed, but the decrypt-direction
    // schedule is only needed when this call is itself a decrypt; scheduling
    // it unconditionally (as before) wasted a full AES key expansion on
    // every encrypt call.
    mbedtls_aes_context encCtx;
    mbedtls_aes_init(&encCtx);
    if (mbedtls_aes_setkey_enc(&encCtx, key, keyLen * 8) != 0) {
        mbedtls_aes_free(&encCtx);
        return false;
    }

    mbedtls_aes_context decCtx;
    bool haveDecCtx = false;
    if (!encrypt) {
        mbedtls_aes_init(&decCtx);
        if (mbedtls_aes_setkey_dec(&decCtx, key, keyLen * 8) != 0) {
            mbedtls_aes_free(&encCtx);
            mbedtls_aes_free(&decCtx);
            return false;
        }
        haveDecCtx = true;
    }

    mbedtls_aes_context* mainCtx = encrypt ? &encCtx : &decCtx;

    // Tabulate L table: L_0 = 2 * AES-Enc(K, 0)
    uint8_t eZero[16] = {0};
    uint8_t Li[16];
    mbedtls_aes_crypt_ecb(&encCtx, MBEDTLS_AES_ENCRYPT, eZero, Li);

    // One contiguous buffer instead of a vector-of-vectors: m <= 128 was
    // already enforced above, so this is at most 128*16 = 2048 bytes in a
    // single allocation rather than up to 128 separate small heap
    // allocations (one per LTable[i]).
    std::vector<uint8_t> LTable(m * 16);
    uint8_t currentL[16];
    std::memcpy(currentL, Li, 16);

    for (size_t i = 0; i < m; i++) {
        emeMultByTwo(currentL, currentL);
        std::memcpy(LTable.data() + i * 16, currentL, 16);
    }

    std::vector<uint8_t> C(len);

    // Step 1: PP_j = P_j ^ L_j; PPP_j = AES(K, PP_j)
    uint8_t PPj[16];
    for (size_t j = 0; j < m; j++) {
        xor16(PPj, in + j * 16, LTable.data() + j * 16);
        mbedtls_aes_crypt_ecb(mainCtx, encrypt ? MBEDTLS_AES_ENCRYPT : MBEDTLS_AES_DECRYPT, PPj, C.data() + j * 16);
    }

    // MP = (sum PPP_j) ^ tweak
    uint8_t MP[16];
    xor16(MP, C.data(), tweak);
    for (size_t j = 1; j < m; j++) {
        xor16(MP, MP, C.data() + j * 16);
    }

    // MC = AES(K, MP)
    uint8_t MC[16];
    mbedtls_aes_crypt_ecb(mainCtx, encrypt ? MBEDTLS_AES_ENCRYPT : MBEDTLS_AES_DECRYPT, MP, MC);

    // M = MP ^ MC
    uint8_t M[16];
    xor16(M, MP, MC);

    // CCC_j = 2^(j-1) * M ^ PPP_j
    uint8_t CCCj[16];
    for (size_t j = 1; j < m; j++) {
        emeMultByTwo(M, M);
        xor16(CCCj, C.data() + j * 16, M);
        std::memcpy(C.data() + j * 16, CCCj, 16);
    }

    // CCC_0 = (sum CCC_j) ^ tweak ^ MC
    uint8_t CCC1[16];
    xor16(CCC1, MC, tweak);
    for (size_t j = 1; j < m; j++) {
        xor16(CCC1, CCC1, C.data() + j * 16);
    }
    std::memcpy(C.data(), CCC1, 16);

    // Step 3: CC_j = AES(K, CCC_j); C_j = CC_j ^ L_j
    for (size_t j = 0; j < m; j++) {
        mbedtls_aes_crypt_ecb(mainCtx, encrypt ? MBEDTLS_AES_ENCRYPT : MBEDTLS_AES_DECRYPT, C.data() + j * 16, C.data() + j * 16);
        xor16(out + j * 16, C.data() + j * 16, LTable.data() + j * 16);
    }

    mbedtls_aes_free(&encCtx);
    if (haveDecCtx) mbedtls_aes_free(&decCtx);

    // These are all key-derived or key-adjacent intermediate values (the
    // L-table is AES(K,0) directly); wipe them rather than leaving them on
    // the stack/heap after we're done, consistent with the zeroization
    // discipline used elsewhere in the crypto layer.
    mbedtls_platform_zeroize(Li, sizeof(Li));
    mbedtls_platform_zeroize(currentL, sizeof(currentL));
    mbedtls_platform_zeroize(LTable.data(), LTable.size());
    mbedtls_platform_zeroize(C.data(), C.size());
    mbedtls_platform_zeroize(PPj, sizeof(PPj));
    mbedtls_platform_zeroize(MP, sizeof(MP));
    mbedtls_platform_zeroize(MC, sizeof(MC));
    mbedtls_platform_zeroize(M, sizeof(M));
    mbedtls_platform_zeroize(CCCj, sizeof(CCCj));
    mbedtls_platform_zeroize(CCC1, sizeof(CCC1));

    return true;
}