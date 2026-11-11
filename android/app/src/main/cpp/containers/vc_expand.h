#pragma once
// Volume expansion (VeraCrypt "Volume Expander", src/ExpandVolume/ExpandVolume.c), file containers.
//
// What desktop does, and what this does:
//   * only a STANDARD volume is expanded (not a hidden-volume header);
//   * the host file is extended; the data area grows from (old - 256 KiB) to (new - 256 KiB);
//   * the new space is initialised with data encrypted under the volume's own key (so it looks like
//     the rest of the volume) -- or, in quick mode, only the old embedded backup header (now inside
//     the data area) is wiped with random bytes and the rest stays as the sparse extension;
//   * the volume header gets the new volume size / encrypted-area length and a fresh salt; the
//     embedded backup header is written at the NEW end (V-128 KiB) BEFORE the primary header, both
//     under independent salts, and the new tail header group is random filler.
// The file system INSIDE the volume is not touched (desktop extends NTFS through the OS only):
// the added space is unallocated until the file system is grown.
// Header-only; I/O and randomness are callbacks so it can be tested on the host
// (containers/test/vc_expand_test.cpp).
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <functional>
#include <memory>
#include "vc_geometry.h"
#include "vc_header_build.h"

enum class VcExpandResult { kOk, kHiddenHeader, kNotLarger, kInconsistentHeader, kIoError, kBuildFailed, kCancelled };

struct VcExpandIo {
    std::function<bool(uint64_t, const unsigned char*, size_t)> writeAt;
    std::function<bool(uint64_t newSize)> setSize;
    std::function<bool(unsigned char*, size_t)> random;
    std::function<bool(uint64_t done, uint64_t total)> progress;   // return false to cancel (optional)
};

// [body] is the verified, decrypted primary header body of the standard volume (modified in place on success);
// [oldSize] the current host size; [newSize] the requested host size (rounded down to 4096 here).
inline VcExpandResult vcExpandVolume(unsigned char* body, CascadeId cipher, HashId hash,
                                     const unsigned char* password, size_t passwordLen, int pim,
                                     uint64_t oldSize, uint64_t newSize, bool initFreeSpace, VcExpandIo& io) {
    newSize = (newSize / 4096) * 4096;
    auto rd64 = [&](int off) { uint64_t v = 0; for (int i = 0; i < 8; i++) v = (v << 8) | body[off + i]; return v; };
    auto wr64 = [&](int off, uint64_t v) { for (int i = 7; i >= 0; --i) { body[off + i] = v & 0xFF; v >>= 8; } };
    const uint64_t G = VC_DATA_AREA_OFFSET;                       // one header group (128 KiB)
    if (rd64(VC_HDR_OFF_HIDDEN_VOL_SIZE) != 0) return VcExpandResult::kHiddenHeader;
    if (newSize <= oldSize) return VcExpandResult::kNotLarger;
    if (oldSize < 2 * G || rd64(VC_HDR_OFF_VOLUME_SIZE) != oldSize - 2 * G ||
        rd64(VC_HDR_OFF_KEY_SCOPE_START) != G || rd64(VC_HDR_OFF_KEY_SCOPE_SIZE) != oldSize - 2 * G) {
        return VcExpandResult::kInconsistentHeader;               // not a plain full-size standard volume
    }
    const CascadeSpec spec = cascadeSpecFor(cipher);
    CascadeContext dataCtx;
    if (!cascadeSetKeys(dataCtx, cipher, body + VC_KEY_OFFSET_MASTER, spec.layerCount * 64)) return VcExpandResult::kBuildFailed;

    if (!io.setSize(newSize)) return VcExpandResult::kIoError;

    const uint64_t newStart = oldSize - G, newEnd = newSize - G;   // [newStart, newEnd) is the added data area
    if (initFreeSpace) {
        constexpr uint64_t kBatch = 2048;                          // sectors per write (1 MiB)
        std::unique_ptr<unsigned char[]> buf(new unsigned char[kBatch * 512]);
        static const unsigned char zero[512] = {0};
        const uint64_t total = (newEnd - newStart) / 512;
        for (uint64_t s = 0; s < total;) {
            const uint64_t n = (total - s < kBatch) ? total - s : kBatch;
            for (uint64_t i = 0; i < n; i++) cascadeEncryptSector(dataCtx, newStart / 512 + s + i, zero, buf.get() + i * 512);
            if (!io.writeAt(newStart + s * 512, buf.get(), n * 512)) return VcExpandResult::kIoError;
            s += n;
            if (io.progress && !io.progress(s, total)) return VcExpandResult::kCancelled;
        }
    } else {
        // Quick expand: the old embedded backup header group now lies inside the data area -- wipe it.
        std::unique_ptr<unsigned char[]> rnd(new unsigned char[G]);
        if (!io.random(rnd.get(), G) || !io.writeAt(oldSize - G, rnd.get(), G)) return VcExpandResult::kIoError;
    }

    // New tail header group: random filler, then the embedded backup header at the new end.
    std::unique_ptr<unsigned char[]> tail(new unsigned char[G]);
    if (!io.random(tail.get(), G)) return VcExpandResult::kIoError;

    const uint64_t newData = newSize - 2 * G;
    wr64(VC_HDR_OFF_VOLUME_SIZE, newData);
    wr64(VC_HDR_OFF_KEY_SCOPE_SIZE, newData);
    const unsigned version = (static_cast<unsigned>(body[VC_HDR_OFF_VERSION]) << 8) | body[VC_HDR_OFF_VERSION + 1];
    if (version < VC_HEADER_FORMAT_VERSION) vcStampHeaderPreamble(body);
    uint32_t crc = vcCrc32(body, VC_HDR_CRC_COVERAGE_LEN);
    for (int i = 0; i < 4; i++) body[VC_HDR_OFF_HEADER_CRC + i] = static_cast<unsigned char>(crc >> (24 - 8 * i));

    unsigned char backup[VC_FULL_HEADER_SIZE], primary[VC_FULL_HEADER_SIZE];
    if (!vcBuildFreshlySaltedHeaderSector(body, cipher, hash, password, passwordLen, clampPim(pim), backup) ||
        !vcBuildFreshlySaltedHeaderSector(body, cipher, hash, password, passwordLen, clampPim(pim), primary)) {
        return VcExpandResult::kBuildFailed;
    }
    std::memcpy(tail.get(), backup, sizeof(backup));
    if (!io.writeAt(newSize - G, tail.get(), G)) return VcExpandResult::kIoError;   // backup (+ random hidden-backup slot) first
    if (!io.writeAt(0, primary, sizeof(primary))) return VcExpandResult::kIoError;  // then the primary header
    return VcExpandResult::kOk;
}
