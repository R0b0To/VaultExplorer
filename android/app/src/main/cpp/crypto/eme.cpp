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

    mbedtls_aes_context encCtx, decCtx;
    mbedtls_aes_init(&encCtx);
    mbedtls_aes_init(&decCtx);

    if (mbedtls_aes_setkey_enc(&encCtx, key, keyLen * 8) != 0 ||
        mbedtls_aes_setkey_dec(&decCtx, key, keyLen * 8) != 0) {
        mbedtls_aes_free(&encCtx);
        mbedtls_aes_free(&decCtx);
        return false;
    }

    mbedtls_aes_context* mainCtx = encrypt ? &encCtx : &decCtx;

    // Tabulate L table: L_0 = 2 * AES-Enc(K, 0)
    uint8_t eZero[16] = {0};
    uint8_t Li[16];
    mbedtls_aes_crypt_ecb(&encCtx, MBEDTLS_AES_ENCRYPT, eZero, Li);

    std::vector<std::vector<uint8_t>> LTable(m, std::vector<uint8_t>(16));
    uint8_t currentL[16];
    std::memcpy(currentL, Li, 16);

    for (size_t i = 0; i < m; i++) {
        emeMultByTwo(currentL, currentL);
        std::memcpy(LTable[i].data(), currentL, 16);
    }

    std::vector<uint8_t> C(len);

    // Step 1: PP_j = P_j ^ L_j; PPP_j = AES(K, PP_j)
    uint8_t PPj[16];
    for (size_t j = 0; j < m; j++) {
        xor16(PPj, in + j * 16, LTable[j].data());
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
        xor16(out + j * 16, C.data() + j * 16, LTable[j].data());
    }

    mbedtls_aes_free(&encCtx);
    mbedtls_aes_free(&decCtx);
    return true;
}