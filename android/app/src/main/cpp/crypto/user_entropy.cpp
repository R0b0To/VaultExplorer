#include "user_entropy.h"
#include "os_random.h"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <vector>

#include "mbedtls/md.h"
#include "mbedtls/platform_util.h"

namespace userentropy {

namespace {

constexpr char kDomain[] = "VaultExplorer/user-entropy/v1";
constexpr size_t kDomainLen = sizeof(kDomain) - 1;  // no trailing NUL

// Per-thread keystream state. Trivially destructible on purpose: it holds key
// material, so it is wiped explicitly by Scope rather than left to a
// destructor that may not run for a thread_local on a detached JNI thread.
struct State {
    bool active;
    uint8_t seed[kSeedSize];
    uint64_t counter;           // index of the next keystream block to generate
    uint8_t block[kBlockSize];  // current keystream block
    size_t blockPos;            // bytes of `block` already consumed
};

State& state() {
    thread_local State s = {};
    return s;
}

void wipe(State& s) {
    mbedtls_platform_zeroize(&s, sizeof(s));
}

bool sha512Parts(const uint8_t* a, size_t aLen,
                 const uint8_t* b, size_t bLen,
                 const uint8_t* c, size_t cLen,
                 const uint8_t* d, size_t dLen,
                 uint8_t out[64]) {
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA512);
    if (!info) return false;
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    bool ok = mbedtls_md_setup(&ctx, info, 0) == 0 &&
              mbedtls_md_starts(&ctx) == 0 &&
              (aLen == 0 || mbedtls_md_update(&ctx, a, aLen) == 0) &&
              (bLen == 0 || mbedtls_md_update(&ctx, b, bLen) == 0) &&
              (cLen == 0 || mbedtls_md_update(&ctx, c, cLen) == 0) &&
              (dLen == 0 || mbedtls_md_update(&ctx, d, dLen) == 0) &&
              mbedtls_md_finish(&ctx, out) == 0;
    mbedtls_md_free(&ctx);
    return ok;
}

// Reads exactly `len` bytes from the OS CSPRNG (see crypto/os_random.h:
// /dev/urandom off Windows, BCryptGenRandom on it).
bool readUrandom(uint8_t* buf, size_t len) {
    return osRandomBytes(buf, len);
}

}  // namespace

struct Scope::Saved {
    State previous;
};

bool deriveSeed(const uint8_t* data, size_t len, uint8_t outSeed[kSeedSize]) {
    const uint8_t lenBe[4] = {
        static_cast<uint8_t>(len >> 24), static_cast<uint8_t>(len >> 16),
        static_cast<uint8_t>(len >> 8),  static_cast<uint8_t>(len),
    };
    return sha512Parts(reinterpret_cast<const uint8_t*>(kDomain), kDomainLen,
                       lenBe, sizeof(lenBe),
                       data, len,
                       nullptr, 0,
                       outSeed);
}

bool keystreamBlock(const uint8_t seed[kSeedSize], uint64_t counter, uint8_t outBlock[kBlockSize]) {
    uint8_t ctrBe[8];
    for (int i = 0; i < 8; ++i) {
        ctrBe[i] = static_cast<uint8_t>(counter >> (56 - 8 * i));
    }
    return sha512Parts(seed, kSeedSize, ctrBe, sizeof(ctrBe), nullptr, 0, nullptr, 0, outBlock);
}

Scope::Scope(const uint8_t* data, size_t len) : saved_(new Saved()) {
    State& s = state();
    std::memcpy(&saved_->previous, &s, sizeof(State));

    if (data == nullptr || len == 0) {
        // Nothing to add: leave whatever was installed (possibly nothing).
        return;
    }
    State fresh = {};
    if (!deriveSeed(data, len, fresh.seed)) {
        // SHA-512 unavailable (cannot happen with the bundled mbedtls). Fall
        // back to plain /dev/urandom rather than failing key generation.
        wipe(fresh);
        return;
    }
    fresh.active = true;
    fresh.counter = 0;
    fresh.blockPos = kBlockSize;  // forces generation of block 0 on first use
    std::memcpy(&s, &fresh, sizeof(State));
    wipe(fresh);
}

Scope::~Scope() {
    State& s = state();
    std::memcpy(&s, &saved_->previous, sizeof(State));
    wipe(saved_->previous);
    delete saved_;
}

bool active() {
    return state().active;
}

bool applyKeystream(uint8_t* buf, size_t len) {
    State& s = state();
    if (!s.active || len == 0) return true;
    if (buf == nullptr) return false;

    // Build the keystream for this request on local copies of the stream
    // position, and only commit it (and touch buf) once every block succeeded,
    // so a failure leaves both buf and the keystream exactly as they were.
    std::vector<uint8_t> ks(len);
    uint64_t counter = s.counter;
    uint8_t block[kBlockSize];
    std::memcpy(block, s.block, sizeof(block));
    size_t blockPos = s.blockPos;

    bool ok = true;
    for (size_t i = 0; i < len; ++i) {
        if (blockPos == kBlockSize) {
            if (!keystreamBlock(s.seed, counter, block)) {
                ok = false;
                break;
            }
            counter++;
            blockPos = 0;
        }
        ks[i] = block[blockPos++];
    }

    if (ok) {
        for (size_t i = 0; i < len; ++i) buf[i] ^= ks[i];
        s.counter = counter;
        std::memcpy(s.block, block, sizeof(block));
        s.blockPos = blockPos;
    }
    mbedtls_platform_zeroize(ks.data(), ks.size());
    mbedtls_platform_zeroize(block, sizeof(block));
    return ok;
}

bool fillRandom(uint8_t* buf, size_t len) {
    if (len == 0) return true;
    if (buf == nullptr) return false;
    if (!readUrandom(buf, len)) return false;
    if (!applyKeystream(buf, len)) {
        // Do not hand back output the caller believes is mixed when it is not.
        mbedtls_platform_zeroize(buf, len);
        return false;
    }
    return true;
}

}  // namespace userentropy
