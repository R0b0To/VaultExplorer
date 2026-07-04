// crypto/keyfile_mixing.cpp
#include "keyfile_mixing.h"
#include "mbedtls/platform_util.h" // mbedtls_platform_zeroize
#include <unistd.h>
#include <algorithm>

// Same reflected CRC-32 (IEEE 802.3, polynomial 0xEDB88320) construction
// vaultexplorer.cpp's crc32() uses for header CRCs, run one byte at a time
// instead of table-driven. This is mathematically identical to the
// table-driven "UPDC32" macro upstream Crc.c defines — a CRC table entry
// IS the result of running this exact bit loop 8 times over
// (crc_low_byte XOR input_byte); doing it bit-by-bit here just trades a
// little speed for not needing to vendor Crc.c's precomputed table.
//
// Deliberately NOT XORed with 0xFFFFFFFF at the end: upstream keyfile
// mixing uses the raw running CRC register value directly as mixing
// entropy (KeyFileProcess: `crc = UPDC32(byte, crc);` immediately followed
// by using crc's individual bytes) — unlike a "report this as the file's
// checksum" use of CRC-32, there is no final inversion here.
static inline uint32_t crc32UpdateByte(uint32_t crc, unsigned char b) {
    crc ^= b;
    for (int i = 0; i < 8; i++)
        crc = (crc >> 1) ^ (0xEDB88320u & ~((crc & 1) - 1));
    return crc;
}

// Mirrors KeyFileProcess(): reads up to KEYFILE_MAX_READ_LEN bytes from
// [fd], maintaining its OWN fresh CRC state (starting at 0xFFFFFFFF, reset
// per keyfile call — this is deliberate; each keyfile's contribution uses
// an independent running CRC, only the additive writes into [keyPool] are
// shared/cumulative across keyfiles). Every byte read advances the CRC and
// adds 4 bytes (crc>>24, crc>>16, crc>>8, crc) into keyPool at a rotating
// position, wrapping at keyPoolSize.
static bool mixKeyfileIntoPool(int fd, unsigned char* keyPool, size_t keyPoolSize) {
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
            crc = crc32UpdateByte(crc, buffer[i]);

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

    // Upstream treats a keyfile that produced zero bytes as ERR_HANDLE_EOF
    // (a hard error, not a no-op) — an empty keyfile is almost certainly a
    // mistake (wrong file picked, truncated copy, ...) and silently
    // ignoring it would mean the derived key doesn't match what the user
    // expects, so we surface it the same way rather than mounting with a
    // silently-wrong key.
    return sawAnyByte;
}

bool applyKeyfilesToPassword(const int* keyfileFds, int keyfileCount,
                              unsigned char* password, size_t* passwordLen) {
    if (keyfileCount <= 0) return true;
    if (!keyfileFds || !password || !passwordLen) return false;

    // Pool size selection is based on the password length AS TYPED, before
    // any mixing — this matches upstream's (slightly quirky, but real)
    // behavior exactly.
    const size_t keyPoolSize = (*passwordLen <= MAX_LEGACY_PASSWORD)
        ? KEYFILE_POOL_LEGACY_SIZE : KEYFILE_POOL_SIZE;

    unsigned char keyPool[KEYFILE_POOL_SIZE] = {0};
    bool ok = true;

    // Every fd is consumed (read + closed) regardless of an earlier
    // failure, so callers never leak descriptors on a partial-failure path.
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

    // KeyFilesApply()'s final step: additively mix the pool into the
    // existing password bytes, then extend (never truncate) the password
    // with the remaining pool bytes if the pool is larger than it.
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
