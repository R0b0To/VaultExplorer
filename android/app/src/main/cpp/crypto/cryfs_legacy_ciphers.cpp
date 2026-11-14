// Twofish, Serpent, CAST-256 and MARS (encrypt direction only) plus generic GCM/CFB-128, wire-compatible with
// the Crypto++ implementations official CryFS 1.x uses. Algorithm structure and constants follow the published
// specifications as implemented in Crypto++ 8.9.0 (Boost Software License 1.0, https://www.cryptopp.com);
// tests/cryfs_cipher_oracle verifies every cipher against that library.
#include "crypto/cryfs_legacy_ciphers.h"
#include "crypto/cryfs_legacy_tables.h"
#include <cstring>

namespace cryfs_legacy {
namespace {

typedef uint32_t word32;
typedef uint64_t word64;

template <unsigned R> inline word32 rotlConstant(word32 x) { return (x << R) | (x >> (32 - R)); }
inline word32 rotl(word32 x, unsigned n) { n &= 31; return n ? (x << n) | (x >> (32 - n)) : x; }
inline word32 rotr(word32 x, unsigned n) { return rotl(x, (32 - (n & 31)) & 31); }
inline word32 byteOf(word32 x, int i) { return (x >> (8 * i)) & 0xFF; }

inline word32 loadLE(const uint8_t* p) { return (word32)p[0] | ((word32)p[1] << 8) | ((word32)p[2] << 16) | ((word32)p[3] << 24); }
inline void storeLE(uint8_t* p, word32 v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }
inline word32 loadBE(const uint8_t* p) { return ((word32)p[0] << 24) | ((word32)p[1] << 16) | ((word32)p[2] << 8) | (word32)p[3]; }
inline void storeBE(uint8_t* p, word32 v) { p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v; }

// Key bytes -> [nWords] words, zero padded (Crypto++ GetUserKey).
void userKeyLE(word32* w, size_t nWords, const uint8_t* key, size_t keyLen) {
    for (size_t i = 0; i < nWords; i++) w[i] = 0;
    for (size_t i = 0; i < keyLen && i / 4 < nWords; i++) w[i / 4] |= (word32)key[i] << (8 * (i % 4));
}
void userKeyBE(word32* w, size_t nWords, const uint8_t* key, size_t keyLen) {
    for (size_t i = 0; i < nWords; i++) w[i] = 0;
    for (size_t i = 0; i < keyLen && i / 4 < nWords; i++) w[i / 4] |= (word32)key[i] << (8 * (3 - i % 4));
}

// ------------------------------------------------------------------------------------------------ Twofish
class Twofish final : public Block128 {
public:
    Twofish(const uint8_t* userKey, size_t keyLen) {
        const unsigned len = keyLen <= 16 ? 2 : (keyLen <= 24 ? 3 : 4);
        word32 key[8];
        userKeyLE(key, len * 2, userKey, keyLen);
        for (unsigned i = 0; i < 40; i += 2) {
            word32 a = h(i, key, len);
            word32 b = rotlConstant<8>(h(i + 1, key + 1, len));
            k_[i] = a + b;
            k_[i + 1] = rotlConstant<9>(a + 2 * b);
        }
        word32 svec[8];
        for (unsigned i = 0; i < len; i++) svec[2 * (len - i - 1)] = reedSolomon(key[2 * i + 1], key[2 * i]);
        for (unsigned i = 0; i < 256; i++) {
            word32 t = h0(i, svec, len);
            for (int j = 0; j < 4; j++) s_[j * 256 + i] = cryfs_legacy_tables::kTwofishMds[j * 256 + byteOf(t, j)];
        }
    }

    void encrypt(const uint8_t in[16], uint8_t out[16]) const override {
        word32 a = loadLE(in), b = loadLE(in + 4), c = loadLE(in + 8), d = loadLE(in + 12), x, y;
        a ^= k_[0]; b ^= k_[1]; c ^= k_[2]; d ^= k_[3];
        const word32* k = k_ + 8;
        for (int n = 0; n < 8; n++) {
            x = g1(a); y = g2(b); x += y; y += x + k[4 * n + 1];
            c ^= x + k[4 * n]; c = rotr(c, 1); d = rotl(d, 1) ^ y;
            x = g1(c); y = g2(d); x += y; y += x + k[4 * n + 3];
            a ^= x + k[4 * n + 2]; a = rotr(a, 1); b = rotl(b, 1) ^ y;
        }
        c ^= k_[4]; d ^= k_[5]; a ^= k_[6]; b ^= k_[7];
        storeLE(out, c); storeLE(out + 4, d); storeLE(out + 8, a); storeLE(out + 12, b);
    }

private:
    static word32 mod(word32 c) {
        const word32 modulus = 0x14d;
        word32 c2 = (c << 1) ^ ((c & 0x80) ? modulus : 0);
        word32 c1 = c2 ^ (c >> 1) ^ ((c & 1) ? (modulus >> 1) : 0);
        return c | (c1 << 8) | (c2 << 16) | (c1 << 24);
    }
    static word32 reedSolomon(word32 high, word32 low) {
        for (unsigned i = 0; i < 8; i++) { high = mod(high >> 24) ^ (high << 8) ^ (low >> 24); low <<= 8; }
        return high;
    }
    static word32 q4(int a, int b, int c, int d, word32 t) {
        const uint8_t* q = cryfs_legacy_tables::kTwofishQ;
        return (word32)q[a * 256 + byteOf(t, 0)] ^ ((word32)q[b * 256 + byteOf(t, 1)] << 8) ^
               ((word32)q[c * 256 + byteOf(t, 2)] << 16) ^ ((word32)q[d * 256 + byteOf(t, 3)] << 24);
    }
    static word32 h0(word32 x, const word32* key, unsigned kLen) {
        x = x | (x << 8) | (x << 16) | (x << 24);
        if (kLen >= 4) x = q4(1, 0, 0, 1, x) ^ key[6];
        if (kLen >= 3) x = q4(1, 1, 0, 0, x) ^ key[4];
        x = q4(0, 1, 0, 1, x) ^ key[2];
        x = q4(0, 0, 1, 1, x) ^ key[0];
        return x;
    }
    static word32 h(word32 x, const word32* key, unsigned kLen) {
        x = h0(x, key, kLen);
        const word32* m = cryfs_legacy_tables::kTwofishMds;
        return m[byteOf(x, 0)] ^ m[256 + byteOf(x, 1)] ^ m[512 + byteOf(x, 2)] ^ m[768 + byteOf(x, 3)];
    }
    word32 g1(word32 x) const { return s_[byteOf(x, 0)] ^ s_[256 + byteOf(x, 1)] ^ s_[512 + byteOf(x, 2)] ^ s_[768 + byteOf(x, 3)]; }
    word32 g2(word32 x) const { return s_[byteOf(x, 3)] ^ s_[256 + byteOf(x, 0)] ^ s_[512 + byteOf(x, 1)] ^ s_[768 + byteOf(x, 2)]; }

    word32 k_[40];
    word32 s_[4 * 256];
};

// ------------------------------------------------------------------------------------------------- Serpent
#include "crypto/cryfs_serpent_macros.inc"

class Serpent final : public Block128 {
public:
    Serpent(const uint8_t* userKey, size_t keyLen) {
        word32 k0[8];
        userKeyLE(k0, 8, userKey, keyLen);
        if (keyLen < 32) k0[keyLen / 4] |= word32(1) << ((keyLen % 4) * 8);
        word32* rk = ks_ + 20;             // the 132 round-key words; the key-schedule macros index 20 words below it
        word32 t = k0[7];
        for (unsigned i = 0; i < 8; ++i) rk[i] = k0[i] = t = rotlConstant<11>(k0[i] ^ k0[(i + 3) % 8] ^ k0[(i + 5) % 8] ^ t ^ 0x9e3779b9 ^ i);
        for (unsigned i = 8; i < 132; ++i) rk[i] = t = rotlConstant<11>(rk[i - 8] ^ rk[i - 5] ^ rk[i - 3] ^ t ^ 0x9e3779b9 ^ i);
        word32* k = ks_;                   // == rk - 20
        word32 a, b, c, d, e;
        for (unsigned i = 0; i < 4; i++) {
            afterS2(LK); afterS2(S3); afterS3(SK);
            afterS1(LK); afterS1(S2); afterS2(SK);
            afterS0(LK); afterS0(S1); afterS1(SK);
            beforeS0(LK); beforeS0(S0); afterS0(SK);
            k += 8 * 4;
            afterS6(LK); afterS6(S7); afterS7(SK);
            afterS5(LK); afterS5(S6); afterS6(SK);
            afterS4(LK); afterS4(S5); afterS5(SK);
            afterS3(LK); afterS3(S4); afterS4(SK);
        }
        afterS2(LK); afterS2(S3); afterS3(SK);
    }

    void encrypt(const uint8_t in[16], uint8_t out[16]) const override {
        word32 a = loadLE(in), b = loadLE(in + 4), c = loadLE(in + 8), d = loadLE(in + 12), e;
        const word32* k = ks_ + 20;
        unsigned i = 1;
        do {
            beforeS0(KX); beforeS0(S0); afterS0(LT);
            afterS0(KX); afterS0(S1); afterS1(LT);
            afterS1(KX); afterS1(S2); afterS2(LT);
            afterS2(KX); afterS2(S3); afterS3(LT);
            afterS3(KX); afterS3(S4); afterS4(LT);
            afterS4(KX); afterS4(S5); afterS5(LT);
            afterS5(KX); afterS5(S6); afterS6(LT);
            afterS6(KX); afterS6(S7);
            if (i == 4) break;
            ++i;
            c = b; b = e; e = d; d = a; a = e;
            k += 32;
            beforeS0(LT);
        } while (true);
        afterS7(KX);
        storeLE(out, d); storeLE(out + 4, e); storeLE(out + 8, b); storeLE(out + 12, a);
    }

private:
    word32 ks_[152];
};

// The Serpent macros are only for the class above; MARS below has helpers with the same names.
#undef LT
#undef beforeS0
#undef afterS0
#undef afterS1
#undef afterS2
#undef afterS3
#undef afterS4
#undef afterS5
#undef afterS6
#undef afterS7
#undef S0
#undef S1
#undef S2
#undef S3
#undef S4
#undef S5
#undef S6
#undef S7
#undef KX
#undef LK
#undef SK

// ------------------------------------------------------------------------------------------------ CAST-256
class Cast256 final : public Block128 {
public:
    Cast256(const uint8_t* userKey, size_t keyLen) {
        word32 kappa[8];
        userKeyBE(kappa, 8, userKey, keyLen);
        for (int i = 0; i < 12; ++i) {
            omega(2 * i, kappa);
            omega(2 * i + 1, kappa);
            K_[8 * i] = kappa[0] & 31;
            K_[8 * i + 1] = kappa[2] & 31;
            K_[8 * i + 2] = kappa[4] & 31;
            K_[8 * i + 3] = kappa[6] & 31;
            K_[8 * i + 4] = kappa[7];
            K_[8 * i + 5] = kappa[5];
            K_[8 * i + 6] = kappa[3];
            K_[8 * i + 7] = kappa[1];
        }
    }

    void encrypt(const uint8_t in[16], uint8_t out[16]) const override {
        word32 blk[4] = {loadBE(in), loadBE(in + 4), loadBE(in + 8), loadBE(in + 12)};
        for (int i = 0; i < 6; i++) {          // six forward quad rounds
            F1(blk[2], blk[3], 8 * i + 4);
            F2(blk[1], blk[2], 8 * i + 5);
            F3(blk[0], blk[1], 8 * i + 6);
            F1(blk[3], blk[0], 8 * i + 7);
        }
        for (int i = 6; i < 12; i++) {         // six reverse quad rounds
            F1(blk[3], blk[0], 8 * i + 7);
            F3(blk[0], blk[1], 8 * i + 6);
            F2(blk[1], blk[2], 8 * i + 5);
            F1(blk[2], blk[3], 8 * i + 4);
        }
        for (int i = 0; i < 4; i++) storeBE(out + 4 * i, blk[i]);
    }

private:
    static const word32* S(int box) { return cryfs_legacy_tables::kCastS + 256 * box; }
    static word32 tm(int j, int i) { return 0x5a827999u + (word32)(i * 8 + j) * 0x6ed9eba1u; }
    static unsigned tr(int j, int i) { return (unsigned)(19 + (i * 8 + j) * 17) & 31; }
    static void f1(word32& l, word32 r, word32 km, unsigned kr) {
        word32 t = rotl(km + r, kr);
        l ^= ((S(0)[t >> 24] ^ S(1)[(t >> 16) & 255]) - S(2)[(t >> 8) & 255]) + S(3)[t & 255];
    }
    static void f2(word32& l, word32 r, word32 km, unsigned kr) {
        word32 t = rotl(km ^ r, kr);
        l ^= ((S(0)[t >> 24] - S(1)[(t >> 16) & 255]) + S(2)[(t >> 8) & 255]) ^ S(3)[t & 255];
    }
    static void f3(word32& l, word32 r, word32 km, unsigned kr) {
        word32 t = rotl(km - r, kr);
        l ^= ((S(0)[t >> 24] + S(1)[(t >> 16) & 255]) ^ S(2)[(t >> 8) & 255]) - S(3)[t & 255];
    }
    static void omega(int i, word32 kappa[8]) {
        f1(kappa[6], kappa[7], tm(0, i), tr(0, i));
        f2(kappa[5], kappa[6], tm(1, i), tr(1, i));
        f3(kappa[4], kappa[5], tm(2, i), tr(2, i));
        f1(kappa[3], kappa[4], tm(3, i), tr(3, i));
        f2(kappa[2], kappa[3], tm(4, i), tr(4, i));
        f3(kappa[1], kappa[2], tm(5, i), tr(5, i));
        f1(kappa[0], kappa[1], tm(6, i), tr(6, i));
        f2(kappa[7], kappa[0], tm(7, i), tr(7, i));
    }
    void F1(word32& l, word32 r, int i) const { f1(l, r, K_[i], K_[i - 4]); }
    void F2(word32& l, word32 r, int i) const { f2(l, r, K_[i], K_[i - 4]); }
    void F3(word32& l, word32 r, int i) const { f3(l, r, K_[i], K_[i - 4]); }

    word32 K_[96];
};

// --------------------------------------------------------------------------------------------------- MARS
class Mars final : public Block128 {
public:
    Mars(const uint8_t* userKey, size_t keyLen) {
        word32 T[15];
        userKeyLE(T, 15, userKey, keyLen);
        T[keyLen / 4] = (word32)(keyLen / 4);
        for (unsigned j = 0; j < 4; j++) {          // compute 10 words of K[] in each iteration
            for (unsigned i = 0; i < 15; i++) T[i] = T[i] ^ rotlConstant<3>(T[(i + 8) % 15] ^ T[(i + 13) % 15]) ^ (4 * i + j);
            for (unsigned k = 0; k < 4; k++)       // four rounds of stirring
                for (unsigned i = 0; i < 15; i++) T[i] = rotlConstant<9>(T[i] + Sbox()[T[(i + 14) % 15] % 512]);
            for (unsigned i = 0; i < 10; i++) k_[10 * j + i] = T[4 * i % 15];
        }
        for (unsigned i = 5; i < 37; i += 2) {      // modify the multiplication key words
            word32 m, w = k_[i] | 3;
            m = (~w ^ (w << 1)) & (~w ^ (w >> 1)) & 0x7ffffffe;
            m &= m >> 1; m &= m >> 2; m &= m >> 4;
            m |= m << 1; m |= m << 2; m |= m << 4;
            m &= 0x7ffffffc;
            w ^= rotl(Sbox()[265 + (k_[i] & 3)], k_[i - 1]) & m;
            k_[i] = w;
        }
    }

    void encrypt(const uint8_t in[16], uint8_t out[16]) const override {
        word32 a = loadLE(in), b = loadLE(in + 4), c = loadLE(in + 8), d = loadLE(in + 12), l, m, r, t;
        const word32* k = k_;
        a += k[0]; b += k[1]; c += k[2]; d += k[3];
        for (unsigned i = 0; i < 8; i++) {           // forward mixing
            b = (b ^ S0(a)) + S1(a >> 8);
            c += S0(a >> 16);
            a = rotr(a, 24);
            d ^= S1(a);
            a += (i % 4 == 0) ? d : 0;
            a += (i % 4 == 1) ? b : 0;
            t = a; a = b; b = c; c = d; d = t;
        }
        for (unsigned i = 0; i < 16; i++) {          // keyed transformation
            t = rotl(a, 13);
            r = rotl(t * k[2 * i + 5], 10);
            m = a + k[2 * i + 4];
            l = rotl(S9(m) ^ rotr(r, 5) ^ r, r);
            c += rotl(m, rotr(r, 5));
            if (i < 8) { b += l; d ^= r; } else { d += l; b ^= r; }
            a = b; b = c; c = d; d = t;
        }
        for (unsigned i = 0; i < 8; i++) {           // backwards mixing
            a -= (i % 4 == 2) ? d : 0;
            a -= (i % 4 == 3) ? b : 0;
            b ^= S1(a);
            c -= S0(a >> 24);
            t = rotl(a, 24);
            d = (d - S1(a >> 16)) ^ S0(t);
            a = b; b = c; c = d; d = t;
        }
        a -= k[36]; b -= k[37]; c -= k[38]; d -= k[39];
        storeLE(out, a); storeLE(out + 4, b); storeLE(out + 8, c); storeLE(out + 12, d);
    }

private:
    static const word32* Sbox() { return cryfs_legacy_tables::kMarsS; }
    static word32 S0(word32 a) { return Sbox()[a & 0xff]; }
    static word32 S1(word32 a) { return Sbox()[(a & 0xff) + 256]; }
    static word32 S9(word32 a) { return Sbox()[a & 0x1ff]; }
    word32 k_[40];
};

// ------------------------------------------------------------------------------------------- GCM / CFB
// Multiplication in GF(2^128) as in NIST SP 800-38D (bit-serial; branch-free).
struct Ghash {
    word64 hh, hl;
    explicit Ghash(const uint8_t h[16]) {
        hh = ((word64)loadBE(h) << 32) | loadBE(h + 4);
        hl = ((word64)loadBE(h + 8) << 32) | loadBE(h + 12);
    }
    // y = (y ^ block) * H
    void update(word64& yh, word64& yl, const uint8_t block[16]) const {
        const word64 xh = yh ^ (((word64)loadBE(block) << 32) | loadBE(block + 4));
        const word64 xl = yl ^ (((word64)loadBE(block + 8) << 32) | loadBE(block + 12));
        word64 vh = hh, vl = hl, zh = 0, zl = 0;
        for (int i = 0; i < 128; i++) {
            const word64 bit = i < 64 ? (xh >> (63 - i)) & 1 : (xl >> (127 - i)) & 1;
            const word64 mask = 0 - bit;
            zh ^= vh & mask;
            zl ^= vl & mask;
            const word64 lsb = vl & 1;
            vl = (vh << 63) | (vl >> 1);
            vh = (vh >> 1) ^ (0xE100000000000000ULL & (0 - lsb));
        }
        yh = zh; yl = zl;
    }
};

void putBE64(uint8_t* p, word64 v) { storeBE(p, (word32)(v >> 32)); storeBE(p + 4, (word32)v); }

void ghashBlocks(const Ghash& g, word64& yh, word64& yl, const uint8_t* data, size_t n) {
    uint8_t blk[16];
    while (n >= 16) { g.update(yh, yl, data); data += 16; n -= 16; }
    if (n) { std::memset(blk, 0, 16); std::memcpy(blk, data, n); g.update(yh, yl, blk); }
}

void inc32(uint8_t ctr[16]) { for (int i = 15; i >= 12; i--) if (++ctr[i] != 0) break; }

// J0 for a 16-byte IV: GHASH(IV || 0^64 || [128]_64)
void gcmJ0(const Ghash& g, const uint8_t iv[16], uint8_t j0[16]) {
    word64 yh = 0, yl = 0;
    g.update(yh, yl, iv);
    uint8_t lenBlock[16] = {0};
    putBE64(lenBlock + 8, 128);
    g.update(yh, yl, lenBlock);
    putBE64(j0, yh); putBE64(j0 + 8, yl);
}

void gcmCtr(const Block128& bc, const uint8_t j0[16], const uint8_t* in, size_t n, uint8_t* out) {
    uint8_t ctr[16], ks[16];
    std::memcpy(ctr, j0, 16);
    for (size_t off = 0; off < n; off += 16) {
        inc32(ctr);
        bc.encrypt(ctr, ks);
        const size_t m = n - off < 16 ? n - off : 16;
        for (size_t i = 0; i < m; i++) out[off + i] = in[off + i] ^ ks[i];
    }
}

void gcmTag(const Block128& bc, const Ghash& g, const uint8_t j0[16], const uint8_t* cipher, size_t n, uint8_t tag[16]) {
    word64 yh = 0, yl = 0;
    ghashBlocks(g, yh, yl, cipher, n);
    uint8_t lenBlock[16] = {0};                      // len(A) = 0 bits || len(C) in bits
    putBE64(lenBlock + 8, (word64)n * 8);
    g.update(yh, yl, lenBlock);
    uint8_t s[16], ek[16];
    putBE64(s, yh); putBE64(s + 8, yl);
    bc.encrypt(j0, ek);
    for (int i = 0; i < 16; i++) tag[i] = s[i] ^ ek[i];
}

}  // namespace

// ------------------------------------------------------------------------------------------------ public
namespace {
const Spec kSpecs[kSpecCount] = {
    {"twofish-256-gcm", Algo::Twofish, Mode::Gcm, 32}, {"twofish-256-cfb", Algo::Twofish, Mode::Cfb, 32},
    {"twofish-128-gcm", Algo::Twofish, Mode::Gcm, 16}, {"twofish-128-cfb", Algo::Twofish, Mode::Cfb, 16},
    {"serpent-256-gcm", Algo::Serpent, Mode::Gcm, 32}, {"serpent-256-cfb", Algo::Serpent, Mode::Cfb, 32},
    {"serpent-128-gcm", Algo::Serpent, Mode::Gcm, 16}, {"serpent-128-cfb", Algo::Serpent, Mode::Cfb, 16},
    {"cast-256-gcm", Algo::Cast256, Mode::Gcm, 32},    {"cast-256-cfb", Algo::Cast256, Mode::Cfb, 32},
    {"mars-256-gcm", Algo::Mars, Mode::Gcm, 32},       {"mars-256-cfb", Algo::Mars, Mode::Cfb, 32},
    {"mars-448-gcm", Algo::Mars, Mode::Gcm, 56},       {"mars-448-cfb", Algo::Mars, Mode::Cfb, 56},
    {"mars-128-gcm", Algo::Mars, Mode::Gcm, 16},       {"mars-128-cfb", Algo::Mars, Mode::Cfb, 16},
};
}  // namespace

const Spec& spec(size_t index) { return kSpecs[index]; }

int findSpecIndex(const char* name) {
    if (!name) return -1;
    for (size_t i = 0; i < kSpecCount; i++) if (std::strcmp(kSpecs[i].name, name) == 0) return (int)i;
    return -1;
}

std::unique_ptr<Block128> makeBlockCipher(Algo algo, const uint8_t* key, size_t keyLen) {
    switch (algo) {
        case Algo::Twofish: if (keyLen != 16 && keyLen != 24 && keyLen != 32) return nullptr; return std::make_unique<Twofish>(key, keyLen);
        case Algo::Serpent: if (keyLen != 16 && keyLen != 24 && keyLen != 32) return nullptr; return std::make_unique<Serpent>(key, keyLen);
        case Algo::Cast256: if (keyLen < 16 || keyLen > 32 || keyLen % 4 != 0) return nullptr; return std::make_unique<Cast256>(key, keyLen);
        case Algo::Mars:    if (keyLen < 16 || keyLen > 56 || keyLen % 8 != 0) return nullptr; return std::make_unique<Mars>(key, keyLen);
    }
    return nullptr;
}

void gcmSeal(const Block128& bc, const uint8_t iv[16], const uint8_t* plain, size_t n, uint8_t* out) {
    uint8_t h[16] = {0};
    bc.encrypt(h, h);
    Ghash g(h);
    uint8_t j0[16];
    gcmJ0(g, iv, j0);
    gcmCtr(bc, j0, plain, n, out);
    gcmTag(bc, g, j0, out, n, out + n);
}

bool gcmOpen(const Block128& bc, const uint8_t iv[16], const uint8_t* cipher, size_t n, const uint8_t tag[16], uint8_t* out) {
    uint8_t h[16] = {0};
    bc.encrypt(h, h);
    Ghash g(h);
    uint8_t j0[16], expect[16];
    gcmJ0(g, iv, j0);
    gcmTag(bc, g, j0, cipher, n, expect);
    uint8_t diff = 0;
    for (int i = 0; i < 16; i++) diff |= (uint8_t)(expect[i] ^ tag[i]);
    if (diff != 0) return false;
    gcmCtr(bc, j0, cipher, n, out);
    return true;
}

void cfbCrypt(const Block128& bc, bool encrypt, const uint8_t iv[16], const uint8_t* in, size_t n, uint8_t* out) {
    uint8_t reg[16], ks[16], next[16];
    std::memcpy(reg, iv, 16);
    for (size_t off = 0; off < n; off += 16) {
        bc.encrypt(reg, ks);
        const size_t m = n - off < 16 ? n - off : 16;
        for (size_t i = 0; i < m; i++) {
            const uint8_t inByte = in[off + i];
            const uint8_t outByte = inByte ^ ks[i];
            out[off + i] = outByte;
            next[i] = encrypt ? outByte : inByte;      // the ciphertext byte feeds the next block
        }
        if (m == 16) std::memcpy(reg, next, 16);
    }
}

}  // namespace cryfs_legacy
