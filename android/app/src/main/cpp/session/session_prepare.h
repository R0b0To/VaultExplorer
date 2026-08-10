#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <vector>

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


bool enableHiddenVolumeProtection(
    int volId,
    const unsigned char* hiddenPassword, size_t hiddenPasswordLen,
    int hiddenPim, int hiddenCipherId, int hiddenHashId,
    const int* hiddenKeyfileFds = nullptr, int hiddenKeyfileCount = 0);

void clearUnlockCancellation(int volId);
void requestUnlockCancellation(int volId);
bool isUnlockCancelled(int volId);

// ── Whole-disk-image partition scanning (Check & Repair tool reuses these
//    for BitLocker format detection -- see container_repair.cpp) ─────────

struct PartitionCandidate {
    uint64_t startSector;
    uint64_t sectorCount;
};

// Parses an MBR (and, if present, GPT) partition table from any
// sector-addressable block source via [readSectors]. Always appends a
// trailing {0, 0} sentinel -- see the .cpp doc comment for why.
std::vector<PartitionCandidate> scanPartitionTable(
    const std::function<bool(uint64_t startSector, uint32_t count, unsigned char* out)>& readSectors);

// Fixed-format VHD files are raw disk bytes plus a trailing 512-byte
// "conectix" footer; this returns [fileSize] with that footer excluded
// when present, or [fileSize] unchanged otherwise. Only meaningful for
// flat (fixed/raw) whole-disk files -- see the .cpp doc comment for why
// dynamic/differencing VHDs must never be passed through this path.
uint64_t usableFileBytesExcludingVhdFooter(int fd, uint64_t fileSize);