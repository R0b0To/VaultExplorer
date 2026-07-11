#pragma once

#include <cstdint>

// Decrypted VeraCrypt-compatible header fields.  Keeping this data-only type
// outside the session implementation makes validation and session setup
// independently testable and reusable by future container readers.
struct ParsedHeaderFields {
    uint64_t volumeSize = 0;
    uint64_t hiddenVolumeSize = 0;
    uint64_t encryptedAreaStart = 0;
    uint64_t encryptedAreaLength = 0;
    uint32_t sectorSize = 0;

    bool isHiddenVolume() const { return hiddenVolumeSize != 0; }
};

bool isValidBootSector(const unsigned char* sector);
uint64_t readHeaderBE64(const unsigned char* data, int offset);
uint32_t readHeaderBE32(const unsigned char* data, int offset);
