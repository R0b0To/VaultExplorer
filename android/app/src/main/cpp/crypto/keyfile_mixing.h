#pragma once
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


static inline uint32_t vcKeyfileCrc32UpdateByte(uint32_t crc, unsigned char b) {
    crc ^= b;
    for (int i = 0; i < 8; i++)
        crc = (crc >> 1) ^ (0xEDB88320u & ~((crc & 1) - 1));
    return crc;
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