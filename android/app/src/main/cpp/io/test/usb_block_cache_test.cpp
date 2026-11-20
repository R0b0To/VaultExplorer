// Host-side test, no Android toolchain required:
//   g++ -std=c++17 -I filesystems/test/host_stubs -I . -I jni io/test/usb_block_cache_test.cpp -o usb_block_cache_test
//
// Exercises the real UsbBlockCache against an in-memory "device" and pins the
// coherence contract the filesystem drivers rely on:
//   * last write wins, even across the metadata and data streams;
//   * a read never returns bytes older than a write the cache has accepted
//     (read-ahead chunks filled while a write was still pending included);
//   * a failed flush keeps the acknowledged bytes pending for a retry;
//   * a failed device sync is reported by sync().
#include "io/usb_block_cache.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

constexpr size_t kSector = 512;
std::vector<unsigned char> g_disk;
bool g_failWrites = false;
bool g_failSync = false;
int g_writeCalls = 0;

void resetDevice() {
    g_disk.assign(1024 * 1024, 'o');
    g_failWrites = false;
    g_failSync = false;
    g_writeCalls = 0;
}

std::vector<unsigned char> sectors(unsigned char fill, size_t n) {
    return std::vector<unsigned char>(n * kSector, fill);
}

bool backingIs(uint64_t sector, unsigned char fill, size_t n = 1) {
    for (size_t i = 0; i < n * kSector; ++i)
        if (g_disk[sector * kSector + i] != fill) return false;
    return true;
}

}  // namespace

bool usbReadSectors(int, uint64_t sec, uint32_t n, unsigned char* out) {
    if ((sec + n) * kSector > g_disk.size()) return false;
    std::memcpy(out, g_disk.data() + sec * kSector, n * kSector);
    return true;
}
bool usbWriteSectors(int, uint64_t sec, uint32_t n, const unsigned char* in) {
    ++g_writeCalls;
    if (g_failWrites || (sec + n) * kSector > g_disk.size()) return false;
    std::memcpy(g_disk.data() + sec * kSector, in, n * kSector);
    return true;
}
bool usbSyncDevice(int) { return !g_failSync; }

static unsigned char readByte(UsbBlockCache& c, uint64_t sector) {
    unsigned char buf[kSector];
    bool ok = c.read(0, sector * kSector, buf, sizeof buf);
    assert(ok);
    (void)ok;
    return buf[0];
}

static void write(UsbBlockCache& c, uint64_t sector, unsigned char fill, size_t n) {
    auto b = sectors(fill, n);
    bool ok = c.write(0, sector * kSector, b.data(), b.size());
    assert(ok);
    (void)ok;
}

// Older small (metadata-stream) write, newer larger (data-stream) write over it.
static void testOverlapAcrossStreamsLastWriteWins() {
    resetDevice();
    UsbBlockCache c;
    write(c, 100, 'O', 1);
    write(c, 100, 'N', 8);
    assert(c.flush(0));
    assert(backingIs(100, 'N', 8));
}

// Same, but the newer write only partly overlaps the older one.
static void testPartialOverlapLastWriteWins() {
    resetDevice();
    UsbBlockCache c;
    write(c, 104, 'O', 2);   // meta stream: sectors 104-105
    write(c, 100, 'N', 6);   // data stream: sectors 100-105, covers it
    assert(c.flush(0));
    assert(backingIs(100, 'N', 6));
}

// Older data-stream write, newer small write in the middle, then a newer big
// write over both: every ordering of the three must resolve to the newest.
static void testThreeWritesNewestWins() {
    resetDevice();
    UsbBlockCache c;
    write(c, 100, 'A', 8);
    write(c, 102, 'B', 1);
    write(c, 100, 'C', 8);
    assert(c.flush(0));
    assert(backingIs(100, 'C', 8));
    assert(readByte(c, 102) == 'C');
}

// A write wholly inside a buffered stream is merged without losing neighbours.
static void testWriteInsideBufferedStreamMerges() {
    resetDevice();
    UsbBlockCache c;
    write(c, 100, 'A', 8);
    write(c, 103, 'B', 2);
    assert(c.flush(0));
    assert(backingIs(100, 'A', 3));
    assert(backingIs(103, 'B', 2));
    assert(backingIs(105, 'A', 3));
}

// Read of a neighbouring sector populates a 64 KiB chunk that includes the
// still-pending write; the pending sector must not come back stale.
static void testReadAheadNotStaleAfterWriteback() {
    for (size_t writeSectors : {size_t(1), size_t(8)}) {
        resetDevice();
        UsbBlockCache c;
        const uint64_t target = 200;
        write(c, target, 'n', writeSectors);
        // Reading the sector just past the pending write fills the whole 64 KiB
        // chunk from the device, including the old copy of the pending sectors.
        (void)readByte(c, target + writeSectors);
        assert(readByte(c, target) == 'n');
        assert(c.flush(0));
        assert(backingIs(target, 'n', writeSectors));
        assert(readByte(c, target) == 'n');
    }
}

// Same chunk, but the write is flushed before the stale chunk is consulted by
// a read that does not itself overlap the (now drained) write.
static void testChunkInvalidatedWhenStreamDrains() {
    resetDevice();
    UsbBlockCache c;
    write(c, 200, 'n', 1);
    (void)readByte(c, 201);                     // chunk now holds old sector 200
    assert(c.flush(0));                         // drain; chunk must be dropped
    assert(readByte(c, 200) == 'n');
}

// A flush the device rejects must not forget the bytes.
static void testFailedFlushKeepsDataForRetry() {
    resetDevice();
    UsbBlockCache c;
    write(c, 10, 'X', 1);
    write(c, 40, 'Y', 8);
    g_failWrites = true;
    assert(!c.flush(0));
    assert(backingIs(10, 'o') && backingIs(40, 'o', 8));
    g_failWrites = false;
    assert(c.flush(0));
    assert(backingIs(10, 'X'));
    assert(backingIs(40, 'Y', 8));
}

// Data parked behind a failed flush is still what a read sees.
static void testFailedFlushThenRead() {
    resetDevice();
    UsbBlockCache c;
    write(c, 10, 'X', 1);
    g_failWrites = true;
    unsigned char buf[kSector];
    assert(!c.read(0, 10 * kSector, buf, sizeof buf));   // read needs the flush
    g_failWrites = false;
    assert(readByte(c, 10) == 'X');
    assert(backingIs(10, 'X'));
}

static void testSyncReportsFlushAndDeviceFailure() {
    resetDevice();
    UsbBlockCache c;
    write(c, 10, 'X', 1);
    g_failWrites = true;
    assert(!c.sync(0));
    g_failWrites = false;
    g_failSync = true;
    assert(!c.sync(0));                          // flush ok, device sync fails
    assert(backingIs(10, 'X'));
    g_failSync = false;
    assert(c.sync(0));
}

// Large writes bypass the buffers but must still order after older pending
// writes and invalidate read-ahead.
static void testBypassWriteOrdersAfterPending() {
    resetDevice();
    UsbBlockCache c;
    write(c, 100, 'O', 1);
    (void)readByte(c, 101);
    write(c, 100, 'N', 256);
    assert(c.flush(0));
    assert(backingIs(100, 'N', 256));
    assert(readByte(c, 100) == 'N');
}

int main() {
    testOverlapAcrossStreamsLastWriteWins();
    testPartialOverlapLastWriteWins();
    testThreeWritesNewestWins();
    testWriteInsideBufferedStreamMerges();
    testReadAheadNotStaleAfterWriteback();
    testChunkInvalidatedWhenStreamDrains();
    testFailedFlushKeepsDataForRetry();
    testFailedFlushThenRead();
    testSyncReportsFlushAndDeviceFailure();
    testBypassWriteOrdersAfterPending();
    std::puts("usb_block_cache_test: all passed");
    return 0;
}
