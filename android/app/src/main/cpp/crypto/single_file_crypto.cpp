#include "crypto/single_file_crypto.h"
#include "crypto/cipher_shim.h"
#include "crypto/cascade.h"
#include "crypto/keyfile_mixing.h"
#include "crypto/xchacha20poly1305.h"
#include "mbedtls/gcm.h"
#include "mbedtls/md.h"
#include "mbedtls/platform_util.h"
#include <unistd.h>
#include <sys/stat.h>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <vector>

static constexpr size_t KDF_ITERATIONS = 100000;
static constexpr size_t CLEAR_CHUNK_SIZE = 64 * 1024; // 64 KB

static void hmacSha256(const unsigned char* key, size_t keyLen,
                        const unsigned char* input, size_t inputLen,
                        unsigned char outTag[32]) {
    const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_hmac(mdInfo, key, keyLen, input, inputLen, outTag);
}

bool encryptSingleFile(
    int srcFd,
    int destFd,
    int cipherIndex,
    const unsigned char* password,
    size_t passwordLen,
    const int* keyfileFds,
    int keyfileCount,
    int opId,
    std::function<bool()> cancelCheck,
    std::function<void(uint64_t bytesDone, uint64_t bytesTotal)> progressCallback
) {
    if (srcFd < 0 || destFd < 0) return false;

    unsigned char mixedPassword[128] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
    std::memcpy(mixedPassword, password, mixedPasswordLen);
    if (keyfileCount > 0 && keyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            return false;
        }
    }

    unsigned char salt[32];
    unsigned char fileId[16];
    FILE* urnd = fopen("/dev/urandom", "rb");
    if (!urnd) return false;
    bool ok = (fread(salt, 1, 32, urnd) == 32) && (fread(fileId, 1, 16, urnd) == 16);
    fclose(urnd);
    if (!ok) return false;

    struct stat st{};
    if (fstat(srcFd, &st) != 0) return false;
    uint64_t originalFileSize = static_cast<uint64_t>(st.st_size);

    unsigned char derivedKeyBuf[256] = {0};
    ScopeZeroize derivedKeyGuard(derivedKeyBuf, sizeof(derivedKeyBuf));

    if (!pbkdf2Hmac(HashId::kSha256, mixedPassword, mixedPasswordLen, salt, 32, KDF_ITERATIONS, derivedKeyBuf, sizeof(derivedKeyBuf), cancelCheck)) {
        return false;
    }

    const unsigned char* masterKey = derivedKeyBuf;          // 192 bytes
    const unsigned char* headerMacKey = derivedKeyBuf + 192; // 32 bytes
    const unsigned char* chunkMacKey = derivedKeyBuf + 224;  // 32 bytes

    // Build 128-byte Header
    unsigned char header[128] = {0};
    header[0] = 'V'; header[1] = 'X'; header[2] = 'E'; header[3] = 'N'; header[4] = 'C'; header[5] = 0x01;
    header[6] = static_cast<unsigned char>((cipherIndex >> 8) & 0xFF);
    header[7] = static_cast<unsigned char>(cipherIndex & 0xFF);
    header[8] = 0; header[9] = 0; // KDF_ID = 0 (PBKDF2-SHA256)
    header[10] = static_cast<unsigned char>((KDF_ITERATIONS >> 24) & 0xFF);
    header[11] = static_cast<unsigned char>((KDF_ITERATIONS >> 16) & 0xFF);
    header[12] = static_cast<unsigned char>((KDF_ITERATIONS >> 8) & 0xFF);
    header[13] = static_cast<unsigned char>(KDF_ITERATIONS & 0xFF);

    std::memcpy(header + 14, salt, 32);
    std::memcpy(header + 46, fileId, 16);

    for (int i = 0; i < 8; i++) {
        header[62 + i] = static_cast<unsigned char>((originalFileSize >> (56 - i * 8)) & 0xFF);
    }

    hmacSha256(headerMacKey, 32, header, 70, header + 70);

    if (pwrite(destFd, header, 128, 0) != 128) {
        return false;
    }

    CascadeContext cascadeCtx;
    if (cipherIndex >= 2) {
        CascadeId cascadeId = static_cast<CascadeId>(cipherIndex - 2);
        CascadeSpec spec = cascadeSpecFor(cascadeId);
        if (!cascadeSetKeys(cascadeCtx, cascadeId, masterKey, spec.layerCount * 64)) {
            return false;
        }
    }

    std::vector<unsigned char> clearBuf(CLEAR_CHUNK_SIZE);
    std::vector<unsigned char> encBuf(CLEAR_CHUNK_SIZE + 64);

    uint64_t bytesReadTotal = 0;
    uint64_t bytesWrittenTotal = 128;
    uint64_t chunkIndex = 0;

    if (progressCallback) progressCallback(0, originalFileSize);

    while (bytesReadTotal < originalFileSize) {
        if (cancelCheck && cancelCheck()) return false;

        size_t wantRead = static_cast<size_t>(std::min<uint64_t>(CLEAR_CHUNK_SIZE, originalFileSize - bytesReadTotal));
        ssize_t nRead = pread(srcFd, clearBuf.data(), wantRead, static_cast<off_t>(bytesReadTotal));
        if (nRead != static_cast<ssize_t>(wantRead)) return false;

        size_t encChunkLen = 0;
        if (cipherIndex == 0) {
            // XChaCha20-Poly1305
            unsigned char nonce[24] = {0};
            std::memcpy(nonce, fileId, 16);
            for (int b = 0; b < 8; b++) nonce[16 + b] = static_cast<unsigned char>((chunkIndex >> (56 - b * 8)) & 0xFF);

            unsigned char aad[24] = {0};
            std::memcpy(aad, fileId, 16);
            for (int b = 0; b < 8; b++) aad[16 + b] = static_cast<unsigned char>((chunkIndex >> (56 - b * 8)) & 0xFF);

            if (!xchacha20Poly1305Seal(masterKey, nonce, aad, 24, clearBuf.data(), nRead, encBuf.data())) {
                return false;
            }
            encChunkLen = nRead + 16;
        } else if (cipherIndex == 1) {
            // AES-256-GCM
            unsigned char iv[12] = {0};
            std::memcpy(iv, fileId, 8);
            for (int b = 0; b < 4; b++) iv[8 + b] = static_cast<unsigned char>((chunkIndex >> (24 - b * 8)) & 0xFF);

            unsigned char aad[24] = {0};
            std::memcpy(aad, fileId, 16);
            for (int b = 0; b < 8; b++) aad[16 + b] = static_cast<unsigned char>((chunkIndex >> (56 - b * 8)) & 0xFF);

            mbedtls_gcm_context gcm;
            mbedtls_gcm_init(&gcm);
            if (mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, masterKey, 256) != 0) {
                mbedtls_gcm_free(&gcm);
                return false;
            }
            int ret = mbedtls_gcm_crypt_and_tag(&gcm, MBEDTLS_GCM_ENCRYPT, nRead,
                                                iv, 12, aad, 24,
                                                clearBuf.data(), encBuf.data(),
                                                16, encBuf.data() + nRead);
            mbedtls_gcm_free(&gcm);
            if (ret != 0) return false;
            encChunkLen = nRead + 16;
        } else {
            // Cascade / XTS Cipher
            size_t sectorCount = (nRead + 511) / 512;
            size_t paddedLen = sectorCount * 512;
            std::memset(clearBuf.data() + nRead, 0, paddedLen - nRead);

            for (size_t s = 0; s < sectorCount; s++) {
                uint64_t sectorNum = chunkIndex * 128 + s;
                cascadeEncryptSector(cascadeCtx, sectorNum, clearBuf.data() + s * 512, encBuf.data() + s * 512);
            }

            std::vector<unsigned char> macInput(24 + paddedLen);
            std::memcpy(macInput.data(), fileId, 16);
            for (int b = 0; b < 8; b++) macInput[16 + b] = static_cast<unsigned char>((chunkIndex >> (56 - b * 8)) & 0xFF);
            std::memcpy(macInput.data() + 24, encBuf.data(), paddedLen);

            hmacSha256(chunkMacKey, 32, macInput.data(), macInput.size(), encBuf.data() + paddedLen);
            encChunkLen = paddedLen + 32;
        }

        if (pwrite(destFd, encBuf.data(), encChunkLen, static_cast<off_t>(bytesWrittenTotal)) != static_cast<ssize_t>(encChunkLen)) {
            return false;
        }

        bytesReadTotal += nRead;
        bytesWrittenTotal += encChunkLen;
        chunkIndex++;

        if (progressCallback) progressCallback(bytesReadTotal, originalFileSize);
    }

    return true;
}

bool decryptSingleFile(
    int srcFd,
    int destFd,
    const unsigned char* password,
    size_t passwordLen,
    const int* keyfileFds,
    int keyfileCount,
    int opId,
    std::function<bool()> cancelCheck,
    std::function<void(uint64_t bytesDone, uint64_t bytesTotal)> progressCallback
) {
    if (srcFd < 0 || destFd < 0) return false;

    unsigned char header[128];
    if (pread(srcFd, header, 128, 0) != 128) return false;

    if (header[0] != 'V' || header[1] != 'X' || header[2] != 'E' || header[3] != 'N' || header[4] != 'C' || header[5] != 0x01) {
        return false;
    }

    int cipherIndex = (static_cast<int>(header[6]) << 8) | header[7];
    uint32_t iterations = (static_cast<uint32_t>(header[10]) << 24) |
                          (static_cast<uint32_t>(header[11]) << 16) |
                          (static_cast<uint32_t>(header[12]) << 8) |
                          header[13];
    const unsigned char* salt = header + 14;
    const unsigned char* fileId = header + 46;

    uint64_t originalFileSize = 0;
    for (int i = 0; i < 8; i++) {
        originalFileSize = (originalFileSize << 8) | header[62 + i];
    }
    const unsigned char* expectedHeaderMac = header + 70;

    unsigned char mixedPassword[128] = {0};
    ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
    size_t mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
    std::memcpy(mixedPassword, password, mixedPasswordLen);
    if (keyfileCount > 0 && keyfileFds != nullptr) {
        if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
            return false;
        }
    }

    unsigned char derivedKeyBuf[256] = {0};
    ScopeZeroize derivedKeyGuard(derivedKeyBuf, sizeof(derivedKeyBuf));

    if (!pbkdf2Hmac(HashId::kSha256, mixedPassword, mixedPasswordLen, salt, 32, iterations, derivedKeyBuf, sizeof(derivedKeyBuf), cancelCheck)) {
        return false;
    }

    const unsigned char* masterKey = derivedKeyBuf;
    const unsigned char* headerMacKey = derivedKeyBuf + 192;
    const unsigned char* chunkMacKey = derivedKeyBuf + 224;

    unsigned char computedHeaderMac[32];
    hmacSha256(headerMacKey, 32, header, 70, computedHeaderMac);

    int macDiff = 0;
    for (int i = 0; i < 32; i++) {
        macDiff |= (expectedHeaderMac[i] ^ computedHeaderMac[i]);
    }
    if (macDiff != 0) {
        return false; // Wrong password or invalid keyfiles
    }

    CascadeContext cascadeCtx;
    if (cipherIndex >= 2) {
        CascadeId cascadeId = static_cast<CascadeId>(cipherIndex - 2);
        CascadeSpec spec = cascadeSpecFor(cascadeId);
        if (!cascadeSetKeys(cascadeCtx, cascadeId, masterKey, spec.layerCount * 64)) {
            return false;
        }
    }

    std::vector<unsigned char> encBuf(CLEAR_CHUNK_SIZE + 64);
    std::vector<unsigned char> clearBuf(CLEAR_CHUNK_SIZE);

    uint64_t bytesWrittenTotal = 0;
    uint64_t bytesReadTotal = 128;
    uint64_t chunkIndex = 0;

    if (progressCallback) progressCallback(0, originalFileSize);

    while (bytesWrittenTotal < originalFileSize) {
        if (cancelCheck && cancelCheck()) return false;

        uint64_t remainingClear = originalFileSize - bytesWrittenTotal;
        size_t wantClear = static_cast<size_t>(std::min<uint64_t>(CLEAR_CHUNK_SIZE, remainingClear));

        size_t encChunkLen = 0;
        if (cipherIndex == 0 || cipherIndex == 1) {
            encChunkLen = wantClear + 16;
        } else {
            size_t sectorCount = (wantClear + 511) / 512;
            encChunkLen = sectorCount * 512 + 32;
        }

        ssize_t nRead = pread(srcFd, encBuf.data(), encChunkLen, static_cast<off_t>(bytesReadTotal));
        if (nRead != static_cast<ssize_t>(encChunkLen)) return false;

        if (cipherIndex == 0) {
            // XChaCha20-Poly1305
            unsigned char nonce[24] = {0};
            std::memcpy(nonce, fileId, 16);
            for (int b = 0; b < 8; b++) nonce[16 + b] = static_cast<unsigned char>((chunkIndex >> (56 - b * 8)) & 0xFF);

            unsigned char aad[24] = {0};
            std::memcpy(aad, fileId, 16);
            for (int b = 0; b < 8; b++) aad[16 + b] = static_cast<unsigned char>((chunkIndex >> (56 - b * 8)) & 0xFF);

            if (!xchacha20Poly1305Open(masterKey, nonce, aad, 24, encBuf.data(), wantClear, encBuf.data() + wantClear, clearBuf.data())) {
                return false;
            }
        } else if (cipherIndex == 1) {
            // AES-256-GCM
            unsigned char iv[12] = {0};
            std::memcpy(iv, fileId, 8);
            for (int b = 0; b < 4; b++) iv[8 + b] = static_cast<unsigned char>((chunkIndex >> (24 - b * 8)) & 0xFF);

            unsigned char aad[24] = {0};
            std::memcpy(aad, fileId, 16);
            for (int b = 0; b < 8; b++) aad[16 + b] = static_cast<unsigned char>((chunkIndex >> (56 - b * 8)) & 0xFF);

            mbedtls_gcm_context gcm;
            mbedtls_gcm_init(&gcm);
            if (mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, masterKey, 256) != 0) {
                mbedtls_gcm_free(&gcm);
                return false;
            }
            int ret = mbedtls_gcm_auth_decrypt(&gcm, wantClear, iv, 12, aad, 24, encBuf.data() + wantClear, 16, encBuf.data(), clearBuf.data());
            mbedtls_gcm_free(&gcm);
            if (ret != 0) return false;
        } else {
            // Cascade / XTS
            size_t sectorCount = (wantClear + 511) / 512;
            size_t paddedLen = sectorCount * 512;

            std::vector<unsigned char> macInput(24 + paddedLen);
            std::memcpy(macInput.data(), fileId, 16);
            for (int b = 0; b < 8; b++) macInput[16 + b] = static_cast<unsigned char>((chunkIndex >> (56 - b * 8)) & 0xFF);
            std::memcpy(macInput.data() + 24, encBuf.data(), paddedLen);

            unsigned char computedChunkMac[32];
            hmacSha256(chunkMacKey, 32, macInput.data(), macInput.size(), computedChunkMac);

            const unsigned char* expectedChunkMac = encBuf.data() + paddedLen;
            int tagDiff = 0;
            for (int i = 0; i < 32; i++) tagDiff |= (expectedChunkMac[i] ^ computedChunkMac[i]);
            if (tagDiff != 0) return false;

            for (size_t s = 0; s < sectorCount; s++) {
                uint64_t sectorNum = chunkIndex * 128 + s;
                cascadeDecryptSector(cascadeCtx, sectorNum, encBuf.data() + s * 512, clearBuf.data() + s * 512);
            }
        }

        if (pwrite(destFd, clearBuf.data(), wantClear, static_cast<off_t>(bytesWrittenTotal)) != static_cast<ssize_t>(wantClear)) {
            return false;
        }

        bytesReadTotal += encChunkLen;
        bytesWrittenTotal += wantClear;
        chunkIndex++;

        if (progressCallback) progressCallback(bytesWrittenTotal, originalFileSize);
    }

    return true;
}