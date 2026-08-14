// Host-side test, no Android toolchain required. From cpp/, all on one line:
//   g++ -std=c++17 -I. -pthread crypto/test/cryfs_block_cipher_test.cpp crypto/cryfs_block_cipher.cpp crypto/xchacha20poly1305.cpp -o cryfs_block_cipher_test -lmbedcrypto && ./cryfs_block_cipher_test
// (also wired into CMakeLists.txt's `if(NOT ANDROID)` host-test block,
// alongside kdf_table_test and friends, so `ctest` picks it up too.)
//
// Covers, for every cipher CryfsBlockCipher.kt can select:
//   - encrypt/decrypt round-trips the plaintext exactly
//   - two encryptions of the same plaintext never produce the same
//     ciphertext (i.e. the IV/nonce really is fresh per call -- this is
//     the property the randomBytes() rewrite in this file needs to hold)
//   - wrong key is rejected for every *authenticated* cipher
//   - tampering with any ciphertext byte is rejected for every
//     *authenticated* cipher
//   - CFB is pinned as the one exception to the above: it is legacy and
//     unauthenticated, so tampering must NOT be rejected (only comments
//     said this before; this test makes it a checked property)
// Plus: cryfsCipherIdFromName() name<->id mapping, cryfsBlockCleartextSize()
// bookkeeping, and a concurrency stress test of cryfsBlockEncrypt() itself,
// since CryFS calls it from a worker thread pool in production
// (CryfsDataTree.kt's sharedExecutor) and this file's RNG is now a single
// shared, mutex-guarded DRBG rather than one fopen() per call.
#include "../cryfs_block_cipher.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <thread>
#include <vector>

// Deliberately not CHECK(): CHECK() is compiled out under -DNDEBUG, which
// Release builds define -- and this file's very first CMake Release build
// did exactly that, silently dropping every check that only existed inside
// an CHECK() (ctest still reported "100% tests passed"). A test's checks
// must not depend on build configuration, so this always evaluates.
#define CHECK(cond) do { \
    if (!(cond)) { \
        std::fprintf(stderr, "CHECK FAILED at %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        std::abort(); \
    } \
} while (0)

namespace {

const CryfsCipherId kAllCiphers[] = {
    CryfsCipherId::kAes256Gcm,
    CryfsCipherId::kAes256Cfb,
    CryfsCipherId::kAes128Gcm,
    CryfsCipherId::kAes128Cfb,
    CryfsCipherId::kXChaCha20Poly1305,
};

bool isAuthenticated(CryfsCipherId c) {
    return c != CryfsCipherId::kAes256Cfb && c != CryfsCipherId::kAes128Cfb;
}

size_t keyLenFor(CryfsCipherId c) {
    switch (c) {
        case CryfsCipherId::kAes256Gcm:
        case CryfsCipherId::kAes256Cfb:
        case CryfsCipherId::kXChaCha20Poly1305:
            return 32;
        case CryfsCipherId::kAes128Gcm:
        case CryfsCipherId::kAes128Cfb:
            return 16;
        default:
            return 0;
    }
}

std::vector<uint8_t> fixedBytes(size_t n, uint8_t seed) {
    std::vector<uint8_t> v(n);
    for (size_t i = 0; i < n; i++) v[i] = static_cast<uint8_t>(seed + i);
    return v;
}

void expectRoundTrip(CryfsCipherId cipher, const char* label) {
    const auto key = fixedBytes(keyLenFor(cipher), 0x11);
    const auto plaintext = fixedBytes(137, 0x42); // deliberately not block-aligned

    const auto ciphertext = cryfsBlockEncrypt(cipher, key.data(), key.size(),
                                               plaintext.data(), plaintext.size());
    CHECK(!ciphertext.empty() && "encrypt returned empty (failure sentinel)");

    std::vector<uint8_t> decrypted;
    const bool ok = cryfsBlockDecrypt(cipher, key.data(), key.size(),
                                       ciphertext.data(), ciphertext.size(), decrypted);
    CHECK(ok && "decrypt of freshly-encrypted ciphertext failed");
    CHECK(decrypted == plaintext && "round-trip did not reproduce the plaintext");

    const long clearSize = cryfsBlockCleartextSize(cipher, ciphertext.size());
    CHECK(clearSize >= 0 && static_cast<size_t>(clearSize) == plaintext.size() &&
           "cryfsBlockCleartextSize disagrees with the actual round-trip size");

    printf("  [ok] %s: round-trip (%zu -> %zu -> %zu bytes)\n",
           label, plaintext.size(), ciphertext.size(), decrypted.size());
}

void expectFreshIvPerCall(CryfsCipherId cipher, const char* label) {
    const auto key = fixedBytes(keyLenFor(cipher), 0x22);
    const auto plaintext = fixedBytes(64, 0x99);

    const auto c1 = cryfsBlockEncrypt(cipher, key.data(), key.size(), plaintext.data(), plaintext.size());
    const auto c2 = cryfsBlockEncrypt(cipher, key.data(), key.size(), plaintext.data(), plaintext.size());
    CHECK(!c1.empty() && !c2.empty());
    CHECK(c1 != c2 && "same plaintext+key produced identical ciphertext twice -- IV/nonce reuse");
    // First 16 (AES ciphers) or 24 (XChaCha20) bytes are the IV/nonce itself;
    // confirm those differ too, not just the (already-guaranteed-different,
    // for GCM/CFB) rest of the buffer.
    const size_t ivLen = (cipher == CryfsCipherId::kXChaCha20Poly1305) ? 24 : 16;
    CHECK(!std::equal(c1.begin(), c1.begin() + ivLen, c2.begin()) &&
           "IV/nonce prefix identical across two encrypt calls");

    printf("  [ok] %s: IV/nonce differs across repeated encrypts of identical input\n", label);
}

void expectWrongKeyRejected(CryfsCipherId cipher, const char* label) {
    const auto key = fixedBytes(keyLenFor(cipher), 0x33);
    auto wrongKey = key;
    wrongKey[0] ^= 0xFF;
    const auto plaintext = fixedBytes(50, 0x77);

    const auto ciphertext = cryfsBlockEncrypt(cipher, key.data(), key.size(), plaintext.data(), plaintext.size());
    std::vector<uint8_t> decrypted;
    const bool ok = cryfsBlockDecrypt(cipher, wrongKey.data(), wrongKey.size(),
                                       ciphertext.data(), ciphertext.size(), decrypted);
    CHECK(!ok && "decrypt succeeded with the wrong key");
    CHECK(decrypted.empty() && "rejected decrypt left data in the output buffer");

    printf("  [ok] %s: wrong key is rejected\n", label);
}

void expectTamperRejected(CryfsCipherId cipher, const char* label) {
    const auto key = fixedBytes(keyLenFor(cipher), 0x44);
    const auto plaintext = fixedBytes(80, 0x55);
    auto ciphertext = cryfsBlockEncrypt(cipher, key.data(), key.size(), plaintext.data(), plaintext.size());
    ciphertext.back() ^= 0x01; // flip one bit near the end (inside the tag, for authenticated ciphers)

    std::vector<uint8_t> decrypted;
    const bool ok = cryfsBlockDecrypt(cipher, key.data(), key.size(),
                                       ciphertext.data(), ciphertext.size(), decrypted);

    if (isAuthenticated(cipher)) {
        CHECK(!ok && "tampered ciphertext was accepted by an authenticated cipher");
        CHECK(decrypted.empty());
        printf("  [ok] %s: tampered ciphertext is rejected (authenticated)\n", label);
    } else {
        // CFB is legacy and unauthenticated by design (see the comment on
        // isCfb's callers in cryfs_block_cipher.cpp) -- decrypt "succeeds"
        // and just hands back corrupted plaintext. Pinning this so it's a
        // documented, checked property rather than only a comment.
        CHECK(ok && "CFB decrypt unexpectedly rejected tampered input");
        CHECK(decrypted != plaintext && "tampering had no effect on CFB output");
        printf("  [ok] %s: tampered ciphertext is silently accepted (unauthenticated, as documented)\n", label);
    }
}

void expectUnknownCipherRejected() {
    const auto key = fixedBytes(32, 0x66);
    const auto plaintext = fixedBytes(10, 0x88);
    const auto ciphertext = cryfsBlockEncrypt(CryfsCipherId::kUnknown, key.data(), key.size(),
                                               plaintext.data(), plaintext.size());
    CHECK(ciphertext.empty() && "kUnknown cipher should refuse to encrypt");

    std::vector<uint8_t> decrypted;
    const bool ok = cryfsBlockDecrypt(CryfsCipherId::kUnknown, key.data(), key.size(),
                                       plaintext.data(), plaintext.size(), decrypted);
    CHECK(!ok);
    CHECK(cryfsBlockCleartextSize(CryfsCipherId::kUnknown, 100) == -1);

    printf("  [ok] kUnknown: encrypt/decrypt/size all refuse cleanly\n");
}

void expectNameMapping() {
    CHECK(cryfsCipherIdFromName("aes-256-gcm") == CryfsCipherId::kAes256Gcm);
    CHECK(cryfsCipherIdFromName("aes-256-cfb") == CryfsCipherId::kAes256Cfb);
    CHECK(cryfsCipherIdFromName("aes-128-gcm") == CryfsCipherId::kAes128Gcm);
    CHECK(cryfsCipherIdFromName("aes-128-cfb") == CryfsCipherId::kAes128Cfb);
    CHECK(cryfsCipherIdFromName("xchacha20-poly1305") == CryfsCipherId::kXChaCha20Poly1305);
    CHECK(cryfsCipherIdFromName("not-a-real-cipher") == CryfsCipherId::kUnknown);
    CHECK(cryfsCipherIdFromName(nullptr) == CryfsCipherId::kUnknown);
    printf("  [ok] cryfsCipherIdFromName: known names map correctly, unknown/null map to kUnknown\n");
}

// Mirrors the real call pattern: CryfsDataTree.kt's sharedExecutor runs
// several block writes (-> cryfsBlockEncrypt) concurrently. This is the
// test that actually exercises the mutex added around the shared DRBG in
// this file's randomBytes() -- run under `-fsanitize=thread` for the
// strongest signal, but even without TSan a corrupted/hung run here would
// indicate the locking is wrong.
void expectConcurrentEncryptIsSafe() {
    constexpr int kThreads = 8;
    constexpr int kEncryptsPerThread = 250;
    const auto key = fixedBytes(32, 0xAB);

    std::vector<std::thread> threads;
    std::vector<std::vector<std::vector<uint8_t>>> results(kThreads);

    for (int t = 0; t < kThreads; t++) {
        threads.emplace_back([&, t]() {
            std::vector<uint8_t> plaintext = fixedBytes(32 * 1024, static_cast<uint8_t>(t));
            for (int i = 0; i < kEncryptsPerThread; i++) {
                results[t].push_back(
                    cryfsBlockEncrypt(CryfsCipherId::kAes256Gcm, key.data(), key.size(),
                                       plaintext.data(), plaintext.size()));
            }
        });
    }
    for (auto& th : threads) th.join();

    // Every single encrypt must have succeeded and round-trip correctly, and
    // no two IVs across the whole run may collide.
    std::vector<std::vector<uint8_t>> allIvs;
    for (int t = 0; t < kThreads; t++) {
        std::vector<uint8_t> plaintext = fixedBytes(32 * 1024, static_cast<uint8_t>(t));
        for (const auto& ciphertext : results[t]) {
            CHECK(!ciphertext.empty());
            std::vector<uint8_t> decrypted;
            CHECK(cryfsBlockDecrypt(CryfsCipherId::kAes256Gcm, key.data(), key.size(),
                                      ciphertext.data(), ciphertext.size(), decrypted));
            CHECK(decrypted == plaintext);
            allIvs.emplace_back(ciphertext.begin(), ciphertext.begin() + 16);
        }
    }
    for (size_t i = 0; i < allIvs.size(); i++) {
        for (size_t j = i + 1; j < allIvs.size(); j++) {
            CHECK(allIvs[i] != allIvs[j] && "IV collision across concurrent encrypts");
        }
    }

    printf("  [ok] concurrency: %d threads x %d encrypts (%d total), all round-trip, zero IV collisions\n",
           kThreads, kEncryptsPerThread, kThreads * kEncryptsPerThread);
}

} // namespace

int main() {
    printf("cryfs_block_cipher_test:\n");

    for (CryfsCipherId c : kAllCiphers) {
        const char* label = nullptr;
        switch (c) {
            case CryfsCipherId::kAes256Gcm: label = "aes-256-gcm"; break;
            case CryfsCipherId::kAes256Cfb: label = "aes-256-cfb"; break;
            case CryfsCipherId::kAes128Gcm: label = "aes-128-gcm"; break;
            case CryfsCipherId::kAes128Cfb: label = "aes-128-cfb"; break;
            case CryfsCipherId::kXChaCha20Poly1305: label = "xchacha20-poly1305"; break;
            default: label = "?"; break;
        }
        expectRoundTrip(c, label);
        expectFreshIvPerCall(c, label);
        if (isAuthenticated(c)) {
            expectWrongKeyRejected(c, label);
        }
        expectTamperRejected(c, label);
    }

    expectUnknownCipherRejected();
    expectNameMapping();
    expectConcurrentEncryptIsSafe();

    printf("cryfs_block_cipher_test: all assertions passed\n");
    return 0;
}
