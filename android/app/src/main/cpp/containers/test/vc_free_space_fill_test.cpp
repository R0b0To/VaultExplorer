// Host-side test, no Android toolchain required:
//   g++ -std=c++17 -I containers/test/host_stubs -I . containers/test/vc_free_space_fill_test.cpp -o vc_free_space_fill_test
//
// Free space of a new full-format volume must decrypt to noise under the real
// data key. Stand-in crypto (containers/test/host_stubs/crypto): a keyed XOR
// stream, which is all that is needed to tell "same key" from "other key".
#include "containers/vc_free_space_fill.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {
bool g_rngFail = false;
uint32_t g_rngState = 99;
}

namespace userentropy {
bool fillRandom(uint8_t* buf, size_t len) {
    if (g_rngFail) return false;
    for (size_t i = 0; i < len; ++i) {
        g_rngState = g_rngState * 1664525u + 1013904223u;
        buf[i] = static_cast<uint8_t>(g_rngState >> 24);
    }
    return true;
}
}  // namespace userentropy

namespace {

constexpr int kKeyLen = 64;
constexpr uint8_t kUntouched = 0xEE;

struct Image {
    std::vector<unsigned char> bytes;
    std::vector<std::pair<uint64_t, size_t>> calls;
    explicit Image(size_t sectors) : bytes(sectors * 512, kUntouched) {}
    bool write(uint64_t off, const unsigned char* p, size_t n) {
        calls.emplace_back(off, n);
        if (off + n > bytes.size()) return false;
        std::memcpy(bytes.data() + off, p, n);
        return true;
    }
};

// Fraction of zero bytes after decrypting sectors [first, first+count) with `realKey`.
double zeroFractionUnderKey(const Image& img, const CascadeContext& real, uint64_t first, uint64_t count) {
    uint64_t zeros = 0, total = 0;
    unsigned char pt[512];
    for (uint64_t s = first; s < first + count; ++s) {
        cascadeDecryptSector(real, s, img.bytes.data() + s * 512, pt);
        for (int i = 0; i < 512; ++i) { zeros += (pt[i] == 0); ++total; }
    }
    return static_cast<double>(zeros) / static_cast<double>(total);
}

CascadeContext realKeyContext() {
    unsigned char realKey[kKeyLen];
    for (int i = 0; i < kKeyLen; ++i) realKey[i] = static_cast<unsigned char>(0x40 + i * 3);
    CascadeContext c;
    assert(cascadeSetKeys(c, CascadeId::kAes, realKey, kKeyLen));
    return c;
}

}  // namespace

// Exactly the range requested is written, in order, in batches (with a ragged tail).
static void testWritesExactlyTheRange() {
    Image img(1000);
    const uint64_t first = 10, count = 300;
    assert(vcfill::fillWithRandomizedKey(CascadeId::kAes, kKeyLen, first, count, 64,
                                         [&](uint64_t o, const unsigned char* p, size_t n) { return img.write(o, p, n); }));
    uint64_t expect = first * 512;
    for (auto& c : img.calls) { assert(c.first == expect); expect += c.second; assert(c.second <= 64 * 512); }
    assert(expect == (first + count) * 512);
    for (size_t i = 0; i < first * 512; ++i) assert(img.bytes[i] == kUntouched);
    for (size_t i = (first + count) * 512; i < img.bytes.size(); ++i) assert(img.bytes[i] == kUntouched);
}

// The property being fixed: under the volume's real key the fill is noise.
static void testFreeSpaceIsNoiseUnderTheRealKey() {
    Image img(400);
    assert(vcfill::fillWithRandomizedKey(CascadeId::kAes, kKeyLen, 0, 400, 256,
                                         [&](uint64_t o, const unsigned char* p, size_t n) { return img.write(o, p, n); }));
    const CascadeContext real = realKeyContext();
    const double z = zeroFractionUnderKey(img, real, 0, 400);
    assert(z < 0.02);   // random bytes are ~0.4% zero; "decrypts to zeros" would be 100%
}

// What the old code did, kept as a documented contrast: zeros encrypted with the
// real key decrypt to all zeros under that key.
static void testOldBehaviourWasDistinguishable() {
    const CascadeContext real = realKeyContext();
    unsigned char zero[512] = {0}, ct[512], pt[512];
    cascadeEncryptSector(real, 7, zero, ct);
    cascadeDecryptSector(real, 7, ct, pt);
    for (int i = 0; i < 512; ++i) assert(pt[i] == 0);
}

// Each run draws its own temporary key.
static void testEachFillUsesAFreshKey() {
    Image a(64), b(64);
    assert(vcfill::fillWithRandomizedKey(CascadeId::kAes, kKeyLen, 0, 64, 16,
                                         [&](uint64_t o, const unsigned char* p, size_t n) { return a.write(o, p, n); }));
    assert(vcfill::fillWithRandomizedKey(CascadeId::kAes, kKeyLen, 0, 64, 16,
                                         [&](uint64_t o, const unsigned char* p, size_t n) { return b.write(o, p, n); }));
    assert(a.bytes != b.bytes);
}

static void testFailuresPropagate() {
    Image img(64);
    auto sink = [&](uint64_t o, const unsigned char* p, size_t n) { return img.write(o, p, n); };
    assert(!vcfill::fillWithRandomizedKey(CascadeId::kAes, kKeyLen, 0, 64, 0, sink));     // bad batch size
    assert(!vcfill::fillWithRandomizedKey(CascadeId::kAes, 0, 0, 64, 16, sink));          // bad key length
    assert(!vcfill::fillWithRandomizedKey(CascadeId::kAes, 1024, 0, 64, 16, sink));       // key too long
    g_rngFail = true;
    assert(!vcfill::fillWithRandomizedKey(CascadeId::kAes, kKeyLen, 0, 64, 16, sink));    // no randomness
    g_rngFail = false;
    assert(!vcfill::fillWithRandomizedKey(CascadeId::kAes, kKeyLen, 60, 64, 16, sink));   // write past the end
    assert(vcfill::fillWithRandomizedKey(CascadeId::kAes, kKeyLen, 0, 0, 16, sink));      // empty range is fine
}

int main() {
    testWritesExactlyTheRange();
    testFreeSpaceIsNoiseUnderTheRealKey();
    testOldBehaviourWasDistinguishable();
    testEachFillUsesAFreshKey();
    testFailuresPropagate();
    std::puts("vc_free_space_fill_test: all passed");
    return 0;
}
