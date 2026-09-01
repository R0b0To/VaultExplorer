#pragma once

// Header-only, pure logic (no I/O, no JNI, no Android dependency) --
// mirrors the sector_batching.h pattern in this directory so it can be
// exercised directly by a host-side test:
//   g++ -std=c++17 mbr_builder_test.cpp -o mbr_builder_test && ./mbr_builder_test
// See io/test/mbr_builder_test.cpp.

#include <cstdint>
#include <cstring>
#include "../containers/usb_create_diagnostics.h"

namespace mbr_builder_detail {
inline void writeUint32LE(unsigned char* buf, uint32_t val) {
    buf[0] = static_cast<unsigned char>(val & 0xFF);
    buf[1] = static_cast<unsigned char>((val >> 8) & 0xFF);
    buf[2] = static_cast<unsigned char>((val >> 16) & 0xFF);
    buf[3] = static_cast<unsigned char>((val >> 24) & 0xFF);
}
}  // namespace mbr_builder_detail

// A classic MBR partition entry's LBA-start and sector-count fields are
// each 32 bits wide. Anything that doesn't fit must be rejected explicitly
// -- silently truncating via static_cast<uint32_t>() (the previous
// behavior, before this reliability fix) writes a partition table entry
// that describes a completely different, wrong-sized partition with no
// error at all, on any device whose usable capacity exceeds 2TB at
// 512-byte sectors (~4.3 billion sectors).
constexpr uint64_t kMbr32BitFieldMax = 0xFFFFFFFFULL;

// Builds sector 0 (the MBR) for a single primary partition starting at
// `startSector` spanning `numSectors`, into `out` (must be exactly 512
// bytes). Performs no I/O.
//
// Validates before writing anything into `out`:
//   - startSector and numSectors are both nonzero
//   - both fit in the MBR partition entry's 32-bit LBA/sector-count fields
//   - startSector + numSectors does not exceed deviceSectorCount, when
//     deviceSectorCount is nonzero (pass 0 only when the caller genuinely
//     has no independent capacity figure to check against; every real
//     call site has one)
// Returns UsbCreateResult::Ok() (with `out` filled in) or
// UsbCreateResult::Fail(UsbCreatePhase::kWriteMbr, ...) (with `out`
// untouched) either way -- no I/O is performed by this function.
inline UsbCreateResult buildMbrSector0(unsigned char out[512], uint64_t startSector, uint64_t numSectors,
                                        uint64_t deviceSectorCount) {
    if (startSector == 0 || numSectors == 0) {
        return UsbCreateResult::Fail(UsbCreatePhase::kWriteMbr, "USB_MBR_INVALID_ARGS",
                                      "MBR partition start/size must be nonzero", startSector * 512ULL,
                                      startSector, 0);
    }
    if (startSector > kMbr32BitFieldMax || numSectors > kMbr32BitFieldMax) {
        return UsbCreateResult::Fail(
            UsbCreatePhase::kWriteMbr, "USB_MBR_SIZE_OVERFLOW",
            "Partition start or size exceeds the MBR's 32-bit sector fields "
            "(device is larger than a classic MBR can address)",
            startSector * 512ULL, startSector,
            numSectors > kMbr32BitFieldMax ? 0xFFFFFFFFu : static_cast<uint32_t>(numSectors));
    }
    // Bounds-check independently of whatever the caller already checked --
    // the Kotlin layer computes a size check against the capacity it read,
    // but native code should not assume that figure is still accurate.
    // deviceSectorCount == 0 means the caller has no independent figure to
    // check against; every real call site supplies one.
    if (deviceSectorCount != 0 && (startSector + numSectors > deviceSectorCount)) {
        return UsbCreateResult::Fail(UsbCreatePhase::kWriteMbr, "USB_MBR_OUT_OF_BOUNDS",
                                      "Partition would extend past the end of the device",
                                      startSector * 512ULL, startSector, static_cast<uint32_t>(numSectors));
    }

    memset(out, 0, 512);

    // Boot signature
    out[510] = 0x55;
    out[511] = 0xAA;

    // Partition 1 entry (at offset 446)
    unsigned char* p1 = &out[446];

    // Status (0x00 = non-bootable)
    p1[0] = 0x00;

    // CHS start (not really used much anymore, setting to 0xFFFFFF)
    p1[1] = 0xFF;
    p1[2] = 0xFF;
    p1[3] = 0xFF;

    // Partition type (0x83 = Linux native, typical for LUKS/VeraCrypt)
    p1[4] = 0x83;

    // CHS end
    p1[5] = 0xFF;
    p1[6] = 0xFF;
    p1[7] = 0xFF;

    // LBA start
    mbr_builder_detail::writeUint32LE(&p1[8], static_cast<uint32_t>(startSector));

    // Number of sectors
    mbr_builder_detail::writeUint32LE(&p1[12], static_cast<uint32_t>(numSectors));

    return UsbCreateResult::Ok();
}
