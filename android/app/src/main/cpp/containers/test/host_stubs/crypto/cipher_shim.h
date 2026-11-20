#pragma once
// Host-test stand-in for crypto/cipher_shim.h: a keyed, invertible per-block
// transform (XOR with a key-dependent stream). Not a cipher -- it only has to
// depend on the key so the tests can tell differently keyed outputs apart.
#include <cstdint>
struct BlockCipherContext {
    uint32_t k = 0;
};
inline void blockCipherEncryptBlock(const BlockCipherContext& ctx, const unsigned char in[16],
                                    unsigned char out[16]) {
    for (uint32_t j = 0; j < 16; ++j) {
        uint32_t s = ctx.k + j * 0x9E3779B9u;
        s ^= s >> 15;
        s *= 2246822519u;
        s ^= s >> 13;
        out[j] = static_cast<unsigned char>(in[j] ^ (s & 0xFF));
    }
}
