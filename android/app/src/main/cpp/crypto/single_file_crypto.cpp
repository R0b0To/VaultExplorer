#include "crypto/single_file_crypto.h"
#include "crypto/cipher_shim.h"
#include "crypto/cascade.h"
#include "crypto/keyfile_mixing.h"
#include "crypto/xchacha20poly1305.h"
#include "mbedtls/gcm.h"
#include "mbedtls/md.h"
#include "mbedtls/aes.h"
#include "mbedtls/platform_util.h"
#include <unistd.h>
#include <sys/stat.h>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <vector>

static constexpr size_t KDF_ITERATIONS = 100000;
static constexpr size_t CLEAR_CHUNK_SIZE = 64 * 1024;

static void hmacSha256(const unsigned char* key, size_t keyLen,
                        const unsigned char* input, size_t inputLen,
                        unsigned char outTag[32]) {
    const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_hmac(mdInfo, key, keyLen, input, inputLen, outTag);
}

static std::vector<unsigned char> utf8ToUtf16Le(const unsigned char* utf8, size_t len) {
    std::vector<unsigned char> out;
    out.reserve(len * 2);
    size_t i = 0;
    while (i < len) {
        uint32_t cp = 0;
        unsigned char c = utf8[i];
        if (c < 0x80) {
            cp = c;
            i += 1;
        } else if ((c & 0xE0) == 0xC0) {
            if (i + 1 >= len) break;
            cp = ((c & 0x1F) << 6) | (utf8[i + 1] & 0x3F);
            i += 2;
        } else if ((c & 0xF0) == 0xE0) {
            if (i + 2 >= len) break;
            cp = ((c & 0x0F) << 12) | ((utf8[i + 1] & 0x3F) << 6) | (utf8[i + 2] & 0x3F);
            i += 3;
        } else if ((c & 0xF8) == 0xF0) {
            if (i + 3 >= len) break;
            cp = ((c & 0x07) << 18) | ((utf8[i + 1] & 0x3F) << 12) | ((utf8[i + 2] & 0x3F) << 6) | (utf8[i + 3] & 0x3F);
            i += 4;
        } else {
            i += 1;
            continue;
        }
        if (cp < 0x10000) {
            out.push_back(static_cast<unsigned char>(cp & 0xFF));
            out.push_back(static_cast<unsigned char>((cp >> 8) & 0xFF));
        } else {
            cp -= 0x10000;
            uint16_t high = static_cast<uint16_t>(0xD800 | (cp >> 10));
            uint16_t low  = static_cast<uint16_t>(0xDC00 | (cp & 0x3FF));
            out.push_back(static_cast<unsigned char>(high & 0xFF));
            out.push_back(static_cast<unsigned char>((high >> 8) & 0xFF));
            out.push_back(static_cast<unsigned char>(low & 0xFF));
            out.push_back(static_cast<unsigned char>((low >> 8) & 0xFF));
        }
    }
    return out;
}

static void aesCryptDeriveKey(const unsigned char* iv1, const std::vector<unsigned char>& passwordUtf16, unsigned char outKey[32]) {
    const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, mdInfo, 0);

    // Initial seed: iv1 (16 bytes) + 16 zero bytes (32 bytes total)
    unsigned char current[32];
    std::memcpy(current, iv1, 16);
    std::memset(current + 16, 0, 16);

    for (int i = 0; i < 8192; i++) {
        mbedtls_md_starts(&ctx);
        mbedtls_md_update(&ctx, current, 32);
        if (!passwordUtf16.empty()) {
            mbedtls_md_update(&ctx, passwordUtf16.data(), passwordUtf16.size());
        }
        mbedtls_md_finish(&ctx, current);
    }
    mbedtls_md_free(&ctx);
    std::memcpy(outKey, current, 32);
    mbedtls_platform_zeroize(current, sizeof(current));
}

static bool encryptAesCryptFile(
    int srcFd,
    int destFd,
    const unsigned char* password,
    size_t passwordLen,
    int opId,
    std::function<bool()> cancelCheck,
    std::function<void(uint64_t bytesDone, uint64_t bytesTotal)> progressCallback
) {
    if (srcFd < 0 || destFd < 0) return false;

    struct stat st{};
    if (fstat(srcFd, &st) != 0) return false;
    uint64_t originalFileSize = static_cast<uint64_t>(st.st_size);

    unsigned char iv0[16];
    unsigned char intKey[32];
    unsigned char iv1[16];

    FILE* urnd = fopen("/dev/urandom", "rb");
    if (!urnd) return false;
    bool ok = (fread(iv0, 1, 16, urnd) == 16) &&
              (fread(intKey, 1, 32, urnd) == 32) &&
              (fread(iv1, 1, 16, urnd) == 16);
    fclose(urnd);
    if (!ok) return false;

    std::vector<unsigned char> passwordUtf16 = utf8ToUtf16Le(password, passwordLen);

    unsigned char masterKey[32];
    aesCryptDeriveKey(iv1, passwordUtf16, masterKey);
    ScopeZeroize masterKeyGuard(masterKey, sizeof(masterKey));

    unsigned char iv1Copy[16];
    std::memcpy(iv1Copy, iv1, 16);
    unsigned char plainIvKey[48];
    std::memcpy(plainIvKey, iv0, 16);
    std::memcpy(plainIvKey + 16, intKey, 32);

    unsigned char cIvKey[48];
    mbedtls_aes_context aesKeyCtx;
    mbedtls_aes_init(&aesKeyCtx);
    mbedtls_aes_setkey_enc(&aesKeyCtx, masterKey, 256);
    mbedtls_aes_crypt_cbc(&aesKeyCtx, MBEDTLS_AES_ENCRYPT, 48, iv1Copy, plainIvKey, cIvKey);
    mbedtls_aes_free(&aesKeyCtx);
    mbedtls_platform_zeroize(plainIvKey, sizeof(plainIvKey));

    unsigned char hmac1Tag[32];
    hmacSha256(masterKey, 32, cIvKey, 48, hmac1Tag);

    unsigned char header[103];
    header[0] = 'A';
    header[1] = 'E';
    header[2] = 'S';
    header[3] = 0x02; // Version 2
    header[4] = 0x00; // Reserved
    header[5] = 0x00; // Extension length high byte
    header[6] = 0x00; // Extension length low byte (0 length = end of extensions)
    std::memcpy(header + 7, iv1, 16);
    std::memcpy(header + 23, cIvKey, 48);
    std::memcpy(header + 71, hmac1Tag, 32);

    if (pwrite(destFd, header, 103, 0) != 103) {
        mbedtls_platform_zeroize(intKey, sizeof(intKey));
        return false;
    }

    mbedtls_aes_context aesPayloadCtx;
    mbedtls_aes_init(&aesPayloadCtx);
    mbedtls_aes_setkey_enc(&aesPayloadCtx, intKey, 256);

    const mbedtls_md_info_t* sha256Info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_context_t hmacPayloadCtx;
    mbedtls_md_init(&hmacPayloadCtx);
    mbedtls_md_setup(&hmacPayloadCtx, sha256Info, 1);
    mbedtls_md_hmac_starts(&hmacPayloadCtx, intKey, 32);

    unsigned char iv0Copy[16];
    std::memcpy(iv0Copy, iv0, 16);

    std::vector<unsigned char> clearBuf(CLEAR_CHUNK_SIZE);
    std::vector<unsigned char> encBuf(CLEAR_CHUNK_SIZE);

    uint64_t bytesReadTotal = 0;
    uint64_t bytesWrittenTotal = 103;

    if (progressCallback) progressCallback(0, originalFileSize);

    while (bytesReadTotal < originalFileSize) {
        if (cancelCheck && cancelCheck()) {
            mbedtls_aes_free(&aesPayloadCtx);
            mbedtls_md_free(&hmacPayloadCtx);
            mbedtls_platform_zeroize(intKey, sizeof(intKey));
            return false;
        }

        size_t wantRead = static_cast<size_t>(std::min<uint64_t>(CLEAR_CHUNK_SIZE, originalFileSize - bytesReadTotal));
        ssize_t nRead = pread(srcFd, clearBuf.data(), wantRead, static_cast<off_t>(bytesReadTotal));
        if (nRead != static_cast<ssize_t>(wantRead)) {
            mbedtls_aes_free(&aesPayloadCtx);
            mbedtls_md_free(&hmacPayloadCtx);
            mbedtls_platform_zeroize(intKey, sizeof(intKey));
            return false;
        }

        bytesReadTotal += nRead;
        bool isFinal = (bytesReadTotal == originalFileSize);

        size_t cipherBlockLen = 0;
        if (!isFinal) {
            cipherBlockLen = nRead;
            mbedtls_aes_crypt_cbc(&aesPayloadCtx, MBEDTLS_AES_ENCRYPT, cipherBlockLen, iv0Copy, clearBuf.data(), encBuf.data());
        } else {
            size_t padLen = 16 - (nRead % 16);
            cipherBlockLen = nRead + padLen;
            std::memcpy(encBuf.data(), clearBuf.data(), nRead);
            std::memset(encBuf.data() + nRead, static_cast<unsigned char>(padLen), padLen);
            mbedtls_aes_crypt_cbc(&aesPayloadCtx, MBEDTLS_AES_ENCRYPT, cipherBlockLen, iv0Copy, encBuf.data(), encBuf.data());
        }

        mbedtls_md_hmac_update(&hmacPayloadCtx, encBuf.data(), cipherBlockLen);

        if (pwrite(destFd, encBuf.data(), cipherBlockLen, static_cast<off_t>(bytesWrittenTotal)) != static_cast<ssize_t>(cipherBlockLen)) {
            mbedtls_aes_free(&aesPayloadCtx);
            mbedtls_md_free(&hmacPayloadCtx);
            mbedtls_platform_zeroize(intKey, sizeof(intKey));
            return false;
        }
        bytesWrittenTotal += cipherBlockLen;

        if (progressCallback) progressCallback(bytesReadTotal, originalFileSize);
    }

    if (originalFileSize == 0) {
        std::memset(encBuf.data(), 16, 16);
        mbedtls_aes_crypt_cbc(&aesPayloadCtx, MBEDTLS_AES_ENCRYPT, 16, iv0Copy, encBuf.data(), encBuf.data());
        mbedtls_md_hmac_update(&hmacPayloadCtx, encBuf.data(), 16);
        if (pwrite(destFd, encBuf.data(), 16, static_cast<off_t>(bytesWrittenTotal)) != 16) {
            mbedtls_aes_free(&aesPayloadCtx);
            mbedtls_md_free(&hmacPayloadCtx);
            mbedtls_platform_zeroize(intKey, sizeof(intKey));
            return false;
        }
        bytesWrittenTotal += 16;
    }

    unsigned char fs16 = static_cast<unsigned char>(originalFileSize % 16);
    if (pwrite(destFd, &fs16, 1, static_cast<off_t>(bytesWrittenTotal)) != 1) {
        mbedtls_aes_free(&aesPayloadCtx);
        mbedtls_md_free(&hmacPayloadCtx);
        mbedtls_platform_zeroize(intKey, sizeof(intKey));
        return false;
    }
    bytesWrittenTotal += 1;

    unsigned char hmac2Tag[32];
    mbedtls_md_hmac_finish(&hmacPayloadCtx, hmac2Tag);
    mbedtls_aes_free(&aesPayloadCtx);
    mbedtls_md_free(&hmacPayloadCtx);
    mbedtls_platform_zeroize(intKey, sizeof(intKey));

    if (pwrite(destFd, hmac2Tag, 32, static_cast<off_t>(bytesWrittenTotal)) != 32) {
        return false;
    }

    return true;
}

static bool decryptAesCryptFile(
    int srcFd,
    int destFd,
    const unsigned char* password,
    size_t passwordLen,
    int opId,
    std::function<bool()> cancelCheck,
    std::function<void(uint64_t bytesDone, uint64_t bytesTotal)> progressCallback
) {
    if (srcFd < 0 || destFd < 0) return false;

    struct stat st{};
    if (fstat(srcFd, &st) != 0) return false;
    uint64_t totalFileSize = static_cast<uint64_t>(st.st_size);

    if (totalFileSize < 136) return false;

    unsigned char headerStart[5];
    if (pread(srcFd, headerStart, 5, 0) != 5) return false;
    if (headerStart[0] != 'A' || headerStart[1] != 'E' || headerStart[2] != 'S') {
        return false;
    }
    uint8_t version = headerStart[3];
    if (version != 0x01 && version != 0x02 && version != 0x03) {
        return false;
    }

    uint64_t currentOffset = 5;

    if (version == 0x02 || version == 0x03) {
        while (currentOffset + 2 <= totalFileSize) {
            unsigned char extLenBuf[2];
            if (pread(srcFd, extLenBuf, 2, static_cast<off_t>(currentOffset)) != 2) return false;
            currentOffset += 2;
            uint16_t extLen = (static_cast<uint16_t>(extLenBuf[0]) << 8) | extLenBuf[1];
            if (extLen == 0) break;
            currentOffset += extLen;
        }
    }

    if (currentOffset + 16 + 48 + 32 > totalFileSize) return false;

    unsigned char iv1[16];
    unsigned char cIvKey[48];
    unsigned char hmac1Tag[32];

    if (pread(srcFd, iv1, 16, static_cast<off_t>(currentOffset)) != 16) return false;
    currentOffset += 16;
    if (pread(srcFd, cIvKey, 48, static_cast<off_t>(currentOffset)) != 48) return false;
    currentOffset += 48;
    if (pread(srcFd, hmac1Tag, 32, static_cast<off_t>(currentOffset)) != 32) return false;
    currentOffset += 32;

    uint64_t payloadStartOffset = currentOffset;

    std::vector<unsigned char> passwordUtf16 = utf8ToUtf16Le(password, passwordLen);
    unsigned char masterKey[32];
    aesCryptDeriveKey(iv1, passwordUtf16, masterKey);
    ScopeZeroize masterKeyGuard(masterKey, sizeof(masterKey));

    const mbedtls_md_info_t* sha256Info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    unsigned char computedHmac1[32];
    mbedtls_md_hmac(sha256Info, masterKey, 32, cIvKey, 48, computedHmac1);

    int hmac1Diff = 0;
    for (int i = 0; i < 32; i++) {
        hmac1Diff |= (hmac1Tag[i] ^ computedHmac1[i]);
    }
    if (hmac1Diff != 0) {
        return false;
    }

    unsigned char iv1Copy[16];
    std::memcpy(iv1Copy, iv1, 16);
    unsigned char plainIvKey[48];

    mbedtls_aes_context aesKeyCtx;
    mbedtls_aes_init(&aesKeyCtx);
    mbedtls_aes_setkey_dec(&aesKeyCtx, masterKey, 256);
    mbedtls_aes_crypt_cbc(&aesKeyCtx, MBEDTLS_AES_DECRYPT, 48, iv1Copy, cIvKey, plainIvKey);
    mbedtls_aes_free(&aesKeyCtx);

    unsigned char iv0[16];
    unsigned char intKey[32];
    std::memcpy(iv0, plainIvKey, 16);
    std::memcpy(intKey, plainIvKey + 16, 32);
    mbedtls_platform_zeroize(plainIvKey, sizeof(plainIvKey));

    if (totalFileSize < payloadStartOffset + 33) {
        mbedtls_platform_zeroize(intKey, sizeof(intKey));
        return false;
    }
    uint64_t totalPayloadArea = totalFileSize - payloadStartOffset;
    uint64_t ciphertextLen = totalPayloadArea - 33;
    if (ciphertextLen % 16 != 0) {
        mbedtls_platform_zeroize(intKey, sizeof(intKey));
        return false;
    }

    unsigned char fs16 = 0;
    if (pread(srcFd, &fs16, 1, static_cast<off_t>(payloadStartOffset + ciphertextLen)) != 1) {
        mbedtls_platform_zeroize(intKey, sizeof(intKey));
        return false;
    }

    unsigned char expectedHmac2[32];
    if (pread(srcFd, expectedHmac2, 32, static_cast<off_t>(payloadStartOffset + ciphertextLen + 1)) != 32) {
        mbedtls_platform_zeroize(intKey, sizeof(intKey));
        return false;
    }

    mbedtls_aes_context aesPayloadCtx;
    mbedtls_aes_init(&aesPayloadCtx);
    mbedtls_aes_setkey_dec(&aesPayloadCtx, intKey, 256);

    mbedtls_md_context_t hmacPayloadCtx;
    mbedtls_md_init(&hmacPayloadCtx);
    mbedtls_md_setup(&hmacPayloadCtx, sha256Info, 1);
    mbedtls_md_hmac_starts(&hmacPayloadCtx, intKey, 32);

    unsigned char iv0Copy[16];
    std::memcpy(iv0Copy, iv0, 16);

    std::vector<unsigned char> encBuf(CLEAR_CHUNK_SIZE);
    std::vector<unsigned char> decBuf(CLEAR_CHUNK_SIZE);

    uint64_t bytesReadTotal = 0;
    uint64_t bytesWrittenTotal = 0;

    uint64_t expectedCleartextSize = (ciphertextLen > 0)
        ? (ciphertextLen - 16 + (fs16 == 0 ? 16 : (fs16 & 0x0F)))
        : 0;

    if (progressCallback) progressCallback(0, expectedCleartextSize);

    while (bytesReadTotal < ciphertextLen) {
        if (cancelCheck && cancelCheck()) {
            mbedtls_aes_free(&aesPayloadCtx);
            mbedtls_md_free(&hmacPayloadCtx);
            mbedtls_platform_zeroize(intKey, sizeof(intKey));
            return false;
        }

        size_t wantRead = static_cast<size_t>(std::min<uint64_t>(CLEAR_CHUNK_SIZE, ciphertextLen - bytesReadTotal));
        ssize_t nRead = pread(srcFd, encBuf.data(), wantRead, static_cast<off_t>(payloadStartOffset + bytesReadTotal));
        if (nRead != static_cast<ssize_t>(wantRead)) {
            mbedtls_aes_free(&aesPayloadCtx);
            mbedtls_md_free(&hmacPayloadCtx);
            mbedtls_platform_zeroize(intKey, sizeof(intKey));
            return false;
        }

        mbedtls_md_hmac_update(&hmacPayloadCtx, encBuf.data(), wantRead);
        mbedtls_aes_crypt_cbc(&aesPayloadCtx, MBEDTLS_AES_DECRYPT, wantRead, iv0Copy, encBuf.data(), decBuf.data());

        bytesReadTotal += wantRead;
        bool isFinalChunk = (bytesReadTotal == ciphertextLen);

        size_t writeLen = wantRead;
        if (isFinalChunk) {
            size_t validInLastBlock = (fs16 == 0) ? 16 : (fs16 & 0x0F);
            writeLen = (wantRead - 16) + validInLastBlock;
        }

        if (writeLen > 0) {
            if (pwrite(destFd, decBuf.data(), writeLen, static_cast<off_t>(bytesWrittenTotal)) != static_cast<ssize_t>(writeLen)) {
                mbedtls_aes_free(&aesPayloadCtx);
                mbedtls_md_free(&hmacPayloadCtx);
                mbedtls_platform_zeroize(intKey, sizeof(intKey));
                return false;
            }
            bytesWrittenTotal += writeLen;
        }

        if (progressCallback) progressCallback(bytesWrittenTotal, expectedCleartextSize);
    }

    unsigned char computedHmac2[32];
    mbedtls_md_hmac_finish(&hmacPayloadCtx, computedHmac2);

    mbedtls_aes_free(&aesPayloadCtx);
    mbedtls_md_free(&hmacPayloadCtx);
    mbedtls_platform_zeroize(intKey, sizeof(intKey));

    int hmac2Diff = 0;
    for (int i = 0; i < 32; i++) {
        hmac2Diff |= (expectedHmac2[i] ^ computedHmac2[i]);
    }

    if (hmac2Diff != 0) {
        return false;
    }

    return true;
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

    if (cipherIndex == 2) {
        unsigned char mixedPassword[128] = {0};
        ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
        size_t mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
        std::memcpy(mixedPassword, password, mixedPasswordLen);
        if (keyfileCount > 0 && keyfileFds != nullptr) {
            if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
                return false;
            }
        }
        return encryptAesCryptFile(srcFd, destFd, mixedPassword, mixedPasswordLen, opId, cancelCheck, progressCallback);
    }

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

    const unsigned char* masterKey = derivedKeyBuf;
    const unsigned char* headerMacKey = derivedKeyBuf + 192;
    const unsigned char* chunkMacKey = derivedKeyBuf + 224;

    unsigned char header[128] = {0};
    header[0] = 'V'; header[1] = 'X'; header[2] = 'E'; header[3] = 'N'; header[4] = 'C'; header[5] = 0x01;
    header[6] = static_cast<unsigned char>((cipherIndex >> 8) & 0xFF);
    header[7] = static_cast<unsigned char>(cipherIndex & 0xFF);
    header[8] = 0; header[9] = 0;
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
    if (cipherIndex >= 3) {
        CascadeId cascadeId = static_cast<CascadeId>(cipherIndex - 3);
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

    // Auto-detect AES Crypt header magic "AES"
    unsigned char magic[3];
    if (pread(srcFd, magic, 3, 0) == 3 && magic[0] == 'A' && magic[1] == 'E' && magic[2] == 'S') {
        unsigned char mixedPassword[128] = {0};
        ScopeZeroize mixedPasswordGuard(mixedPassword, sizeof(mixedPassword));
        size_t mixedPasswordLen = std::min(passwordLen, sizeof(mixedPassword));
        std::memcpy(mixedPassword, password, mixedPasswordLen);
        if (keyfileCount > 0 && keyfileFds != nullptr) {
            if (!applyKeyfilesToPassword(keyfileFds, keyfileCount, mixedPassword, &mixedPasswordLen)) {
                return false;
            }
        }
        return decryptAesCryptFile(srcFd, destFd, mixedPassword, mixedPasswordLen, opId, cancelCheck, progressCallback);
    }

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
        return false;
    }

    CascadeContext cascadeCtx;
    if (cipherIndex >= 3) {
        CascadeId cascadeId = static_cast<CascadeId>(cipherIndex - 3);
        CascadeSpec spec = cascadeSpecFor(cascadeId);
        if (!cascadeSetKeys(cascadeCtx, cascadeId, masterKey, spec.layerCount * 64)) {
            return false;
        }
    } else if (cipherIndex == 2) {
        CascadeId cascadeId = static_cast<CascadeId>(0);
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