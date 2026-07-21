#include "block_io.h"
#include <unistd.h>
#include <chrono>
#include <android/log.h>
#include "jni_callbacks.h"
#include "volume_state.h"

// Separate tag from the general "VaultExplorer_C++" one so these can be
// filtered on their own, e.g. `adb logcat -s VaultExplorer_IO`. Debug level
// (not Info) since this fires on every single physical read/write and is
// meant to be enabled while diagnosing performance, not left on by default.
#define LOGD_IO(...) __android_log_print(ANDROID_LOG_DEBUG, "VaultExplorer_IO", __VA_ARGS__)

bool physicalRead(int volumeId, uint64_t byteOffset, unsigned char* buffer,
                  size_t byteCount) {
    VolumeState& volume = volumes[volumeId];
    const auto t0 = std::chrono::steady_clock::now();
    bool ok;
    if (volume.isUsbSource) {
        ok = usbReadSectors(volumeId, byteOffset / 512,
                            static_cast<uint32_t>(byteCount / 512), buffer);
    } else {
        const ssize_t received = pread(volume.fd, buffer, byteCount,
                                       static_cast<off_t>(byteOffset));
        ok = received == static_cast<ssize_t>(byteCount);
    }
    const double ms = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - t0).count();
    LOGD_IO("physicalRead: vol=%d src=%s offset=%llu bytes=%zu ok=%d took=%.2fms",
            volumeId, volume.isUsbSource ? "usb" : "file",
            static_cast<unsigned long long>(byteOffset), byteCount, ok ? 1 : 0, ms);
    return ok;
}

bool physicalWrite(int volumeId, uint64_t byteOffset,
                   const unsigned char* buffer, size_t byteCount) {
    VolumeState& volume = volumes[volumeId];
    if (volume.readOnly) return false;
    const auto t0 = std::chrono::steady_clock::now();
    bool ok;
    if (volume.isUsbSource) {
        ok = usbWriteSectors(volumeId, byteOffset / 512,
                             static_cast<uint32_t>(byteCount / 512), buffer);
    } else {
        const ssize_t written = pwrite(volume.fd, buffer, byteCount,
                                       static_cast<off_t>(byteOffset));
        ok = written == static_cast<ssize_t>(byteCount);
    }
    const double ms = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - t0).count();
    LOGD_IO("physicalWrite: vol=%d src=%s offset=%llu bytes=%zu ok=%d took=%.2fms",
            volumeId, volume.isUsbSource ? "usb" : "file",
            static_cast<unsigned long long>(byteOffset), byteCount, ok ? 1 : 0, ms);
    return ok;
}