// Developer tool: prints the Crypto++-produced known-answer table embedded in foldervault/test/fv_tests.cpp
// (testCryfsLegacyCiphers). Build like test/cryfs_cipher_oracle.cpp, run, and paste the output into the table.
#include <crypto++/twofish.h>
#include <crypto++/serpent.h>
#include <crypto++/cast.h>
#include <crypto++/mars.h>
#include <crypto++/modes.h>
#include <crypto++/gcm.h>
#include <crypto++/filters.h>
#include <cstdio>
#include "crypto/cryfs_legacy_ciphers.h"
using namespace CryptoPP;
using cryfs_legacy::Algo; using cryfs_legacy::Mode;
template <class BC> static std::string gcm(const std::string& k, const std::string& iv, const std::string& pt) {
    typename GCM<BC>::Encryption e; e.SetKeyWithIV((const byte*)k.data(), k.size(), (const byte*)iv.data(), iv.size());
    std::string o; AuthenticatedEncryptionFilter f(e, new StringSink(o), false, 16); f.Put((const byte*)pt.data(), pt.size()); f.MessageEnd(); return iv + o; }
template <class BC> static std::string cfb(const std::string& k, const std::string& iv, const std::string& pt) {
    typename CFB_Mode<BC>::Encryption e((const byte*)k.data(), k.size(), (const byte*)iv.data());
    std::string o; StringSource(pt, true, new StreamTransformationFilter(e, new StringSink(o))); return iv + o; }
static std::string hex(const std::string& s) { static const char* d = "0123456789abcdef"; std::string r; for (unsigned char c : s) { r += d[c >> 4]; r += d[c & 15]; } return r; }
int main() {
    for (size_t i = 0; i < cryfs_legacy::kSpecCount; i++) {
        const auto& sp = cryfs_legacy::spec(i);
        std::string k(sp.keyLen, 0), iv(16, 0), pt(37, 0);
        for (size_t j = 0; j < k.size(); j++) k[j] = (char)((j * 7 + 3) & 0xff);
        for (size_t j = 0; j < iv.size(); j++) iv[j] = (char)((j * 5 + 11) & 0xff);
        for (size_t j = 0; j < pt.size(); j++) pt[j] = (char)((j * 3 + 1) & 0xff);
        std::string out;
        bool g = sp.mode == Mode::Gcm;
        switch (sp.algo) {
            case Algo::Twofish: out = g ? gcm<Twofish>(k, iv, pt) : cfb<Twofish>(k, iv, pt); break;
            case Algo::Serpent: out = g ? gcm<Serpent>(k, iv, pt) : cfb<Serpent>(k, iv, pt); break;
            case Algo::Cast256: out = g ? gcm<CAST256>(k, iv, pt) : cfb<CAST256>(k, iv, pt); break;
            case Algo::Mars:    out = g ? gcm<MARS>(k, iv, pt) : cfb<MARS>(k, iv, pt); break;
        }
        std::printf("        {\"%s\", \"%s\",\n         \"%s\"},\n", sp.name, hex(k).c_str(), hex(out).c_str());
    }
}
