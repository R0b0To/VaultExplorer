// Host-side test for containers/vc_header_build.h. Needs the crypto sources, so
// it is not part of the stand-alone CMake test list; build it by hand, e.g. (see
// the harness notes in the fix README):
//   g++ -std=c++17 -I<cpp> -I<cpp>/crypto -I<VeraCrypt>/src/Crypto -I<VeraCrypt>/src/Crypto/Argon2/include \
//       vc_header_build_test.cpp crypto/{cascade,cipher_shim,kdf_table,user_entropy}.cpp \
//       <VeraCrypt Serpent,Twofish,Camellia,kuznyechik,Whirlpool,Streebog,blake2s,Argon2 objects> \
//       -lmbedcrypto -lcrypto -lpthread -o vc_header_build_test && ./vc_header_build_test
//
// Pins what upstream requires of every header we write: format version 5,
// minimum program version 0x010b, and a backup copy that is a SEPARATE
// encryption (fresh salt) of the same header -- never a byte-identical clone.
#include "../vc_header_build.h"
#include <cassert>
#include <cstdio>

// The app's real implementation lives in session_prepare.cpp (which drags in the
// whole Android/filesystem stack); this is the same few lines for the PBKDF2 PRFs.
bool deriveHeaderKey(HashId hash, const unsigned char* pw, size_t pwLen, const unsigned char* salt,
                     int clampedPim, unsigned char* out, size_t outLen, std::function<bool()> cancel) {
    if (hash == HashId::kArgon2id) return false;  // not exercised here (hundreds of MiB)
    return pbkdf2Hmac(hash, pw, pwLen, salt, VC_SALT_SIZE,
                      static_cast<unsigned int>(iterationsForHash(hash, clampedPim)), out, outLen, cancel);
}

static bool decryptBody(CascadeId c, HashId h, const unsigned char* pw, size_t pwLen, int pim,
                        const unsigned char* sector, unsigned char* bodyOut) {
    unsigned char hk[192] = {0};
    if (!deriveHeaderKey(h, pw, pwLen, sector, pim, hk, sizeof hk, nullptr)) return false;
    const CascadeSpec spec = cascadeSpecFor(c);
    CascadeContext ctx;
    if (!cascadeSetKeys(ctx, c, hk, spec.layerCount * 64)) return false;
    std::memcpy(bodyOut, sector + VC_SALT_SIZE, VC_HEADER_BODY_SIZE);
    for (int layer = 0; layer < spec.layerCount; layer++) {   // decryption order
        const XtsLayerKey& lk = ctx.layers[layer];
        unsigned char T[16] = {0};
        blockCipherEncryptBlock(lk.tweakKey, T, T);
        for (int blk = 0; blk < 28; blk++) {
            unsigned char* bp = bodyOut + blk * 16;
            unsigned char tmp[16];
            for (int j = 0; j < 16; j++) tmp[j] = bp[j] ^ T[j];
            blockCipherDecryptBlock(lk.dataKeyDec, tmp, tmp);
            for (int j = 0; j < 16; j++) bp[j] = tmp[j] ^ T[j];
            xtsMultiplyTweak(T);
        }
    }
    return true;
}

int main() {
    // preamble
    unsigned char b[VC_HEADER_BODY_SIZE] = {0};
    vcStampHeaderPreamble(b);
    assert(b[0] == 'V' && b[1] == 'E' && b[2] == 'R' && b[3] == 'A');
    assert(b[4] == 0x00 && b[5] == 0x05);   // header format version 5
    assert(b[6] == 0x01 && b[7] == 0x0b);   // minimum program version 0x010b

    const CascadeId ciphers[] = {CascadeId::kAes, CascadeId::kSerpent, CascadeId::kAesTwofishSerpent,
                                 CascadeId::kKuznyechikSerpentCamellia};
    const HashId hashes[] = {HashId::kSha512, HashId::kBlake2s256, HashId::kWhirlpool};
    const unsigned char pw[] = "correct horse battery staple";
    for (CascadeId c : ciphers) for (HashId h : hashes) {
        unsigned char body[VC_HEADER_BODY_SIZE];
        for (size_t i = 0; i < sizeof body; i++) body[i] = static_cast<unsigned char>(i * 31 + 7);
        vcStampHeaderPreamble(body);
        unsigned char s1[VC_FULL_HEADER_SIZE], s2[VC_FULL_HEADER_SIZE];
        assert(vcBuildFreshlySaltedHeaderSector(body, c, h, pw, sizeof(pw) - 1, 1, s1));
        assert(vcBuildFreshlySaltedHeaderSector(body, c, h, pw, sizeof(pw) - 1, 1, s2));
        // two builds of the SAME header must differ in salt and in ciphertext
        assert(std::memcmp(s1, s2, VC_SALT_SIZE) != 0);
        assert(std::memcmp(s1 + VC_SALT_SIZE, s2 + VC_SALT_SIZE, VC_HEADER_BODY_SIZE) != 0);
        // ... and each must decrypt back to the original plaintext under the password
        unsigned char d1[VC_HEADER_BODY_SIZE], d2[VC_HEADER_BODY_SIZE];
        assert(decryptBody(c, h, pw, sizeof(pw) - 1, 1, s1, d1) && std::memcmp(d1, body, sizeof body) == 0);
        assert(decryptBody(c, h, pw, sizeof(pw) - 1, 1, s2, d2) && std::memcmp(d2, body, sizeof body) == 0);
        // wrong password must not
        assert(decryptBody(c, h, reinterpret_cast<const unsigned char*>("wrong"), 5, 1, s1, d1) &&
               std::memcmp(d1, body, sizeof body) != 0);
    }
    printf("vc_header_build_test: all assertions passed\n");
    return 0;
}
