#pragma once
// Acceptance rules for a DECRYPTED VeraCrypt header body, mirroring upstream's
// VolumeHeader::Deserialize() (Volume/VolumeHeader.cpp, master 1.26.x):
//   * magic "VERA"
//   * header format version 1..5          (higher => HigherVersionRequired upstream)
//   * header CRC-32                        (only exists from format version 4 on)
//   * minimum program version <= ours      (HigherVersionRequired upstream)
//   * key-area CRC-32
//   * sector size: from format version 5 on 512..4096 and a multiple of the 512-byte
//     XTS data unit, otherwise (older formats) fixed at 512
// Header-only so it can be unit-tested on the host (containers/test/vc_header_validate_test.cpp).
#include <cstddef>
#include <cstdint>
#include "container_header.h"
#include "crypto/vc_header_layout.h"

uint32_t container_crc32(const unsigned char* data, size_t length);   // containers/container_utils.cpp

inline bool vcAcceptDecryptedHeader(const unsigned char* decH, ParsedHeaderFields* outFields) {
    if (decH[0] != 'V' || decH[1] != 'E' || decH[2] != 'R' || decH[3] != 'A') return false;

    const unsigned version = (static_cast<unsigned>(decH[VC_HDR_OFF_VERSION]) << 8) | decH[VC_HDR_OFF_VERSION + 1];
    if (version < VC_MIN_HEADER_FORMAT_VERSION || version > VC_HEADER_FORMAT_VERSION) return false;

    if (version >= 4 &&
        container_crc32(decH, VC_HDR_CRC_COVERAGE_LEN) != readHeaderBE32(decH, VC_HDR_OFF_HEADER_CRC)) {
        return false;
    }

    const unsigned requiredVersion =
        (static_cast<unsigned>(decH[VC_HDR_OFF_REQUIRED_VERSION]) << 8) | decH[VC_HDR_OFF_REQUIRED_VERSION + 1];
    if (requiredVersion > VC_PROGRAM_VERSION) return false;

    if (container_crc32(&decH[VC_KEY_OFFSET_MASTER], VC_HDR_KEY_CRC_COVERAGE_LEN) !=
        readHeaderBE32(decH, VC_HDR_OFF_KEY_CRC)) {
        return false;
    }

    const uint32_t sectorSize = (version >= 5) ? readHeaderBE32(decH, VC_HDR_OFF_SECTOR_SIZE)
                                               : static_cast<uint32_t>(VC_ENCRYPTION_DATA_UNIT_SIZE);
    if (sectorSize < VC_MIN_SECTOR_SIZE || sectorSize > VC_MAX_SECTOR_SIZE ||
        sectorSize % VC_ENCRYPTION_DATA_UNIT_SIZE != 0) {
        return false;
    }

    if (outFields) {
        outFields->volumeSize          = readHeaderBE64(decH, VC_HDR_OFF_VOLUME_SIZE);
        outFields->hiddenVolumeSize    = readHeaderBE64(decH, VC_HDR_OFF_HIDDEN_VOL_SIZE);
        outFields->encryptedAreaStart  = readHeaderBE64(decH, VC_HDR_OFF_KEY_SCOPE_START);
        outFields->encryptedAreaLength = readHeaderBE64(decH, VC_HDR_OFF_KEY_SCOPE_SIZE);
        outFields->sectorSize          = sectorSize;
    }
    return true;
}
