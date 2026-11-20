#pragma once
// Host-test stand-in for crypto/xts_tweak.h (same GF(2^128) doubling).
inline void xtsMultiplyTweak(unsigned char T[16]) {
    unsigned char carry = 0;
    for (int i = 0; i < 16; ++i) {
        const unsigned char c = static_cast<unsigned char>(T[i] >> 7);
        T[i] = static_cast<unsigned char>((T[i] << 1) | carry);
        carry = c;
    }
    if (carry) T[0] ^= 0x87;
}
