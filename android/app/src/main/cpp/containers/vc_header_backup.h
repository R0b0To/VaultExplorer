#pragma once
// "Restore Volume Header" -- the write half, exactly as desktop VeraCrypt does it
// (src/Mount/Mount.c RestoreVolumeHeader, external-file branch).
//
// A VeraCrypt header backup file is TC_VOLUME_HEADER_GROUP_SIZE (131072) bytes:
// the standard-volume header slot at 0 and the hidden-volume header slot at
// 65536 (each a 512-byte header followed by random filler). Restoring one:
//   1. the password decrypts ONE of the two slots -- that decides whether the
//      backup is of a standard or of a hidden-volume header;
//   2. only THAT header is written back -- at offset 0 / 65536 -- and the other
//      header slot of the volume is left alone (a restore must never touch the
//      other volume's header);
//   3. every written copy is re-encrypted under its OWN fresh salt (KDF re-run),
//      and the volume's embedded backup copy (V-128K for a standard volume,
//      V-64K for a hidden one) is rewritten the same way;
//   4. a header whose two XTS key halves are identical is refused.
// Header-only (the I/O is a callback) so it can be tested on the host
// (containers/test/vc_header_backup_test.cpp).
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <functional>
#include "vc_geometry.h"
#include "vc_header_build.h"

enum class VcRestoreApplyResult { kOk, kVulnerableKey, kContainerTooSmall, kBuildFailed, kIoError };

// True if the XTS key halves of the master key area are identical (upstream's
// "XTS key vulnerable" condition, Volume/VolumeHeader.cpp).
inline bool vcXtsKeysIdentical(const unsigned char* decryptedBody, CascadeId cipher) {
    const size_t eaKeySize = static_cast<size_t>(cascadeSpecFor(cipher).layerCount) * 32;
    return std::memcmp(decryptedBody + VC_KEY_OFFSET_MASTER,
                       decryptedBody + VC_KEY_OFFSET_MASTER + eaKeySize, eaKeySize) == 0;
}

// [decryptedBody] is the verified plaintext header body; [password]/[pim]/[hash]/
// [cipher] are what it was decrypted with; [hidden] whether it is a hidden-volume
// header; [hostSize] the container size. [writeAt] writes bytes at a host offset.
inline VcRestoreApplyResult vcApplyRestoredHeader(
    const unsigned char* decryptedBody, CascadeId cipher, HashId hash,
    const unsigned char* password, size_t passwordLen, int pim,
    bool hidden, uint64_t hostSize,
    const std::function<bool(uint64_t, const unsigned char*, size_t)>& writeAt) {
    if (vcXtsKeysIdentical(decryptedBody, cipher)) return VcRestoreApplyResult::kVulnerableKey;
    uint64_t backupOffset = 0;
    if (!vcgeom::backupHeaderOffset(hostSize, hidden, &backupOffset)) {
        return VcRestoreApplyResult::kContainerTooSmall;
    }
    const uint64_t primaryOffset = hidden ? static_cast<uint64_t>(VC_HIDDEN_HEADER_OFFSET) : 0;
    unsigned char primary[VC_FULL_HEADER_SIZE];
    unsigned char backup[VC_FULL_HEADER_SIZE];
    const bool built =
        vcBuildFreshlySaltedHeaderSector(decryptedBody, cipher, hash, password, passwordLen, clampPim(pim), primary) &&
        vcBuildFreshlySaltedHeaderSector(decryptedBody, cipher, hash, password, passwordLen, clampPim(pim), backup);
    VcRestoreApplyResult r = VcRestoreApplyResult::kOk;
    if (!built) r = VcRestoreApplyResult::kBuildFailed;
    else if (!writeAt(primaryOffset, primary, sizeof(primary)) ||
             !writeAt(backupOffset, backup, sizeof(backup))) r = VcRestoreApplyResult::kIoError;
    mbedtls_platform_zeroize(primary, sizeof(primary));
    mbedtls_platform_zeroize(backup, sizeof(backup));
    return r;
}
