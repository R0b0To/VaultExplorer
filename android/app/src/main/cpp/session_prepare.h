#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <functional>

#include "container_header.h"
#include "crypto/cascade.h"
#include "crypto/vc_header_layout.h"

bool deriveAndValidateHeader(
    const unsigned char headerSector[VC_FULL_HEADER_SIZE],
    const unsigned char* password, size_t passwordLen, int pim,
    int cipherIdParam, int hashIdParam,
    unsigned char outKeyMaterial[192],
    unsigned char outDecryptedHeader[VC_HEADER_BODY_SIZE],
    CascadeId& outMatchedCipher,
    HashId& outMatchedHash,
    ParsedHeaderFields& outFields,
    int volId = -1,
    std::atomic<bool>* externalAbort = nullptr,
    int slotId = 0);

bool deriveHeaderKey(HashId hash,
                     const unsigned char* password, size_t passwordLen,
                     const unsigned char* salt, int clampedPim,
                     unsigned char* out, size_t outLen,
                     std::function<bool()> cancelCheck = nullptr);

bool prepareSession(int fd, const unsigned char* password, size_t passwordLen,
                    int pim, int volId, bool forceDerive, int cipherId, int hashId,
                    const unsigned char* preservedKey = nullptr, size_t preservedKeyLen = 0,
                    const int* keyfileFds = nullptr, int keyfileCount = 0,
                    bool readOnly = false);

bool prepareUsbSession(const unsigned char* password, size_t passwordLen, int pim, int volId,
                       int cipherId, int hashId, const unsigned char* preservedKey = nullptr,
                       size_t preservedKeyLen = 0, int64_t partitionOffsetHint = -1,
                       const int* keyfileFds = nullptr, int keyfileCount = 0,
                       bool readOnly = false);

void clearUnlockCancellation(int volId);
void requestUnlockCancellation(int volId);
bool isUnlockCancelled(int volId);