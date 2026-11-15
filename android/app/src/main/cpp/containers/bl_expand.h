// BitLocker volume expansion: rewrites the FVE metadata so the encrypted volume covers a larger container.
//
// Header-only and free of Android/JNI/dislocker dependencies so it can be unit-tested on the host
// (containers/test/bl_expand_test.cpp). The container-level orchestration (unlock, file extension, free-space
// initialisation, NTFS grow) lives in containers/container_expand_bitlocker.cpp.
//
// Why this exists: dislocker bounds every read and write by `encrypted_volume_size` from the FVE metadata (not by the
// file size), so enlarging the container file alone leaves the new space unreachable. Writing it as plaintext would put
// unencrypted data into an encrypted container, so the metadata has to be updated instead.
//
// On-disk facts used here (Windows 7+ metadata, version 2; see libbde's format notes and dislocker's metadata.c):
//   * The volume header (sector 0, "-FVE-FS-" at byte 3) holds the sector size at 0x0B, the metadata-offset GUID at
//     0xA0 (only the classic one is handled) and the absolute volume offsets of three metadata copies at 0xB0.
//   * Each copy is a block of (size << 4) bytes starting with a 64-byte header (signature, size, version, state,
//     encrypted_volume_size @0x10, the three copy offsets @0x20) followed by the 48-byte dataset header
//     (next_counter @0x60 of the block) and the datums.
//   * Directly after the block sits a validation record: u16 size, u16 version, u32 CRC-32 of the block, then an
//     AES-CCM datum whose payload (nonce 12 | MAC 16 | 44 encrypted bytes) is keyed with the VMK and holds a SHA-256 of
//     the block. dislocker only checks the CRC; Windows and cryptsetup also check the sealed hash, so both are rewritten.
//
// Safety design: before anything is modified the unmodified copy must pass the very same CRC-32 and sealed-SHA-256
// checks this file later uses to produce the new copies. If a volume deviates from what is assumed here, the checks fail
// and nothing is written (kInvalidMetadata) instead of risking an unreadable volume. After writing, all copies are read
// back and validated again.
#pragma once

#include <cstdint>
#include <cstring>
#include <functional>
#include <vector>

#include "mbedtls/ccm.h"
#include "mbedtls/platform_util.h"
#include "mbedtls/sha256.h"

enum class BlExpandResult {
    kOk = 0,
    kNotBitLocker,      // sector 0 is not a "-FVE-FS-" BitLocker volume header
    kNotExpandable,     // valid BitLocker, but not a fully encrypted Windows 7+ volume that fits its container
    kInvalidMetadata,   // metadata unreadable, failed CRC / sealed-hash verification, or not in the assumed layout
    kNotLarger,         // requested size does not exceed the current encrypted volume size
    kIoError,
};

// Volume-relative byte I/O (for a raw container file the volume starts at file offset 0). [setSize] grows the host file.
struct BlExpandIo {
    std::function<bool(uint64_t offset, unsigned char* out, size_t len)> readAt;
    std::function<bool(uint64_t offset, const unsigned char* data, size_t len)> writeAt;
    std::function<bool(uint64_t newHostSize)> setSize;
    std::function<bool()> sync;   // optional: fsync between metadata copies
};

namespace blexp {

constexpr size_t kVbrProbeLen = 512;
constexpr size_t kVbrSigOffset = 3;
constexpr size_t kVbrSectorSizeOffset = 0x0B;
constexpr size_t kVbrGuidOffset = 0xA0;           // GUID that names the volume's metadata-offset scheme
constexpr size_t kVbrInfoOffsetsOffset = 0xB0;

constexpr size_t kHdrSize = 64;
constexpr size_t kHdrOffSize = 8;                 // u16, in 16-byte units
constexpr size_t kHdrOffVersion = 10;             // u16
constexpr size_t kHdrOffCurrState = 12;           // u16
constexpr size_t kHdrOffNextState = 14;           // u16
constexpr size_t kHdrOffVolumeSize = 16;          // u64
constexpr size_t kHdrOffInfoOffsets = 32;         // 3 x u64
constexpr size_t kDatasetOffNextCounter = 0x60;   // u32 (dataset header at 0x40, next_counter at +0x20)

constexpr uint16_t kVersionSeven = 2;
constexpr uint16_t kStateEncrypted = 4;

constexpr size_t kMaxBlockSize = 65536;
constexpr size_t kMinBlockSize = 0x70;

// Validation record that follows the block.
constexpr size_t kValSizeOff = 0;                 // u16
constexpr size_t kValCrcOff = 4;                  // u32
constexpr size_t kValNestedSizeOff = 8;           // u16 (== 80)
constexpr size_t kValNestedRoleOff = 10;          // u16 (== 0)
constexpr size_t kValNestedTypeOff = 12;          // u16 (== 5, AES-CCM encrypted)
constexpr size_t kValNonceOff = 16;               // 12 bytes
constexpr size_t kValMacOff = 28;                 // 16 bytes
constexpr size_t kValEncOff = 44;                 // 44 bytes
constexpr size_t kValRecordLen = 88;              // bytes this code reads, verifies and rewrites
constexpr size_t kSealPlainLen = 44;              // size/role/type/flags/hash_type/unknown (12) + SHA-256 (32)
constexpr size_t kSealHashOff = 12;
constexpr size_t kNonceLen = 12;
constexpr size_t kMacLen = 16;

inline uint16_t rd16(const unsigned char* p) { return static_cast<uint16_t>(p[0] | (p[1] << 8)); }
inline uint32_t rd32(const unsigned char* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}
inline uint64_t rd64(const unsigned char* p) { return static_cast<uint64_t>(rd32(p)) | (static_cast<uint64_t>(rd32(p + 4)) << 32); }
inline void wr16(unsigned char* p, uint16_t v) { p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF; }
inline void wr32(unsigned char* p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (v >> (8 * i)) & 0xFF; }
inline void wr64(unsigned char* p, uint64_t v) { for (int i = 0; i < 8; i++) p[i] = (v >> (8 * i)) & 0xFF; }

// Standard CRC-32 (same convention as dislocker's crc32() and zlib's crc32(0, ...)).
inline uint32_t crc32(const unsigned char* data, size_t len) {
    static uint32_t table[256];
    static bool ready = false;
    if (!ready) {
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            table[i] = c;
        }
        ready = true;
    }
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++) crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    return ~crc;
}

inline bool sha256(const unsigned char* data, size_t len, unsigned char out[32]) {
    return mbedtls_sha256(data, len, out, 0) == 0;
}

// One parsed metadata copy: the block followed by the first kValRecordLen bytes of its validation record.
struct Copy {
    uint64_t offset = 0;
    size_t blockSize = 0;
    std::vector<unsigned char> raw;   // blockSize + kValRecordLen bytes
    bool crcOk = false;
    bool sealOk = false;
    uint64_t volumeSize = 0;
};

struct VolumeInfo {
    uint32_t sectorSize = 0;
    uint64_t infoOffsets[3] = {0, 0, 0};
};

// Parses the volume header. kNotBitLocker if it is not a "-FVE-FS-" header, kNotExpandable for the encrypt-on-write
// (EOW) layout, kInvalidMetadata for implausible fields.
inline BlExpandResult parseVolumeHeader(const unsigned char* vbr, VolumeInfo& info) {
    static const unsigned char kSig[8] = {'-', 'F', 'V', 'E', '-', 'F', 'S', '-'};
    // The classic metadata-offset GUID (dislocker's INFORMATION_OFFSET_GUID). Volumes carrying the EOW GUID
    // (Windows' encrypt-on-write / partially encrypted layout) keep extra bookkeeping this code does not rewrite,
    // and dislocker itself refuses to write to them, so nothing could follow the metadata change anyway.
    static const unsigned char kClassicGuid[16] = {0x3b, 0xd6, 0x67, 0x49, 0x29, 0x2e, 0xd8, 0x4a,
                                                   0x83, 0x99, 0xf6, 0xa3, 0x39, 0xe3, 0xd0, 0x01};
    if (std::memcmp(vbr + kVbrSigOffset, kSig, sizeof(kSig)) != 0) return BlExpandResult::kNotBitLocker;
    if (std::memcmp(vbr + kVbrGuidOffset, kClassicGuid, sizeof(kClassicGuid)) != 0)
        return BlExpandResult::kNotExpandable;
    info.sectorSize = rd16(vbr + kVbrSectorSizeOffset);
    if (info.sectorSize < 512 || info.sectorSize > 4096 || (info.sectorSize & (info.sectorSize - 1)) != 0)
        return BlExpandResult::kInvalidMetadata;
    for (int i = 0; i < 3; i++) info.infoOffsets[i] = rd64(vbr + kVbrInfoOffsetsOffset + 8 * i);
    if (info.infoOffsets[0] == 0 || info.infoOffsets[1] == 0 || info.infoOffsets[2] == 0 ||
        info.infoOffsets[0] == info.infoOffsets[1] || info.infoOffsets[0] == info.infoOffsets[2] ||
        info.infoOffsets[1] == info.infoOffsets[2]) return BlExpandResult::kInvalidMetadata;
    return BlExpandResult::kOk;
}

// Reads one copy and checks structure + CRC-32. Returns false only on I/O failure or an implausible structure;
// a CRC mismatch leaves crcOk == false so the caller can tolerate one torn copy.
inline bool loadCopy(const BlExpandIo& io, uint64_t offset, uint64_t hostSize, const VolumeInfo& vol, Copy& out) {
    out = Copy{};
    out.offset = offset;
    if (offset > hostSize || hostSize - offset < kHdrSize) return false;
    unsigned char hdr[kHdrSize];
    if (!io.readAt(offset, hdr, sizeof(hdr))) return false;
    static const unsigned char kSig[8] = {'-', 'F', 'V', 'E', '-', 'F', 'S', '-'};
    if (std::memcmp(hdr, kSig, sizeof(kSig)) != 0) return false;
    if (rd16(hdr + kHdrOffVersion) != kVersionSeven) return false;
    const size_t blockSize = static_cast<size_t>(rd16(hdr + kHdrOffSize)) << 4;
    if (blockSize < kMinBlockSize || blockSize > kMaxBlockSize) return false;
    if (hostSize - offset < blockSize + kValRecordLen) return false;
    // The header must name the same three copies the volume header does.
    for (int i = 0; i < 3; i++)
        if (rd64(hdr + kHdrOffInfoOffsets + 8 * i) != vol.infoOffsets[i]) return false;

    out.blockSize = blockSize;
    out.raw.assign(blockSize + kValRecordLen, 0);
    if (!io.readAt(offset, out.raw.data(), out.raw.size())) return false;
    const unsigned char* val = out.raw.data() + blockSize;
    if (rd16(val + kValSizeOff) < kValRecordLen) return false;
    out.crcOk = crc32(out.raw.data(), blockSize) == rd32(val + kValCrcOff);
    out.volumeSize = rd64(out.raw.data() + kHdrOffVolumeSize);
    return true;
}

// Decrypts the sealed hash with the VMK and compares it with SHA-256 of the block. [plain] receives the 44 plaintext
// bytes (whose header fields are reused when re-sealing).
inline bool checkSeal(const Copy& copy, const unsigned char* vmk, size_t vmkLen, unsigned char plain[kSealPlainLen]) {
    const unsigned char* val = copy.raw.data() + copy.blockSize;
    if (rd16(val + kValNestedSizeOff) != 80 || rd16(val + kValNestedRoleOff) != 0 ||
        rd16(val + kValNestedTypeOff) != 5) return false;
    mbedtls_ccm_context ccm;
    mbedtls_ccm_init(&ccm);
    bool ok = mbedtls_ccm_setkey(&ccm, MBEDTLS_CIPHER_ID_AES, vmk, static_cast<unsigned int>(vmkLen * 8)) == 0 &&
              mbedtls_ccm_auth_decrypt(&ccm, kSealPlainLen, val + kValNonceOff, kNonceLen, nullptr, 0,
                                       val + kValEncOff, plain, val + kValMacOff, kMacLen) == 0;
    mbedtls_ccm_free(&ccm);
    if (!ok) return false;
    unsigned char digest[32];
    if (!sha256(copy.raw.data(), copy.blockSize, digest)) return false;
    return std::memcmp(digest, plain + kSealHashOff, 32) == 0;
}

// Applies [newVolumeSize] to the block, then rebuilds the validation record (fresh nonce from the dataset's
// next_counter, sealed SHA-256, CRC-32). [plainTemplate] is the previously verified 44-byte seal plaintext.
inline bool rebuildCopy(Copy& copy, const unsigned char* vmk, size_t vmkLen, uint64_t newVolumeSize,
                        uint64_t fileTime, const unsigned char plainTemplate[kSealPlainLen]) {
    unsigned char* block = copy.raw.data();
    unsigned char* val = block + copy.blockSize;
    wr64(block + kHdrOffVolumeSize, newVolumeSize);

    const uint32_t counter = rd32(block + kDatasetOffNextCounter);
    wr32(block + kDatasetOffNextCounter, counter + 1);

    unsigned char plain[kSealPlainLen];
    std::memcpy(plain, plainTemplate, sizeof(plain));
    if (!sha256(block, copy.blockSize, plain + kSealHashOff)) return false;

    unsigned char nonce[kNonceLen];
    wr64(nonce, fileTime);
    wr32(nonce + 8, counter);

    unsigned char enc[kSealPlainLen], mac[kMacLen];
    mbedtls_ccm_context ccm;
    mbedtls_ccm_init(&ccm);
    const bool ok = mbedtls_ccm_setkey(&ccm, MBEDTLS_CIPHER_ID_AES, vmk, static_cast<unsigned int>(vmkLen * 8)) == 0 &&
                    mbedtls_ccm_encrypt_and_tag(&ccm, kSealPlainLen, nonce, kNonceLen, nullptr, 0, plain, enc,
                                                mac, kMacLen) == 0;
    mbedtls_ccm_free(&ccm);
    mbedtls_platform_zeroize(plain, sizeof(plain));
    if (!ok) return false;

    std::memcpy(val + kValNonceOff, nonce, kNonceLen);
    std::memcpy(val + kValMacOff, mac, kMacLen);
    std::memcpy(val + kValEncOff, enc, kSealPlainLen);
    wr32(val + kValCrcOff, crc32(block, copy.blockSize));
    return true;
}

}  // namespace blexp

// Reads the encrypted volume size recorded in the metadata (first copy with a valid CRC, the one dislocker uses).
// Needs no key; used by the file-system-only retry to know how far the NTFS grow may reach.
inline BlExpandResult blReadEncryptedVolumeSize(const BlExpandIo& io, uint64_t hostSize, uint64_t& volumeSize,
                                                uint32_t& sectorSize) {
    unsigned char vbr[blexp::kVbrProbeLen];
    if (!io.readAt(0, vbr, sizeof(vbr))) return BlExpandResult::kIoError;
    blexp::VolumeInfo vol;
    const BlExpandResult parsed = blexp::parseVolumeHeader(vbr, vol);
    if (parsed != BlExpandResult::kOk) return parsed;
    for (int i = 0; i < 3; i++) {
        blexp::Copy copy;
        if (blexp::loadCopy(io, vol.infoOffsets[i], hostSize, vol, copy) && copy.crcOk && copy.volumeSize != 0) {
            volumeSize = copy.volumeSize;
            sectorSize = vol.sectorSize;
            return BlExpandResult::kOk;
        }
    }
    return BlExpandResult::kInvalidMetadata;
}

// The result of the read-only verification that precedes any write: the parsed volume header, the three metadata
// copies, and the first copy whose CRC-32 and sealed SHA-256 both verified (the template for the rewrite).
struct BlExpandPlan {
    blexp::VolumeInfo vol;
    blexp::Copy copies[3];
    int source = -1;
    unsigned char plainTemplate[blexp::kSealPlainLen] = {0};
    uint64_t oldVolumeSize = 0;   // encrypted_volume_size of the source copy
};

// Read-only half of the expansion: proves the volume is in the layout this code understands, that the VMK is the
// right key for the metadata seal, and that the current CRC and sealed hash can be reproduced. Writes nothing.
// [hostSize] is the number of bytes available to the volume (the container file, or the partition holding it); the
// volume and all its metadata copies must already fit inside it. The disk-image path calls this before it touches the
// virtual disk or the partition table, so a volume that would be refused never causes any change.
inline BlExpandResult blPlanExpand(const unsigned char* vmk, size_t vmkLen, uint64_t hostSize, const BlExpandIo& io,
                                   BlExpandPlan& plan) {
    using namespace blexp;
    if (vmk == nullptr || (vmkLen != 16 && vmkLen != 24 && vmkLen != 32)) return BlExpandResult::kInvalidMetadata;

    unsigned char vbr[kVbrProbeLen];
    if (!io.readAt(0, vbr, sizeof(vbr))) return BlExpandResult::kIoError;
    const BlExpandResult parsed = parseVolumeHeader(vbr, plan.vol);
    if (parsed != BlExpandResult::kOk) return parsed;

    // Load all three copies; the first valid, sealed one is the template for the rewrite.
    plan.source = -1;
    for (int i = 0; i < 3; i++) {
        if (!loadCopy(io, plan.vol.infoOffsets[i], hostSize, plan.vol, plan.copies[i])) continue;
        if (!plan.copies[i].crcOk) continue;
        unsigned char plain[kSealPlainLen];
        plan.copies[i].sealOk = checkSeal(plan.copies[i], vmk, vmkLen, plain);
        if (plan.copies[i].sealOk && plan.source < 0) {
            plan.source = i;
            std::memcpy(plan.plainTemplate, plain, sizeof(plain));
        }
        mbedtls_platform_zeroize(plain, sizeof(plain));
    }
    if (plan.source < 0) return BlExpandResult::kInvalidMetadata;

    const Copy& src = plan.copies[plan.source];
    const unsigned char* hdr = src.raw.data();
    if (rd16(hdr + kHdrOffCurrState) != kStateEncrypted || rd16(hdr + kHdrOffNextState) != kStateEncrypted)
        return BlExpandResult::kNotExpandable;   // still (de)crypting or switching: Windows owns the metadata then

    plan.oldVolumeSize = src.volumeSize;
    if (plan.oldVolumeSize == 0 || plan.oldVolumeSize % plan.vol.sectorSize != 0 || plan.oldVolumeSize > hostSize)
        return BlExpandResult::kNotExpandable;
    for (int i = 0; i < 3; i++)   // every metadata copy must lie inside the volume being grown
        if (plan.vol.infoOffsets[i] + src.blockSize + kValRecordLen > plan.oldVolumeSize)
            return BlExpandResult::kNotExpandable;
    return BlExpandResult::kOk;
}

// Write half of the expansion; [plan] must come from blPlanExpand() with the same [io] and [vmk]. Grows the volume to
// [requestedSize] bytes (rounded down to the volume's sector size). [hostSize] is the space available now; the host is
// extended first (io.setSize) when it is smaller than the new volume size. The three metadata copies are written last
// copy first, so an interruption leaves the first copy (the one readers prefer) describing the old, still consistent
// volume. On kOk, *oldVolumeSize / *newVolumeSize are the sizes before and after.
inline BlExpandResult blApplyExpand(const unsigned char* vmk, size_t vmkLen, uint64_t hostSize,
                                    uint64_t requestedSize, uint64_t fileTime, const BlExpandIo& io,
                                    const BlExpandPlan& plan, uint64_t* oldVolumeSize = nullptr,
                                    uint64_t* newVolumeSize = nullptr) {
    using namespace blexp;
    const uint64_t oldSize = plan.oldVolumeSize;
    const uint64_t newSize = (requestedSize / plan.vol.sectorSize) * plan.vol.sectorSize;
    if (newSize <= oldSize) return BlExpandResult::kNotLarger;
    if (oldVolumeSize) *oldVolumeSize = oldSize;
    if (newVolumeSize) *newVolumeSize = newSize;

    if (newSize > hostSize && !io.setSize(newSize)) return BlExpandResult::kIoError;
    if (io.sync && !io.sync()) return BlExpandResult::kIoError;

    // Build the new copy once from the verified source copy; every copy gets the same bytes (each is self-contained).
    Copy fresh = plan.copies[plan.source];
    if (!rebuildCopy(fresh, vmk, vmkLen, newSize, fileTime, plan.plainTemplate)) return BlExpandResult::kIoError;

    for (int i = 2; i >= 0; i--) {
        if (!io.writeAt(plan.vol.infoOffsets[i], fresh.raw.data(), fresh.raw.size())) return BlExpandResult::kIoError;
        if (io.sync && !io.sync()) return BlExpandResult::kIoError;
    }

    // Read everything back and run the same validation again.
    const uint64_t finalHost = newSize > hostSize ? newSize : hostSize;
    for (int i = 0; i < 3; i++) {
        Copy check;
        unsigned char plain[kSealPlainLen];
        const bool good = loadCopy(io, plan.vol.infoOffsets[i], finalHost, plan.vol, check) && check.crcOk &&
                          checkSeal(check, vmk, vmkLen, plain) && check.volumeSize == newSize;
        mbedtls_platform_zeroize(plain, sizeof(plain));
        if (!good) return BlExpandResult::kIoError;
    }
    return BlExpandResult::kOk;
}

// Grows the BitLocker volume stored at the start of a container to [requestedSize] bytes (see blApplyExpand). [hostSize]
// is the container file's current size. [vmk] is the unlocked Volume Master Key.
inline BlExpandResult blExpandVolume(const unsigned char* vmk, size_t vmkLen, uint64_t hostSize,
                                     uint64_t requestedSize, uint64_t fileTime, const BlExpandIo& io,
                                     uint64_t* oldVolumeSize = nullptr, uint64_t* newVolumeSize = nullptr) {
    BlExpandPlan plan;
    const BlExpandResult planned = blPlanExpand(vmk, vmkLen, hostSize, io, plan);
    if (planned != BlExpandResult::kOk) return planned;
    return blApplyExpand(vmk, vmkLen, hostSize, requestedSize, fileTime, io, plan, oldVolumeSize, newVolumeSize);
}
