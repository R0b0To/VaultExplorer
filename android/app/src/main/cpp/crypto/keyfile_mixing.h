#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <unistd.h>
#include <algorithm>
#include "mbedtls/platform_util.h"

static constexpr size_t KEYFILE_POOL_LEGACY_SIZE = 64;
static constexpr size_t KEYFILE_POOL_SIZE        = 128;
static constexpr size_t KEYFILE_MAX_READ_LEN     = 1024 * 1024;


static constexpr size_t MAX_LEGACY_PASSWORD = 64;


static constexpr size_t MAX_PASSWORD_LEN = 128;

// RAII guard: zeroizes [buf, buf+len) when it goes out of scope, regardless
// of how the enclosing function returns. Used to scrub stack-resident
// password/key buffers after derivation. Shared by every caller that mixes
// keyfiles into a password (session_prepare.cpp) and by the standalone
// quick-unlock key export (deriveKeyMaterialNative in vaultexplorer.cpp).
struct ScopeZeroize {
    unsigned char* buf; size_t len;
    ScopeZeroize(unsigned char* b, size_t l) : buf(b), len(l) {}
    ~ScopeZeroize() { mbedtls_platform_zeroize(buf, len); }
    ScopeZeroize(const ScopeZeroize&) = delete;
    ScopeZeroize& operator=(const ScopeZeroize&) = delete;
};

// Closes every valid (>=0) fd in [keyfileFds]. applyKeyfilesToPassword()
// below already closes each fd itself as part of mixing, so this is only
// needed on early-exit paths that bail out *before* reaching that call —
// keeps the "every keyfile fd is closed exactly once" ownership contract
// (see VeraCryptEngine.kt's deriveKeyMaterialNative/unlockAndListNative
// doc comments) intact regardless of which path a caller takes.
static inline void closeUnusedKeyfileFds(const int* keyfileFds, int keyfileCount) {
    if (!keyfileFds) return;
    for (int i = 0; i < keyfileCount; i++) {
        if (keyfileFds[i] >= 0) close(keyfileFds[i]);
    }
}


// Table-driven (Sarwate) CRC32 step -- roughly 10-30x fewer operations per
// byte than the classic bit-loop it replaces, since it's now a single
// 256-entry lookup + XOR instead of 8 conditional shift/XOR iterations.
// Verified bit-for-bit identical to the original bit-loop this replaced
// (streaming equivalence checked across 70M+ random bytes plus a full
// transition sanity check -- see patches/crc32_equivalence_test.cpp) since
// this value feeds directly into keyfile-derived password material and
// must match exactly, not just "look like a CRC32".
static inline const uint32_t* vcKeyfileCrc32Table() {
    static const auto table = [] {
        std::array<uint32_t, 256> t{};
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int k = 0; k < 8; k++)
                c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            t[i] = c;
        }
        return t;
    }();
    return table.data();
}

static inline uint32_t vcKeyfileCrc32UpdateByte(uint32_t crc, unsigned char b) {
    return vcKeyfileCrc32Table()[(crc ^ b) & 0xFFu] ^ (crc >> 8);
}


static inline bool mixKeyfileIntoPool(int fd, unsigned char* keyPool, size_t keyPoolSize) {
    unsigned char buffer[64 * 1024];
    uint32_t crc = 0xFFFFFFFFu;
    uint32_t writePos = 0;
    size_t totalRead = 0;
    bool sawAnyByte = false;

    while (totalRead < KEYFILE_MAX_READ_LEN) {
        ssize_t n = read(fd, buffer, sizeof(buffer));
        if (n < 0) return false; // read error
        if (n == 0) break;       // EOF

        for (ssize_t i = 0; i < n; i++) {
            sawAnyByte = true;
            crc = vcKeyfileCrc32UpdateByte(crc, buffer[i]);

            keyPool[writePos] = static_cast<unsigned char>(keyPool[writePos] + ((crc >> 24) & 0xFF));
            writePos = (writePos + 1) % keyPoolSize;
            keyPool[writePos] = static_cast<unsigned char>(keyPool[writePos] + ((crc >> 16) & 0xFF));
            writePos = (writePos + 1) % keyPoolSize;
            keyPool[writePos] = static_cast<unsigned char>(keyPool[writePos] + ((crc >> 8) & 0xFF));
            writePos = (writePos + 1) % keyPoolSize;
            keyPool[writePos] = static_cast<unsigned char>(keyPool[writePos] + (crc & 0xFF));
            writePos = (writePos + 1) % keyPoolSize;

            if (++totalRead >= KEYFILE_MAX_READ_LEN) break;
        }
    }


    return sawAnyByte;
}


static inline bool applyKeyfilesToPassword(const int* keyfileFds, int keyfileCount,
                                            unsigned char* password, size_t* passwordLen) {
    if (keyfileCount <= 0) return true;
    if (!keyfileFds || !password || !passwordLen) return false;


    const size_t keyPoolSize = (*passwordLen <= MAX_LEGACY_PASSWORD)
        ? KEYFILE_POOL_LEGACY_SIZE : KEYFILE_POOL_SIZE;

    unsigned char keyPool[KEYFILE_POOL_SIZE] = {0};
    bool ok = true;

    for (int i = 0; i < keyfileCount; i++) {
        int fd = keyfileFds[i];
        if (fd < 0) { ok = false; continue; }
        if (!mixKeyfileIntoPool(fd, keyPool, keyPoolSize)) ok = false;
        close(fd);
    }

    if (!ok) {
        mbedtls_platform_zeroize(keyPool, sizeof(keyPool));
        return false;
    }


    const size_t applyLen = std::min(keyPoolSize, MAX_PASSWORD_LEN);
    for (size_t i = 0; i < applyLen; i++) {
        if (i < *passwordLen)
            password[i] = static_cast<unsigned char>(password[i] + keyPool[i]);
        else
            password[i] = keyPool[i];
    }
    if (*passwordLen < applyLen)
        *passwordLen = applyLen;

    mbedtls_platform_zeroize(keyPool, sizeof(keyPool));
    return true;
}