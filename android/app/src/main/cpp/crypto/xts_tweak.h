#pragma once

// Doubles an XTS tweak value T in GF(2^128), modulo the field's primitive
// polynomial x^128 + x^7 + x^2 + x + 1 (0x87) — the standard per-block
// tweak update used between successive 16-byte blocks of the same XTS
// data unit (IEEE P1619).
inline void xtsMultiplyTweak(unsigned char T[16]) {
    unsigned char carry = 0;
    for (int i = 0; i < 16; i++) {
        const unsigned char nextCarry = (T[i] & 0x80) ? 1 : 0;
        T[i] = static_cast<unsigned char>((T[i] << 1) | carry);
        carry = nextCarry;
    }
    if (carry) {
        T[0] ^= 0x87;
    }
}