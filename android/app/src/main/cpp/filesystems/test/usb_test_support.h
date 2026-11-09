// A fake USB mass-storage device for the host-side filesystem backend tests
// (ext_backend_test.cpp, ntfs_backend_test.cpp).
//
// Production UsbBlockCache talks to the real device through usbReadSectors /
// usbWriteSectors / usbSyncDevice (jni/jni_callbacks.h). The backends call into that
// cache whenever a volume is a USB source, so every test binary that links a backend
// has to provide those three symbols. Here they sit over plain memory, with switches to
// make the "device" refuse writes or the sync barrier and counters to see what reached
// it -- which is what the USB write-back regression tests assert on.
//
// Include after diskio.h / volume_state.h (it needs FF_VOLUMES and the callback
// declarations). Header-only; each test binary is a single translation unit.
#pragma once

#include <cstdint>
#include <cstring>
#include <vector>

struct FakeUsbDevice {
    std::vector<uint8_t> media;
    bool refuseWrites = false;
    bool refuseSync = false;
    int writeCalls = 0;
    int syncCalls = 0;

    // Fresh zero-filled medium, healthy and with the counters cleared.
    void reset(size_t bytes) {
        media.assign(bytes, 0);
        refuseWrites = false;
        refuseSync = false;
        writeCalls = 0;
        syncCalls = 0;
    }
};

static FakeUsbDevice g_usbDevice[FF_VOLUMES];

bool usbReadSectors(int volId, uint64_t startSector, uint32_t sectorCount, unsigned char* outBuf) {
    FakeUsbDevice& d = g_usbDevice[volId];
    const uint64_t off = startSector * 512, len = static_cast<uint64_t>(sectorCount) * 512;
    if (off + len > d.media.size()) return false;
    std::memcpy(outBuf, d.media.data() + off, len);
    return true;
}

bool usbWriteSectors(int volId, uint64_t startSector, uint32_t sectorCount, const unsigned char* inBuf) {
    FakeUsbDevice& d = g_usbDevice[volId];
    ++d.writeCalls;
    const uint64_t off = startSector * 512, len = static_cast<uint64_t>(sectorCount) * 512;
    if (d.refuseWrites || off + len > d.media.size()) return false;
    std::memcpy(d.media.data() + off, inBuf, len);
    return true;
}

bool usbSyncDevice(int volId) {
    FakeUsbDevice& d = g_usbDevice[volId];
    ++d.syncCalls;
    return !d.refuseSync;
}
