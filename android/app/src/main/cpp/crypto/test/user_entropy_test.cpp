// Host-side test for crypto/user_entropy (needs mbedtls, no Android toolchain):
// built and run by the "Native host-side tests" CMake target user_entropy_test.
//
// The known-answer vectors were generated independently with Python's hashlib
// from the construction documented in user_entropy.h:
//   seed    = SHA-512("VaultExplorer/user-entropy/v1" || u32be(len) || input)
//   block_i = SHA-512(seed || u64be(i))
// util/UserEntropy.kt's unit test checks the SAME vectors, which is what keeps
// the native and JVM mixers interchangeable.
#include "../user_entropy.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#define CHECK(cond)                                                              \
    do {                                                                         \
        if (!(cond)) {                                                           \
            std::fprintf(stderr, "CHECK failed at %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            std::exit(1);                                                        \
        }                                                                        \
    } while (0)

static std::string hex(const uint8_t* p, size_t n) {
    static const char* d = "0123456789abcdef";
    std::string s;
    for (size_t i = 0; i < n; ++i) {
        s.push_back(d[p[i] >> 4]);
        s.push_back(d[p[i] & 15]);
    }
    return s;
}

static std::vector<uint8_t> bytes(const char* s) {
    return std::vector<uint8_t>(s, s + std::strlen(s));
}

static std::vector<uint8_t> sequence256() {
    std::vector<uint8_t> v(256);
    for (int i = 0; i < 256; ++i) v[i] = static_cast<uint8_t>(i);
    return v;
}

// Reads `n` keystream bytes from the active Scope (XOR into zeros).
static std::vector<uint8_t> stream(size_t n) {
    std::vector<uint8_t> v(n, 0);
    CHECK(userentropy::applyKeystream(v.data(), v.size()));
    return v;
}

int main() {
    using namespace userentropy;

    // ── Known answers ────────────────────────────────────────────────────
    {
        const auto abc = bytes("abc");
        uint8_t seed[kSeedSize], b0[kBlockSize], b1[kBlockSize];
        CHECK(deriveSeed(abc.data(), abc.size(), seed));
        CHECK(hex(seed, sizeof(seed)) ==
              "7c00470b61007d223a813096dc10d2de10072461f61bc31ea5d52636c02f47d3"
              "c956ee84b68d7ed20996d2f1444520b80e7fd8880674f782df3bcf7ea0eb5fcf");
        CHECK(keystreamBlock(seed, 0, b0));
        CHECK(hex(b0, sizeof(b0)) ==
              "4d82b192197f6acf18b25fb7a614234cccba32f491980a5b5e557c754c070f00"
              "55b7ea618fa08a4522dfa3eb8cb475ea7cbaea174958d99734218f46b1c5751e");
        CHECK(keystreamBlock(seed, 1, b1));
        CHECK(hex(b1, sizeof(b1)) ==
              "3db069c51204be1e6422515dd2e7e32b39c05ca232de6486a18a3d2f732fd784"
              "58cf3a26b06df3909e0f32deff55a69bdb7e65a9ed0b45f31df5fa87d208509d");
    }
    {
        const auto seq = sequence256();
        uint8_t seed[kSeedSize], b0[kBlockSize];
        CHECK(deriveSeed(seq.data(), seq.size(), seed));
        CHECK(hex(seed, sizeof(seed)) ==
              "e99bd0d71f96e5fbf1b9cfdd3b56d52fb375e9644f2877f56f45d0fc247d6377"
              "9733403eccc7ca1960b2ef0df07493e638ca31d5980a8818bc29b9bf4fac2cf8");
        CHECK(keystreamBlock(seed, 0, b0));
        CHECK(hex(b0, sizeof(b0)) ==
              "f829110957796a853df92a16f2a4230c86b2bacf8749487654f4fbf263eeff04"
              "e9d47b03044dfbe1b1b37b2f4b81a229115f43618b071426614fa1a06c42ee56");
    }

    // ── No scope: nothing is mixed ───────────────────────────────────────
    {
        CHECK(!active());
        uint8_t buf[16] = {0};
        CHECK(applyKeystream(buf, sizeof(buf)));
        for (uint8_t b : buf) CHECK(b == 0);
    }

    // ── Scope XORs exactly the documented keystream ──────────────────────
    {
        const auto abc = bytes("abc");
        Scope scope(abc.data(), abc.size());
        CHECK(active());
        // 64 + 16 bytes spans block 0 and the start of block 1.
        const auto got = stream(80);
        CHECK(hex(got.data(), 64) ==
              "4d82b192197f6acf18b25fb7a614234cccba32f491980a5b5e557c754c070f00"
              "55b7ea618fa08a4522dfa3eb8cb475ea7cbaea174958d99734218f46b1c5751e");
        CHECK(hex(got.data() + 64, 16) == "3db069c51204be1e6422515dd2e7e32b");
    }
    CHECK(!active());  // destructor removed it

    // ── The stream is consumed sequentially and never reused ─────────────
    {
        const auto abc = bytes("abc");
        Scope scope(abc.data(), abc.size());
        const auto a = stream(48);
        const auto b = stream(48);  // crosses the 64-byte block boundary
        CHECK(a != b);
        Scope again(abc.data(), abc.size());  // nested: restarts from block 0
        const auto fromStart = stream(96);
        CHECK(std::vector<uint8_t>(fromStart.begin(), fromStart.begin() + 48) == a);
        CHECK(std::vector<uint8_t>(fromStart.begin() + 48, fromStart.end()) == b);
    }

    // ── Nested scopes restore the outer stream position exactly ──────────
    {
        const auto abc = bytes("abc");
        const auto seq = sequence256();

        std::vector<uint8_t> reference;  // what the outer scope alone yields
        {
            Scope s(abc.data(), abc.size());
            reference = stream(100);
        }

        Scope outer(abc.data(), abc.size());
        auto first = stream(30);
        std::vector<uint8_t> inner;
        {
            Scope s(seq.data(), seq.size());
            inner = stream(30);
        }
        auto second = stream(70);
        std::vector<uint8_t> combined = first;
        combined.insert(combined.end(), second.begin(), second.end());
        CHECK(combined == reference);   // outer stream unaffected by the inner scope
        CHECK(inner != first);          // different input -> different stream
    }
    CHECK(!active());

    // ── Empty / null input installs nothing, and keeps an outer scope ────
    {
        Scope none(nullptr, 0);
        CHECK(!active());
        uint8_t zero = 0;
        Scope empty(&zero, 0);
        CHECK(!active());

        const auto abc = bytes("abc");
        Scope outer(abc.data(), abc.size());
        {
            Scope noop(nullptr, 0);
            CHECK(active());  // the outer scope is still in force
        }
        CHECK(active());
    }

    // ── Different inputs give different streams; single-bit change too ───
    {
        auto x = bytes("abc");
        auto y = bytes("abd");
        std::vector<uint8_t> sx, sy;
        { Scope s(x.data(), x.size()); sx = stream(64); }
        { Scope s(y.data(), y.size()); sy = stream(64); }
        CHECK(sx != sy);
    }

    // ── Scope is per thread ──────────────────────────────────────────────
    {
        const auto abc = bytes("abc");
        Scope scope(abc.data(), abc.size());
        CHECK(active());
        bool otherThreadActive = true;
        std::thread t([&] { otherThreadActive = active(); });
        t.join();
        CHECK(!otherThreadActive);
    }

    // ── fillRandom: urandom + keystream ──────────────────────────────────
    {
        CHECK(fillRandom(nullptr, 0));
        uint8_t a[64], b[64];
        CHECK(fillRandom(a, sizeof(a)));
        CHECK(fillRandom(b, sizeof(b)));
        CHECK(std::memcmp(a, b, sizeof(a)) != 0);  // 2^-512 false-failure odds

        // With a scope the output is still random-looking and differs per call.
        const auto abc = bytes("abc");
        Scope scope(abc.data(), abc.size());
        uint8_t c[64], d[64];
        CHECK(fillRandom(c, sizeof(c)));
        CHECK(fillRandom(d, sizeof(d)));
        CHECK(std::memcmp(c, d, sizeof(c)) != 0);

        // Large request (LUKS anti-forensic material is ~250 KB).
        std::vector<uint8_t> big(256000, 0);
        CHECK(fillRandom(big.data(), big.size()));
        size_t zeros = 0;
        for (uint8_t v : big) zeros += (v == 0);
        CHECK(zeros < 2000);  // ~1000 expected for uniform bytes
    }

    std::puts("user_entropy_test: OK");
    return 0;
}
