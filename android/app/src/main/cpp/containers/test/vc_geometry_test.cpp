// Host-side test, no Android toolchain required:
//   g++ -std=c++17 -I . containers/test/vc_geometry_test.cpp -o vc_geometry_test && ./vc_geometry_test
//
// Pins the header-area arithmetic shared by container creation, password
// change and hidden-volume protection. The numbers follow the layout this app
// creates (see createContainer / createContainerWithHidden):
//   normal header at 0, hidden header at 64 KiB, outer data [A, V-A),
//   backup normal header at V-A, backup hidden header at V-64 KiB,
//   hidden data [V-A-H, V-A).
#include "containers/vc_geometry.h"
#include <cassert>
#include <cstdio>

namespace {
constexpr uint64_t kA = 131072;                 // header group
constexpr uint64_t kV = 64ULL * 1024 * 1024;    // 64 MiB container
constexpr uint64_t kH = 8ULL * 1024 * 1024;     // 8 MiB hidden volume
}

static void testBackupHeaderOffsets() {
    uint64_t off = 0;
    assert(vcgeom::backupHeaderOffset(kV, false, &off) && off == 66977792 && off == kV - kA);
    assert(vcgeom::backupHeaderOffset(kV, true, &off) && off == kV - 65536);
    // The old code derived the backup from the header's data-area size: V-3A.
    // It lands inside the data area and must be rejected as a backup slot.
    const uint64_t oldBuggy = (kV - 2 * kA) - kA;
    assert(oldBuggy == 66715648);
    assert(!vcgeom::headerClearOfDataArea(oldBuggy, kA, kV - 2 * kA));
    assert(vcgeom::headerClearOfDataArea(kV - kA, kA, kV - 2 * kA));
    assert(!vcgeom::backupHeaderOffset(kA, false, &off));           // too small
    assert(!vcgeom::backupHeaderOffset(kV, false, nullptr));
}

static void testHeaderClearOfDataArea() {
    assert(vcgeom::headerClearOfDataArea(0, kA, 1000));             // before
    assert(vcgeom::headerClearOfDataArea(kA + 1000, kA, 1000));     // right after
    assert(!vcgeom::headerClearOfDataArea(kA + 999, kA, 1000));     // last byte overlaps
    assert(!vcgeom::headerClearOfDataArea(kA - 1, kA, 1000));       // first byte overlaps
    assert(!vcgeom::headerClearOfDataArea(~0ULL - 10, 0, 100));     // overflow fails closed
}

static void testHiddenProtectedRangeCoversWholeHiddenVolume() {
    uint64_t s = 0, e = 0;
    const uint64_t hiddenStart = kV - kA - kH;
    assert(hiddenStart == 58589184);
    assert(vcgeom::hiddenProtectedRange(kA, kV - 2 * kA, hiddenStart, kH, &s, &e));
    assert(s == hiddenStart);                    // not V-H (58720256): that skipped the first A bytes
    assert(e == kV - kA);                        // ends where the backup header group begins
    assert(e - s == kH);
}

// Outer volume that sits inside a device partition: result stays absolute.
static void testHiddenProtectedRangeWithPartitionBase() {
    const uint64_t partStart = 1ULL * 1024 * 1024;
    uint64_t s = 0, e = 0;
    assert(vcgeom::hiddenProtectedRange(partStart + kA, kV - 2 * kA, kV - kA - kH, kH, &s, &e));
    assert(s == partStart + kV - kA - kH);
    assert(e == partStart + kV - kA);
}

// Layout produced before creation stopped overlapping the backup headers:
// hidden data [V-H, V). It fits the container and is honoured as stated.
static void testHiddenProtectedRangeLegacyLayout() {
    uint64_t s = 0, e = 0;
    assert(vcgeom::hiddenProtectedRange(kA, kV - 2 * kA, kV - kH, kH, &s, &e));
    assert(s == kV - kH && e == kV);
}

static void testHiddenProtectedRangeRejectsBadGeometry() {
    uint64_t s = 0, e = 0;
    const uint64_t outerLen = kV - 2 * kA;
    assert(!vcgeom::hiddenProtectedRange(kA, outerLen, kV - kA - kH, 0, &s, &e));          // empty
    assert(!vcgeom::hiddenProtectedRange(kA, outerLen, kA - 512, kH, &s, &e));             // starts in header group
    assert(!vcgeom::hiddenProtectedRange(kA, outerLen, kV - kA, kH, &s, &e));              // runs past container
    assert(!vcgeom::hiddenProtectedRange(kA, outerLen, ~0ULL - 10, 100, &s, &e));          // overflow
    assert(!vcgeom::hiddenProtectedRange(kA - 1, outerLen, kV - kA - kH, kH, &s, &e));     // outer offset < A
    assert(!vcgeom::hiddenProtectedRange(kA, outerLen, kV - kA - kH, kH, nullptr, &e));
}

int main() {
    testBackupHeaderOffsets();
    testHeaderClearOfDataArea();
    testHiddenProtectedRangeCoversWholeHiddenVolume();
    testHiddenProtectedRangeWithPartitionBase();
    testHiddenProtectedRangeLegacyLayout();
    testHiddenProtectedRangeRejectsBadGeometry();
    std::puts("vc_geometry_test: all passed");
    return 0;
}
