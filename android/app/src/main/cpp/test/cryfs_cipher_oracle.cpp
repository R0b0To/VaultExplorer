// Developer tool (not part of the app or CI): verifies crypto/cryfs_legacy_ciphers.cpp against Crypto++ 8.9.0, the
// library official CryFS 1.x used -- raw blocks, GCM with a 16-byte IV, and CFB-128, for every valid key length.
// Build (needs Crypto++ headers/library, e.g. Debian/Ubuntu "libcrypto++-dev"):
//   g++ -std=c++20 -O1 -I<cpp dir> test/cryfs_cipher_oracle.cpp crypto/cryfs_legacy_ciphers.cpp -lcryptopp -o oracle && ./oracle
#include <crypto++/twofish.h>
#include <crypto++/serpent.h>
#include <crypto++/cast.h>
#include <crypto++/mars.h>
#include <crypto++/modes.h>
#include <crypto++/gcm.h>
#include <crypto++/filters.h>
#include <random>
#include <cstdio>
#include "crypto/cryfs_legacy_ciphers.h"
using namespace CryptoPP;
using cryfs_legacy::Algo;
static int failures = 0, checks = 0;
#define CHECK(c, ...) do { checks++; if (!(c)) { failures++; if (failures < 25) { std::printf("FAIL line %d: %s ", __LINE__, #c); std::printf(__VA_ARGS__); std::printf("\n"); } } } while (0)
static std::mt19937 rng(12345);
static std::string rnd(size_t n) { std::string s(n, 0); for (auto& c : s) c = (char)rng(); return s; }

template <class BC> static std::string refBlock(const std::string& key, const std::string& in) {
    typename BC::Encryption e; e.SetKey((const byte*)key.data(), key.size());
    std::string out(16, 0); e.ProcessBlock((const byte*)in.data(), (byte*)&out[0]); return out;
}
template <class BC> static std::string refGcm(const std::string& key, const std::string& iv, const std::string& pt) {
    typename GCM<BC>::Encryption e; e.SetKeyWithIV((const byte*)key.data(), key.size(), (const byte*)iv.data(), iv.size());
    std::string out; AuthenticatedEncryptionFilter f(e, new StringSink(out), false, 16); f.Put((const byte*)pt.data(), pt.size()); f.MessageEnd(); return out;
}
template <class BC> static std::string refCfb(const std::string& key, const std::string& iv, const std::string& pt) {
    typename CFB_Mode<BC>::Encryption e((const byte*)key.data(), key.size(), (const byte*)iv.data());
    std::string out; StringSource(pt, true, new StreamTransformationFilter(e, new StringSink(out))); return out;
}
static std::string refBlockFor(Algo a, const std::string& k, const std::string& in) {
    switch (a) { case Algo::Twofish: return refBlock<Twofish>(k, in); case Algo::Serpent: return refBlock<Serpent>(k, in);
                 case Algo::Cast256: return refBlock<CAST256>(k, in); case Algo::Mars: return refBlock<MARS>(k, in); } return {};
}
static std::string refGcmFor(Algo a, const std::string& k, const std::string& iv, const std::string& pt) {
    switch (a) { case Algo::Twofish: return refGcm<Twofish>(k, iv, pt); case Algo::Serpent: return refGcm<Serpent>(k, iv, pt);
                 case Algo::Cast256: return refGcm<CAST256>(k, iv, pt); case Algo::Mars: return refGcm<MARS>(k, iv, pt); } return {};
}
static std::string refCfbFor(Algo a, const std::string& k, const std::string& iv, const std::string& pt) {
    switch (a) { case Algo::Twofish: return refCfb<Twofish>(k, iv, pt); case Algo::Serpent: return refCfb<Serpent>(k, iv, pt);
                 case Algo::Cast256: return refCfb<CAST256>(k, iv, pt); case Algo::Mars: return refCfb<MARS>(k, iv, pt); } return {};
}
static const char* nameOf(Algo a) { return a == Algo::Twofish ? "twofish" : a == Algo::Serpent ? "serpent" : a == Algo::Cast256 ? "cast256" : "mars"; }

int main() {
    struct Cfg { Algo a; std::vector<size_t> keys; };
    const Cfg cfgs[] = {{Algo::Twofish, {16, 24, 32}}, {Algo::Serpent, {16, 24, 32}}, {Algo::Cast256, {16, 20, 24, 28, 32}},
                        {Algo::Mars, {16, 24, 32, 40, 48, 56}}};
    for (auto& c : cfgs) {
        int before = failures;
        for (size_t kl : c.keys) for (int iter = 0; iter < 25; iter++) {
            std::string key = rnd(kl);
            auto bc = cryfs_legacy::makeBlockCipher(c.a, (const uint8_t*)key.data(), key.size());
            CHECK(bc != nullptr, "%s key %zu", nameOf(c.a), kl);
            if (!bc) continue;
            std::string in = rnd(16), out(16, 0);
            bc->encrypt((const uint8_t*)in.data(), (uint8_t*)&out[0]);
            CHECK(out == refBlockFor(c.a, key, in), "%s block, key %zu", nameOf(c.a), kl);
            std::string alias = in; bc->encrypt((const uint8_t*)alias.data(), (uint8_t*)&alias[0]);   // in == out is allowed
            CHECK(alias == out, "%s in-place", nameOf(c.a));
            for (size_t n : {0, 1, 15, 16, 17, 31, 32, 33, 100, 1000}) {
                std::string iv = rnd(16), pt = rnd(n);
                std::string g(n + 16, 0);
                cryfs_legacy::gcmSeal(*bc, (const uint8_t*)iv.data(), (const uint8_t*)pt.data(), n, (uint8_t*)&g[0]);
                CHECK(g == refGcmFor(c.a, key, iv, pt), "%s gcm key %zu n %zu", nameOf(c.a), kl, n);
                std::string back(n, 0);
                CHECK(cryfs_legacy::gcmOpen(*bc, (const uint8_t*)iv.data(), (const uint8_t*)g.data(), n, (const uint8_t*)g.data() + n, (uint8_t*)&back[0]) && back == pt, "%s gcm open", nameOf(c.a));
                std::string bad = g; if (!bad.empty()) bad[bad.size() / 2] ^= 1;
                std::string sink(n, 0);
                CHECK(n == 0 ? true : !cryfs_legacy::gcmOpen(*bc, (const uint8_t*)iv.data(), (const uint8_t*)bad.data(), n, (const uint8_t*)bad.data() + n, (uint8_t*)&sink[0]), "%s tamper", nameOf(c.a));
                std::string f(n, 0);
                cryfs_legacy::cfbCrypt(*bc, true, (const uint8_t*)iv.data(), (const uint8_t*)pt.data(), n, (uint8_t*)&f[0]);
                CHECK(f == refCfbFor(c.a, key, iv, pt), "%s cfb key %zu n %zu", nameOf(c.a), kl, n);
                std::string d(n, 0);
                cryfs_legacy::cfbCrypt(*bc, false, (const uint8_t*)iv.data(), (const uint8_t*)f.data(), n, (uint8_t*)&d[0]);
                CHECK(d == pt, "%s cfb decrypt", nameOf(c.a));
            }
        }
        std::printf("%-8s %s\n", nameOf(c.a), failures == before ? "OK" : "MISMATCH");
    }
    std::printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
