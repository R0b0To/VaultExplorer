// Host-side test, no Android toolchain required:
//   g++ -std=c++17 mbr_builder_test.cpp -o mbr_builder_test && ./mbr_builder_test
#include "../mbr_builder.h"
#include <cassert>
#include <cstdio>

static uint32_t readUint32LE(const unsigned char* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

int main() {
    unsigned char sector0[512];

    // --- Happy path: typical 32GB USB drive, 2048-sector alignment. ---
    {
        uint64_t startSector = 2048;
        uint64_t numSectors = 62333952;  // ~29.7GB usable at 512B sectors
        uint64_t deviceSectorCount = startSector + numSectors + 100;  // some slack, like a real device
        UsbCreateResult r = buildMbrSector0(sector0, startSector, numSectors, deviceSectorCount);
        assert(r.success);
        assert(sector0[510] == 0x55 && sector0[511] == 0xAA);
        assert(sector0[446 + 4] == 0x83);  // partition type
        assert(readUint32LE(&sector0[446 + 8]) == static_cast<uint32_t>(startSector));
        assert(readUint32LE(&sector0[446 + 12]) == static_cast<uint32_t>(numSectors));
    }

    // --- deviceSectorCount == 0 means "no independent capacity to check
    //     against" and must not be treated as "device has zero capacity". ---
    {
        UsbCreateResult r = buildMbrSector0(sector0, 2048, 1000, /*deviceSectorCount=*/0);
        assert(r.success);
    }

    // --- Zero start/size are always rejected. ---
    {
        UsbCreateResult r = buildMbrSector0(sector0, 0, 1000, 100000);
        assert(!r.success);
        assert(r.errorCode == "USB_MBR_INVALID_ARGS");
        assert(r.phase == UsbCreatePhase::kWriteMbr);

        UsbCreateResult r2 = buildMbrSector0(sector0, 2048, 0, 100000);
        assert(!r2.success);
        assert(r2.errorCode == "USB_MBR_INVALID_ARGS");
    }

    // --- The core reliability-fix bug: numSectors that doesn't fit in the
    //     MBR's 32-bit sector-count field must be REJECTED, not silently
    //     truncated by a static_cast<uint32_t>(). A >2TB USB SSD easily
    //     produces a numSectors above 0xFFFFFFFF at 512B sectors. ---
    {
        uint64_t hugeNumSectors = 0x100000000ULL;  // 2^32, one past the max
        UsbCreateResult r = buildMbrSector0(sector0, 2048, hugeNumSectors, hugeNumSectors + 2048);
        assert(!r.success);
        assert(r.errorCode == "USB_MBR_SIZE_OVERFLOW");
        // Must NOT have written a truncated (wrong) partition table.
        assert(sector0[446 + 4] != 0x83 || readUint32LE(&sector0[446 + 12]) != 0);
    }

    // --- Exactly at the 32-bit boundary must still succeed (off-by-one
    //     check against the reject-above-max threshold). ---
    {
        uint64_t maxNumSectors = 0xFFFFFFFFULL;
        UsbCreateResult r = buildMbrSector0(sector0, 1, maxNumSectors, maxNumSectors + 1);
        assert(r.success);
        assert(readUint32LE(&sector0[446 + 12]) == 0xFFFFFFFFu);
    }

    // --- startSector itself overflowing the 32-bit LBA-start field must
    //     also be rejected (not just numSectors). ---
    {
        uint64_t hugeStart = 0x100000000ULL;
        UsbCreateResult r = buildMbrSector0(sector0, hugeStart, 1000, hugeStart + 1000);
        assert(!r.success);
        assert(r.errorCode == "USB_MBR_SIZE_OVERFLOW");
    }

    // --- Bounds check: partition extending past the device's real
    //     capacity must be rejected even though it fits in 32 bits and the
    //     caller-supplied numSectors is otherwise well-formed (this is the
    //     "native code should not trust the Kotlin-side check alone" case). ---
    {
        uint64_t startSector = 2048;
        uint64_t numSectors = 1000000;
        uint64_t deviceSectorCount = startSector + numSectors - 1;  // one sector short
        UsbCreateResult r = buildMbrSector0(sector0, startSector, numSectors, deviceSectorCount);
        assert(!r.success);
        assert(r.errorCode == "USB_MBR_OUT_OF_BOUNDS");
    }

    // --- Exactly filling the device (startSector + numSectors ==
    //     deviceSectorCount) is the boundary and must succeed. ---
    {
        uint64_t startSector = 2048;
        uint64_t numSectors = 1000000;
        uint64_t deviceSectorCount = startSector + numSectors;
        UsbCreateResult r = buildMbrSector0(sector0, startSector, numSectors, deviceSectorCount);
        assert(r.success);
    }

    printf("mbr_builder_test: all assertions passed\n");
    return 0;
}
