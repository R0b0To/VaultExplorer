// Host-side test, no Android toolchain required:
//   g++ -std=c++17 -I filesystems/test/host_stubs -I . -I jni -I session session/test/lock_policy_test.cpp -o lock_policy_test
//
// 1) Pure ordering of lockpolicy::lockVolume.
// 2) The same policy driven with the real UsbBlockCache: a lock that the device
//    refuses must leave the acknowledged bytes pending, a retry must persist them,
//    and only a forced lock may discard them.
#include "session/lock_policy.h"
#include "io/usb_block_cache.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// ---- in-memory USB "device" for the real cache ------------------------------------
static std::vector<unsigned char> g_disk;
static bool g_failWrites = false;
static bool g_failSync = false;

bool usbReadSectors(int, uint64_t s, uint32_t n, unsigned char* out) {
    if ((s + n) * 512 > g_disk.size()) return false;
    std::memcpy(out, g_disk.data() + s * 512, n * 512);
    return true;
}
bool usbWriteSectors(int, uint64_t s, uint32_t n, const unsigned char* in) {
    if (g_failWrites || (s + n) * 512 > g_disk.size()) return false;
    std::memcpy(g_disk.data() + s * 512, in, n * 512);
    return true;
}
bool usbSyncDevice(int) { return !g_failSync; }

static void resetDevice() {
    g_disk.assign(256 * 512, 'o');
    g_failWrites = g_failSync = false;
}

// ---- pure ordering --------------------------------------------------------------
struct Trace {
    std::string log;
    bool flushOk = true, durable = true;
};

static bool run(Trace& t, bool flushable, bool force, bool* discarded = nullptr) {
    return lockpolicy::lockVolume(
        flushable, force,
        [&] { t.log += "F"; return t.flushOk; },
        [&] { t.log += "T"; return t.durable; },
        [&] { t.log += "R"; },
        discarded);
}

static void testNormalLockOrder() {
    Trace t;
    bool d = true;
    assert(run(t, true, false, &d));
    assert(t.log == "FTR" && !d);   // flush, tear down, reset
}

static void testPreFlushFailureChangesNothing() {
    Trace t; t.flushOk = false;
    assert(!run(t, true, false));
    assert(t.log == "F");           // not torn down, not reset: the vault stays usable
}

static void testFinalFlushFailureKeepsStateForRetry() {
    Trace t; t.durable = false;
    bool d = true;
    assert(!run(t, true, false, &d));
    assert(t.log == "FT");          // torn down, but NOT reset
    assert(!d);
}

static void testForceAlwaysResets() {
    Trace t; t.flushOk = false; t.durable = false;
    bool d = false;
    assert(run(t, true, true, &d));
    assert(t.log == "TR" && d);     // no pre-flush attempt, discard reported
    Trace ok;
    assert(run(ok, true, true, &d) && ok.log == "TR" && !d);
}

static void testNotFlushableSkipsPreFlush() {
    Trace t;
    assert(run(t, false, false));
    assert(t.log == "TR");
}

// ---- with the real cache ----------------------------------------------------------
struct CacheVolume {
    UsbBlockCache cache;
    bool lock(bool force, bool* discarded = nullptr) {
        return lockpolicy::lockVolume(
            true, force,
            [&] { return cache.sync(0); },
            [&] { return cache.sync(0); },   // stands in for unmount's flush
            [&] { cache.clear(); },          // VolumeState::reset()
            discarded);
    }
};

static std::vector<unsigned char> sector(unsigned char c) { return std::vector<unsigned char>(512, c); }

static void testRefusedLockKeepsAcknowledgedBytesAndRetryPersistsThem() {
    resetDevice();
    CacheVolume v;
    auto data = sector('X');
    assert(v.cache.write(0, 10 * 512, data.data(), data.size()));   // acknowledged to the filesystem
    g_failWrites = true;
    assert(!v.lock(false));                                          // device refuses: not locked
    assert(g_disk[10 * 512] == 'o');
    g_failWrites = false;                                            // device recovers
    assert(v.lock(false));                                           // retry flushes and locks
    assert(g_disk[10 * 512] == 'X');                                 // nothing was lost
}

static void testHardwareSyncFailureAlsoRefusesToLock() {
    resetDevice();
    CacheVolume v;
    auto data = sector('Y');
    assert(v.cache.write(0, 20 * 512, data.data(), data.size()));
    g_failSync = true;
    assert(!v.lock(false));
    g_failSync = false;
    assert(v.lock(false));
    assert(g_disk[20 * 512] == 'Y');
}

static void testForcedLockDiscardsWhatCouldNotBeWritten() {
    resetDevice();
    CacheVolume v;
    auto data = sector('Z');
    assert(v.cache.write(0, 30 * 512, data.data(), data.size()));
    g_failWrites = true;
    bool discarded = false;
    assert(v.lock(true, &discarded));                                // removed device / "lock anyway"
    assert(discarded);
    g_failWrites = false;
    assert(v.cache.sync(0));                                         // nothing left to write
    assert(g_disk[30 * 512] == 'o');
}

int main() {
    testNormalLockOrder();
    testPreFlushFailureChangesNothing();
    testFinalFlushFailureKeepsStateForRetry();
    testForceAlwaysResets();
    testNotFlushableSkipsPreFlush();
    testRefusedLockKeepsAcknowledgedBytesAndRetryPersistsThem();
    testHardwareSyncFailureAlsoRefusesToLock();
    testForcedLockDiscardsWhatCouldNotBeWritten();
    std::puts("lock_policy_test: all passed");
    return 0;
}
